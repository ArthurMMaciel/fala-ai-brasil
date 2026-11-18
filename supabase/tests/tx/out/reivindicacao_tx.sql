-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar reivindicacao_checks.sql e as migrations.
-- Migrations: 20261109180000_resposta_revisada_ativa.sql, 20261117120000_representante_verificado_estrutura.sql, 20261117150000_pausa_do_piloto.sql, 20261117130000_representante_verificado_gate.sql, 20261118120000_empresa_pre_cadastrada_estrutura.sql, 20261118130000_empresa_pre_cadastrada_funcoes.sql, 20261118140000_reivindicacao_cnpj.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'efffffff-ffff-ffff-ffff-ffffffffffff'; u_c1 uuid := 'f1111111-1111-1111-1111-111111111111'; u_c2 uuid := 'f2222222-2222-2222-2222-222222222222'; u_c3 uuid := 'f3333333-3333-3333-3333-333333333333'; u_op uuid := 'f4444444-4444-4444-4444-444444444444'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_pre text := '16180339000157'; cnpj_reg text := '14142135000104'; co uuid; cp uuid; r record;
begin
  begin  -- trava: nada pode commitar daqui para dentro
    -- Sem lock em 3 s, falha limpa em vez de enfileirar o site atrás do DDL. (statement_timeout não se aplica: o
    -- cronômetro começa no DO, que é a instrução de topo; um SET aqui dentro não o rearma.)
    execute 'set local lock_timeout = ''3s''';

    -- 20261109180000_resposta_revisada_ativa.sql (4 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261109180000') then
      res := res || jsonb_build_object('20261109180000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- TASK-0035 / ADR-0013, passo (d): a resposta da empresa passa pela equipe antes de chegar ao trabalhador.
-- Só aplicar DEPOIS do front tolerante (passo c) estar em produção: ele precisa conhecer 'answer_in_review'
-- e ler review_status/worker_summary.
-- Rollback: liberar ou devolver pela Operação todas as respostas em revisão ANTES de reverter (nunca expor ao trabalhador
-- resposta não revisada); depois reaplicar respond_complaint de 20261109170000, a política responses_read_worker de
-- 20261027024534 e o default 'released'.

alter table public.company_responses alter column review_status set default 'in_review'$s0$;
      execute $s0$-- Empresa responde: a resposta fica em revisão; com uma em revisão, não envia outra.
create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_company_user(v_company) or v_status not in ('shared', 'answer_in_review', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if v_status = 'answer_in_review' or exists (select 1 from public.company_responses where complaint_id = p_id and review_status = 'in_review') then
    raise exception 'Já existe uma resposta em revisão pela equipe.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'in_review');
  update public.complaints set status = 'answer_in_review' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, 'answer_in_review', 'company', 'A empresa respondeu. A equipe revisa a resposta antes de você receber.');
end;
$$$s0$;
      execute $s0$-- Trabalhador só lê respostas liberadas (conteúdo revisado e descrição da equipe).
drop policy responses_read_worker on public.company_responses$s0$;
      execute $s0$create policy responses_read_worker on public.company_responses for select to authenticated
  using (review_status = 'released' and public.owns_complaint(complaint_id))$s0$;
      res := res || jsonb_build_object('20261109180000', 'aplicada na transação de teste');
    end if;

    -- 20261117120000_representante_verificado_estrutura.sql (17 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117120000') then
      res := res || jsonb_build_object('20261117120000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0012 (recorte do piloto, V1 + C1 + R3), parte 1 de 2: estrutura da verificação do representante.
-- Não muda acesso a manifestações; a troca do gate fica na 20261117130000.
-- Todo vínculo existente e todo cadastro novo nasce 'pending' (default da coluna; o cliente só tem SELECT em company_users).
-- A verificação é feita pela equipe por ligação ao telefone público da empresa ('callback') ou por documento de
-- representação conferido fora da plataforma ('document_review'); nenhum arquivo é guardado.
-- Sem enum novo: estados em text + check, para tudo rodar numa transação só.
--
-- Rollback (antes da 20261117130000): drop function public.ops_verify_representative(uuid, uuid, text, text, text, text),
--   public.ops_list_representatives(text), public.ops_representative_history(uuid), public.is_verified_company_user(uuid);
--   drop table public.representative_verifications; drop function private.block_trail_change();
--   alter table public.company_users drop column verified_at, drop column verification_status;
--   Antes do drop da tabela, exportar a trilha.

-- Se company_users estiver ocupada, falha em 5 s em vez de travar o portal da empresa na fila de locks.
set local lock_timeout = '5s'$s0$;
      execute $s0$-- 1) Estado do vínculo.
alter table public.company_users
  add column verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected', 'revoked')),
  add column verified_at timestamptz$s0$;
      execute $s0$-- 2) Histórico das decisões: só inserção, sobrevive à exclusão da conta (sem FK para auth.users).
create table public.representative_verifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  user_id uuid not null,
  decision text not null check (decision in ('verified', 'rejected', 'revoked')),
  method text check (method is null or method in ('callback', 'document_review')),
  evidence_ref text check (evidence_ref is null or char_length(btrim(evidence_ref)) between 3 and 200),
  reason text check (reason is null or char_length(btrim(reason)) between 10 and 500),
  reviewer_id uuid not null,
  created_at timestamptz not null default now(),
  check (decision <> 'verified' or (method is not null and evidence_ref is not null)),
  check (decision = 'verified' or reason is not null)
)$s0$;
      execute $s0$create index representative_verifications_company_idx on public.representative_verifications (company_id, created_at)$s0$;
      execute $s0$alter table public.representative_verifications enable row level security$s0$;
      execute $s0$revoke all on public.representative_verifications from public, anon, authenticated$s0$;
      execute $s0$-- Trilha imutável (lacuna 2 da TASK-0009): nem o dono altera ou apaga por engano; retenção futura troca este gatilho.
create function private.block_trail_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Registro de auditoria não pode ser alterado nem apagado.' using errcode = 'P0001';
end;
$$$s0$;
      execute $s0$revoke all on function private.block_trail_change() from public, anon, authenticated$s0$;
      execute $s0$create trigger representative_verifications_immutable before update or delete on public.representative_verifications
  for each row execute function private.block_trail_change()$s0$;
      execute $s0$-- 3) Gate novo (usado pela 20261117130000).
create function public.is_verified_company_user(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.company_users
                 where company_id = p_company and user_id = auth.uid() and verification_status = 'verified');
$$$s0$;
      execute $s0$revoke execute on function public.is_verified_company_user(uuid) from public, anon$s0$;
      execute $s0$grant execute on function public.is_verified_company_user(uuid) to authenticated$s0$;
      execute $s0$-- 4) Fila da equipe: e-mail de login para a ligação de conferência; nada de manifestação.
create function public.ops_list_representatives(p_status text default 'pending')
returns table (company_id uuid, company_name text, cnpj text, user_id uuid, email text, role public.member_role,
               verification_status text, linked_at timestamptz, verified_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), co.cnpj, cu.user_id, u.email::text, cu.role,
         cu.verification_status, cu.created_at, cu.verified_at
  from public.company_users cu
  join public.companies co on co.id = cu.company_id
  left join auth.users u on u.id = cu.user_id
  where p_status is null or cu.verification_status = p_status
  order by cu.created_at;
end;
$$$s0$;
      execute $s0$-- 5) Decisão da equipe. Transições: pending|rejected -> verified|rejected; verified -> revoked; revoked -> verified.
