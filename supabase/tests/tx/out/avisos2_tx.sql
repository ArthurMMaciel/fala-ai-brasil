-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar avisos2_checks.sql e as migrations.
-- Migrations: 20261126120000_ate_3_contatos.sql, 20261126130000_avisos_por_evento_e_aviso_automatico.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'f0000000-0000-0000-0000-000000000021'; u_c uuid := 'f0000000-0000-0000-0000-000000000022'; u_op uuid := 'f0000000-0000-0000-0000-000000000023'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765007987610'; cnpj_a text := '98765001987643'; cnpj_b text := '98765004987687'; cnpj_d text := '98765005987621'; cnpj_e text := '98765009987600'; v_co uuid; v_worker uuid; v_cp uuid; v_resp uuid; cp_a uuid; cp_b uuid; cp_d uuid; cp_e uuid; cp_r uuid; co_a uuid; co_b uuid; co_d uuid; co_e uuid; n_a uuid; n_b uuid; n_d uuid; n_e uuid; v_id uuid; mine uuid[]; n int; i int; r record; base jsonb;
begin
  begin  -- trava: nada pode commitar daqui para dentro
    -- Sem lock em 3 s, falha limpa em vez de enfileirar o site atrás do DDL. (statement_timeout não se aplica: o
    -- cronômetro começa no DO, que é a instrução de topo; um SET aqui dentro não o rearma.)
    execute 'set local lock_timeout = ''3s''';

    -- 20261126120000_ate_3_contatos.sql (18 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261126120000') then
      res := res || jsonb_build_object('20261126120000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0023, revisão de 2026-11-26 (responsável, "Até 3"; repassado pelo Gestor): o trabalhador indica ATÉ 3 contatos da
-- empresa por manifestação (antes, 1). Cada contato tem e-mail e/ou telefone, possibly_involved e status próprios e o
-- mesmo consentimento de uso. O aviso à empresa não cadastrada continua 1 por manifestação e 1 por empresa a cada 30 dias;
-- a equipe escolhe o destino entre os contatos com e-mail que NÃO são possivelmente envolvidos (p_contact_id) ou a Receita.
--
-- Compatibilidade com o front em produção até o push novo:
--   - create_complaint aceita p.notice_contacts (lista de 1 a 3) e continua aceitando p.notice_contact (um objeto);
--   - ops_list_notice_candidates, ops_complaint_contact e my_complaint_contact mantêm a assinatura e devolvem UMA linha por
--     manifestação: o contato "padrão" (o primeiro com e-mail e não envolvido; se não houver, o primeiro indicado);
--   - a lista completa sai pelas funções novas ops_complaint_contacts_list e my_complaint_contacts_list;
--   - ops_decide_notice ganha p_contact_id (padrão nulo); os nomes dos parâmetros de antes não mudam.
-- Retenção de 90 dias e ops_purge_expired_contacts valem para cada contato, sem mudança.
--
-- Rollback: supabase/tests/rollback/20261126120000_rollback.sql (exige no máximo 1 contato por manifestação).

set local lock_timeout = '5s'$s0$;
      execute $s0$-- 1) Até 3 contatos por manifestação.
alter table public.complaint_contacts drop constraint complaint_contacts_complaint_id_key$s0$;
      execute $s0$create index complaint_contacts_complaint_idx on public.complaint_contacts (complaint_id, created_at)$s0$;
      execute $s0$create function private.complaint_contacts_max3()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.complaints where id = new.complaint_id for update;  -- serializa inserções da mesma manifestação
  if (select count(*) from public.complaint_contacts where complaint_id = new.complaint_id) >= 3 then
    raise exception 'No máximo 3 contatos por manifestação.' using errcode = 'P0001';
  end if;
  return new;
end;
$$$s0$;
      execute $s0$revoke all on function private.complaint_contacts_max3() from public, anon, authenticated, service_role$s0$;
      execute $s0$create trigger complaint_contacts_max3 before insert on public.complaint_contacts
  for each row execute function private.complaint_contacts_max3()$s0$;
      execute $s0$-- Contato padrão de uma manifestação (para as funções de uma linha só): o primeiro com e-mail e não envolvido; senão o
-- primeiro indicado.
create function private.default_complaint_contact(p_complaint uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select k.id from public.complaint_contacts k where k.complaint_id = p_complaint
  order by (k.email is not null and not k.possibly_involved) desc, k.created_at, k.id
  limit 1;
$$$s0$;
      execute $s0$revoke all on function private.default_complaint_contact(uuid) from public, anon, authenticated, service_role$s0$;
      execute $s0$-- 2) Nova manifestação: corpo de 20261118130000, com a lista de contatos.
-- Contatos: p.notice_contacts = [{"email"?, "phone"?, "possibly_involved": bool, "consent": true}, ...] (1 a 3), ou
-- p.notice_contact = {...} (um, compatível). Só com p_share; cada um com e-mail ou telefone; sem e-mail repetido.
create or replace function public.create_complaint(p jsonb, p_share boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_worker uuid;
  v_id uuid;
  v_company uuid;
  v_company_status text;
  v_cnpj text;
  v_manual jsonb := p -> 'company_manual';
  v_shared text := nullif(btrim(p ->> 'shared_content'), '');
  v_list jsonb := p -> 'notice_contacts';
  v_one jsonb := p -> 'notice_contact';
  v_item jsonb;
  v_norm jsonb := '[]'::jsonb;
  v_email text;
  v_phone text;
  v_notice_consent jsonb := p -> 'notice_consent';
begin
  perform private.assert_pilot_open();
  select id into v_worker from public.workers where user_id = auth.uid();
  if v_worker is null then raise exception 'Somente trabalhadores podem registrar manifestações.' using errcode = 'P0001'; end if;
  if p_share and v_shared is null then raise exception 'Escreva a versão que poderá ser compartilhada com a empresa.' using errcode = 'P0001'; end if;

  -- Contatos: só validação de entrada, sem olhar a empresa.
  if v_list is not null and jsonb_typeof(v_list) <> 'null' then
    if v_one is not null and jsonb_typeof(v_one) <> 'null' then
      raise exception 'Envie os contatos em notice_contacts ou em notice_contact, não nos dois.' using errcode = 'P0001';
    end if;
    if jsonb_typeof(v_list) <> 'array' or jsonb_array_length(v_list) not between 1 and 3 then
      raise exception 'Indique de 1 a 3 contatos da empresa.' using errcode = 'P0001';
    end if;
  elsif v_one is not null and jsonb_typeof(v_one) <> 'null' then
    v_list := jsonb_build_array(v_one);
  else
    v_list := null;
  end if;
  if v_list is not null then
    if not p_share then
      raise exception 'O aviso à empresa só é possível quando você envia a versão compartilhável para revisão.' using errcode = 'P0001';
    end if;
    for v_item in select value from jsonb_array_elements(v_list) loop
      if jsonb_typeof(v_item) <> 'object' then raise exception 'Contato para o aviso inválido.' using errcode = 'P0001'; end if;
      v_email := nullif(lower(btrim(coalesce(v_item ->> 'email', ''))), '');
      v_phone := nullif(regexp_replace(coalesce(v_item ->> 'phone', ''), '\D', '', 'g'), '');
      if v_email is null and v_phone is null then
        raise exception 'Informe um e-mail ou um telefone de contato.' using errcode = 'P0001';
      end if;
      if v_email is not null and (char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
        raise exception 'Informe um e-mail de contato válido.' using errcode = 'P0001';
      end if;
      if v_phone is not null and v_phone !~ '^\d{10,11}$' then
        raise exception 'Informe um telefone de contato com DDD (10 ou 11 dígitos).' using errcode = 'P0001';
      end if;
      if jsonb_typeof(v_item -> 'possibly_involved') is distinct from 'boolean' then
        raise exception 'Responda se a pessoa desse contato pode estar envolvida no que você relata.' using errcode = 'P0001';
      end if;
      if jsonb_typeof(v_item -> 'consent') is distinct from 'boolean' or not (v_item ->> 'consent')::boolean then
        raise exception 'Para indicar um contato, confirme o uso dele pela equipe.' using errcode = 'P0001';
      end if;
      if v_email is not null and exists (select 1 from jsonb_array_elements(v_norm) x where x ->> 'email' = v_email) then
        raise exception 'O mesmo e-mail foi indicado mais de uma vez.' using errcode = 'P0001';
      end if;
      v_norm := v_norm || jsonb_build_array(jsonb_build_object('email', v_email, 'phone', v_phone,
                                                              'possibly_involved', (v_item ->> 'possibly_involved')::boolean));
    end loop;
  end if;

  -- Consentimento ao aviso: só validação de entrada, sem olhar a empresa.
  if v_notice_consent is not null and jsonb_typeof(v_notice_consent) <> 'null' then
    if jsonb_typeof(v_notice_consent) <> 'boolean' then
      raise exception 'Resposta inválida sobre o aviso à empresa.' using errcode = 'P0001';
    end if;
    if (v_notice_consent)::text = 'true' and not p_share then
      raise exception 'O aviso à empresa só é possível quando você envia a versão compartilhável para revisão.' using errcode = 'P0001';
    end if;
  end if;

  -- Empresa.
  if nullif(p ->> 'company_id', '') is not null then
    select id, registration_status into v_company, v_company_status from public.companies where id = (p ->> 'company_id')::uuid;
    if v_company is null then raise exception 'Empresa não encontrada.' using errcode = 'P0001'; end if;
  else
    v_cnpj := private.norm_cnpj(p ->> 'company_cnpj');
    if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
    if not exists (select 1 from private.cnpj_cache where cnpj = v_cnpj and not natural_person) then
      if v_manual is null or jsonb_typeof(v_manual) <> 'object'
         or char_length(btrim(coalesce(v_manual ->> 'name', ''))) not between 2 and 160 then
        raise exception 'Informe o nome da empresa (2 a 160 caracteres).' using errcode = 'P0001';
      end if;
      if char_length(btrim(coalesce(v_manual ->> 'city', ''))) not between 2 and 80 then
        raise exception 'Informe o município da empresa.' using errcode = 'P0001';
      end if;
      if upper(btrim(coalesce(v_manual ->> 'state', ''))) not in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
           'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO') then
        raise exception 'Informe a UF da empresa.' using errcode = 'P0001';
      end if;
    end if;
    if not private.take_quota(auth.uid(), 'prereg_day', 3) then
      raise exception 'Limite de relatos por CNPJ atingido hoje. Tente amanhã.' using errcode = 'P0001';
    end if;
    v_company := private.preregister_company(v_cnpj, v_manual);
    select registration_status into v_company_status from public.companies where id = v_company;
  end if;

  insert into public.complaints (worker_id, company_id, category, title, incident_period, recurrence, expected_outcomes, status)
  values (
    v_worker, v_company, btrim(p ->> 'category'), btrim(p ->> 'title'),
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
  if v_notice_consent is not null and jsonb_typeof(v_notice_consent) = 'boolean' then
    insert into private.complaint_notice_consents (complaint_id, consented) values (v_id, (v_notice_consent)::text = 'true');
  end if;
  -- Um insert por contato, na ordem indicada (created_at distinto preserva a ordem).
  for v_item in select value from jsonb_array_elements(v_norm) loop
    insert into public.complaint_contacts (complaint_id, email, phone, possibly_involved, worker_consented, created_at)
    values (v_id, v_item ->> 'email', v_item ->> 'phone', (v_item ->> 'possibly_involved')::boolean, true, clock_timestamp());
  end loop;
  return v_id;
end;
$$$s0$;
      execute $s0$-- 3) Fila do aviso: mesma assinatura, uma linha por manifestação, com o contato padrão. A lista completa sai em
-- ops_complaint_contacts_list.
create or replace function public.ops_list_notice_candidates()
returns table (complaint_id uuid, protocol text, complaint_status public.complaint_status, company_id uuid, company_name text,
               registration_status text, natural_person boolean, review_decision text, notice_consented boolean, contact_id uuid,
               contact_email text, contact_phone text, possibly_involved boolean, receita_email text,
               destination_email text, destination_source text, opted_out boolean, last_company_notice_at timestamptz,
               notice_id uuid, notice_status text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select c.id, c.protocol, c.status, co.id, coalesce(co.trade_name, co.legal_name), co.registration_status,
         coalesce(pr.natural_person, false), pr.review_decision, coalesce(nc.consented, false),
         k.id, k.email, k.phone, k.possibly_involved, cc.email,
         d.email, d.source,
         d.email is not null and exists (select 1 from private.notice_opt_outs o where o.email_hash = private.email_hash(d.email)),
         (select max(n.decided_at) from public.company_notices n where n.company_id = co.id and n.status in ('approved', 'sent')),
         ln.id, ln.status
  from public.complaints c
  join public.companies co on co.id = c.company_id
  left join private.company_preregistrations pr on pr.company_id = co.id
  left join public.complaint_contacts k on k.id = private.default_complaint_contact(c.id)
  left join private.complaint_notice_consents nc on nc.complaint_id = c.id
  left join private.cnpj_cache cc on cc.cnpj = co.cnpj and not cc.natural_person
  cross join lateral (select case when k.email is not null and not k.possibly_involved then k.email else cc.email end as email,
                             case when k.email is not null and not k.possibly_involved then 'worker'
                                  when cc.email is not null then 'receita' end as source) d
  left join lateral (select n.id, n.status from public.company_notices n where n.complaint_id = c.id
                     order by n.decided_at desc limit 1) ln on true
  where co.registration_status <> 'registered' and c.status not in ('received', 'canceled')
  order by (ln.id is null) desc, c.created_at;
end;
$$$s0$;
      execute $s0$-- 4) Lista completa dos contatos de uma manifestação, para a equipe (detalhe e escolha do destino do aviso).
create function public.ops_complaint_contacts_list(p_complaint uuid)
returns table (contact_id uuid, email text, phone text, possibly_involved boolean, status text, created_at timestamptz,
               opted_out boolean, eligible_for_notice boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select k.id, k.email, k.phone, k.possibly_involved, k.status, k.created_at,
         k.email is not null and exists (select 1 from private.notice_opt_outs o where o.email_hash = private.email_hash(k.email)),
         k.email is not null and not k.possibly_involved
           and not exists (select 1 from private.notice_opt_outs o where o.email_hash = private.email_hash(k.email))
  from public.complaint_contacts k where k.complaint_id = p_complaint
  order by k.created_at, k.id;
end;
$$$s0$;
      execute $s0$-- Lista completa para o próprio trabalhador. A empresa nunca lê.
create function public.my_complaint_contacts_list(p_complaint uuid)
returns table (contact_id uuid, email text, phone text, possibly_involved boolean)
language sql stable security definer set search_path = '' as $$
  select k.id, k.email, k.phone, k.possibly_involved
  from public.complaint_contacts k
  join public.complaints c on c.id = k.complaint_id
  join public.workers w on w.id = c.worker_id
  where k.complaint_id = p_complaint and w.user_id = auth.uid()
  order by k.created_at, k.id;
$$$s0$;
      execute $s0$-- Funções de uma linha (front atual): o contato padrão.
create or replace function public.ops_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean, status text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query select k.email, k.phone, k.possibly_involved, k.status, k.created_at
  from public.complaint_contacts k where k.id = private.default_complaint_contact(p_complaint);
end;
$$$s0$;
      execute $s0$create or replace function public.my_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean)
language sql stable security definer set search_path = '' as $$
  select k.email, k.phone, k.possibly_involved
  from public.complaint_contacts k
  join public.complaints c on c.id = k.complaint_id
  join public.workers w on w.id = c.worker_id
  where k.id = private.default_complaint_contact(p_complaint) and w.user_id = auth.uid();
$$$s0$;
      execute $s0$-- 5) Decisão do aviso com escolha do contato. Mesmas travas de antes (ADR-0023); o destino do trabalhador é um contato
-- com e-mail e NÃO possivelmente envolvido: p_contact_id, ou, sem ele, o contato padrão elegível. Receita: recusa se o
-- e-mail for o de QUALQUER contato possivelmente envolvido. Recusa (rejected): todos os contatos ainda candidatos ficam
-- 'rejected'.
drop function public.ops_decide_notice(uuid, text, text, text)$s0$;
      execute $s0$create function public.ops_decide_notice(p_complaint uuid, p_decision text, p_reason text default null,
                                         p_destination text default null, p_contact_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_status public.complaint_status; v_company uuid; k record; co record; pr record; v_id uuid;
  v_receita text; v_source text; v_email text;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_decision not in ('approved', 'rejected') then raise exception 'Decisão inválida.' using errcode = 'P0001'; end if;
  if p_destination is not null and p_destination not in ('worker', 'receita') then
    raise exception 'Destino inválido.' using errcode = 'P0001';
  end if;
  if p_contact_id is not null and p_destination = 'receita' then
    raise exception 'Escolha um contato do trabalhador ou a Receita, não os dois.' using errcode = 'P0001';
  end if;
  select status, company_id into v_status, v_company from public.complaints where id = p_complaint for update;
  if v_status is null then raise exception 'Manifestação não encontrada.' using errcode = 'P0001'; end if;
  -- Trava por empresa: duas decisões simultâneas para a mesma empresa não furam o intervalo de 30 dias.
  select id, registration_status, cnpj into co from public.companies where id = v_company for update;
  if co.registration_status = 'registered' then
    raise exception 'A empresa já é cadastrada; o aviso não se aplica.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.company_notices where complaint_id = p_complaint and status in ('approved', 'sent', 'rejected')) then
    raise exception 'O aviso desta manifestação já foi decidido.' using errcode = 'P0001';
  end if;
  perform 1 from public.complaint_contacts where complaint_id = p_complaint for update;
  select * into k from public.complaint_contacts where false;  -- registro sempre atribuído (k.id nulo no destino Receita)
  select * into pr from private.company_preregistrations where company_id = v_company;
  select email into v_receita from private.cnpj_cache where cnpj = co.cnpj and not natural_person;

  if p_decision = 'rejected' then
    if v_reason is null or char_length(v_reason) not between 10 and 300 then
      raise exception 'Informe o motivo (10 a 300 caracteres, sem conteúdo de relato).' using errcode = 'P0001';
    end if;
    insert into public.company_notices (company_id, complaint_id, contact_id, status, reason, decided_by)
    values (v_company, p_complaint, p_contact_id, 'rejected', v_reason, auth.uid()) returning id into v_id;
    update public.complaint_contacts set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
    where complaint_id = p_complaint and status = 'candidate';
    return v_id;
  end if;

  if not exists (select 1 from pg_proc where oid = to_regprocedure('public.list_company_complaints()')
                 and prosrc like '%is_verified_company_user%') then
    raise exception 'A troca do gate (20261117130000) não está aplicada: a empresa avisada veria casos sem verificação.' using errcode = 'P0001';
  end if;
  if v_status <> 'shared' then
    raise exception 'O aviso só sai depois que a equipe libera a manifestação (retida ou em revisão não recebe aviso).' using errcode = 'P0001';
  end if;
  if not coalesce((select consented from private.complaint_notice_consents where complaint_id = p_complaint), false) then
    raise exception 'O trabalhador não autorizou o aviso à empresa nesta manifestação: só é possível recusar.' using errcode = 'P0001';
  end if;
  if co.registration_status = 'pending_check' then
    raise exception 'Confira os dados da empresa antes do aviso.' using errcode = 'P0001';
  end if;
  if pr.review_decision = 'blocked' or coalesce(pr.natural_person, false) then
    raise exception 'Empresa bloqueada para aviso ou pessoa física/MEI: aviso não permitido.' using errcode = 'P0001';
  end if;

  -- Destino.
  if p_contact_id is not null then
    select * into k from public.complaint_contacts where id = p_contact_id and complaint_id = p_complaint;
    if k.id is null then raise exception 'Contato não pertence a esta manifestação.' using errcode = 'P0001'; end if;
    v_source := 'worker';
  elsif p_destination = 'receita' then
    v_source := 'receita';
  else
    select * into k from public.complaint_contacts
    where complaint_id = p_complaint and email is not null and not possibly_involved order by created_at, id limit 1;
    if k.id is not null then v_source := 'worker';
    elsif p_destination = 'worker' then
      raise exception 'O trabalhador não indicou contato com e-mail que não seja possivelmente envolvido.' using errcode = 'P0001';
    else v_source := 'receita';
    end if;
  end if;

  if v_source = 'worker' then
    if k.email is null then raise exception 'Esse contato não tem e-mail para o aviso.' using errcode = 'P0001'; end if;
    if k.possibly_involved then
      raise exception 'O trabalhador marcou esse contato como possivelmente envolvido: aviso não permitido para ele.' using errcode = 'P0001';
    end if;
    v_email := k.email;
  else
    if v_receita is null then raise exception 'Não há e-mail da Receita para esta empresa.' using errcode = 'P0001'; end if;
    if exists (select 1 from public.complaint_contacts where complaint_id = p_complaint and possibly_involved and email = v_receita) then
      raise exception 'O e-mail da Receita é o de um contato marcado como possivelmente envolvido: aviso não permitido.' using errcode = 'P0001';
    end if;
    v_email := v_receita;
  end if;
  if exists (select 1 from private.notice_opt_outs where email_hash = private.email_hash(v_email)) then
    raise exception 'Este e-mail pediu para não receber avisos.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.company_notices n where n.company_id = v_company and n.status in ('approved', 'sent')
             and n.decided_at > now() - interval '30 days') then
    raise exception 'A empresa já recebeu aviso nos últimos 30 dias.' using errcode = 'P0001';
  end if;

  insert into public.company_notices (company_id, complaint_id, contact_id, status, destination_source, decided_by)
  values (v_company, p_complaint, case when v_source = 'worker' then k.id end, 'approved', v_source, auth.uid())
  returning id into v_id;
  if v_source = 'worker' then
    update public.complaint_contacts set status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() where id = k.id;
  end if;
  return v_id;
end;
$$$s0$;
      execute $s0$revoke execute on function public.ops_decide_notice(uuid, text, text, text, uuid), public.ops_complaint_contacts_list(uuid),
  public.my_complaint_contacts_list(uuid) from public, anon, service_role$s0$;
      execute $s0$grant execute on function public.ops_decide_notice(uuid, text, text, text, uuid), public.ops_complaint_contacts_list(uuid),
  public.my_complaint_contacts_list(uuid) to authenticated$s0$;
      res := res || jsonb_build_object('20261126120000', 'aplicada na transação de teste');
    end if;

    -- 20261126130000_avisos_por_evento_e_aviso_automatico.sql (19 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261126130000') then
      res := res || jsonb_build_object('20261126130000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0020 e ADR-0023, revisão de 2026-11-26 (pedido do Gestor; aplicação depende da aprovação do responsável).
-- Duas mudanças na fila de avisos (20261123130000), sem tocar no conteúdo dos relatos:
--
-- 1) Motivo do aviso (coluna reason), para a send-notifications escolher um texto curto por evento:
--      worker_update  -> 'update' (qualquer novidade na manifestação, feita por outra pessoa que não o trabalhador);
--      company_update -> 'released' (liberação), 'closed' (encerramento), 'response_returned' (resposta devolvida);
--                        'update' fica para as linhas criadas antes desta migration (texto genérico).
--    O motivo é um código fixo; nada de protocolo, categoria, empresa ou texto.
--
-- 2) Aviso automático à empresa não cadastrada (kind 'company_notice'), depois da aprovação humana:
--    - ops_decide_notice continua com todas as travas e não muda. A aprovação (company_notices 'approved') põe uma linha
--      na fila por gatilho, com notice_id; o e-mail de destino NÃO fica na fila: é resolvido no envio
--      (contato indicado pelo trabalhador ou e-mail da Receita) e conferido de novo (opt-out, aviso ainda aprovado,
--      empresa ainda não cadastrada nem bloqueada, manifestação existente, Receita diferente de contato possivelmente
--      envolvido). Se não passar, a linha vira
--      'suppressed' e o aviso fica 'approved' para a equipe decidir (marcar devolvido à mão).
--    - Enviado: company_notices vira 'sent' (sent_by nulo = envio automático). Falha definitiva: 'bounced'.
--    - Conta no teto de 300 mensagens por dia, como os demais.
--    - notification_claim ganha p_include_notices (padrão false): a versão da função já publicada (que não conhece o tipo)
--      nunca recebe avisos de empresa; a nova versão pede true. Aplicar esta migration ANTES de publicar a função nova.
--    - ops_mark_notice_sent (marcação manual) retira da fila o envio pendente e recusa enquanto o envio estiver em curso.
--    Muda a regra "nada automático para contato ou Receita" da ADR-0023: o envio passa a ser automático, a decisão
--    continua humana, um aviso por manifestação e no máximo um por empresa a cada 30 dias.
--
-- Rollback: supabase/tests/rollback/20261126130000_rollback.sql.

set local lock_timeout = '5s'$s0$;
      execute $s0$-- 1) Colunas e regras da fila.
