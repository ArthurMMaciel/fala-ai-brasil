-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar contatos3_checks.sql e as migrations.
-- Migrations: 20261126120000_ate_3_contatos.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'f0000000-0000-0000-0000-000000000011'; u_c uuid := 'f0000000-0000-0000-0000-000000000012'; u_op uuid := 'f0000000-0000-0000-0000-000000000013'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_a text := '98765001987643'; cnpj_b text := '98765004987687'; cnpj_reg text := '98765005987621'; co_a uuid; co_b uuid; co_reg uuid; cp1 uuid; cp2 uuid; cp3 uuid; cp4 uuid; k1 uuid; k2 uuid; k3 uuid; n1 uuid; n int; r record; base jsonb;
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

    -- Verificações (contatos3_checks.sql)
    -- declare: u_w uuid := 'f0000000-0000-0000-0000-000000000011'; u_c uuid := 'f0000000-0000-0000-0000-000000000012'; u_op uuid := 'f0000000-0000-0000-0000-000000000013'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_a text := '98765001987643'; cnpj_b text := '98765004987687'; cnpj_reg text := '98765005987621'; co_a uuid; co_b uuid; co_reg uuid; cp1 uuid; cp2 uuid; cp3 uuid; cp4 uuid; k1 uuid; k2 uuid; k3 uuid; n1 uuid; n int; r record; base jsonb;
    -- Verificações de 20261126120000 (até 3 contatos por manifestação). CNPJs de teste conferidos como inexistentes
    -- (404 na Minha Receita e na BrasilAPI em 2026-11-18); CPF de teste só na transação.
    if exists (select 1 from public.companies where cnpj in (cnpj_a, cnpj_b, cnpj_reg)) or exists (select 1 from public.workers where cpf = '27182818205') then
      raise exception 'Valor de teste já existe; troque os CNPJs/CPF do teste.';
    end if;
    base := jsonb_build_object('category', 'Carga de trabalho', 'title', 'Tx caso', 'original_content', 'Tx relato original.',
                               'shared_content', 'Tx versao compartilhavel.', 'notice_consent', true);
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-3w@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Contatos Trabalhador', 'cpf', '27182818205', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-3c@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Contatos Cadastrada Ltda', 'cnpj', cnpj_reg, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-3op@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    select company_id into co_reg from public.company_users where user_id = u_c;
    -- Duas empresas não cadastradas vindas do cache, com e-mail da Receita.
    perform public.cnpj_cache_put(cnpj_a, false, 'Tx Empresa A Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', 'receita@tx-a.invalid');
    perform public.cnpj_cache_put(cnpj_b, false, 'Tx Empresa B Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', 'receita@tx-b.invalid');
    
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    -- Validação da lista.
    begin
      perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a, 'notice_contacts', jsonb_build_array(
        jsonb_build_object('email', 'a@x.invalid', 'possibly_involved', false, 'consent', true),
        jsonb_build_object('email', 'b@x.invalid', 'possibly_involved', false, 'consent', true),
        jsonb_build_object('email', 'c@x.invalid', 'possibly_involved', false, 'consent', true),
        jsonb_build_object('email', 'd@x.invalid', 'possibly_involved', false, 'consent', true))), true);
      falhas := falhas || jsonb_build_object('4 contatos aceitos', true);
    exception when others then null; end;
    begin
      perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a, 'notice_contacts', '[]'::jsonb), true);
      falhas := falhas || jsonb_build_object('lista vazia aceita', true);
    exception when others then null; end;
    begin
      perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a,
        'notice_contacts', jsonb_build_array(jsonb_build_object('email', 'a@x.invalid', 'possibly_involved', false, 'consent', true)),
        'notice_contact', jsonb_build_object('email', 'a@x.invalid', 'possibly_involved', false, 'consent', true)), true);
      falhas := falhas || jsonb_build_object('lista e objeto juntos aceitos', true);
    exception when others then null; end;
    begin
      perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a, 'notice_contacts', jsonb_build_array(
        jsonb_build_object('email', 'Rep@x.invalid', 'possibly_involved', false, 'consent', true),
        jsonb_build_object('email', 'rep@x.invalid', 'possibly_involved', true, 'consent', true))), true);
      falhas := falhas || jsonb_build_object('e-mail repetido aceito', true);
    exception when others then null; end;
    begin
      perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a, 'notice_contacts', jsonb_build_array(
        jsonb_build_object('email', 'a@x.invalid', 'possibly_involved', false, 'consent', true),
        jsonb_build_object('phone', '123', 'possibly_involved', false, 'consent', true))), true);
      falhas := falhas || jsonb_build_object('contato inválido na lista aceito', true);
    exception when others then null; end;
    
    -- cp1: 3 contatos (envolvido com o e-mail da Receita, só telefone, e-mail não envolvido).
    cp1 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'Receita@tx-a.invalid', 'possibly_involved', true, 'consent', true),
      jsonb_build_object('phone', '(11) 3333-0000', 'possibly_involved', false, 'consent', true),
      jsonb_build_object('email', 'rh@tx-a.invalid', 'possibly_involved', false, 'consent', true))), true);
    -- cp2: formato antigo (um objeto), compatível.
    execute 'reset role';
    select id into co_a from public.companies where cnpj = cnpj_a;
    execute 'set local role authenticated';
    cp2 := public.create_complaint(base || jsonb_build_object('company_id', co_a,
      'notice_contact', jsonb_build_object('email', 'ouvidoria@tx-a.invalid', 'possibly_involved', false, 'consent', true)), true);
    -- cp3: empresa B, só contatos envolvidos (nenhum com o e-mail da Receita B).
    cp3 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_b, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'chefe@tx-b.invalid', 'possibly_involved', true, 'consent', true))), true);
    -- cp4: empresa cadastrada, 2 contatos (segundo canal; sem aviso).
    cp4 := public.create_complaint(base || jsonb_build_object('company_id', co_reg, 'notice_contacts', jsonb_build_array(
      jsonb_build_object('email', 'rh@tx-reg.invalid', 'possibly_involved', false, 'consent', true),
      jsonb_build_object('phone', '11988887777', 'possibly_involved', false, 'consent', true))), true);
    -- Leitura do trabalhador.
    if (select count(*) from public.my_complaint_contacts_list(cp1)) <> 3 then falhas := falhas || jsonb_build_object('trabalhador não vê os 3 contatos', true); end if;
    if (select count(*) from public.my_complaint_contact(cp1)) <> 1
       or (select email from public.my_complaint_contact(cp1)) is distinct from 'rh@tx-a.invalid' then
      falhas := falhas || jsonb_build_object('my_complaint_contact sem o contato padrão (1 linha)', true);
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    if exists (select 1 from public.my_complaint_contacts_list(cp4)) then falhas := falhas || jsonb_build_object('empresa lê a lista de contatos', true); end if;
    execute 'reset role';
    select id into co_b from public.companies where cnpj = cnpj_b;
    -- Banco recusa o 4º contato direto.
    begin
      insert into public.complaint_contacts (complaint_id, email, possibly_involved, worker_consented) values (cp1, 'quarto@x.invalid', false, true);
      falhas := falhas || jsonb_build_object('4º contato aceito no banco', true);
    exception when others then null; end;
    if (select count(*) from public.complaint_contacts where complaint_id = cp1) <> 3 or (select count(*) from public.complaint_contacts where complaint_id = cp2) <> 1 then
      falhas := falhas || jsonb_build_object('contatos gravados em quantidade errada', true);
    end if;
    select id into k1 from public.complaint_contacts where complaint_id = cp1 and email = 'receita@tx-a.invalid';
    select id into k2 from public.complaint_contacts where complaint_id = cp1 and email is null;
    select id into k3 from public.complaint_contacts where complaint_id = cp1 and email = 'rh@tx-a.invalid';
    
    -- Equipe.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    if (select count(*) from public.ops_list_notice_candidates() c where c.complaint_id = cp1) <> 1 then
      falhas := falhas || jsonb_build_object('fila duplicou a manifestação com vários contatos', true);
    end if;
    select * into r from public.ops_list_notice_candidates() c where c.complaint_id = cp1;
    if r.contact_id is distinct from k3 or r.destination_source is distinct from 'worker' then
      falhas := falhas || jsonb_build_object('fila sem o contato padrão elegível', true);
    end if;
    if (select count(*) from public.ops_complaint_contacts_list(cp1)) <> 3
       or (select count(*) from public.ops_complaint_contacts_list(cp1) l where l.eligible_for_notice) <> 1 then
      falhas := falhas || jsonb_build_object('lista da equipe errada (3 contatos, 1 elegível)', true);
    end if;
    if (select count(*) from public.ops_complaint_contacts_list(cp4)) <> 2 then falhas := falhas || jsonb_build_object('equipe não vê os contatos da cadastrada', true); end if;
    perform public.ops_decide_complaint(cp1, 'released', null);
    perform public.ops_decide_complaint(cp2, 'released', null);
    perform public.ops_decide_complaint(cp3, 'released', null);
    -- Destino escolhido: envolvido, sem e-mail, de outra manifestação e Receita igual ao envolvido são recusados.
    begin perform public.ops_decide_notice(cp1, 'approved', null, null, k1); falhas := falhas || jsonb_build_object('aviso a contato envolvido', true); exception when others then null; end;
    begin perform public.ops_decide_notice(cp1, 'approved', null, null, k2); falhas := falhas || jsonb_build_object('aviso a contato sem e-mail', true); exception when others then null; end;
    begin perform public.ops_decide_notice(cp2, 'approved', null, null, k3); falhas := falhas || jsonb_build_object('contato de outra manifestação aceito', true); exception when others then null; end;
    begin
      perform public.ops_decide_notice(cp1, 'approved', null, 'receita');
      falhas := falhas || jsonb_build_object('Receita igual a contato envolvido aceita', true);
    exception when others then
      if sqlerrm not like '%possivelmente envolvido%' then falhas := falhas || jsonb_build_object('mensagem Receita = envolvido', sqlerrm); end if;
    end;
    -- Aprovado com o contato escolhido; o contato vira verified e o aviso guarda o contact_id.
    n1 := public.ops_decide_notice(cp1, 'approved', null, null, k3);
    -- 30 dias por empresa continua valendo (cp2 é da mesma empresa A).
    begin perform public.ops_decide_notice(cp2, 'approved', null); falhas := falhas || jsonb_build_object('segundo aviso à empresa A em 30 dias', true); exception when others then null; end;
    -- Empresa B: sem contato elegível, o padrão vai para a Receita (diferente do envolvido).
    n := 0;
    perform public.ops_decide_notice(cp3, 'approved', null);
    execute 'reset role';
    if (select contact_id from public.company_notices where id = n1) is distinct from k3
       or (select status from public.complaint_contacts where id = k3) is distinct from 'verified' then
      falhas := falhas || jsonb_build_object('aviso sem o contato escolhido ou contato não verificado', true);
    end if;
    if (select destination_source from public.company_notices where complaint_id = cp3 and status = 'approved') is distinct from 'receita' then
      falhas := falhas || jsonb_build_object('sem contato elegível, destino não foi a Receita', true);
    end if;
    -- Retenção vale para cada contato (manifestação encerrada há mais de 90 dias).
    update public.complaints set status = 'closed', closed_at = now() - interval '91 days' where id = cp4;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    if public.ops_purge_expired_contacts() < 2 then falhas := falhas || jsonb_build_object('retenção não apagou os 2 contatos vencidos', true); end if;
    execute 'reset role';
    res := res || jsonb_build_object('verificações de até 3 contatos', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
