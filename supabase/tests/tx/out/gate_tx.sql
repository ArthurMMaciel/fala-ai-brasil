-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar gate_checks.sql e as migrations.
-- Migrations: 20261109180000_resposta_revisada_ativa.sql, 20261117120000_representante_verificado_estrutura.sql, 20261117130000_representante_verificado_gate.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'e1111111-1111-1111-1111-111111111111'; u_c uuid := 'e2222222-2222-2222-2222-222222222222'; u_c2 uuid := 'e3333333-3333-3333-3333-333333333333'; u_op uuid := 'e4444444-4444-4444-4444-444444444444'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; v_co uuid; v_cp uuid; n int; v_ok boolean;
begin
  begin  -- trava: nada pode commitar daqui para dentro
    -- Sem lock em 3 s, falha limpa em vez de enfileirar o site atrás do DDL; teto de 60 s para a execução.
    execute 'set local lock_timeout = ''3s''';
    execute 'set local statement_timeout = ''60s''';

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

    -- 20261117130000_representante_verificado_gate.sql (7 instruções)
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
      res := res || jsonb_build_object('20261117130000', 'aplicada na transação de teste');
    end if;

    -- Verificações (gate_checks.sql)
    -- declare: u_w uuid := 'e1111111-1111-1111-1111-111111111111'; u_c uuid := 'e2222222-2222-2222-2222-222222222222'; u_c2 uuid := 'e3333333-3333-3333-3333-333333333333'; u_op uuid := 'e4444444-4444-4444-4444-444444444444'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; v_co uuid; v_cp uuid; n int; v_ok boolean;
    -- Verificações da ADR-0012 (20261117120000 e 20261117130000) depois de aplicadas na transação de teste.
    -- Imprime só contagens e nomes de verificação; nenhum dado real.
    
    -- Estado real (contagens): quantos vínculos ficam 'pending' e perdem acesso a manifestações com a troca do gate.
    select count(*) into n from public.company_users where verification_status = 'pending';
    res := res || jsonb_build_object('vínculos reais que ficam pending', n);
    select count(*) into n from public.company_users where verification_status <> 'pending';
    if n > 0 then falhas := falhas || jsonb_build_object('vínculo real nasceu fora de pending', n); end if;
    
    -- Montagem: trabalhador, empresa (dono + segundo membro, ambos pending) e equipe.
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-w@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Trabalhador', 'cpf', '11144477735', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-c@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Empresa Gate Ltda', 'cnpj', '11444777000161', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c2, 'authenticated', 'authenticated', 'tx-c2@teste.invalid', '{}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-op@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    select company_id into v_co from public.company_users where user_id = u_c;
    insert into public.company_users (company_id, user_id, role) values (v_co, u_c2, 'member');
    if (select verification_status from public.company_users where user_id = u_c) is distinct from 'pending' then
      falhas := falhas || jsonb_build_object('cadastro novo não nasce pending', true);
    end if;
    
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    v_cp := public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso do gate',
      'original_content', 'Tx relato original do teste do gate.', 'shared_content', 'Tx versao compartilhavel do gate.'), true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_complaint(v_cp, 'released', null);
    
    -- Pending: não vê, não responde, sem números próprios; lê o próprio estado.
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_company_complaints() where id = v_cp) <> 0 then falhas := falhas || jsonb_build_object('pending vê caso liberado', true); end if;
    if (select count(*) from public.get_company_complaint_timeline(v_cp)) <> 0 then falhas := falhas || jsonb_build_object('pending vê linha do tempo', true); end if;
    if (select count(*) from public.my_company_responsiveness()) <> 0 then falhas := falhas || jsonb_build_object('pending vê números próprios', true); end if;
    if (select count(*) from public.my_company_satisfaction()) <> 0 then falhas := falhas || jsonb_build_object('pending vê satisfação', true); end if;
    if (select verification_status from public.company_users where company_id = v_co and user_id = u_c) is distinct from 'pending' then
      falhas := falhas || jsonb_build_object('empresa não lê o próprio estado', true);
    end if;
    begin
      perform public.respond_complaint(v_cp, 'Tx resposta de vínculo pending.');
      falhas := falhas || jsonb_build_object('pending responde', true);
    exception when others then null; end;
    
    -- A empresa não se autoverifica.
    begin
      update public.company_users set verification_status = 'verified' where user_id = u_c;
      get diagnostics n = row_count;
      if n > 0 then falhas := falhas || jsonb_build_object('empresa altera o próprio estado', n); end if;
    exception when insufficient_privilege then null; end;
    begin
      perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação', null);
      falhas := falhas || jsonb_build_object('empresa usa função da equipe', true);
    exception when others then null; end;
    
    -- Equipe: validações e verificação.
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    if not exists (select 1 from public.ops_list_representatives('pending') where user_id = u_c) then falhas := falhas || jsonb_build_object('fila da equipe sem o pending', true); end if;
    begin
      perform public.ops_verify_representative(v_co, u_c, 'verified', null, 'Tx ligação', null);
      falhas := falhas || jsonb_build_object('verificação sem método aceita', true);
    exception when others then null; end;
    begin
      perform public.ops_verify_representative(v_co, u_c, 'revoked', null, null, 'Tx motivo de revogação longo.');
      falhas := falhas || jsonb_build_object('revogar pending aceito', true);
    exception when others then null; end;
    perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação ao telefone público', null);
    
    -- Verified vê e responde; o membro ainda pending continua sem ver.
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_company_complaints() where id = v_cp) <> 1 then falhas := falhas || jsonb_build_object('verified não vê caso liberado', true); end if;
    if (select count(*) from public.my_company_responsiveness()) <> 1 then falhas := falhas || jsonb_build_object('verified sem números próprios', true); end if;
    begin
      perform public.respond_complaint(v_cp, 'Tx resposta do representante verificado.');
    exception when others then falhas := falhas || jsonb_build_object('verified não responde: ' || sqlerrm, true); end;
    perform set_config('request.jwt.claims', json_build_object('sub', u_c2, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_company_complaints() where id = v_cp) <> 0 then falhas := falhas || jsonb_build_object('membro pending vê caso', true); end if;
    
    -- Revogação tira o acesso.
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_verify_representative(v_co, u_c, 'revoked', null, null, 'Tx representante deixou a empresa.');
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    if (select count(*) from public.list_company_complaints() where id = v_cp) <> 0 then falhas := falhas || jsonb_build_object('revoked vê caso', true); end if;
    if (select count(*) from public.get_company_complaint_timeline(v_cp)) <> 0 then falhas := falhas || jsonb_build_object('revoked vê linha do tempo', true); end if;
    
    -- Anon não executa as funções novas.
    execute 'reset role';
    execute 'set local role anon';
    begin
      perform public.is_verified_company_user(v_co);
      falhas := falhas || jsonb_build_object('anon executa is_verified_company_user', true);
    exception when insufficient_privilege then null; end;
    begin
      perform public.ops_list_representatives('pending');
      falhas := falhas || jsonb_build_object('anon executa ops_list_representatives', true);
    exception when insufficient_privilege then null; end;
    
    -- Trilha: 2 decisões e imutável até para o dono.
    execute 'reset role';
    select count(*) into n from public.representative_verifications where company_id = v_co;
    if n <> 2 then falhas := falhas || jsonb_build_object('trilha com ' || n || ' decisões (esperado 2)', true); end if;
    begin
      update public.representative_verifications set reason = 'Tx alteração indevida da trilha.' where company_id = v_co;
      falhas := falhas || jsonb_build_object('trilha alterável', true);
    exception when others then null; end;
    begin
      delete from public.representative_verifications where company_id = v_co;
      falhas := falhas || jsonb_build_object('trilha apagável', true);
    exception when others then null; end;
    res := res || jsonb_build_object('verificações do gate', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