alter table private.notification_outbox
  add column reason text not null default 'update',
  add column notice_id uuid references public.company_notices (id) on delete cascade$s0$;
      execute $s0$alter table private.notification_outbox drop constraint notification_outbox_kind_check$s0$;
      execute $s0$alter table private.notification_outbox drop constraint notification_outbox_check$s0$;
      execute $s0$alter table private.notification_outbox
  add constraint notification_outbox_kind_check check (kind in ('worker_update', 'company_update', 'company_notice')),
  add constraint notification_outbox_check check (
    (kind = 'worker_update' and worker_id is not null and company_id is null and notice_id is null)
    or (kind = 'company_update' and company_id is not null and worker_id is null and notice_id is null)
    or (kind = 'company_notice' and notice_id is not null and company_id is not null and worker_id is null)),
  add constraint notification_outbox_reason_check check (
    (kind = 'worker_update' and reason = 'update')
    or (kind = 'company_update' and reason in ('update', 'released', 'closed', 'response_returned'))
    or (kind = 'company_notice' and reason = 'notice'))$s0$;
      execute $s0$create unique index notification_outbox_notice_idx on private.notification_outbox (notice_id) where notice_id is not null$s0$;
      execute $s0$-- 2) Gatilhos com o motivo. Mesmas regras de 20261123130000; só o reason é novo.
