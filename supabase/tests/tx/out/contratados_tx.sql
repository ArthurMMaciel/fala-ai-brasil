-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar contratados_checks.sql e as migrations.
-- Migrations: 20261109180000_resposta_revisada_ativa.sql, 20261117120000_representante_verificado_estrutura.sql, 20261117130000_representante_verificado_gate.sql, 20261118150000_empresa_contratados.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_ca uuid := 'f6666666-6666-6666-6666-666666666666'; u_cam uuid := 'f7777777-7777-7777-7777-777777777777'; u_cb uuid := 'f8888888-8888-8888-8888-888888888888'; u_p1 uuid := 'f9999999-9999-9999-9999-999999999999'; u_p2 uuid := 'faaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; u_op uuid := 'fbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_a text := '98765006987676'; cnpj_b text := '98765007987610'; co_a uuid; co_b uuid; p1 uuid; p2 uuid; n int;
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

    -- 20261118150000_empresa_contratados.sql (4 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261118150000') then
      res := res || jsonb_build_object('20261118150000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- Fluxo 2 do teste ponta a ponta (pedido do Gestor, 2026-11-18): a empresa vê, na aba "Contratados", os parceiros que a
-- marcaram como cliente (partner_connections.stage = 'client').
-- Só função; nenhuma tabela, coluna ou policy muda. Coerente com a troca do gate (20261117130000): só vínculo verificado.
--   1) list_my_contracted_partners(): parceiros com stage 'client' para as empresas em que a conta tem vínculo verified.
--      Devolve só o que o diretório de parceiros já mostra (nome, especialidade, descrição, foto, município, UF). O parceiro
--      não tem contato público no banco hoje; incluir e-mail/telefone exige colunas novas (decisão de modelo, à parte).
--   2) company_request_partner passa a exigir vínculo verified: com a D11 (20261118140000) qualquer conta entra como
--      membro pending de uma empresa cadastrada, e o pedido de contato libera ao parceiro o e-mail e o telefone de contato
--      da empresa (list_partner_companies, estágio company_interest). Sem verificação, uma conta não confirmada falaria em
--      nome da empresa e exporia o contato dela.
--
-- Rollback: drop function public.list_my_contracted_partners(); reaplicar company_request_partner de
--   20261027024534_mvp_manifestacoes_e_conexoes.sql.

