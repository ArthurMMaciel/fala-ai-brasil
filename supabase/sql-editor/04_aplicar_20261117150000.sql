-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/migrations/20261117150000_pausa_do_piloto.sql. Não editar à mão.
-- Passo 04 de 04. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 04_conferir_20261117150000.sql (todas as linhas com ok = true).
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117150000') then
    raise exception 'A migration 20261117150000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117140000') then
    raise exception 'Falta a 20261117140000 (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261117150000_pausa_do_piloto.sql (17 instruções) ========
-- ADR-0021: pausa do piloto pela equipe. Só aditiva, salvo create_complaint, que ganha a checagem no início.
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
);
insert into private.platform_settings (id) values (true);
revoke all on private.platform_settings from public, anon, authenticated;

-- 2) Trilha das mudanças: só inserção e imutável (gatilho da 20261117120000).
create table public.pilot_state_log (
  id uuid primary key default gen_random_uuid(),
  previous_state text not null,
  new_state text not null check (new_state in ('open', 'paused')),
  reason text not null check (char_length(btrim(reason)) between 10 and 500),
  actor_user_id uuid not null,
  created_at timestamptz not null default now()
);
alter table public.pilot_state_log enable row level security;
revoke all on public.pilot_state_log from public, anon, authenticated;
create trigger pilot_state_log_immutable before update or delete on public.pilot_state_log
  for each row execute function private.block_trail_change();

-- 3) Estado público (o front mostra o aviso antes do formulário); sem quem pausou nem motivo.
create function public.pilot_state()
returns text language sql stable security definer set search_path = '' as $$
  select pilot_state from private.platform_settings where id;
$$;

create function private.assert_pilot_open()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if (select pilot_state from private.platform_settings where id) = 'paused' then
    raise exception 'Novas manifestações estão temporariamente suspensas. Quem já tem caso aberto continua acompanhando normalmente.'
      using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function private.assert_pilot_open() from public, anon, authenticated;

-- 4) Liga e desliga: só a equipe, com motivo.
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
$$;

create function public.ops_pilot_state_log()
returns table (previous_state text, new_state text, reason text, actor_user_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query select l.previous_state, l.new_state, l.reason, l.actor_user_id, l.created_at from public.pilot_state_log l order by l.created_at desc;
end;
$$;

revoke execute on function public.pilot_state(), public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() from public;
grant execute on function public.pilot_state() to anon, authenticated;
revoke execute on function public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() from anon;
grant execute on function public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() to authenticated;

-- 5) Nova manifestação passa pela checagem (corpo de 20261106130100, só com a linha nova no início).
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
$$;
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261117150000', 'pausa_do_piloto', array[
$s0$-- ADR-0021: pausa do piloto pela equipe. Só aditiva, salvo create_complaint, que ganha a checagem no início.
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
)$s0$,
$s0$insert into private.platform_settings (id) values (true)$s0$,
$s0$revoke all on private.platform_settings from public, anon, authenticated$s0$,
$s0$-- 2) Trilha das mudanças: só inserção e imutável (gatilho da 20261117120000).
create table public.pilot_state_log (
  id uuid primary key default gen_random_uuid(),
  previous_state text not null,
  new_state text not null check (new_state in ('open', 'paused')),
  reason text not null check (char_length(btrim(reason)) between 10 and 500),
  actor_user_id uuid not null,
  created_at timestamptz not null default now()
)$s0$,
$s0$alter table public.pilot_state_log enable row level security$s0$,
$s0$revoke all on public.pilot_state_log from public, anon, authenticated$s0$,
$s0$create trigger pilot_state_log_immutable before update or delete on public.pilot_state_log
  for each row execute function private.block_trail_change()$s0$,
$s0$-- 3) Estado público (o front mostra o aviso antes do formulário); sem quem pausou nem motivo.
create function public.pilot_state()
returns text language sql stable security definer set search_path = '' as $$
  select pilot_state from private.platform_settings where id;
$$$s0$,
$s0$create function private.assert_pilot_open()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if (select pilot_state from private.platform_settings where id) = 'paused' then
    raise exception 'Novas manifestações estão temporariamente suspensas. Quem já tem caso aberto continua acompanhando normalmente.'
      using errcode = 'P0001';
  end if;
end;
$$$s0$,
$s0$revoke all on function private.assert_pilot_open() from public, anon, authenticated$s0$,
$s0$-- 4) Liga e desliga: só a equipe, com motivo.
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
$$$s0$,
$s0$create function public.ops_pilot_state_log()
returns table (previous_state text, new_state text, reason text, actor_user_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query select l.previous_state, l.new_state, l.reason, l.actor_user_id, l.created_at from public.pilot_state_log l order by l.created_at desc;
end;
$$$s0$,
$s0$revoke execute on function public.pilot_state(), public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() from public$s0$,
$s0$grant execute on function public.pilot_state() to anon, authenticated$s0$,
$s0$revoke execute on function public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() from anon$s0$,
$s0$grant execute on function public.ops_set_pilot_state(text, text), public.ops_pilot_state_log() to authenticated$s0$,
$s0$-- 5) Nova manifestação passa pela checagem (corpo de 20261106130100, só com a linha nova no início).
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
$$$s0$
]::text[]);

commit;
