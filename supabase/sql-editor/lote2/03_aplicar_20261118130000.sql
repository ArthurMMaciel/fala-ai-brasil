-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/pending/20261118130000_empresa_pre_cadastrada_funcoes.sql. Não editar à mão.
-- Passo 03 de 05. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 03_conferir_20261118130000.sql (todas as linhas com ok = true).
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261118130000') then
    raise exception 'A migration 20261118130000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118120000') then
    raise exception 'Falta a 20261118120000 (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261118130000_empresa_pre_cadastrada_funcoes.sql (19 instruções) ========
-- ADR-0023 e ADR-0017 (aceitas em 2026-11-17), migration 2 de 2: funções. Revista em 2026-11-18 pela revisão do DevOps.
-- Depende de 20261118120000 (estrutura) e de 20261117150000 (create_complaint com a checagem da pausa).
-- Pré-requisito de operação: 20261117130000 (troca do gate) aplicada antes de qualquer aviso sair, porque a empresa
-- avisada vai se cadastrar; ops_decide_notice recusa aprovar sem ela.
--
-- Regra de não revelar (decisões "grava quando relatar" e "aviso sem revelar"): a pré-cadastrada só existe porque alguém
-- relatou. Nada que um cliente chama pode distinguir "nunca relatada" de "já relatada":
--   - find_company_by_cnpj devolve só empresa registered (a mesma que está no diretório);
--   - não há RPC de pré-cadastro: a empresa nasce dentro de create_complaint, na mesma transação do relato;
--   - em create_complaint, as validações e a cota não dependem de a empresa existir.
-- Revisão de 2026-11-19 (responsável, "Isso, confirmo"): o contato do trabalhador (e-mail e/ou telefone) é gravado para
-- qualquer empresa; na não cadastrada é o destino do aviso, e sem ele a equipe pode usar o e-mail da Receita; na
-- cadastrada é segundo canal para a equipe e não gera aviso.
-- Revisão do DevOps (2026-11-19): o aviso exige p.notice_consent = true no relato (com ou sem contato); com destino
-- Receita, recusa se o e-mail da Receita for o do contato marcado como possivelmente envolvido.
-- Empresa pré-cadastrada fora do diretório, do ranking, da responsividade, da lista dos parceiros e de ops_list_companies:
-- essas funções fazem join interno com addresses, e a pré-cadastrada não tem endereço (check da migration 1). O teste
-- confere; nenhuma delas é redefinida aqui.
--
-- Rollback: reaplicar create_complaint de 20261117150000; depois
--   drop function public.find_company_by_cnpj(text), public.my_complaint_companies(), private.preregister_company(text, jsonb),
--     public.ops_list_pending_companies(), public.ops_review_company(uuid, text, text, boolean),
--     public.ops_list_notice_candidates(), public.ops_decide_notice(uuid, text, text, text), public.ops_complaint_contact(uuid),
--     public.my_complaint_contact(uuid), public.ops_mark_notice_sent(uuid, text),
--     public.ops_add_opt_out(text), public.ops_purge_expired_contacts(), private.norm_cnpj(text), private.email_hash(text);

-- Normalização comum.
create function private.norm_cnpj(p text)
returns text language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g'));
$$;
create function private.email_hash(p text)
returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(lower(btrim(coalesce(p, ''))), 'UTF8')), 'hex');
$$;
revoke all on function private.norm_cnpj(text), private.email_hash(text) from public, anon, authenticated, service_role;

-- 1) Busca por CNPJ só entre as cadastradas (as mesmas do diretório). Não cadastrada, nunca relatada ou já relatada:
-- a mesma resposta (nenhuma linha), e o front segue pela Edge Function. Sem cota: não revela nada além do diretório.
create function public.find_company_by_cnpj(p_cnpj text)
returns table (id uuid, name text, city text, state text)
language plpgsql stable security definer set search_path = '' as $$
declare v_cnpj text := private.norm_cnpj(p_cnpj);
begin
  if auth.uid() is null then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state
  from public.companies co
  join public.addresses a on a.id = co.address_id
  where co.cnpj = v_cnpj and co.registration_status = 'registered';
end;
$$;