create function public.ops_verify_representative(p_company uuid, p_user uuid, p_decision text,
                                                 p_method text default null, p_evidence_ref text default null, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
  v_method text := nullif(btrim(coalesce(p_method, '')), '');
  v_ref text := nullif(btrim(coalesce(p_evidence_ref, '')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select verification_status into v_status from public.company_users
  where company_id = p_company and user_id = p_user for update;
  if v_status is null then raise exception 'Vínculo não encontrado.' using errcode = 'P0001'; end if;
  if p_decision not in ('verified', 'rejected', 'revoked') then raise exception 'Decisão inválida.' using errcode = 'P0001'; end if;
  if not ((v_status in ('pending', 'rejected') and p_decision in ('verified', 'rejected'))
          or (v_status = 'verified' and p_decision = 'revoked')
          or (v_status = 'revoked' and p_decision = 'verified')) then
    raise exception 'Transição não permitida a partir do estado atual.' using errcode = 'P0001';
  end if;
  if p_decision = 'verified' then
    if v_method is null or v_method not in ('callback', 'document_review') then
      raise exception 'Informe o método: ligação ou documento conferido.' using errcode = 'P0001';
    end if;
    if v_ref is null or char_length(v_ref) not between 3 and 200 then
      raise exception 'Informe a referência da conferência (3 a 200 caracteres, sem número de documento).' using errcode = 'P0001';
    end if;
  elsif v_reason is null or char_length(v_reason) not between 10 and 500 then
    raise exception 'Informe o motivo (10 a 500 caracteres).' using errcode = 'P0001';
  end if;

  insert into public.representative_verifications (company_id, user_id, decision, method, evidence_ref, reason, reviewer_id)
  values (p_company, p_user, p_decision,
          case when p_decision = 'verified' then v_method end,
          case when p_decision = 'verified' then v_ref end,
          v_reason, auth.uid());
  update public.company_users
  set verification_status = p_decision, verified_at = case when p_decision = 'verified' then now() else verified_at end
  where company_id = p_company and user_id = p_user;
end;
$$$s0$;
      execute $s0$-- 6) Histórico para a equipe.
create function public.ops_representative_history(p_company uuid)
returns table (user_id uuid, decision text, method text, evidence_ref text, reason text, reviewer_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select v.user_id, v.decision, v.method, v.evidence_ref, v.reason, v.reviewer_id, v.created_at
  from public.representative_verifications v where v.company_id = p_company order by v.created_at;
end;
$$$s0$;
      execute $s0$revoke execute on function public.ops_list_representatives(text), public.ops_verify_representative(uuid, uuid, text, text, text, text),
  public.ops_representative_history(uuid) from public, anon$s0$;
      execute $s0$grant execute on function public.ops_list_representatives(text), public.ops_verify_representative(uuid, uuid, text, text, text, text),
  public.ops_representative_history(uuid) to authenticated$s0$;
      res := res || jsonb_build_object('20261117120000', 'aplicada na transação de teste');
    end if;

    -- 20261117150000_pausa_do_piloto.sql (17 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117150000') then
      res := res || jsonb_build_object('20261117150000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0021: pausa do piloto pela equipe. Só aditiva, salvo create_complaint, que ganha a checagem no início.
-- Pausado: recusa nova manifestação. Preserva cadastro de conta (decisão do responsável), leitura, ajuste (share_complaint),
-- encerramento, avaliação, resposta da empresa e todo o trabalho da equipe. Formulário público de contato fica fora.
-- Convites e lembretes (ADR-0012) não existem ainda; quando existirem, chamam private.assert_pilot_open().
-- Estado inicial: 'open'.
--
-- Rollback: reaplicar create_complaint de 20261106130100 (sem a checagem); depois, se quiser remover tudo, exportar
--   public.pilot_state_log e: drop function public.ops_set_pilot_state(text, text), public.pilot_state(),
--   public.ops_pilot_state_log(), private.assert_pilot_open(); drop table public.pilot_state_log, private.platform_settings.

-- 1) Configuração da plataforma (linha única).
create table private.platform_settings (
  id boolean primary key default true check (id),
  pilot_state text not null default 'open' check (pilot_state in ('open', 'paused')),
  updated_at timestamptz not null default now(),
  updated_by uuid
)$s0$;
      execute $s0$insert into private.platform_settings (id) values (true)$s0$;
      execute $s0$revoke all on private.platform_settings from public, anon, authenticated$s0$;
      execute $s0$-- 2) Trilha das mudanças: só inserção e imutável (gatilho da 20261117120000).
create table public.pilot_state_log (
  id uuid primary key default gen_random_uuid(),
  previous_state text not null,
  new_state text not null check (new_state in ('open', 'paused')),
  reason text not null check (char_length(btrim(reason)) between 10 and 500),
  actor_user_id uuid not null,
  created_at timestamptz not null default now()
)$s0$;
      execute $s0$alter table public.pilot_state_log enable row level security$s0$;
      execute $s0$revoke all on public.pilot_state_log from public, anon, authenticated$s0$;
      execute $s0$create trigger pilot_state_log_immutable before update or delete on public.pilot_state_log
  for each row execute function private.block_trail_change()$s0$;
      execute $s0$-- 3) Estado público (o front mostra o aviso antes do formulário); sem quem pausou nem motivo.
create function public.pilot_state()
returns text language sql stable security definer set search_path = '' as $$
  select pilot_state from private.platform_settings where id;
$$$s0$;
      execute $s0$create function private.assert_pilot_open()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if (select pilot_state from private.platform_settings where id) = 'paused' then
    raise exception 'Novas manifestações estão temporariamente suspensas. Quem já tem caso aberto continua acompanhando normalmente.'
      using errcode = 'P0001';
  end if;
end;
$$$s0$;
      execute $s0$revoke all on function private.assert_pilot_open() from public, anon, authenticated$s0$;
      execute $s0$-- 4) Liga e desliga: só a equipe, com motivo.
create function public.ops_set_pilot_state(p_state text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_prev text; v_reason text := btrim(coalesce(p_reason, ''));
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_state not in ('open', 'paused') then raise exception 'Estado inválido.' using errcode = 'P0001'; end if;
  if char_length(v_reason) not between 10 and 500 then raise exception 'Informe o motivo (10 a 500 caracteres).' using errcode = 'P0001'; end if;
  select pilot_state into v_prev from private.platform_settings where id for update;
  if v_prev = p_state then raise exception 'O piloto já está nesse estado.' using errcode = 'P0001'; end if;
  update private.platform_settings set pilot_state = p_state, updated_at = now(), updated_by = auth.uid() where id;
  insert into public.pilot_state_log (previous_state, new_state, reason, actor_user_id) values (v_prev, p_state, v_reason, auth.uid());
end;
$$$s0$;
      execute $s0$create function public.ops_pilot_state_log()
returns table (previous_state text, new_state text, reason text, actor_user_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query select l.previous_state, l.new_state, l.reason, l.actor_user_id, l.created_at from public.pilot_state_log l order by l.created_at desc;
end;
$$$s0$;
      execute $s0$revoke execute on function public.pilot_state(), public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() from public$s0$;
      execute $s0$grant execute on function public.pilot_state() to anon, authenticated$s0$;
      execute $s0$revoke execute on function public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() from anon$s0$;
      execute $s0$grant execute on function public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() to authenticated$s0$;
      execute $s0$-- 5) Nova manifestação passa pela checagem (corpo de 20261106130100, só com a linha nova no início).
create or replace function public.create_complaint(p jsonb, p_share boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_worker uuid;
  v_id uuid;
  v_shared text := nullif(btrim(p ->> 'shared_content'), '');
begin
  perform private.assert_pilot_open();
  select id into v_worker from public.workers where user_id = auth.uid();
  if v_worker is null then raise exception 'Somente trabalhadores podem registrar manifestações.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.companies where id = (p ->> 'company_id')::uuid) then
    raise exception 'Empresa não encontrada.' using errcode = 'P0001';
  end if;
  if p_share and v_shared is null then raise exception 'Escreva a versão que poderá ser compartilhada com a empresa.' using errcode = 'P0001'; end if;

  insert into public.complaints (worker_id, company_id, category, title, incident_period, recurrence, expected_outcomes, status)
  values (
    v_worker, (p ->> 'company_id')::uuid, btrim(p ->> 'category'), btrim(p ->> 'title'),
    nullif(btrim(p ->> 'incident_period'), ''), nullif(btrim(p ->> 'recurrence'), ''),
    coalesce(array(select jsonb_array_elements_text(p -> 'expected_outcomes')), '{}'),
    case when p_share then 'in_review'::public.complaint_status else 'received'::public.complaint_status end
  )
  returning id into v_id;
  insert into public.complaint_originals (complaint_id, original_content) values (v_id, btrim(p ->> 'original_content'));
  insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'received', 'worker', 'Manifestação registrada.');
  if p_share then
    insert into public.complaint_shared_versions (complaint_id, shared_content) values (v_id, v_shared);
    insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'in_review', 'worker', 'Revisão solicitada. A equipe confere a versão antes de liberar à empresa.');
  end if;
  return v_id;
end;
$$$s0$;
      res := res || jsonb_build_object('20261117150000', 'aplicada na transação de teste');
    end if;

    -- 20261117130000_representante_verificado_gate.sql (8 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117130000') then
      res := res || jsonb_build_object('20261117130000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0012 (recorte do piloto), parte 2 de 2: troca do gate. Só o vínculo 'verified' vê e responde manifestações
-- e vê os próprios números; o vínculo 'pending', 'rejected' ou 'revoked' continua com portal, perfil e diretório.
-- Depende da 20261109180000 (respond_complaint com revisão) e da 20261117120000.
-- Fica em supabase/pending/ até o Front publicar a fila de verificação; só então é movida para supabase/migrations/.
-- Corpos copiados das últimas definições (170000, 150000, 180000), com is_company_user -> is_verified_company_user
-- e o filtro verification_status = 'verified' nas duas funções de números próprios. Mesmas assinaturas: os grants seguem.
--
-- ATENÇÃO na aplicação: todo vínculo existente nasce 'pending' pela 20261117120000. Depois desta migration, nenhuma
-- empresa vê manifestação até a equipe verificar o representante (ops_verify_representative).
--
-- Também: update_company_profile recusa vínculo 'rejected' ou 'revoked' (ajuste aceito pelo Gestor em 17/11, dentro da ADR-0012).
--
-- Rollback: reaplicar os mesmos blocos trocando is_verified_company_user por is_company_user e retirando o filtro
-- verification_status (texto pronto em supabase/tests/rollback/20261117130000_rollback.sql). Isso reabre o risco do
-- representante não verificado; só com decisão registrada.

create or replace function public.list_company_complaints()
returns table (id uuid, protocol text, category text, title text, status public.complaint_status, shared_content text,
               created_at timestamptz, updated_at timestamptz, responses integer, last_response_at timestamptz, worker_feedback public.complaint_feedback)
language sql stable security definer set search_path = '' as $$
  select c.id, c.protocol, c.category, c.title, c.status, s.shared_content, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select max(r.created_at) from public.company_responses r where r.complaint_id = c.id),
         c.worker_feedback
  from public.complaints c
  join public.complaint_shared_versions s on s.complaint_id = c.id
  where c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
  order by c.created_at desc;
$$$s0$;
      execute $s0$create or replace function public.get_company_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.kind, t.status, t.actor, t.content, t.created_at
  from (
    select 'event'::text as kind, e.status, e.actor, e.note as content, e.created_at, 4 as kind_rank, e.id
    from public.complaint_events e
    join public.complaints c on c.id = e.complaint_id
    where e.complaint_id = p_id and c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
      and e.status in ('shared', 'answered', 'closed')
    union all
    select 'response'::text, null::public.complaint_status, 'company'::public.complaint_actor, r.content, r.created_at, 2, r.id
    from public.company_responses r
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and public.is_verified_company_user(c.company_id)
    union all
    select 'response_review'::text, null::public.complaint_status, 'platform'::public.complaint_actor,
           case rv.decision when 'released' then 'Resposta liberada ao trabalhador.' else 'Resposta devolvida para ajuste: ' || rv.reason end,
           rv.created_at, 1, rv.id
    from public.company_response_reviews rv
    join public.company_responses r on r.id = rv.response_id
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and rv.decision in ('released', 'returned') and public.is_verified_company_user(c.company_id)
  ) t
  order by t.created_at, t.kind_rank, t.status nulls first, t.id;
$$$s0$;
      execute $s0$create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_verified_company_user(v_company) or v_status not in ('shared', 'answer_in_review', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if v_status = 'answer_in_review' or exists (select 1 from public.company_responses where complaint_id = p_id and review_status = 'in_review') then
    raise exception 'Já existe uma resposta em revisão pela equipe.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'in_review');
  update public.complaints set status = 'answer_in_review' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, 'answer_in_review', 'company', 'A empresa respondeu. A equipe revisa a resposta antes de você receber.');
end;
$$$s0$;
      execute $s0$create or replace function public.company_ranking()
returns table (company_id uuid, name text, city text, state text, received integer, response_rate integer, avg_first_response_hours integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state, s.released, round(s.rate)::int, round(s.avg_hours)::int,
         public.is_verified_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by 6 desc, 7 asc nulls last;
$$$s0$;
      execute $s0$create or replace function public.company_responsiveness()
returns table (company_id uuid, name text, city text, state text, response_band text, response_time_band text,
               satisfaction_band text, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state,
         private.response_band(s.rate), private.response_time_band(s.avg_hours),
         null::text, public.is_verified_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$$s0$;
      execute $s0$create or replace function public.my_company_responsiveness()
returns table (company_id uuid, name text, released integer, answered integer, response_rate integer,
               avg_first_response_hours integer, response_band text, response_time_band text, listed boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name),
         coalesce(s.released, 0), coalesce(s.answered, 0),
         round(s.rate)::int, round(s.avg_hours)::int,
         private.response_band(s.rate),
         case when coalesce(s.released, 0) = 0 then null else private.response_time_band(s.avg_hours) end,
         coalesce(s.released, 0) >= 3
  from public.company_users cu
  join public.companies co on co.id = cu.company_id
  left join private.company_response_stats() s on s.company_id = co.id
  where cu.user_id = auth.uid() and cu.verification_status = 'verified'
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$$s0$;
      execute $s0$create or replace function public.my_company_satisfaction()
returns table (company_id uuid, ratings integer, satisfaction_band text)
language sql stable security definer set search_path = '' as $$
  select cu.company_id, case when count(rr.response_id) < 3 then null else count(rr.response_id)::int end,
         case when count(rr.response_id) < 3 then null
              else private.response_band(100.0 * avg(case rr.rating when 'yes' then 1 when 'partial' then 0.5 else 0 end)) end
  from public.company_users cu
  left join public.company_responses r on r.company_id = cu.company_id
  left join public.response_ratings rr on rr.response_id = r.id
  where cu.user_id = auth.uid() and cu.verification_status = 'verified'
  group by cu.company_id;
$$$s0$;
      execute $s0$-- Vínculo recusado ou revogado também perde a edição do perfil da empresa (inclusive contato). 'pending' continua
-- editando para completar o cadastro. Corpo de 20261108120000 com a checagem nova depois da de dono.
create or replace function public.update_company_profile(p_company uuid, p jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.companies%rowtype;
  v_trade text; v_email text; v_phone text; v_changed text[] := '{}';
begin
  if not public.is_company_owner(p_company) then
    raise exception 'Só o responsável pela conta da empresa pode alterar estes dados.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.company_users where company_id = p_company and user_id = auth.uid()
             and verification_status in ('rejected', 'revoked')) then
    raise exception 'Vínculo com a empresa recusado ou revogado pela equipe.' using errcode = 'P0001';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Nada para atualizar.' using errcode = 'P0001'; end if;
  if p ? 'cnpj' or p ? 'legal_name' then raise exception 'CNPJ e razão social só podem ser alterados pela equipe.' using errcode = 'P0001'; end if;
  select * into c from public.companies where id = p_company for update;

  if p ? 'trade_name' then
    v_trade := nullif(btrim(coalesce(p ->> 'trade_name', '')), '');
    if char_length(coalesce(v_trade, '')) > 160 then raise exception 'O nome fantasia pode ter até 160 caracteres.' using errcode = 'P0001'; end if;
    if v_trade is distinct from c.trade_name then
      update public.companies set trade_name = v_trade where id = p_company; v_changed := v_changed || 'trade_name'::text;
    end if;
  end if;
  if p ? 'contact_email' then
    v_email := nullif(lower(btrim(coalesce(p ->> 'contact_email', ''))), '');
    if v_email is not null and (v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254) then
      raise exception 'Informe um e-mail de contato válido.' using errcode = 'P0001';
    end if;
    if v_email is distinct from c.contact_email then
      update public.companies set contact_email = v_email where id = p_company; v_changed := v_changed || 'contact_email'::text;
    end if;
  end if;
  if p ? 'contact_phone' then
    v_phone := nullif(regexp_replace(coalesce(p ->> 'contact_phone', ''), '\D', '', 'g'), '');
    if v_phone is not null and v_phone !~ '^[1-9][0-9](9[0-9]{8}|[2-5][0-9]{7})$' then
      raise exception 'Informe um telefone válido com DDD: celular com 9 dígitos ou fixo com 8.' using errcode = 'P0001';
    end if;
    if v_phone is distinct from c.contact_phone then
      update public.companies set contact_phone = v_phone where id = p_company; v_changed := v_changed || 'contact_phone'::text;
    end if;
  end if;
  if p ? 'address' then v_changed := v_changed || private.update_address(c.address_id, p -> 'address'); end if;

  if cardinality(v_changed) > 0 then
    insert into public.profile_change_log (actor_user_id, entity_type, entity_id, fields, source)
    values (auth.uid(), 'company', p_company, v_changed, 'self');
  end if;
end;
$$$s0$;
      res := res || jsonb_build_object('20261117130000', 'aplicada na transação de teste');
    end if;

    -- 20261118120000_empresa_pre_cadastrada_estrutura.sql (28 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261118120000') then
      res := res || jsonb_build_object('20261118120000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0023 (aceita em 2026-11-17) e ADR-0017 (aceita em 2026-11-17), migration 1 de 2: estrutura.
-- Só aditiva. Não muda acesso de ninguém: tabelas novas sem grant para anon/authenticated; companies só ganha colunas.
-- Funciona com ou sem a Edge Function cnpj-lookup: sem ela, o cache fica vazio e o pré-cadastro segue pelo manual
-- (plano B); a cota vale para o pré-cadastro (banco) e para a busca (função).
-- Desvio registrado em relação ao ERD da ADR-0023: os dados de origem da empresa pré-cadastrada (município, UF,
-- situação, CNAE, natureza, provedor) ficam em private.company_preregistrations, e não em companies, para não expô-los
-- a quem lê companies e para não gravar quem criou a empresa (companies.created_by fica nulo: gravar o trabalhador
-- ligaria a conta ao empregador).
-- Sem enum novo: estados em text + check.
--
-- Rollback (antes da migration 2): drop function public.cnpj_cache_get(text), public.cnpj_cache_put(text, boolean, text, text,
--   text, text, text, text, text, text), public.cnpj_quota_take(uuid), private.take_quota(uuid, text, integer);
--   drop table private.notice_opt_outs, public.company_notices, public.complaint_contacts, private.company_preregistrations,
--   private.cnpj_lookup_quota, private.cnpj_cache; drop function private.company_notice_guard();
--   alter table public.companies drop constraint companies_address_when_registered, drop column data_source,
--   drop column registration_status;  -- e só então: alter column address_id set not null (exige nenhuma empresa sem endereço).

set local lock_timeout = '5s'$s0$;
      execute $s0$-- 1) Empresa pré-cadastrada: existe sem cadastro próprio, sem endereço completo e sem vínculo (ADR-0012 D9).
alter table public.companies
  add column registration_status text not null default 'registered'
    check (registration_status in ('registered', 'pre_registered', 'pending_check')),
  add column data_source text not null default 'signup'
    check (data_source in ('signup', 'cnpj_api', 'manual')),
  alter column address_id drop not null,
  add constraint companies_address_when_registered check (registration_status <> 'registered' or address_id is not null)$s0$;
      execute $s0$-- Dados de origem e conferência da equipe. Uma linha por empresa pré-cadastrada; não guarda quem a criou.
create table private.company_preregistrations (
  company_id uuid primary key references public.companies (id) on delete cascade,
  city text check (city is null or char_length(btrim(city)) between 2 and 80),
  state text check (state is null or state ~ '^[A-Z]{2}$'),
  cadastral_situation text check (cadastral_situation is null or char_length(cadastral_situation) <= 40),
  main_cnae text check (main_cnae is null or main_cnae ~ '^[0-9]{7}$'),
  legal_nature text check (legal_nature is null or legal_nature ~ '^[0-9]{3,4}$'),
  natural_person boolean not null default false,  -- MEI ou empresário individual: o aviso à empresa é recusado
  provider text check (provider is null or provider in ('minhareceita', 'brasilapi')),
  fetched_at timestamptz,
  review_decision text check (review_decision is null or review_decision in ('confirmed', 'blocked')),
  review_reason text check (review_reason is null or char_length(btrim(review_reason)) between 10 and 300),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (review_decision is distinct from 'blocked' or review_reason is not null)
)$s0$;
      execute $s0$revoke all on private.company_preregistrations from public, anon, authenticated$s0$;
      execute $s0$-- 2) Cache de dados públicos de pessoa jurídica (ADR-0017 D4 a D6, com a aceitação: não é apagado, é renovado).
-- Não registra quem consultou. Pessoa física fica só com a marca, sem nome.
create table private.cnpj_cache (
  cnpj text primary key check (cnpj ~ '^[0-9A-Z]{12}[0-9]{2}$'),
  natural_person boolean not null,
  legal_name text check (legal_name is null or char_length(legal_name) between 1 and 160),
  trade_name text check (trade_name is null or char_length(trade_name) <= 160),
  cadastral_situation text check (cadastral_situation is null or char_length(cadastral_situation) <= 40),
  city text check (city is null or char_length(city) <= 80),
  state text check (state is null or state ~ '^[A-Z]{2}$'),
  main_cnae text check (main_cnae is null or main_cnae ~ '^[0-9]{7}$'),
  legal_nature text check (legal_nature is null or legal_nature ~ '^[0-9]{3,4}$'),
  provider text not null check (provider in ('minhareceita', 'brasilapi')),
  fetched_at timestamptz not null default now(),
  check (not natural_person or (legal_name is null and trade_name is null)),
  check (natural_person or legal_name is not null)
)$s0$;
      execute $s0$revoke all on private.cnpj_cache from public, anon, authenticated$s0$;
      execute $s0$-- 3) Cota por conta, sem o CNPJ (ADR-0017 D9). 'minute'/'day': busca pela função; 'prereg_day': pré-cadastro no banco.
create table private.cnpj_lookup_quota (
  user_id uuid not null,
  window_kind text not null check (window_kind in ('minute', 'day', 'prereg_day')),
  window_start timestamptz not null,
  lookups integer not null default 0 check (lookups >= 0),
  primary key (user_id, window_kind, window_start)
)$s0$;
      execute $s0$revoke all on private.cnpj_lookup_quota from public, anon, authenticated$s0$;
      execute $s0$-- Conta uma tentativa e diz se ainda está dentro do limite. Apaga as janelas da conta com mais de 2 dias.
create function private.take_quota(p_user uuid, p_kind text, p_limit integer)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_start timestamptz; v_count integer;
begin
  if p_user is null or p_kind not in ('minute', 'day', 'prereg_day') then return false; end if;
  v_start := date_trunc(case when p_kind = 'minute' then 'minute' else 'day' end, now());
  delete from private.cnpj_lookup_quota where user_id = p_user and window_start < now() - interval '2 days';
  insert into private.cnpj_lookup_quota as q (user_id, window_kind, window_start, lookups) values (p_user, p_kind, v_start, 1)
  on conflict (user_id, window_kind, window_start) do update set lookups = q.lookups + 1
  returning lookups into v_count;
  return v_count <= p_limit;
end;
$$$s0$;
      execute $s0$revoke all on function private.take_quota(uuid, text, integer) from public, anon, authenticated$s0$;
      execute $s0$-- 4) Interface da Edge Function (service_role). O esquema private não é exposto pela API; estas três ficam em public,
-- executáveis só pela service_role. A assinatura de cnpj_cache_put é a lista branca: nada fora dela entra.
create function public.cnpj_cache_get(p_cnpj text)
returns table (natural_person boolean, legal_name text, trade_name text, cadastral_situation text, city text, state text,
               main_cnae text, legal_nature text, provider text, fetched_at timestamptz, stale boolean)
language sql stable security definer set search_path = '' as $$
  select c.natural_person, c.legal_name, c.trade_name, c.cadastral_situation, c.city, c.state, c.main_cnae, c.legal_nature,
         c.provider, c.fetched_at, c.fetched_at < now() - interval '30 days'
  from private.cnpj_cache c where c.cnpj = upper(regexp_replace(coalesce(p_cnpj, ''), '[^0-9A-Za-z]', '', 'g'));
$$$s0$;
      execute $s0$create function public.cnpj_cache_put(p_cnpj text, p_natural_person boolean, p_legal_name text, p_trade_name text,
                                      p_cadastral_situation text, p_city text, p_state text, p_main_cnae text,
                                      p_legal_nature text, p_provider text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_cnpj text := upper(regexp_replace(coalesce(p_cnpj, ''), '[^0-9A-Za-z]', '', 'g'));
  v_np boolean := coalesce(p_natural_person, true);  -- sem a informação, trata como pessoa física (sem nome)
  v_cnae text := regexp_replace(coalesce(p_main_cnae, ''), '\D', '', 'g');  -- lpad só até 7: lpad corta o que passa
  v_nature text := nullif(regexp_replace(coalesce(p_legal_nature, ''), '\D', '', 'g'), '');
  v_state text := upper(nullif(btrim(p_state), ''));
begin
  if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
  -- Valores fora do formato viram nulo em vez de erro: o provedor não tem contrato estável.
  if not v_np and nullif(btrim(p_legal_name), '') is null then v_np := true; end if;
  insert into private.cnpj_cache as c (cnpj, natural_person, legal_name, trade_name, cadastral_situation, city, state,
                                       main_cnae, legal_nature, provider, fetched_at)
  values (v_cnpj, v_np,
          case when v_np then null else left(btrim(p_legal_name), 160) end,
          case when v_np then null else left(nullif(btrim(p_trade_name), ''), 160) end,
          left(nullif(btrim(p_cadastral_situation), ''), 40), left(nullif(btrim(p_city), ''), 80),
          case when v_state ~ '^[A-Z]{2}$' then v_state end,
          case when char_length(v_cnae) between 5 and 7 then lpad(v_cnae, 7, '0') end,
          case when v_nature ~ '^[0-9]{3,4}$' then v_nature end, p_provider, now())
  on conflict (cnpj) do update set
    natural_person = excluded.natural_person, legal_name = excluded.legal_name, trade_name = excluded.trade_name,
    cadastral_situation = excluded.cadastral_situation, city = excluded.city, state = excluded.state,
    main_cnae = excluded.main_cnae, legal_nature = excluded.legal_nature, provider = excluded.provider, fetched_at = now();
end;
$$$s0$;
      execute $s0$-- Cota da busca: 10 por minuto e 50 por dia por conta (ADR-0017 D9). Devolve false acima do limite.
create function public.cnpj_quota_take(p_user uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  return private.take_quota(p_user, 'minute', 10) and private.take_quota(p_user, 'day', 50);
end;
$$$s0$;
      execute $s0$revoke all on function public.cnpj_cache_get(text),
  public.cnpj_cache_put(text, boolean, text, text, text, text, text, text, text, text),
  public.cnpj_quota_take(uuid) from public, anon, authenticated$s0$;
      execute $s0$grant execute on function public.cnpj_cache_get(text),
  public.cnpj_cache_put(text, boolean, text, text, text, text, text, text, text, text),
  public.cnpj_quota_take(uuid) to service_role$s0$;
      execute $s0$-- 5) Contato indicado pelo trabalhador para o aviso (ADR-0012 D4, mínimo: só e-mail). A empresa nunca lê.
create table public.complaint_contacts (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null unique references public.complaints (id) on delete cascade,
  email text not null check (char_length(email) <= 254 and email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  possibly_involved boolean not null,
  worker_consented boolean not null check (worker_consented),
  status text not null default 'candidate' check (status in ('candidate', 'verified', 'rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
)$s0$;
      execute $s0$alter table public.complaint_contacts enable row level security$s0$;
      execute $s0$revoke all on public.complaint_contacts from public, anon, authenticated$s0$;
      execute $s0$-- 6) Avisos: decisão da equipe e envio. Só inserção; a única mudança aceita é approved -> sent|bounced, sent -> bounced e o
-- set null das chaves (contato apagado pela retenção, manifestação apagada com a conta).
create table public.company_notices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  complaint_id uuid references public.complaints (id) on delete set null,
  contact_id uuid references public.complaint_contacts (id) on delete set null,
  status text not null check (status in ('approved', 'sent', 'rejected', 'bounced')),
  reason text check (reason is null or char_length(btrim(reason)) between 10 and 300),
  decided_by uuid not null,
  decided_at timestamptz not null default now(),
  sent_by uuid,
  sent_at timestamptz,
  check (status <> 'rejected' or reason is not null)
)$s0$;
      execute $s0$create unique index company_notices_one_active on public.company_notices (complaint_id) where status in ('approved', 'sent')$s0$;
      execute $s0$create index company_notices_company_idx on public.company_notices (company_id, decided_at)$s0$;
      execute $s0$alter table public.company_notices enable row level security$s0$;
      execute $s0$revoke all on public.company_notices from public, anon, authenticated$s0$;
      execute $s0$create function private.company_notice_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.id = old.id and new.company_id = old.company_id and new.decided_by = old.decided_by
     and new.decided_at = old.decided_at and new.reason is not distinct from old.reason then
    -- set null das chaves estrangeiras, sem outra mudança
    if new.status = old.status and new.sent_by is not distinct from old.sent_by and new.sent_at is not distinct from old.sent_at
       and (new.complaint_id is not distinct from old.complaint_id or new.complaint_id is null)
       and (new.contact_id is not distinct from old.contact_id or new.contact_id is null) then
      return new;
    end if;
    -- envio ou devolução
    if new.complaint_id is not distinct from old.complaint_id and new.contact_id is not distinct from old.contact_id
       and ((old.status = 'approved' and new.status in ('sent', 'bounced')) or (old.status = 'sent' and new.status = 'bounced')) then
      return new;
    end if;
  end if;
  raise exception 'Registro de aviso não pode ser alterado nem apagado.' using errcode = 'P0001';
end;
$$$s0$;
      execute $s0$revoke all on function private.company_notice_guard() from public, anon, authenticated$s0$;
      execute $s0$create trigger company_notices_guard before update or delete on public.company_notices
  for each row execute function private.company_notice_guard()$s0$;
      execute $s0$-- 7) Quem pediu para não receber avisos: só o hash do e-mail normalizado (ADR-0012 D8).
create table private.notice_opt_outs (
  email_hash text primary key check (email_hash ~ '^[0-9a-f]{64}$'),
  added_by uuid not null,
  created_at timestamptz not null default now()
)$s0$;
      execute $s0$revoke all on private.notice_opt_outs from public, anon, authenticated$s0$;
      res := res || jsonb_build_object('20261118120000', 'aplicada na transação de teste');
    end if;

    -- 20261118130000_empresa_pre_cadastrada_funcoes.sql (16 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261118130000') then
      res := res || jsonb_build_object('20261118130000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0023 e ADR-0017 (aceitas em 2026-11-17), migration 2 de 2: funções.
-- Depende de 20261118120000 (estrutura) e de 20261117150000 (create_complaint com a checagem da pausa).
-- Pré-requisito de operação: 20261117130000 (troca do gate) aplicada antes de qualquer aviso sair, porque a empresa
-- avisada vai se cadastrar.
--
-- Empresa pré-cadastrada fora do diretório, do ranking, da responsividade, da lista dos parceiros e de ops_list_companies:
-- essas funções fazem join interno com addresses, e a pré-cadastrada não tem endereço (check da migration 1). O teste
-- confere; nenhuma delas é redefinida aqui.
-- Lacuna conhecida até a migration da reivindicação (D11): cadastro de empresa com CNPJ pré-cadastrado falha por CNPJ
-- duplicado; a equipe orienta e liga a conta.
--
-- Rollback: reaplicar create_complaint de 20261117150000; depois
--   drop function public.find_company_by_cnpj(text), public.preregister_company(text),
--     public.preregister_company_manual(text, text, text, text), public.ops_list_pending_companies(),
--     public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
--     public.ops_decide_notice(uuid, text, text), public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
--     public.ops_purge_expired_contacts(), private.norm_cnpj(text), private.email_hash(text);

-- Normalização comum.
create function private.norm_cnpj(p text)
returns text language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g'));
$$$s0$;
      execute $s0$create function private.email_hash(p text)
returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(lower(btrim(coalesce(p, ''))), 'UTF8')), 'hex');
$$$s0$;
      execute $s0$revoke all on function private.norm_cnpj(text), private.email_hash(text) from public, anon, authenticated$s0$;
      execute $s0$-- 1) Busca na base própria. Não informa se a empresa é pré-cadastrada nem se tem manifestação. Conta na cota da busca.
create function public.find_company_by_cnpj(p_cnpj text)
returns table (id uuid, name text, city text, state text)
language plpgsql security definer set search_path = '' as $$
declare v_cnpj text := private.norm_cnpj(p_cnpj);
begin
  if auth.uid() is null then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
  if not (private.take_quota(auth.uid(), 'minute', 10) and private.take_quota(auth.uid(), 'day', 50)) then
    raise exception 'Limite de consultas atingido. Tente mais tarde.' using errcode = 'P0001';
  end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), coalesce(a.city, pr.city), coalesce(a.state, pr.state)
  from public.companies co
  left join public.addresses a on a.id = co.address_id
  left join private.company_preregistrations pr on pr.company_id = co.id
  where co.cnpj = v_cnpj;
end;
$$$s0$;
      execute $s0$-- 2) Pré-cadastro a partir do cache gravado pela Edge Function (ADR-0017 D8). Nunca com dados enviados pelo cliente.
