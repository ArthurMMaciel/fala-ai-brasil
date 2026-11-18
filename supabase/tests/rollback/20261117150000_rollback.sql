-- Rollback R1 da 20261117150000 (pausa do piloto, ADR-0021). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Ordem inversa: R1 150000 -> R2 140000 -> R3 120000 -> R4 180000. Cada um é independente, salvo o R3, que exige o R1 antes.
-- Efeito: create_complaint volta à versão de 20261106130100 (sem a checagem da pausa); somem estado e trilha da pausa;
-- a versão sai de schema_migrations (um db push futuro reaplicaria a migration).
-- Se o piloto estiver pausado, este rollback REABRE o envio de manifestações.
-- Trilha: se pilot_state_log tiver linhas, exporte antes (select * from public.pilot_state_log; -> Download CSV) e troque
-- false por true em v_exportei. Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
declare v_exportei boolean := false;
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117150000') then
    raise exception 'A 20261117150000 não está registrada. Nada foi feito.';
  end if;
  if not v_exportei and exists (select 1 from public.pilot_state_log) then
    raise exception 'pilot_state_log tem registros. Exporte e marque v_exportei = true. Nada foi feito.';
  end if;
end $trava$;

-- create_complaint de 20261106130100, literal.
create or replace function public.create_complaint(p jsonb, p_share boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_worker uuid;
  v_id uuid;
  v_shared text := nullif(btrim(p ->> 'shared_content'), '');
begin
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

drop function public.ops_set_pilot_state(text, text), public.pilot_state(), public.ops_pilot_state_log(), private.assert_pilot_open();
drop table public.pilot_state_log;
drop table private.platform_settings;
delete from supabase_migrations.schema_migrations where version = '20261117150000';

commit;
-- Conferir: select to_regclass('public.pilot_state_log') is null as ok_tabela,
--   (select prosrc not like '%assert_pilot_open%' from pg_proc where oid = 'public.create_complaint(jsonb,boolean)'::regprocedure) as ok_funcao;
