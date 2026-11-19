-- Rollback do lote 2, passo 03 (20261118130000, funções da empresa pré-cadastrada e do aviso). SQL Editor de produção,
-- arquivo INTEIRO, uma vez. Efeito: create_complaint volta à versão de 20261117150000 (só empresa por id, sem contato);
-- somem a busca por CNPJ e as funções da equipe para empresas e avisos. Relatos, empresas pré-cadastradas, contatos e
-- trilha de avisos ficam como estão (só a migration 20261118120000 os remove). A versão sai de schema_migrations.
-- Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118130000') then
    raise exception 'A 20261118130000 não está registrada. Nada foi feito.';
  end if;
end $trava$;

-- create_complaint de 20261117150000, literal.
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

drop function public.find_company_by_cnpj(text), public.my_complaint_companies(), private.preregister_company(text, jsonb), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(), public.ops_decide_notice(uuid, text, text),
  public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text), public.ops_purge_expired_contacts(),
  private.norm_cnpj(text), private.email_hash(text);
delete from supabase_migrations.schema_migrations where version = '20261118130000';

commit;
-- Conferir: select to_regprocedure('public.find_company_by_cnpj(text)') is null as ok;
