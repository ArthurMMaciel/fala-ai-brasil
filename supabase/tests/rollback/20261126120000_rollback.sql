-- Rollback do lote 5, passo 01 (20261126120000, até 3 contatos). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Volta a 1 contato por manifestação e às funções de 20261118130000. Recusa se alguma manifestação tiver mais de 1
-- contato (decisão do responsável antes: apagar os extras ou manter a migration). A versão sai de schema_migrations.
-- Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261126120000') then
    raise exception 'A 20261126120000 não está registrada. Nada foi feito.';
  end if;
  if exists (select 1 from public.complaint_contacts group by complaint_id having count(*) > 1) then
    raise exception 'Há manifestação com mais de 1 contato. Decida antes o que fazer com os extras. Nada foi feito.';
  end if;
end $trava$;

drop function public.ops_complaint_contacts_list(uuid), public.my_complaint_contacts_list(uuid);
drop function public.ops_decide_notice(uuid, text, text, text, uuid);

-- Funções de 20261118130000, literais.
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
  v_contact jsonb := p -> 'notice_contact';
  v_email text;
  v_phone text;
  v_has_contact boolean := false;
  v_notice_consent jsonb := p -> 'notice_consent';
begin
  perform private.assert_pilot_open();
  select id into v_worker from public.workers where user_id = auth.uid();
  if v_worker is null then raise exception 'Somente trabalhadores podem registrar manifestações.' using errcode = 'P0001'; end if;
  if p_share and v_shared is null then raise exception 'Escreva a versão que poderá ser compartilhada com a empresa.' using errcode = 'P0001'; end if;

  -- Contato: só validação de entrada, sem olhar a empresa.
  if v_contact is not null and jsonb_typeof(v_contact) <> 'null' then
    if jsonb_typeof(v_contact) <> 'object' then raise exception 'Contato para o aviso inválido.' using errcode = 'P0001'; end if;
    if not p_share then
      raise exception 'O aviso à empresa só é possível quando você envia a versão compartilhável para revisão.' using errcode = 'P0001';
    end if;
    v_email := nullif(lower(btrim(coalesce(v_contact ->> 'email', ''))), '');
    v_phone := nullif(regexp_replace(coalesce(v_contact ->> 'phone', ''), '\D', '', 'g'), '');
    if v_email is null and v_phone is null then
      raise exception 'Informe um e-mail ou um telefone de contato.' using errcode = 'P0001';
    end if;
    if v_email is not null and (char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
      raise exception 'Informe um e-mail de contato válido.' using errcode = 'P0001';
    end if;
    if v_phone is not null and v_phone !~ '^\d{10,11}$' then
      raise exception 'Informe um telefone de contato com DDD (10 ou 11 dígitos).' using errcode = 'P0001';
    end if;
    v_has_contact := true;
    if jsonb_typeof(v_contact -> 'possibly_involved') is distinct from 'boolean' then
      raise exception 'Responda se a pessoa desse contato pode estar envolvida no que você relata.' using errcode = 'P0001';
    end if;
    if jsonb_typeof(v_contact -> 'consent') is distinct from 'boolean' or not (v_contact ->> 'consent')::boolean then
      raise exception 'Para indicar um contato, confirme o uso dele pela equipe.' using errcode = 'P0001';
    end if;
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
  if v_has_contact then
    insert into public.complaint_contacts (complaint_id, email, phone, possibly_involved, worker_consented)
    values (v_id, v_email, v_phone, (v_contact ->> 'possibly_involved')::boolean, true);
  end if;
  return v_id;
end;
$$;

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
  left join public.complaint_contacts k on k.complaint_id = c.id
  left join private.complaint_notice_consents nc on nc.complaint_id = c.id
  left join private.cnpj_cache cc on cc.cnpj = co.cnpj and not cc.natural_person
  cross join lateral (select case when k.email is not null then k.email else cc.email end as email,
                             case when k.email is not null then 'worker' when cc.email is not null then 'receita' end as source) d
  left join lateral (select n.id, n.status from public.company_notices n where n.complaint_id = c.id
                     order by n.decided_at desc limit 1) ln on true
  where co.registration_status <> 'registered' and c.status not in ('received', 'canceled')
  order by (ln.id is null) desc, c.created_at;
end;
$$;

create function public.ops_decide_notice(p_complaint uuid, p_decision text, p_reason text default null,
                                         p_destination text default null)
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
  select * into k from public.complaint_contacts where complaint_id = p_complaint for update;
  select * into pr from private.company_preregistrations where company_id = v_company;
  select email into v_receita from private.cnpj_cache where cnpj = co.cnpj and not natural_person;

  if p_decision = 'rejected' then
    if v_reason is null or char_length(v_reason) not between 10 and 300 then
      raise exception 'Informe o motivo (10 a 300 caracteres, sem conteúdo de relato).' using errcode = 'P0001';
    end if;
    insert into public.company_notices (company_id, complaint_id, contact_id, status, reason, decided_by)
    values (v_company, p_complaint, k.id, 'rejected', v_reason, auth.uid()) returning id into v_id;
    if k.id is not null then
      update public.complaint_contacts set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now() where id = k.id;
    end if;
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
  v_source := coalesce(p_destination, case when k.email is not null then 'worker' else 'receita' end);
  if v_source = 'worker' then
    if k.email is null then raise exception 'O trabalhador não indicou e-mail para o aviso.' using errcode = 'P0001'; end if;
    if k.possibly_involved then
      raise exception 'O trabalhador marcou esse contato como possivelmente envolvido: aviso não permitido para ele.' using errcode = 'P0001';
    end if;
    v_email := k.email;
  else
    if v_receita is null then raise exception 'Não há e-mail da Receita para esta empresa.' using errcode = 'P0001'; end if;
    if k.possibly_involved and k.email is not null and k.email = v_receita then
      raise exception 'O e-mail da Receita é o do contato marcado como possivelmente envolvido: aviso não permitido.' using errcode = 'P0001';
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
$$;

create or replace function public.ops_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean, status text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query select k.email, k.phone, k.possibly_involved, k.status, k.created_at
  from public.complaint_contacts k where k.complaint_id = p_complaint;
end;
$$;

create or replace function public.my_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean)
language sql stable security definer set search_path = '' as $$
  select k.email, k.phone, k.possibly_involved
  from public.complaint_contacts k
  join public.complaints c on c.id = k.complaint_id
  join public.workers w on w.id = c.worker_id
  where k.complaint_id = p_complaint and w.user_id = auth.uid();
$$;

revoke execute on function public.ops_decide_notice(uuid, text, text, text) from public, anon, service_role;
grant execute on function public.ops_decide_notice(uuid, text, text, text) to authenticated;

drop trigger complaint_contacts_max3 on public.complaint_contacts;
drop function private.complaint_contacts_max3(), private.default_complaint_contact(uuid);
drop index public.complaint_contacts_complaint_idx;
alter table public.complaint_contacts add constraint complaint_contacts_complaint_id_key unique (complaint_id);
delete from supabase_migrations.schema_migrations where version = '20261126120000';

commit;