create function public.preregister_company(p_cnpj text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_cnpj text := private.norm_cnpj(p_cnpj); v_id uuid; c record;
begin
  if auth.uid() is null then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
  select co.id into v_id from public.companies co where co.cnpj = v_cnpj;
  if v_id is not null then return v_id; end if;
  select * into c from private.cnpj_cache where cnpj = v_cnpj;
  if not found or c.natural_person then
    raise exception 'Dados da empresa indisponíveis. Preencha os dados manualmente.' using errcode = 'P0001';
  end if;
  if not private.take_quota(auth.uid(), 'prereg_day', 3) then
    raise exception 'Limite de cadastros de empresa atingido hoje. Tente amanhã.' using errcode = 'P0001';
  end if;
  insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by, registration_status, data_source)
  values (c.legal_name, c.trade_name, v_cnpj, null, null, 'pre_registered', 'cnpj_api')
  on conflict (cnpj) do nothing
  returning id into v_id;
  if v_id is null then  -- outra conta criou ao mesmo tempo
    select co.id into v_id from public.companies co where co.cnpj = v_cnpj;
    return v_id;
  end if;
  insert into private.company_preregistrations (company_id, city, state, cadastral_situation, main_cnae, legal_nature,
                                                natural_person, provider, fetched_at)
  values (v_id, c.city, c.state, c.cadastral_situation, c.main_cnae, c.legal_nature, false, c.provider, c.fetched_at);
  return v_id;