-- 2) Resolve a empresa de um relato pelo CNPJ (só chamada por create_complaint). Devolve a existente, de qualquer estado,
-- ou cria a pré-cadastrada: do cache (ADR-0017 D8), ou dos dados manuais (plano B, pending_check). A validação dos dados
-- manuais é feita por quem chama, antes, sem olhar se a empresa existe.
create function private.preregister_company(p_cnpj text, p_manual jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; c record;
begin
  select co.id into v_id from public.companies co where co.cnpj = p_cnpj for update;
  if v_id is not null then return v_id; end if;
  select * into c from private.cnpj_cache where cnpj = p_cnpj;
  if found and not c.natural_person then
    insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by, registration_status, data_source)
    values (c.legal_name, c.trade_name, p_cnpj, null, null, 'pre_registered', 'cnpj_api')
    on conflict (cnpj) do nothing returning id into v_id;
    if v_id is not null then
      insert into private.company_preregistrations (company_id, original_name, city, state, cadastral_situation, main_cnae,
                                                    legal_nature, natural_person, provider, fetched_at)
      values (v_id, c.legal_name, c.city, c.state, c.cadastral_situation, c.main_cnae, c.legal_nature, false, c.provider, c.fetched_at);
    end if;
  else
    insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by, registration_status, data_source)
    values (btrim(p_manual ->> 'name'), null, p_cnpj, null, null, 'pending_check', 'manual')
    on conflict (cnpj) do nothing returning id into v_id;
    if v_id is not null then
      insert into private.company_preregistrations (company_id, original_name, city, state, natural_person)
      values (v_id, btrim(p_manual ->> 'name'), btrim(p_manual ->> 'city'), upper(btrim(p_manual ->> 'state')),
              coalesce(c.natural_person, false));
    end if;
  end if;
  if v_id is null then  -- outro relato criou a mesma empresa ao mesmo tempo
    select co.id into v_id from public.companies co where co.cnpj = p_cnpj;
  end if;
  return v_id;
end;
$$;
revoke all on function private.preregister_company(text, jsonb) from public, anon, authenticated, service_role;

-- 3) Nova manifestação: corpo de 20261117150000 (com a checagem da pausa) + empresa pelo CNPJ + contato para o aviso.
-- Empresa: p.company_id (cadastrada, do diretório ou de find_company_by_cnpj) OU p.company_cnpj, com
-- p.company_manual = {"name", "city", "state"} quando a Edge Function não trouxe os dados (manual). Pelo CNPJ: até 3
-- relatos por dia por conta, contados existindo a empresa ou não; dados manuais exigidos sempre que o cache não tiver a
-- empresa, existindo ela ou não.
-- Contato: p.notice_contact = {"email"?, "phone"?, "possibly_involved": bool, "consent": true}, só com p_share; pelo menos
-- e-mail ou telefone. Gravado para qualquer empresa (revisão de 2026-11-19). O "consent" do contato é o uso dele pela equipe.
-- Aviso: p.notice_consent (boolean), consentimento do trabalhador ao aviso à empresa não cadastrada, com ou sem contato.
-- Aceito e guardado para qualquer empresa (só é usado na não cadastrada), para não revelar o estado da empresa; true só
-- com p_share.
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

-- 3b) Nome das empresas dos próprios relatos, para a lista do trabalhador. O diretório não serve: ele exclui a
-- pré-cadastrada (sem endereço), e a tela mostrava "—". Só empresas em que a conta tem relato; nada de estado,
-- origem nem contato. Município e UF vêm do endereço (cadastrada) ou do pré-cadastro.
create function public.my_complaint_companies()
returns table (company_id uuid, name text, city text, state text)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), coalesce(a.city, pr.city), coalesce(a.state, pr.state)
  from public.companies co
  left join public.addresses a on a.id = co.address_id
  left join private.company_preregistrations pr on pr.company_id = co.id
  where exists (select 1 from public.complaints c join public.workers w on w.id = c.worker_id
                where c.company_id = co.id and w.user_id = auth.uid())
  order by 2;
$$;

-- 4) Equipe: empresas fora do cadastro, para conferir na Receita.
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

-- 5) Equipe: fila do aviso (revisão de 2026-11-19). Uma linha por manifestação de empresa NÃO cadastrada. Destino: o
-- e-mail do contato do trabalhador; sem ele, o e-mail da Receita (cache), marcado 'receita'. Nada é enviado
-- automaticamente: a equipe aprova ou recusa (ops_decide_notice) e envia à mão.
create function public.ops_list_notice_candidates()
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