create or replace function private.enqueue_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_worker uuid; v_company uuid; v_updates boolean;
begin
  select c.worker_id, c.company_id, w.email_updates into v_worker, v_company, v_updates
  from public.complaints c join public.workers w on w.id = c.worker_id where c.id = new.complaint_id;
  if v_worker is null then return new; end if;
  if new.actor <> 'worker' then  -- a própria ação do trabalhador não o avisa
    insert into private.notification_outbox (kind, worker_id, dedupe_key, status, reason)
    values ('worker_update', v_worker, 'worker_update:' || new.id, case when v_updates then 'pending' else 'suppressed' end, 'update')
    on conflict (dedupe_key) do nothing;
  end if;
  -- Empresa: liberação (pela equipe) e encerramento (pelo trabalhador). 'closed' só existe depois de liberada.
  if (new.status = 'shared' and new.actor <> 'worker') or new.status = 'closed' then
    insert into private.notification_outbox (kind, company_id, dedupe_key, reason)
    values ('company_update', v_company, 'company_update:' || new.id, case when new.status = 'closed' then 'closed' else 'released' end)
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$$s0$;
      execute $s0$create or replace function private.enqueue_response_returned()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.review_status = 'returned' and old.review_status is distinct from 'returned' then
    insert into private.notification_outbox (kind, company_id, dedupe_key, reason)
    values ('company_update', new.company_id, 'company_update:response_returned:' || new.id, 'response_returned')
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$$s0$;
      execute $s0$-- Aprovação do aviso (ops_decide_notice) -> fila. Só a aprovação; a recusa não gera nada.