end;
$$$s0$;
      execute $s0$-- 3) Plano B: API fora do ar, CNPJ não encontrado ou pessoa física. Nasce pending_check para a equipe conferir.
create function public.preregister_company_manual(p_cnpj text, p_name text, p_city text, p_state text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_cnpj text := private.norm_cnpj(p_cnpj);
  v_name text := btrim(coalesce(p_name, ''));
  v_city text := btrim(coalesce(p_city, ''));
  v_state text := upper(btrim(coalesce(p_state, '')));
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
  select co.id into v_id from public.companies co where co.cnpj = v_cnpj;
  if v_id is not null then return v_id; end if;
  if char_length(v_name) not between 2 and 160 then raise exception 'Informe o nome da empresa (2 a 160 caracteres).' using errcode = 'P0001'; end if;
  if char_length(v_city) not between 2 and 80 then raise exception 'Informe o município da empresa.' using errcode = 'P0001'; end if;
  if v_state not in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS',
                     'RO','RR','SC','SP','SE','TO') then
    raise exception 'Informe a UF da empresa.' using errcode = 'P0001';
  end if;
  if not private.take_quota(auth.uid(), 'prereg_day', 3) then
    raise exception 'Limite de cadastros de empresa atingido hoje. Tente amanhã.' using errcode = 'P0001';
  end if;
  insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by, registration_status, data_source)
  values (v_name, null, v_cnpj, null, null, 'pending_check', 'manual')
  on conflict (cnpj) do nothing
  returning id into v_id;
  if v_id is null then
    select co.id into v_id from public.companies co where co.cnpj = v_cnpj;
    return v_id;
  end if;
  insert into private.company_preregistrations (company_id, city, state, natural_person)
  values (v_id, v_city, v_state, coalesce((select natural_person from private.cnpj_cache where cnpj = v_cnpj), false));
  return v_id;