-- Decisão do aviso. Travas no banco (ADR-0023, variante a): manifestação liberada (shared); troca do gate aplicada;
-- empresa não cadastrada, conferida, não bloqueada e não pessoa física; 30 dias por empresa; destino sem opt-out.
-- Destino: p_destination = 'worker' (e-mail do contato do trabalhador, que não pode estar marcado como possivelmente
-- envolvido) ou 'receita' (e-mail do cache). Sem p_destination: o do trabalhador, se houver e-mail; senão o da Receita.
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

-- Contato da manifestação para a equipe (detalhe na Operação). Na empresa cadastrada, é o segundo canal; não gera aviso.
create function public.ops_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean, status text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query select k.email, k.phone, k.possibly_involved, k.status, k.created_at
  from public.complaint_contacts k where k.complaint_id = p_complaint;
end;
$$;

-- Contato da manifestação para o próprio trabalhador. A empresa nunca lê.
create function public.my_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean)
language sql stable security definer set search_path = '' as $$
  select k.email, k.phone, k.possibly_involved
  from public.complaint_contacts k
  join public.complaints c on c.id = k.complaint_id
  join public.workers w on w.id = c.worker_id
  where k.complaint_id = p_complaint and w.user_id = auth.uid();
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

revoke execute on function public.find_company_by_cnpj(text), public.my_complaint_companies(), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text, text), public.ops_complaint_contact(uuid), public.my_complaint_contact(uuid),
  public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() from public, anon, service_role;
grant execute on function public.find_company_by_cnpj(text), public.my_complaint_companies(), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text, text), public.ops_complaint_contact(uuid), public.my_complaint_contact(uuid),
  public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() to authenticated;
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261118130000', 'empresa_pre_cadastrada_funcoes', array[
$s0$-- ADR-0023 e ADR-0017 (aceitas em 2026-11-17), migration 2 de 2: funções. Revista em 2026-11-18 pela revisão do DevOps.
-- Depende de 20261118120000 (estrutura) e de 20261117150000 (create_complaint com a checagem da pausa).
-- Pré-requisito de operação: 20261117130000 (troca do gate) aplicada antes de qualquer aviso sair, porque a empresa
-- avisada vai se cadastrar; ops_decide_notice recusa aprovar sem ela.
--
-- Regra de não revelar (decisões "grava quando relatar" e "aviso sem revelar"): a pré-cadastrada só existe porque alguém
-- relatou. Nada que um cliente chama pode distinguir "nunca relatada" de "já relatada":
--   - find_company_by_cnpj devolve só empresa registered (a mesma que está no diretório);
--   - não há RPC de pré-cadastro: a empresa nasce dentro de create_complaint, na mesma transação do relato;
--   - em create_complaint, as validações e a cota não dependem de a empresa existir.
-- Revisão de 2026-11-19 (responsável, "Isso, confirmo"): o contato do trabalhador (e-mail e/ou telefone) é gravado para
-- qualquer empresa; na não cadastrada é o destino do aviso, e sem ele a equipe pode usar o e-mail da Receita; na
-- cadastrada é segundo canal para a equipe e não gera aviso.
-- Revisão do DevOps (2026-11-19): o aviso exige p.notice_consent = true no relato (com ou sem contato); com destino
-- Receita, recusa se o e-mail da Receita for o do contato marcado como possivelmente envolvido.
-- Empresa pré-cadastrada fora do diretório, do ranking, da responsividade, da lista dos parceiros e de ops_list_companies:
-- essas funções fazem join interno com addresses, e a pré-cadastrada não tem endereço (check da migration 1). O teste
-- confere; nenhuma delas é redefinida aqui.
--
-- Rollback: reaplicar create_complaint de 20261117150000; depois
--   drop function public.find_company_by_cnpj(text), public.my_complaint_companies(), private.preregister_company(text, jsonb),
--     public.ops_list_pending_companies(), public.ops_review_company(uuid, text, text, boolean),
--     public.ops_list_notice_candidates(), public.ops_decide_notice(uuid, text, text, text), public.ops_complaint_contact(uuid),
--     public.my_complaint_contact(uuid), public.ops_mark_notice_sent(uuid, text),
--     public.ops_add_opt_out(text), public.ops_purge_expired_contacts(), private.norm_cnpj(text), private.email_hash(text);