create function private.enqueue_company_notice()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' then
    insert into private.notification_outbox (kind, company_id, notice_id, dedupe_key, reason)
    values ('company_notice', new.company_id, new.id, 'company_notice:' || new.id, 'notice')
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$$s0$;
      execute $s0$revoke all on function private.enqueue_company_notice() from public, anon, authenticated, service_role$s0$;
      execute $s0$create trigger company_notices_enqueue after insert on public.company_notices
  for each row execute function private.enqueue_company_notice()$s0$;
      execute $s0$-- Destino de um aviso de empresa, conferido no envio. Nulo = não enviar. Não grava nada.
create function private.company_notice_destination(p_notice uuid)
returns text language sql stable security definer set search_path = '' as $$
  select d.email
  from public.company_notices n
  join public.companies co on co.id = n.company_id
  cross join lateral (
    select case n.destination_source
             when 'worker' then (select k.email from public.complaint_contacts k
                                 where k.id = n.contact_id and not k.possibly_involved)
             when 'receita' then (select cc.email from private.cnpj_cache cc where cc.cnpj = co.cnpj and not cc.natural_person)
           end as email
  ) d
  where n.id = p_notice and n.status = 'approved' and co.registration_status <> 'registered'
    and n.complaint_id is not null  -- manifestação apagada com a conta: não avisa
    and not exists (select 1 from private.company_preregistrations pr
                    where pr.company_id = n.company_id and (pr.review_decision = 'blocked' or coalesce(pr.natural_person, false)))
    and d.email is not null
    and not exists (select 1 from private.notice_opt_outs o where o.email_hash = private.email_hash(d.email))
    and not (n.destination_source = 'receita' and exists (
      select 1 from public.complaint_contacts k
      where k.complaint_id = n.complaint_id and k.possibly_involved and k.email = lower(d.email)));
