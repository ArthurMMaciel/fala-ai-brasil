-- ADR-0023 e ADR-0017 (aceitas em 2026-11-17), migration 2 de 2: funções.
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
$$;
create function private.email_hash(p text)
returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(lower(btrim(coalesce(p, ''))), 'UTF8')), 'hex');
$$;
revoke all on function private.norm_cnpj(text), private.email_hash(text) from public, anon, authenticated;

-- 1) Busca na base própria. Não informa se a empresa é pré-cadastrada nem se tem manifestação. Conta na cota da busca.
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
$$;

-- 2) Pré-cadastro a partir do cache gravado pela Edge Function (ADR-0017 D8). Nunca com dados enviados pelo cliente.
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
$$;

-- 3) Plano B: API fora do ar, CNPJ não encontrado ou pessoa física. Nasce pending_check para a equipe conferir.
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
$$;

-- 4) Nova manifestação: corpo de 20261117150000 (com a checagem da pausa) + contato opcional para o aviso.
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
$$;

-- 5) Equipe: empresas fora do cadastro, para conferir na Receita.
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
$$;

-- Conferência: confirmed (dados batem na Receita) ou blocked (dado errado; nenhum aviso). Pode marcar pessoa física.
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
$$;

-- 6) Equipe: manifestações com e-mail indicado para o aviso.
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
$$;

-- Decisão do aviso. As travas valem no banco (ADR-0023, variante a).
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
$$;

-- Registro do envio manual (a1): sent, ou bounced se o e-mail voltar.
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
$$;

-- Pedido de não receber avisos (atendido pela equipe; sem link no piloto).
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
$$;

-- Retenção do contato (decisão 5 da ADR-0023): 90 dias após o encerramento da manifestação ou a recusa do aviso.
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
$$;

revoke execute on function public.find_company_by_cnpj(text), public.preregister_company(text),
  public.preregister_company_manual(text, text, text, text), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text), public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() from public, anon;
grant execute on function public.find_company_by_cnpj(text), public.preregister_company(text),
  public.preregister_company_manual(text, text, text, text), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text), public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() to authenticated;