end;
$$$s0$;
      execute $s0$-- 4) Nova manifestação: corpo de 20261117150000 (com a checagem da pausa) + contato opcional para o aviso.
-- p.notice_contact = {"email": "...", "possibly_involved": true|false, "consent": true}. Só para empresa não cadastrada e
-- só quando a versão vai para revisão (p_share); o aviso depende da equipe (ops_decide_notice).
create or replace function public.create_complaint(p jsonb, p_share boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_worker uuid;
  v_id uuid;
  v_shared text := nullif(btrim(p ->> 'shared_content'), '');
  v_contact jsonb := p -> 'notice_contact';
  v_email text;
  v_company_status text;
begin
  perform private.assert_pilot_open();
  select id into v_worker from public.workers where user_id = auth.uid();
  if v_worker is null then raise exception 'Somente trabalhadores podem registrar manifestações.' using errcode = 'P0001'; end if;
  select registration_status into v_company_status from public.companies where id = (p ->> 'company_id')::uuid;
  if v_company_status is null then
    raise exception 'Empresa não encontrada.' using errcode = 'P0001';
  end if;
  if p_share and v_shared is null then raise exception 'Escreva a versão que poderá ser compartilhada com a empresa.' using errcode = 'P0001'; end if;
  if v_contact is not null and jsonb_typeof(v_contact) <> 'null' then
    if jsonb_typeof(v_contact) <> 'object' then raise exception 'Contato para o aviso inválido.' using errcode = 'P0001'; end if;
    if not p_share then
      raise exception 'O aviso à empresa só é possível quando você envia a versão compartilhável para revisão.' using errcode = 'P0001';
    end if;
    if v_company_status = 'registered' then
      raise exception 'Esta empresa já está cadastrada; o aviso não se aplica.' using errcode = 'P0001';
    end if;
    v_email := lower(btrim(coalesce(v_contact ->> 'email', '')));
    if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'Informe um e-mail válido para o aviso.' using errcode = 'P0001';
    end if;
    if jsonb_typeof(v_contact -> 'possibly_involved') is distinct from 'boolean' then
      raise exception 'Responda se a pessoa desse e-mail pode estar envolvida no que você relata.' using errcode = 'P0001';
    end if;
    if jsonb_typeof(v_contact -> 'consent') is distinct from 'boolean' or not (v_contact ->> 'consent')::boolean then
      raise exception 'Para indicar o e-mail, confirme que a empresa receberá o aviso de que existe um relato.' using errcode = 'P0001';
    end if;
  end if;

  insert into public.complaints (worker_id, company_id, category, title, incident_period, recurrence, expected_outcomes, status)
  values (
    v_worker, (p ->> 'company_id')::uuid, btrim(p ->> 'category'), btrim(p ->> 'title'),
    nullif(btrim(p ->> 'incident_period'), ''), nullif(btrim(p ->> 'recurrence'), ''),
    coalesce(array(select jsonb_array_elements_text(p -> 'expected_outcomes')), '{}'),
    case when p_share then 'in_review'::public.complaint_status else 'received'::public.complaint_status end
  )
  returning id into v_id;
  insert into public.complaint_originals (complaint_id, original_content) values (v_id, btrim(p ->> 'original_content'));
  insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'received', 'worker', 'Manifestação registrada.');
  if p_share then
    insert into public.complaint_shared_versions (complaint_id, shared_content) values (v_id, v_shared);
    insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'in_review', 'worker', 'Revisão solicitada. A equipe confere a versão antes de liberar à empresa.');
  end if;
  if v_email is not null then
    insert into public.complaint_contacts (complaint_id, email, possibly_involved, worker_consented)
    values (v_id, v_email, (v_contact ->> 'possibly_involved')::boolean, true);
  end if;
  return v_id;