create function public.list_my_contracted_partners()
returns table (partner_id uuid, company_id uuid, display_name text, specialty text, description text, avatar_path text,
               city text, state text, since timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, pc.company_id, p.display_name, p.specialty, p.description, m.storage_path, a.city, a.state, pc.updated_at
  from public.partner_connections pc
  join public.company_users cu on cu.company_id = pc.company_id and cu.user_id = auth.uid() and cu.verification_status = 'verified'
  join public.partners p on p.id = pc.partner_id
  join public.addresses a on a.id = p.address_id
  left join public.media m on m.id = p.avatar_media_id
  where pc.stage = 'client'
  order by p.display_name, p.id;
$$$s0$;
      execute $s0$revoke execute on function public.list_my_contracted_partners() from public, anon, service_role$s0$;
      execute $s0$grant execute on function public.list_my_contracted_partners() to authenticated$s0$;
      execute $s0$-- Pedido de contato só por vínculo verificado; com mais de uma empresa verificada, a mais antiga (comportamento de antes).
create or replace function public.company_request_partner(p_partner uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid;
begin
  select company_id into v_company from public.company_users
  where user_id = auth.uid() and verification_status = 'verified' order by created_at limit 1;
  if v_company is null then
    if exists (select 1 from public.company_users where user_id = auth.uid()) then
      raise exception 'Seu vínculo com a empresa ainda não foi verificado pela equipe.' using errcode = 'P0001';
    end if;
    raise exception 'Somente empresas podem sinalizar interesse.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.partners where id = p_partner) then raise exception 'Parceiro não encontrado.' using errcode = 'P0001'; end if;
  insert into public.partner_connections (partner_id, company_id, stage) values (p_partner, v_company, 'company_interest')
  on conflict (partner_id, company_id) do nothing;
end;
$$$s0$;
      res := res || jsonb_build_object('20261118150000', 'aplicada na transação de teste');
    end if;

    -- Verificações (contratados_checks.sql)
    -- declare: u_ca uuid := 'f6666666-6666-6666-6666-666666666666'; u_cam uuid := 'f7777777-7777-7777-7777-777777777777'; u_cb uuid := 'f8888888-8888-8888-8888-888888888888'; u_p1 uuid := 'f9999999-9999-9999-9999-999999999999'; u_p2 uuid := 'faaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; u_op uuid := 'fbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_a text := '98765006987676'; cnpj_b text := '98765007987610'; co_a uuid; co_b uuid; p1 uuid; p2 uuid; n int;
    -- Verificações da aba Contratados (20261118150000) na transação de teste. CNPJs de teste conferidos como inexistentes
    -- (404 na Minha Receita e na BrasilAPI em 2026-11-18); CPFs de teste com dígitos válidos, só dentro da transação.
    if exists (select 1 from public.companies where cnpj in (cnpj_a, cnpj_b)) then
      raise exception 'Valor de teste já existe em produção; troque os CNPJs do teste.';
    end if;
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_ca, 'authenticated', 'authenticated', 'tx-kca@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Contratante Alfa Ltda', 'cnpj', cnpj_a, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_cb, 'authenticated', 'authenticated', 'tx-kcb@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Contratante Beta Ltda', 'cnpj', cnpj_b, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_p1, 'authenticated', 'authenticated', 'tx-kp1@teste.invalid', jsonb_build_object('signup_type', 'partner', 'signup', jsonb_build_object('display_name', 'Tx Parceira Um', 'document_type', 'cpf', 'document', '27182818205', 'specialty', 'Mediação', 'plan_id', 'partner-presence', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_p2, 'authenticated', 'authenticated', 'tx-kp2@teste.invalid', jsonb_build_object('signup_type', 'partner', 'signup', jsonb_build_object('display_name', 'Tx Parceira Dois', 'document_type', 'cpf', 'document', '31415926590', 'specialty', 'Ergonomia', 'plan_id', 'partner-presence', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_cam, 'authenticated', 'authenticated', 'tx-kcam@teste.invalid', '{}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-kop@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    select company_id into co_a from public.company_users where user_id = u_ca;
    select company_id into co_b from public.company_users where user_id = u_cb;
    select id into p1 from public.partners where user_id = u_p1;
    select id into p2 from public.partners where user_id = u_p2;
    insert into public.company_users (company_id, user_id, role) values (co_a, u_cam, 'member');  -- membro pending
    
    -- Equipe verifica os donos de Alfa e Beta.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_verify_representative(co_a, u_ca, 'verified', 'callback', 'Tx ligação ao telefone do site', null);
    perform public.ops_verify_representative(co_b, u_cb, 'verified', 'callback', 'Tx ligação ao telefone do site', null);
    
    -- Membro pending não pede contato; verificado pede.
    perform set_config('request.jwt.claims', json_build_object('sub', u_cam, 'role', 'authenticated')::text, true);
    begin
      perform public.company_request_partner(p1);
      falhas := falhas || jsonb_build_object('vínculo pending pede contato a parceiro', true);
    exception when others then
      if sqlerrm not like '%ainda não foi verificado%' then falhas := falhas || jsonb_build_object('mensagem do pending', sqlerrm); end if;
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
    perform public.company_request_partner(p1);
    perform public.company_request_partner(p2);
    if (select count(*) from public.partner_connections where company_id = co_a and stage = 'company_interest') <> 2 then
      falhas := falhas || jsonb_build_object('pedido do verificado não gravou', true);
    end if;
    
    -- Parceiros: um marca cliente, outro só contatado.
    perform set_config('request.jwt.claims', json_build_object('sub', u_p1, 'role', 'authenticated')::text, true);
    if (select contact_email is not distinct from (select contact_email from public.companies where id = co_a)
        from public.list_partner_companies() where id = co_a) is distinct from true then
      falhas := falhas || jsonb_build_object('parceiro não vê a empresa que pediu contato', true);
    end if;
    perform public.partner_set_connection(co_a, 'client');
    perform set_config('request.jwt.claims', json_build_object('sub', u_p2, 'role', 'authenticated')::text, true);
    perform public.partner_set_connection(co_a, 'partner_contacted');
    
    -- Contratados: só o verificado de Alfa vê só a Parceira Um.
    perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_my_contracted_partners()) <> 1
       or (select partner_id from public.list_my_contracted_partners() limit 1) is distinct from p1 then
      falhas := falhas || jsonb_build_object('Contratados da empresa verificada errado', true);
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_cam, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_my_contracted_partners()) <> 0 then falhas := falhas || jsonb_build_object('pending vê Contratados', true); end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_my_contracted_partners()) <> 0 then falhas := falhas || jsonb_build_object('outra empresa vê Contratados', true); end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_p1, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_my_contracted_partners()) <> 0 then falhas := falhas || jsonb_build_object('parceiro vê Contratados de empresa', true); end if;
    
    execute 'reset role';
    execute 'set local role anon';
    begin
      perform public.list_my_contracted_partners();
      falhas := falhas || jsonb_build_object('anon executa list_my_contracted_partners', true);
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    res := res || jsonb_build_object('verificações de Contratados', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