-- Normalização comum.
create function private.norm_cnpj(p text)
returns text language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g'));
$$$s0$,
$s0$create function private.email_hash(p text)
returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(lower(btrim(coalesce(p, ''))), 'UTF8')), 'hex');
$$$s0$,
$s0$revoke all on function private.norm_cnpj(text), private.email_hash(text) from public, anon, authenticated, service_role$s0$,
$s0$-- 1) Busca por CNPJ só entre as cadastradas (as mesmas do diretório). Não cadastrada, nunca relatada ou já relatada:
-- a mesma resposta (nenhuma linha), e o front segue pela Edge Function. Sem cota: não revela nada além do diretório.
create function public.find_company_by_cnpj(p_cnpj text)
returns table (id uuid, name text, city text, state text)
language plpgsql stable security definer set search_path = '' as $$
declare v_cnpj text := private.norm_cnpj(p_cnpj);
begin
  if auth.uid() is null then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state
  from public.companies co
  join public.addresses a on a.id = co.address_id
  where co.cnpj = v_cnpj and co.registration_status = 'registered';
end;
$$$s0$,
$s0$-- 2) Resolve a empresa de um relato pelo CNPJ (só chamada por create_complaint). Devolve a existente, de qualquer estado,
-- ou cria a pré-cadastrada: do cache (ADR-0017 D8), ou dos dados manuais (plano B, pending_check). A validação dos dados
-- manuais é feita por quem chama, antes, sem olhar se a empresa existe.
create function private.preregister_company(p_cnpj text, p_manual jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; c record;
begin
  select co.id into v_id from public.companies co where co.cnpj = p_cnpj for update;
  if v_id is not null then return v_id; end if;
  select * into c from private.cnpj_cache where cnpj = p_cnpj;
  if found and not c.natural_person then
    insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by, registration_status, data_source)
    values (c.legal_name, c.trade_name, p_cnpj, null, null, 'pre_registered', 'cnpj_api')
    on conflict (cnpj) do nothing returning id into v_id;
    if v_id is not null then
      insert into private.company_preregistrations (company_id, original_name, city, state, cadastral_situation, main_cnae,
                                                    legal_nature, natural_person, provider, fetched_at)
      values (v_id, c.legal_name, c.city, c.state, c.cadastral_situation, c.main_cnae, c.legal_nature, false, c.provider, c.fetched_at);
    end if;
  else
    insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by, registration_status, data_source)
    values (btrim(p_manual ->> 'name'), null, p_cnpj, null, null, 'pending_check', 'manual')
    on conflict (cnpj) do nothing returning id into v_id;
    if v_id is not null then
      insert into private.company_preregistrations (company_id, original_name, city, state, natural_person)
      values (v_id, btrim(p_manual ->> 'name'), btrim(p_manual ->> 'city'), upper(btrim(p_manual ->> 'state')),
              coalesce(c.natural_person, false));
    end if;
  end if;
  if v_id is null then  -- outro relato criou a mesma empresa ao mesmo tempo
    select co.id into v_id from public.companies co where co.cnpj = p_cnpj;
  end if;
  return v_id;
end;
$$$s0$,
$s0$revoke all on function private.preregister_company(text, jsonb) from public, anon, authenticated, service_role$s0$,
$s0$-- 3) Nova manifestação: corpo de 20261117150000 (com a checagem da pausa) + empresa pelo CNPJ + contato para o aviso.
-- Empresa: p.company_id (cadastrada, do diretório ou de find_company_by_cnpj) OU p.company_cnpj, com
-- p.company_manual = {"name", "city", "state"} quando a Edge Function não trouxe os dados (manual). Pelo CNPJ: até 3
-- relatos por dia por conta, contados existindo a empresa ou não; dados manuais exigidos sempre que o cache não tiver a
-- empresa, existindo ela ou não.
-- Contato: p.notice_contact = {"email"?, "phone"?, "possibly_involved": bool, "consent": true}, só com p_share; pelo menos
-- e-mail ou telefone. Gravado para qualquer empresa (revisão de 2026-11-19). O "consent" do contato é o uso dele pela equipe.
-- Aviso: p.notice_consent (boolean), consentimento do trabalhador ao aviso à empresa não cadastrada, com ou sem contato.
-- Aceito e guardado para qualquer empresa (só é usado na não cadastrada), para não revelar o estado da empresa; true só
-- com p_share.
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
$$$s0$,
$s0$-- 3b) Nome das empresas dos próprios relatos, para a lista do trabalhador. O diretório não serve: ele exclui a
-- pré-cadastrada (sem endereço), e a tela mostrava "—". Só empresas em que a conta tem relato; nada de estado,
-- origem nem contato. Município e UF vêm do endereço (cadastrada) ou do pré-cadastro.
create function public.my_complaint_companies()
returns table (company_id uuid, name text, city text, state text)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), coalesce(a.city, pr.city), coalesce(a.state, pr.state)
  from public.companies co
  left join public.addresses a on a.id = co.address_id
  left join private.company_preregistrations pr on pr.company_id = co.id
  where exists (select 1 from public.complaints c join public.workers w on w.id = c.worker_id
                where c.company_id = co.id and w.user_id = auth.uid())
  order by 2;