end;
$$$s0$;
      execute $s0$-- 5) Equipe: empresas fora do cadastro, para conferir na Receita.
create function public.ops_list_pending_companies()
returns table (company_id uuid, name text, cnpj text, city text, state text, registration_status text, data_source text,
               natural_person boolean, cadastral_situation text, review_decision text, review_reason text, created_at timestamptz,
               complaints integer, last_notice_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), co.cnpj, pr.city, pr.state, co.registration_status, co.data_source,
         coalesce(pr.natural_person, false), pr.cadastral_situation, pr.review_decision, pr.review_reason, co.created_at,
         (select count(*)::int from public.complaints c where c.company_id = co.id and c.status not in ('received', 'canceled')),
         (select max(n.decided_at) from public.company_notices n where n.company_id = co.id and n.status in ('approved', 'sent'))
  from public.companies co
  left join private.company_preregistrations pr on pr.company_id = co.id
  where co.registration_status <> 'registered'
  order by (co.registration_status = 'pending_check') desc, co.created_at;
end;
$$$s0$;
      execute $s0$-- Conferência: confirmed (dados batem na Receita) ou blocked (dado errado; nenhum aviso). Pode marcar pessoa física.
create function public.ops_review_company(p_company uuid, p_decision text, p_reason text default null,
                                          p_natural_person boolean default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select registration_status into v_status from public.companies where id = p_company for update;
  if v_status is null or v_status = 'registered'
     or not exists (select 1 from private.company_preregistrations where company_id = p_company) then
    raise exception 'Empresa não está pré-cadastrada.' using errcode = 'P0001';
  end if;
  if p_decision not in ('confirmed', 'blocked') then raise exception 'Decisão inválida.' using errcode = 'P0001'; end if;
  if p_decision = 'blocked' and (v_reason is null or char_length(v_reason) not between 10 and 300) then
    raise exception 'Informe o motivo (10 a 300 caracteres, sem conteúdo de relato).' using errcode = 'P0001';
  end if;
  update private.company_preregistrations
  set review_decision = p_decision, review_reason = case when p_decision = 'blocked' then v_reason end,
      natural_person = coalesce(p_natural_person, natural_person), reviewed_by = auth.uid(), reviewed_at = now()
  where company_id = p_company;
  if p_decision = 'confirmed' and v_status = 'pending_check' then
    update public.companies set registration_status = 'pre_registered' where id = p_company;
  end if;
end;
$$$s0$;
      execute $s0$-- 6) Equipe: manifestações com e-mail indicado para o aviso.
