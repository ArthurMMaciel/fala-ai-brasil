-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar pausa_checks.sql e as migrations.
-- Migrations: 20261117120000_representante_verificado_estrutura.sql, 20261117150000_pausa_do_piloto.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'e8888888-8888-8888-8888-888888888888'; u_c uuid := 'e9999999-9999-9999-9999-999999999999'; u_op uuid := 'eaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; v_co uuid; v_cp uuid; n int;
begin
  begin  -- trava: nada pode commitar daqui para dentro

    -- 20261117120000_representante_verificado_estrutura.sql (16 instruções)
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

-- 1) Estado do vínculo.
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

    -- Verificações (pausa_checks.sql)
    -- declare: u_w uuid := 'e8888888-8888-8888-8888-888888888888'; u_c uuid := 'e9999999-9999-9999-9999-999999999999'; u_op uuid := 'eaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; v_co uuid; v_cp uuid; n int;
    -- Verificações da ADR-0021 (20261117150000) depois de aplicada na transação de teste. Funciona com ou sem a troca do gate
    -- (a empresa do teste é verificada pela equipe quando a função existe).
    if public.pilot_state() is distinct from 'open' then falhas := falhas || jsonb_build_object('estado inicial não é open', true); end if;
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-pw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Pausa Trabalhador', 'cpf', '74682489070', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-pc@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Pausa Empresa Ltda', 'cnpj', '34028316000103', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-pop@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    select company_id into v_co from public.company_users where user_id = u_c;
    
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    v_cp := public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso antes da pausa',
      'original_content', 'Tx relato original antes da pausa.', 'shared_content', 'Tx versao compartilhavel antes da pausa.'), true);
    begin
      perform public.ops_set_pilot_state('paused', 'Tx motivo de quem não é da equipe.');
      falhas := falhas || jsonb_build_object('trabalhador pausa o piloto', true);
    exception when others then null; end;
    
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    begin
      perform public.ops_set_pilot_state('paused', 'curto');
      falhas := falhas || jsonb_build_object('pausa com motivo curto', true);
    exception when others then null; end;
    perform public.ops_set_pilot_state('paused', 'Tx pausa de teste do piloto.');
    if public.pilot_state() is distinct from 'paused' then falhas := falhas || jsonb_build_object('estado não mudou', true); end if;
    -- Com o piloto pausado, a equipe ainda pede ajuste.
    perform public.ops_decide_complaint(v_cp, 'adjustment_requested', 'Tx ajuste pedido durante a pausa.');
    
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    begin
      perform public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso durante a pausa',
        'original_content', 'Tx relato original durante a pausa.', 'shared_content', 'Tx versao durante a pausa.'), true);
      falhas := falhas || jsonb_build_object('manifestação nova aceita na pausa', true);
    exception when others then
      if sqlerrm not like 'Novas manifestações estão temporariamente suspensas%' then falhas := falhas || jsonb_build_object('mensagem da pausa diferente', true); end if;
    end;
    begin
      perform public.share_complaint(v_cp, 'Tx versao reenviada durante a pausa.');
    exception when others then falhas := falhas || jsonb_build_object('ajuste bloqueado na pausa', true); end;
    if (select count(*) from public.complaints where id = v_cp) <> 1 then falhas := falhas || jsonb_build_object('trabalhador não lê o próprio caso na pausa', true); end if;
    
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_complaint(v_cp, 'released', null);
    if exists (select 1 from pg_proc where proname = 'ops_verify_representative') then
      execute 'select public.ops_verify_representative($1, $2, ''verified'', ''callback'', ''Tx ligação na pausa'', null)' using v_co, u_c;
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    begin
      perform public.respond_complaint(v_cp, 'Tx resposta da empresa durante a pausa.');
    exception when others then falhas := falhas || jsonb_build_object('empresa não responde na pausa', true); end;
    
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    begin
      perform public.close_complaint(v_cp, 'yes');
    exception when others then falhas := falhas || jsonb_build_object('encerramento bloqueado na pausa', true); end;
    
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    begin
      perform public.ops_set_pilot_state('paused', 'Tx pausa repetida no teste.');
      falhas := falhas || jsonb_build_object('pausa repetida aceita', true);
    exception when others then null; end;
    perform public.ops_set_pilot_state('open', 'Tx reabertura de teste do piloto.');
    if (select count(*) from public.ops_pilot_state_log() where reason like 'Tx %') <> 2 then falhas := falhas || jsonb_build_object('trilha sem as 2 mudanças', true); end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    begin
      perform public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso depois da pausa',
        'original_content', 'Tx relato original depois da pausa.', 'shared_content', 'Tx versao depois da pausa.'), true);
    exception when others then falhas := falhas || jsonb_build_object('manifestação recusada após reabrir', true); end;
    
    -- Anon lê o estado e não muda; trilha imutável.
    execute 'reset role';
    execute 'set local role anon';
    if public.pilot_state() is distinct from 'open' then falhas := falhas || jsonb_build_object('anon não lê o estado', true); end if;
    begin
      perform public.ops_set_pilot_state('paused', 'Tx anon tentando pausar.');
      falhas := falhas || jsonb_build_object('anon executa ops_set_pilot_state', true);
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    begin
      delete from public.pilot_state_log where reason like 'Tx %';
      falhas := falhas || jsonb_build_object('trilha da pausa apagável', true);
    exception when others then null; end;
    res := res || jsonb_build_object('verificações da pausa', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