$$$s0$,
$s0$-- 4) Equipe: empresas fora do cadastro, para conferir na Receita.
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
$$$s0$,
$s0$-- Conferência: confirmed (dados batem na Receita) ou blocked (dado errado; nenhum aviso). Pode marcar pessoa física.
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
$$$s0$,
$s0$-- 5) Equipe: fila do aviso (revisão de 2026-11-19). Uma linha por manifestação de empresa NÃO cadastrada. Destino: o
-- e-mail do contato do trabalhador; sem ele, o e-mail da Receita (cache), marcado 'receita'. Nada é enviado
-- automaticamente: a equipe aprova ou recusa (ops_decide_notice) e envia à mão.
create function public.ops_list_notice_candidates()
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
$$$s0$,
$s0$-- Decisão do aviso. Travas no banco (ADR-0023, variante a): manifestação liberada (shared); troca do gate aplicada;
-- empresa não cadastrada, conferida, não bloqueada e não pessoa física; 30 dias por empresa; destino sem opt-out.
-- Destino: p_destination = 'worker' (e-mail do contato do trabalhador, que não pode estar marcado como possivelmente
-- envolvido) ou 'receita' (e-mail do cache). Sem p_destination: o do trabalhador, se houver e-mail; senão o da Receita.
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
$$$s0$,
$s0$-- Contato da manifestação para a equipe (detalhe na Operação). Na empresa cadastrada, é o segundo canal; não gera aviso.
create function public.ops_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean, status text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query select k.email, k.phone, k.possibly_involved, k.status, k.created_at
  from public.complaint_contacts k where k.complaint_id = p_complaint;
end;
$$$s0$,
$s0$-- Contato da manifestação para o próprio trabalhador. A empresa nunca lê.
create function public.my_complaint_contact(p_complaint uuid)
returns table (email text, phone text, possibly_involved boolean)
language sql stable security definer set search_path = '' as $$
  select k.email, k.phone, k.possibly_involved
  from public.complaint_contacts k
  join public.complaints c on c.id = k.complaint_id
  join public.workers w on w.id = c.worker_id
  where k.complaint_id = p_complaint and w.user_id = auth.uid();
$$$s0$,
$s0$-- Registro do envio manual (a1): sent, ou bounced se o e-mail voltar.
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
$$$s0$,
$s0$-- Pedido de não receber avisos (atendido pela equipe; sem link no piloto).
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
$$$s0$,
$s0$-- Retenção do contato (decisão 5 da ADR-0023): 90 dias após o encerramento da manifestação ou a recusa do aviso.
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
$$$s0$,
$s0$revoke execute on function public.find_company_by_cnpj(text), public.my_complaint_companies(), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text, text), public.ops_complaint_contact(uuid), public.my_complaint_contact(uuid),
  public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() from public, anon, service_role$s0$,
$s0$grant execute on function public.find_company_by_cnpj(text), public.my_complaint_companies(), public.ops_list_pending_companies(),
  public.ops_review_company(uuid, text, text, boolean), public.ops_list_notice_candidates(),
  public.ops_decide_notice(uuid, text, text, text), public.ops_complaint_contact(uuid), public.my_complaint_contact(uuid),
  public.ops_mark_notice_sent(uuid, text), public.ops_add_opt_out(text),
  public.ops_purge_expired_contacts() to authenticated$s0$
]::text[]);

commit;