create function public.ops_list_notice_candidates()
returns table (complaint_id uuid, protocol text, complaint_status public.complaint_status, company_id uuid, company_name text,
               registration_status text, natural_person boolean, review_decision text, contact_id uuid, email text,
               possibly_involved boolean, contact_status text, opted_out boolean, last_company_notice_at timestamptz,
               notice_id uuid, notice_status text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select c.id, c.protocol, c.status, co.id, coalesce(co.trade_name, co.legal_name), co.registration_status,
         coalesce(pr.natural_person, false), pr.review_decision, k.id, k.email, k.possibly_involved, k.status,
         exists (select 1 from private.notice_opt_outs o where o.email_hash = private.email_hash(k.email)),
         (select max(n.decided_at) from public.company_notices n where n.company_id = co.id and n.status in ('approved', 'sent')),
         ln.id, ln.status
  from public.complaint_contacts k
  join public.complaints c on c.id = k.complaint_id
  join public.companies co on co.id = c.company_id
  left join private.company_preregistrations pr on pr.company_id = co.id
  left join lateral (select n.id, n.status from public.company_notices n where n.complaint_id = c.id
                     order by n.decided_at desc limit 1) ln on true
  order by (k.status = 'candidate') desc, k.created_at;
end;
$$$s0$;
      execute $s0$-- Decisão do aviso. As travas valem no banco (ADR-0023, variante a).
create function public.ops_decide_notice(p_complaint uuid, p_decision text, p_reason text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_status public.complaint_status; v_company uuid; k record; co record; pr record; v_id uuid;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_decision not in ('approved', 'rejected') then raise exception 'Decisão inválida.' using errcode = 'P0001'; end if;
  select status, company_id into v_status, v_company from public.complaints where id = p_complaint for update;
  select * into k from public.complaint_contacts where complaint_id = p_complaint for update;
  if v_status is null or k.id is null then raise exception 'Manifestação sem e-mail indicado para aviso.' using errcode = 'P0001'; end if;
  if k.status <> 'candidate' then raise exception 'O aviso desta manifestação já foi decidido.' using errcode = 'P0001'; end if;
  -- Trava por empresa: duas decisões simultâneas para a mesma empresa não furam o intervalo de 30 dias.
  select id, registration_status into co from public.companies where id = v_company for update;
  select * into pr from private.company_preregistrations where company_id = v_company;

  if p_decision = 'rejected' then
    if v_reason is null or char_length(v_reason) not between 10 and 300 then
      raise exception 'Informe o motivo (10 a 300 caracteres, sem conteúdo de relato).' using errcode = 'P0001';
    end if;
    insert into public.company_notices (company_id, complaint_id, contact_id, status, reason, decided_by)
    values (v_company, p_complaint, k.id, 'rejected', v_reason, auth.uid()) returning id into v_id;
    update public.complaint_contacts set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now() where id = k.id;
    return v_id;
  end if;

  if v_status <> 'shared' then
    raise exception 'O aviso só sai depois que a equipe libera a manifestação (retida ou em revisão não recebe aviso).' using errcode = 'P0001';
  end if;
  if k.possibly_involved then
    raise exception 'O trabalhador marcou esse contato como possivelmente envolvido: aviso não permitido.' using errcode = 'P0001';
  end if;
  if exists (select 1 from private.notice_opt_outs where email_hash = private.email_hash(k.email)) then
    raise exception 'Este e-mail pediu para não receber avisos.' using errcode = 'P0001';
  end if;
  if co.registration_status = 'registered' then
    raise exception 'A empresa já é cadastrada; o aviso não se aplica.' using errcode = 'P0001';
  end if;
  if co.registration_status = 'pending_check' then
    raise exception 'Confira os dados da empresa antes do aviso.' using errcode = 'P0001';
  end if;
  if pr.review_decision = 'blocked' or coalesce(pr.natural_person, false) then
    raise exception 'Empresa bloqueada para aviso ou pessoa física/MEI: aviso não permitido.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.company_notices n where n.company_id = v_company and n.status in ('approved', 'sent')
             and n.decided_at > now() - interval '30 days') then
    raise exception 'A empresa já recebeu aviso nos últimos 30 dias.' using errcode = 'P0001';
  end if;

  insert into public.company_notices (company_id, complaint_id, contact_id, status, decided_by)
  values (v_company, p_complaint, k.id, 'approved', auth.uid()) returning id into v_id;
  update public.complaint_contacts set status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() where id = k.id;
  return v_id;
end;
$$$s0$;
      execute $s0$-- Registro do envio manual (a1): sent, ou bounced se o e-mail voltar.
create function public.ops_mark_notice_sent(p_notice uuid, p_outcome text default 'sent')
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select status into v_status from public.company_notices where id = p_notice for update;
  if v_status is null then raise exception 'Aviso não encontrado.' using errcode = 'P0001'; end if;
  if p_outcome = 'sent' and v_status = 'approved' then
    update public.company_notices set status = 'sent', sent_by = auth.uid(), sent_at = now() where id = p_notice;
  elsif p_outcome = 'bounced' and v_status in ('approved', 'sent') then
    update public.company_notices set status = 'bounced' where id = p_notice;
  else
    raise exception 'Mudança não permitida a partir do estado atual.' using errcode = 'P0001';
  end if;
end;
$$$s0$;
      execute $s0$-- Pedido de não receber avisos (atendido pela equipe; sem link no piloto).
create function public.ops_add_opt_out(p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail inválido.' using errcode = 'P0001';
  end if;
  insert into private.notice_opt_outs (email_hash, added_by) values (private.email_hash(v_email), auth.uid())
  on conflict (email_hash) do nothing;
end;
$$$s0$;
      execute $s0$-- Retenção do contato (decisão 5 da ADR-0023): 90 dias após o encerramento da manifestação ou a recusa do aviso.
-- A equipe roda até existir agendamento; a trilha de company_notices fica, com contact_id nulo.
create function public.ops_purge_expired_contacts()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  delete from public.complaint_contacts k
  using public.complaints c
  where c.id = k.complaint_id
    and ((c.status in ('closed', 'canceled') and c.closed_at < now() - interval '90 days')
         or (k.status = 'rejected' and k.reviewed_at < now() - interval '90 days'));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$$s0$;
      execute $s0$revoke execute on function public.find_company_by_cnpj(text), public.preregister_company(text),
  public.preregister_company_manual(text, text, text, text), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text), public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() from public, anon$s0$;
      execute $s0$grant execute on function public.find_company_by_cnpj(text), public.preregister_company(text),
  public.preregister_company_manual(text, text, text, text), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text), public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() to authenticated$s0$;
      res := res || jsonb_build_object('20261118130000', 'aplicada na transação de teste');
    end if;

    -- 20261118140000_reivindicacao_cnpj.sql (2 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261118140000') then
      res := res || jsonb_build_object('20261118140000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0023 / ADR-0012 D11 (aceitas em 2026-11-17), migration 3: reivindicação da empresa pré-cadastrada no cadastro.
-- Prioridade do responsável (2026-11-18, via Gestor): a empresa avisada precisa conseguir se cadastrar; sem isto, o
-- cadastro falha por CNPJ duplicado. Não pode ser cortada.
-- Muda private.create_profile (gatilho do signUp e add_profile), só no ramo 'company':
--   - CNPJ pré-cadastrado (pre_registered ou pending_check): a conta reivindica: dados e endereço do cadastro,
--     created_by = conta, registration_status = 'registered', vínculo 'owner' com verification_status 'pending'.
--   - CNPJ que veio de pré-cadastro e já foi reivindicado: a conta entra como 'member' 'pending'.
--   - CNPJ de empresa que se cadastrou direto (data_source 'signup'): sem mudança (falha por CNPJ duplicado, como hoje).
--   - Demais tipos de conta: corpo idêntico ao de 20261109140000.
-- Pré-requisito: troca do gate (20261117130000) aplicada; sem ela, quem reivindica veria os casos liberados sem
-- verificação. A trava abaixo recusa a migration se list_company_complaints ainda não usar is_verified_company_user.
--
-- Rollback: reaplicar private.create_profile de 20261109140000_cpf_unico.sql. Empresas já reivindicadas continuam
-- registered, com o dono e o endereço do cadastro.

do $trava$
begin
  if not exists (select 1 from pg_proc where oid = to_regprocedure('public.list_company_complaints()')
                 and prosrc like '%is_verified_company_user%') then
    raise exception 'A troca do gate (20261117130000) não está aplicada. A reivindicação não pode entrar antes dela.';
  end if;
  if to_regclass('private.company_preregistrations') is null then
    raise exception 'A estrutura da empresa pré-cadastrada (20261118120000) não está aplicada.';
  end if;
end $trava$$s0$;
      execute $s0$create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
  v_doc text;
  v_reg text;
  v_src text;
begin
  if p_user is null then raise exception 'usuário obrigatório' using errcode = '22023'; end if;
  if p is null then raise exception 'dados do cadastro obrigatórios' using errcode = '22023'; end if;
  if p_type not in ('worker', 'company', 'partner', 'sponsor') then
    raise exception 'tipo de conta inválido' using errcode = '22023';
  end if;

  if p_type = 'worker' or (p_type = 'partner' and p ->> 'document_type' = 'cpf') then
    v_doc := regexp_replace(coalesce(p ->> case when p_type = 'worker' then 'cpf' else 'document' end, ''), '\D', '', 'g');
    if not private.valid_cpf(v_doc) then raise exception 'CPF inválido' using errcode = '22023'; end if;
  else
    v_doc := upper(regexp_replace(coalesce(p ->> case when p_type = 'partner' then 'document' else 'cnpj' end, ''), '[^0-9A-Za-z]', '', 'g'));
    if not private.valid_cnpj(v_doc) then raise exception 'CNPJ inválido' using errcode = '22023'; end if;
  end if;

  v_address := private.create_address(p -> 'address');

  if p_type = 'worker' then
    begin
      insert into public.workers (user_id, full_name, cpf, phone, address_id)
      values (p_user, btrim(p ->> 'full_name'), v_doc,
              nullif(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), ''), v_address)
      returning id into v_id;
    exception when unique_violation then
      -- CPF de outro trabalhador ou conta que já tem perfil de trabalhador: mensagem genérica, sem o valor.
      raise exception 'Não foi possível concluir o cadastro.' using errcode = '23505';
    end;
  elsif p_type = 'company' then
    select c.id, c.registration_status, c.data_source into v_id, v_reg, v_src from public.companies c where c.cnpj = v_doc for update;
    if v_id is not null and v_reg <> 'registered' then
      -- D11: a primeira conta reivindica a empresa pré-cadastrada. Vira dona com vínculo 'pending' (default da 120000);
      -- o acesso a manifestações depende da verificação da equipe (130000).
      update public.companies
      set legal_name = btrim(p ->> 'legal_name'), trade_name = nullif(btrim(p ->> 'trade_name'), ''), address_id = v_address,
          created_by = p_user, registration_status = 'registered'
      where id = v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    elsif v_id is not null and v_src <> 'signup' then
      -- D11: empresa que veio de pré-cadastro e já foi reivindicada: a conta seguinte entra como membro 'pending', nunca
      -- como dona. Evita que quem reivindicou primeiro tranque a empresa verdadeira fora da plataforma; a equipe decide.
      -- Sem assinatura nova: a empresa já tem a da conta que reivindicou (subscriptions não tem unique por empresa).
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'member');
    else
      insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
      values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), v_doc, v_address, p_user)
      returning id into v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    end if;
  elsif p_type = 'partner' then
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type, v_doc,
      btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address
    )
    returning id into v_id;
    perform private.create_subscription('partner', p, null, v_id, null);
  else
    insert into public.sponsors (user_id, name, cnpj, address_id)
    values (p_user, btrim(p ->> 'name'), v_doc, v_address)
    returning id into v_id;
    perform private.create_subscription('sponsor', p, null, null, v_id);
  end if;
  return v_id;