$$$s0$;
      execute $s0$revoke all on function private.company_notice_destination(uuid) from public, anon, authenticated, service_role$s0$;
      execute $s0$-- 3) Interface da Edge Function. A assinatura muda (p_include_notices e a coluna reason): drop e create.
drop function public.notification_claim(integer)$s0$;
      execute $s0$create function public.notification_claim(p_limit integer default 50, p_include_notices boolean default false)
returns table (outbox_id uuid, kind text, reason text, email text, remaining_today integer)
language plpgsql security definer set search_path = '' as $$
declare
  v_day_start timestamptz := (date_trunc('day', now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo';
  v_remaining integer;
  v_ids uuid[];
begin
  -- Manutenção: reserva perdida (queda entre envio e marcação) e retenção.
  update private.notification_outbox set status = 'pending', claimed_at = null
  where status = 'sending' and claimed_at < now() - interval '30 minutes';
  delete from private.notification_outbox
  where status in ('sent', 'suppressed') and coalesce(sent_at, created_at) < now() - interval '90 days';

  v_remaining := 300 - coalesce((select sum(messages_sent) from private.notification_outbox
                                 where status = 'sent' and sent_at >= v_day_start), 0);
  if v_remaining <= 0 then return; end if;

  select array_agg(id) into v_ids from (
    select o.id from private.notification_outbox o
    where o.status = 'pending' and o.next_attempt_at <= now()
      and (o.kind <> 'company_notice' or coalesce(p_include_notices, false))
    order by o.created_at
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    for update skip locked
  ) s;
  if v_ids is null then return; end if;
  update private.notification_outbox set status = 'sending', claimed_at = now() where id = any (v_ids);

  -- Sem destinatário: 'suppressed'. Aviso de empresa que não passa na conferência fica 'approved' em company_notices.
  update private.notification_outbox o set status = 'suppressed', claimed_at = null
  where o.id = any (v_ids) and (
    (o.kind = 'worker_update' and not exists (
       select 1 from public.workers w join auth.users u on u.id = w.user_id
       where w.id = o.worker_id and w.email_updates and u.email is not null))
    or (o.kind = 'company_update' and not exists (
       select 1 from public.company_users cu join auth.users u on u.id = cu.user_id
       where cu.company_id = o.company_id and cu.verification_status = 'verified' and u.email is not null))
    or (o.kind = 'company_notice' and private.company_notice_destination(o.notice_id) is null));

  return query
  select o.id, o.kind, o.reason, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.workers w on w.id = o.worker_id
  join auth.users u on u.id = w.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'worker_update' and w.email_updates and u.email is not null
  union all
  select o.id, o.kind, o.reason, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.company_users cu on cu.company_id = o.company_id and cu.verification_status = 'verified'
  join auth.users u on u.id = cu.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'company_update' and u.email is not null
  union all
  select o.id, o.kind, o.reason, lower(private.company_notice_destination(o.notice_id)), v_remaining
  from private.notification_outbox o
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'company_notice';
end;
$$$s0$;
      execute $s0$-- Mesmo comportamento de 20261123130000, mais o reflexo em company_notices para o tipo company_notice:
-- 'sent' -> aviso 'sent' (sent_by nulo: envio automático); falha definitiva ('failed') -> aviso 'bounced'.
create or replace function public.notification_mark(p_id uuid, p_result text, p_error_code text default null, p_messages integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_attempts integer; v_code text := case when p_error_code ~ '^[a-z0-9_]{1,40}$' then p_error_code end;
        v_notice uuid; v_status text;
begin
  if p_result = 'sent' then
    update private.notification_outbox
    set status = 'sent', sent_at = now(), messages_sent = greatest(coalesce(p_messages, 0), 0), claimed_at = null, last_error_code = null,
        last_attempt_at = now()
    where id = p_id and status = 'sending'
    returning notice_id into v_notice;
    if v_notice is not null then
      update public.company_notices set status = 'sent', sent_at = now() where id = v_notice and status = 'approved';
    end if;
  elsif p_result = 'retry' then
    update private.notification_outbox set attempts = attempts + 1 where id = p_id and status = 'sending'
    returning attempts into v_attempts;
    if v_attempts is null then return; end if;
    update private.notification_outbox
    set status = case when v_attempts > 5 then 'failed' else 'pending' end,
        next_attempt_at = now() + case v_attempts when 1 then interval '5 minutes' when 2 then interval '30 minutes'
                                                  when 3 then interval '2 hours' when 4 then interval '6 hours'
                                                  else interval '24 hours' end,
        last_error_code = v_code, claimed_at = null, last_attempt_at = now()
    where id = p_id
    returning notice_id, status into v_notice, v_status;
    if v_notice is not null and v_status = 'failed' then
      update public.company_notices set status = 'bounced' where id = v_notice and status = 'approved';
    end if;
  elsif p_result = 'release' then
    update private.notification_outbox set status = 'pending', claimed_at = null, last_error_code = v_code, last_attempt_at = now()
    where id = p_id and status = 'sending';
  else
    raise exception 'Resultado inválido.' using errcode = 'P0001';
  end if;
end;
$$$s0$;
      execute $s0$revoke all on function public.notification_claim(integer, boolean) from public, anon, authenticated$s0$;
      execute $s0$grant execute on function public.notification_claim(integer, boolean) to service_role$s0$;
      execute $s0$-- 4) Marcação manual pela equipe: mesma regra de 20261118130000; tira da fila o envio automático pendente e recusa
-- enquanto ele estiver em curso (evita aviso em dobro).
create or replace function public.ops_mark_notice_sent(p_notice uuid, p_outcome text default 'sent')
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select status into v_status from public.company_notices where id = p_notice for update;
  if v_status is null then raise exception 'Aviso não encontrado.' using errcode = 'P0001'; end if;
  if exists (select 1 from private.notification_outbox where notice_id = p_notice and status = 'sending') then
    raise exception 'O envio automático deste aviso está em curso. Tente de novo em alguns minutos.' using errcode = 'P0001';
  end if;
  if p_outcome = 'sent' and v_status = 'approved' then
    update public.company_notices set status = 'sent', sent_by = auth.uid(), sent_at = now() where id = p_notice;
  elsif p_outcome = 'bounced' and v_status in ('approved', 'sent') then
    update public.company_notices set status = 'bounced' where id = p_notice;
  else
    raise exception 'Mudança não permitida a partir do estado atual.' using errcode = 'P0001';
  end if;
  update private.notification_outbox set status = 'suppressed', claimed_at = null
  where notice_id = p_notice and status = 'pending';
end;
$$$s0$;
      res := res || jsonb_build_object('20261126130000', 'aplicada na transação de teste');
    end if;

    -- Verificações (avisos2_checks.sql)
    -- declare: u_w uuid := 'f0000000-0000-0000-0000-000000000021'; u_c uuid := 'f0000000-0000-0000-0000-000000000022'; u_op uuid := 'f0000000-0000-0000-0000-000000000023'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765007987610'; cnpj_a text := '98765001987643'; cnpj_b text := '98765004987687'; cnpj_d text := '98765005987621'; cnpj_e text := '98765009987600'; v_co uuid; v_worker uuid; v_cp uuid; v_resp uuid; cp_a uuid; cp_b uuid; cp_d uuid; cp_e uuid; cp_r uuid; co_a uuid; co_b uuid; co_d uuid; co_e uuid; n_a uuid; n_b uuid; n_d uuid; n_e uuid; v_id uuid; mine uuid[]; n int; i int; r record; base jsonb;
    -- Verificações de 20261126130000 (motivo do aviso e aviso automático à empresa não cadastrada). Roda depois de
    -- 20261126120000. CNPJs de teste conferidos como inexistentes (404 em 2026-11-18); CPF de teste só na transação.
    -- Em produção a reserva pode pegar linhas reais: tudo é desfeito e as contagens filtram pelos ids do teste.
    if exists (select 1 from public.companies where cnpj in (cnpj_c, cnpj_a, cnpj_b, cnpj_d, cnpj_e))
       or exists (select 1 from public.workers where cpf = '31415926590') then
      raise exception 'Valor de teste já existe; troque os CNPJs/CPF do teste.';
    end if;
    base := jsonb_build_object('category', 'Carga de trabalho', 'title', 'Tx caso', 'original_content', 'Tx relato original.',
                               'shared_content', 'Tx versao compartilhavel.', 'notice_consent', true);
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-ew@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Evento Trabalhador', 'cpf', '31415926590', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-ec@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Evento Empresa Ltda', 'cnpj', cnpj_c, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-eop@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    select company_id into v_co from public.company_users where user_id = u_c;
    select id into v_worker from public.workers where user_id = u_w;
    perform public.cnpj_cache_put(cnpj_a, false, 'Tx Empresa A Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', 'receita@tx-a.invalid');
    perform public.cnpj_cache_put(cnpj_b, false, 'Tx Empresa B Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', 'receita@tx-b.invalid');
    perform public.cnpj_cache_put(cnpj_d, false, 'Tx Empresa D Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', null);
    perform public.cnpj_cache_put(cnpj_e, false, 'Tx Empresa E Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', null);
    
    -- 1) Motivo por evento na empresa cadastrada: liberação, devolução da resposta e encerramento.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    v_cp := public.create_complaint(base || jsonb_build_object('company_id', v_co), true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação ao telefone do site', null);
    perform public.ops_decide_complaint(v_cp, 'released', null);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    perform public.respond_complaint(v_cp, 'Tx resposta institucional da empresa.');
    execute 'reset role';
    select id into v_resp from public.company_responses where complaint_id = v_cp;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_response(v_resp, 'returned', null, 'Tx devolução da resposta para ajuste no teste.');
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    perform public.respond_complaint(v_cp, 'Tx resposta institucional revisada da empresa.');
    execute 'reset role';
    select id into v_resp from public.company_responses where complaint_id = v_cp and review_status = 'in_review';
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_response(v_resp, 'released', 'Tx a empresa respondeu e explicou as medidas que vai tomar no caso relatado.', null);
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    perform public.close_complaint(v_cp, 'yes');
    execute 'reset role';
    if (select string_agg(reason, ',' order by reason) from private.notification_outbox where kind = 'company_update' and company_id = v_co)
       is distinct from 'closed,released,response_returned' then
      falhas := falhas || jsonb_build_object('motivos da empresa (esperado closed, released, response_returned)',
        (select string_agg(reason, ',' order by reason) from private.notification_outbox where kind = 'company_update' and company_id = v_co));
    end if;
    if exists (select 1 from private.notification_outbox where kind = 'worker_update' and worker_id = v_worker and reason <> 'update')
       or not exists (select 1 from private.notification_outbox where kind = 'worker_update' and worker_id = v_worker) then
      falhas := falhas || jsonb_build_object('motivo do trabalhador diferente de update', true);
    end if;
    -- Combinações inválidas recusadas pelo banco.
    begin
      insert into private.notification_outbox (kind, worker_id, dedupe_key, reason) values ('worker_update', v_worker, 'tx:motivo', 'released');
      falhas := falhas || jsonb_build_object('worker_update com motivo de empresa aceito', true);
    exception when check_violation then null; end;
    begin
      insert into private.notification_outbox (kind, company_id, dedupe_key, reason) values ('company_notice', v_co, 'tx:sem-aviso', 'notice');
      falhas := falhas || jsonb_build_object('company_notice sem notice_id aceito', true);
    exception when check_violation then null; end;
    
    -- 2) Avisos às empresas não cadastradas: só a aprovação entra na fila.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    cp_a := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'rh@tx-a.invalid', 'possibly_involved', false, 'consent', true))), true);
    cp_b := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_b, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'chefe@tx-b.invalid', 'possibly_involved', true, 'consent', true))), true);
    cp_d := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_d, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'sai@tx-d.invalid', 'possibly_involved', false, 'consent', true))), true);
    -- Limite de 3 pré-cadastros por dia por pessoa: zera o contador do usuário de teste (só nesta transação).
    execute 'reset role';
    select id into co_a from public.companies where cnpj = cnpj_a;
    delete from private.cnpj_lookup_quota where user_id = u_w;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    cp_r := public.create_complaint(base || jsonb_build_object('company_id', co_a, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'outro@tx-a.invalid', 'possibly_involved', false, 'consent', true))), true);
    cp_e := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_e, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'manual@tx-e.invalid', 'possibly_involved', false, 'consent', true))), true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_complaint(cp_a, 'released', null);
    perform public.ops_decide_complaint(cp_r, 'released', null);
    perform public.ops_decide_complaint(cp_b, 'released', null);
    perform public.ops_decide_complaint(cp_d, 'released', null);
    perform public.ops_decide_complaint(cp_e, 'released', null);
    n_a := public.ops_decide_notice(cp_a, 'approved', null);                  -- contato do trabalhador
    perform public.ops_decide_notice(cp_r, 'rejected', 'Tx recusa do aviso no teste da fila.');
    n_b := public.ops_decide_notice(cp_b, 'approved', null);                  -- só envolvido: Receita
    n_d := public.ops_decide_notice(cp_d, 'approved', null);
    n_e := public.ops_decide_notice(cp_e, 'approved', null);
    execute 'reset role';
    if (select count(*) from private.notification_outbox where kind = 'company_notice' and notice_id in (n_a, n_b, n_d, n_e)
        and status = 'pending' and reason = 'notice') <> 4 then
      falhas := falhas || jsonb_build_object('aprovação não pôs os 4 avisos na fila', true);
    end if;
    if exists (select 1 from private.notification_outbox o join public.company_notices cn on cn.id = o.notice_id where cn.complaint_id = cp_r) then
      falhas := falhas || jsonb_build_object('recusa pôs aviso na fila', true);
    end if;
    if (select destination_source from public.company_notices where id = n_b) is distinct from 'receita' then
      falhas := falhas || jsonb_build_object('aviso B não foi para a Receita', true);
    end if;
    
    -- Opt-out depois da aprovação: conferido no envio.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_add_opt_out('Sai@tx-d.invalid');
    -- Marcação manual: recusada com envio em curso; com envio pendente, tira da fila.
    execute 'reset role';
    update private.notification_outbox set status = 'sending', claimed_at = now() where notice_id = n_e;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    begin
      perform public.ops_mark_notice_sent(n_e, 'sent');
      falhas := falhas || jsonb_build_object('marcação manual com envio em curso aceita', true);
    exception when others then
      if sqlerrm not like '%em curso%' then falhas := falhas || jsonb_build_object('mensagem envio em curso', sqlerrm); end if;
    end;
    execute 'reset role';
    update private.notification_outbox set status = 'pending', claimed_at = null where notice_id = n_e;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_mark_notice_sent(n_e, 'sent');
    execute 'reset role';
    if (select status from private.notification_outbox where notice_id = n_e) is distinct from 'suppressed'
       or (select status || '/' || (sent_by = u_op)::text from public.company_notices where id = n_e) is distinct from 'sent/true' then
      falhas := falhas || jsonb_build_object('marcação manual não tirou o envio da fila', true);
    end if;
    
    -- 3) Reserva: sem p_include_notices, nenhum aviso de empresa; com, o destino resolvido agora.
    select array_agg(id) into mine from private.notification_outbox where worker_id = v_worker or company_id in (select id from public.companies where cnpj in (cnpj_c, cnpj_a, cnpj_b, cnpj_d, cnpj_e));
    execute 'set local role authenticated';
    begin
      perform public.notification_claim(10, true);
      falhas := falhas || jsonb_build_object('authenticated reserva a fila', true);
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    if to_regprocedure('public.notification_claim(integer)') is not null then falhas := falhas || jsonb_build_object('reserva antiga (integer) continua', true); end if;
    execute 'set local role service_role';
    select count(*) filter (where kind = 'company_notice') as notices, count(*) filter (where kind = 'company_update' and reason = 'released') as released
      into r from public.notification_claim(200) where outbox_id = any (mine);
    execute 'reset role';
    if r.notices <> 0 then falhas := falhas || jsonb_build_object('reserva padrão entregou aviso de empresa', r.notices); end if;
    if r.released < 1 then falhas := falhas || jsonb_build_object('reserva sem o motivo released', true); end if;
    if exists (select 1 from private.notification_outbox where notice_id in (n_a, n_b, n_d) and status <> 'pending') then
      falhas := falhas || jsonb_build_object('reserva padrão tocou nos avisos de empresa', true);
    end if;
    execute 'set local role service_role';
    select string_agg(c.reason || ':' || c.email, ',' order by c.email) as got into r
      from public.notification_claim(200, true) c where c.outbox_id = any (mine);
    execute 'reset role';
    if r.got is distinct from 'notice:receita@tx-b.invalid,notice:rh@tx-a.invalid' then
      falhas := falhas || jsonb_build_object('reserva com avisos (esperado Receita B e contato A)', r.got);
    end if;
    if (select status from private.notification_outbox where notice_id = n_d) is distinct from 'suppressed'
       or (select status from public.company_notices where id = n_d) is distinct from 'approved' then
      falhas := falhas || jsonb_build_object('opt-out depois da aprovação não suprimiu o envio (aviso continua approved)', true);
    end if;
    
    -- 4) Resultado reflete em company_notices: enviado -> sent (automático, sent_by nulo); 6ª falha -> bounced.
    select id into v_id from private.notification_outbox where notice_id = n_a;
    execute 'set local role service_role';
    perform public.notification_mark(v_id, 'sent', null, 1);
    execute 'reset role';
    if (select status || '/' || coalesce(sent_by::text, 'auto') || '/' || (sent_at is not null)::text from public.company_notices where id = n_a)
       is distinct from 'sent/auto/true' then
      falhas := falhas || jsonb_build_object('envio automático não marcou o aviso como sent', true);
    end if;
    select id into v_id from private.notification_outbox where notice_id = n_b;
    for i in 1..6 loop
      update private.notification_outbox set status = 'sending' where id = v_id;
      execute 'set local role service_role';
      perform public.notification_mark(v_id, 'retry', 'smtp_550', 0);
      execute 'reset role';
      if i = 5 and (select status from public.company_notices where id = n_b) is distinct from 'approved' then
        falhas := falhas || jsonb_build_object('aviso devolvido antes da falha definitiva', true);
      end if;
    end loop;
    if (select status from public.company_notices where id = n_b) is distinct from 'bounced' then
      falhas := falhas || jsonb_build_object('falha definitiva não marcou o aviso como bounced', true);
    end if;
    -- O 30 dias por empresa continua: cp_r (empresa A) não aprova depois do envio... já recusado; nova manifestação na A.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    cp_r := public.create_complaint(base || jsonb_build_object('company_id', co_a), true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_complaint(cp_r, 'released', null);
    begin
      perform public.ops_decide_notice(cp_r, 'approved', null, 'receita');
      falhas := falhas || jsonb_build_object('segundo aviso à empresa A em 30 dias', true);
    exception when others then null; end;
    execute 'reset role';
    -- A fila continua sem e-mail nem conteúdo.
    if exists (select 1 from information_schema.columns where table_schema = 'private' and table_name = 'notification_outbox'
               and column_name in ('email', 'body', 'content', 'subject', 'protocol', 'title', 'note', 'destination')) then
      falhas := falhas || jsonb_build_object('fila com coluna de conteúdo ou destino', true);
    end if;
    res := res || jsonb_build_object('verificações de avisos por evento e aviso automático', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