end;
$$$s0$;
      res := res || jsonb_build_object('20261118140000', 'aplicada na transação de teste');
    end if;

    -- Verificações (reivindicacao_checks.sql)
    -- declare: u_w uuid := 'efffffff-ffff-ffff-ffff-ffffffffffff'; u_c1 uuid := 'f1111111-1111-1111-1111-111111111111'; u_c2 uuid := 'f2222222-2222-2222-2222-222222222222'; u_c3 uuid := 'f3333333-3333-3333-3333-333333333333'; u_op uuid := 'f4444444-4444-4444-4444-444444444444'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_pre text := '16180339000157'; cnpj_reg text := '14142135000104'; co uuid; cp uuid; r record;
    -- Verificações da reivindicação (20261118140000, ADR-0012 D11) depois da troca do gate e das migrations 1 e 2, na
    -- transação de teste. Os CNPJs e o CPF são de teste; se existirem em produção, o teste para antes de criar dados.
    if exists (select 1 from public.companies where cnpj in (cnpj_pre, cnpj_reg)) or exists (select 1 from public.workers where cpf = '31415926590') then
      raise exception 'Valor de teste já existe em produção; troque os CNPJs/CPF do teste.';
    end if;
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-rw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Reivindica Trabalhador', 'cpf', '31415926590', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c3, 'authenticated', 'authenticated', 'tx-rc3@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Cadastro Direto Ltda', 'cnpj', cnpj_reg, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-rop@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    
    -- Trabalhador pré-cadastra e relata; equipe libera.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    co := public.preregister_company_manual(cnpj_pre, 'Tx Nome Digitado Pelo Trabalhador', 'Santos', 'SP');
    cp := public.create_complaint(jsonb_build_object('company_id', co, 'category', 'Carga de trabalho', 'title', 'Tx caso reivindicação',
      'original_content', 'Tx relato original.', 'shared_content', 'Tx versao compartilhavel.'), true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_complaint(cp, 'released', null);
    execute 'reset role';
    
    -- Primeira conta da empresa reivindica.
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_c1, 'authenticated', 'authenticated', 'tx-rc1@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Empresa Reivindicada Ltda', 'cnpj', '16.180.339/0001-57', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
    select c.registration_status, c.legal_name, c.address_id, c.created_by into r from public.companies c where c.id = co;
    if r.registration_status is distinct from 'registered' or r.legal_name is distinct from 'Tx Empresa Reivindicada Ltda'
       or r.address_id is null or r.created_by is distinct from u_c1 then
      falhas := falhas || jsonb_build_object('reivindicação não passou a empresa a registered com os dados do cadastro', true);
    end if;
    select cu.role::text as role, cu.verification_status into r from public.company_users cu where cu.company_id = co and cu.user_id = u_c1;
    if r.role is distinct from 'owner' or r.verification_status is distinct from 'pending' then
      falhas := falhas || jsonb_build_object('quem reivindica não é owner pending', true);
    end if;
    if (select count(*) from public.companies where cnpj = cnpj_pre) <> 1 then falhas := falhas || jsonb_build_object('empresa duplicada', true); end if;
    
    -- Pending não vê o caso liberado (gate 130000).
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_c1, 'role', 'authenticated')::text, true);
    if exists (select 1 from public.list_company_complaints() l where l.id = cp) then
      falhas := falhas || jsonb_build_object('reivindicação sem verificação vê o caso', true);
    end if;
    execute 'reset role';
    
    -- Segunda conta: membro pending, nunca dona.
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_c2, 'authenticated', 'authenticated', 'tx-rc2@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Outra Razao', 'cnpj', cnpj_pre, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
    select cu.role::text as role, cu.verification_status into r from public.company_users cu where cu.company_id = co and cu.user_id = u_c2;
    if r.role is distinct from 'member' or r.verification_status is distinct from 'pending' then
      falhas := falhas || jsonb_build_object('segunda conta não entrou como member pending', true);
    end if;
    if (select count(*) from public.subscriptions where company_id = co) <> 1 then
      falhas := falhas || jsonb_build_object('assinatura duplicada para a mesma empresa', true);
    end if;
    if (select legal_name from public.companies where id = co) is distinct from 'Tx Empresa Reivindicada Ltda' then
      falhas := falhas || jsonb_build_object('segunda conta trocou os dados da empresa', true);
    end if;
    
    -- Empresa de cadastro direto: CNPJ repetido continua recusado.
    begin
      insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', 'tx-rc4@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Repetida', 'cnpj', cnpj_reg, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
      falhas := falhas || jsonb_build_object('CNPJ de cadastro direto aceito duas vezes', true);
    exception when others then null; end;
    -- Trabalhador continua se cadastrando normalmente (outro ramo da função).
    if not exists (select 1 from public.workers where user_id = u_w) then falhas := falhas || jsonb_build_object('cadastro de trabalhador quebrou', true); end if;
    -- A empresa reivindicada sai da fila de pré-cadastradas.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    if exists (select 1 from public.ops_list_pending_companies() p where p.company_id = co) then
      falhas := falhas || jsonb_build_object('reivindicada continua na fila de pré-cadastradas', true);
    end if;
    execute 'reset role';
    res := res || jsonb_build_object('verificações da reivindicação', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
