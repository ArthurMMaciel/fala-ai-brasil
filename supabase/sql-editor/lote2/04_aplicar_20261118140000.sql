-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/pending/20261118140000_reivindicacao_cnpj.sql. Não editar à mão.
-- Passo 04 de 04. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 04_conferir_20261118140000.sql (todas as linhas com ok = true).
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261118140000') then
    raise exception 'A migration 20261118140000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118130000') then
    raise exception 'Falta a 20261118130000 (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261118140000_reivindicacao_cnpj.sql (2 instruções) ========
-- ADR-0023 / ADR-0012 D11 (aceitas em 2026-11-17), migration 3: reivindicação da empresa pré-cadastrada no cadastro.
-- Prioridade do responsável (2026-11-18, via Gestor): a empresa avisada precisa conseguir se cadastrar; sem isto, o
-- cadastro falha por CNPJ duplicado. Não pode ser cortada.
-- Muda private.create_profile (gatilho do signUp e add_profile), só no ramo 'company':
--   - CNPJ pré-cadastrado (pre_registered ou pending_check): a conta reivindica: dados e endereço do cadastro,
--     created_by = conta, registration_status = 'registered', vínculo 'owner' com verification_status 'pending'.
--   - CNPJ que veio de pré-cadastro e já foi reivindicado: a conta entra como 'member' 'pending'.
--   - CNPJ de empresa que se cadastrou direto (data_source 'signup'): sem mudança (falha por CNPJ duplicado, como hoje).
--   - Demais tipos de conta: corpo idêntico ao de 20261109140000.
-- Pré-requisito: troca do gate (20261117130000) aplicada; sem ela, quem reivindica veria os casos liberados sem
-- verificação. A trava abaixo recusa a migration se list_company_complaints ainda não usar is_verified_company_user.
--
-- Rollback: reaplicar private.create_profile de 20261109140000_cpf_unico.sql. Empresas já reivindicadas continuam
-- registered, com o dono e o endereço do cadastro.

do $trava$
begin
  if not exists (select 1 from pg_proc where oid = to_regprocedure('public.list_company_complaints()')
                 and prosrc like '%is_verified_company_user%') then
    raise exception 'A troca do gate (20261117130000) não está aplicada. A reivindicação não pode entrar antes dela.';
  end if;
  if to_regclass('private.company_preregistrations') is null then
    raise exception 'A estrutura da empresa pré-cadastrada (20261118120000) não está aplicada.';
  end if;
end $trava$;

create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
  v_doc text;
  v_reg text;
  v_src text;
begin
  if p_user is null then raise exception 'usuário obrigatório' using errcode = '22023'; end if;
  if p is null then raise exception 'dados do cadastro obrigatórios' using errcode = '22023'; end if;
  if p_type not in ('worker', 'company', 'partner', 'sponsor') then
    raise exception 'tipo de conta inválido' using errcode = '22023';
  end if;

  if p_type = 'worker' or (p_type = 'partner' and p ->> 'document_type' = 'cpf') then
    v_doc := regexp_replace(coalesce(p ->> case when p_type = 'worker' then 'cpf' else 'document' end, ''), '\D', '', 'g');
    if not private.valid_cpf(v_doc) then raise exception 'CPF inválido' using errcode = '22023'; end if;
  else
    v_doc := upper(regexp_replace(coalesce(p ->> case when p_type = 'partner' then 'document' else 'cnpj' end, ''), '[^0-9A-Za-z]', '', 'g'));
    if not private.valid_cnpj(v_doc) then raise exception 'CNPJ inválido' using errcode = '22023'; end if;
  end if;

  v_address := private.create_address(p -> 'address');

  if p_type = 'worker' then
    begin
      insert into public.workers (user_id, full_name, cpf, phone, address_id)
      values (p_user, btrim(p ->> 'full_name'), v_doc,
              nullif(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), ''), v_address)
      returning id into v_id;
    exception when unique_violation then
      -- CPF de outro trabalhador ou conta que já tem perfil de trabalhador: mensagem genérica, sem o valor.
      raise exception 'Não foi possível concluir o cadastro.' using errcode = '23505';
    end;
  elsif p_type = 'company' then
    select c.id, c.registration_status, c.data_source into v_id, v_reg, v_src from public.companies c where c.cnpj = v_doc for update;
    if v_id is not null and v_reg <> 'registered' then
      -- D11: a primeira conta reivindica a empresa pré-cadastrada. Vira dona com vínculo 'pending' (default da 120000);
      -- o acesso a manifestações depende da verificação da equipe (130000).
      update public.companies
      set legal_name = btrim(p ->> 'legal_name'), trade_name = nullif(btrim(p ->> 'trade_name'), ''), address_id = v_address,
          created_by = p_user, registration_status = 'registered'
      where id = v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    elsif v_id is not null and v_src <> 'signup' then
      -- D11: empresa que veio de pré-cadastro e já foi reivindicada: a conta seguinte entra como membro 'pending', nunca
      -- como dona. Evita que quem reivindicou primeiro tranque a empresa verdadeira fora da plataforma; a equipe decide.
      -- Sem assinatura nova: a empresa já tem a da conta que reivindicou (subscriptions não tem unique por empresa).
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'member');
    else
      insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
      values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), v_doc, v_address, p_user)
      returning id into v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    end if;
  elsif p_type = 'partner' then
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type, v_doc,
      btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address
    )
    returning id into v_id;
    perform private.create_subscription('partner', p, null, v_id, null);
  else
    insert into public.sponsors (user_id, name, cnpj, address_id)
    values (p_user, btrim(p ->> 'name'), v_doc, v_address)
    returning id into v_id;
    perform private.create_subscription('sponsor', p, null, null, v_id);
  end if;
  return v_id;
end;
$$;
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261118140000', 'reivindicacao_cnpj', array[
$s0$-- ADR-0023 / ADR-0012 D11 (aceitas em 2026-11-17), migration 3: reivindicação da empresa pré-cadastrada no cadastro.
-- Prioridade do responsável (2026-11-18, via Gestor): a empresa avisada precisa conseguir se cadastrar; sem isto, o
-- cadastro falha por CNPJ duplicado. Não pode ser cortada.
-- Muda private.create_profile (gatilho do signUp e add_profile), só no ramo 'company':
--   - CNPJ pré-cadastrado (pre_registered ou pending_check): a conta reivindica: dados e endereço do cadastro,
--     created_by = conta, registration_status = 'registered', vínculo 'owner' com verification_status 'pending'.
--   - CNPJ que veio de pré-cadastro e já foi reivindicado: a conta entra como 'member' 'pending'.
--   - CNPJ de empresa que se cadastrou direto (data_source 'signup'): sem mudança (falha por CNPJ duplicado, como hoje).
--   - Demais tipos de conta: corpo idêntico ao de 20261109140000.
-- Pré-requisito: troca do gate (20261117130000) aplicada; sem ela, quem reivindica veria os casos liberados sem
-- verificação. A trava abaixo recusa a migration se list_company_complaints ainda não usar is_verified_company_user.
--
-- Rollback: reaplicar private.create_profile de 20261109140000_cpf_unico.sql. Empresas já reivindicadas continuam
-- registered, com o dono e o endereço do cadastro.

do $trava$
begin
  if not exists (select 1 from pg_proc where oid = to_regprocedure('public.list_company_complaints()')
                 and prosrc like '%is_verified_company_user%') then
    raise exception 'A troca do gate (20261117130000) não está aplicada. A reivindicação não pode entrar antes dela.';
  end if;
  if to_regclass('private.company_preregistrations') is null then
    raise exception 'A estrutura da empresa pré-cadastrada (20261118120000) não está aplicada.';
  end if;
end $trava$$s0$,
$s0$create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
  v_doc text;
  v_reg text;
  v_src text;
begin
  if p_user is null then raise exception 'usuário obrigatório' using errcode = '22023'; end if;
  if p is null then raise exception 'dados do cadastro obrigatórios' using errcode = '22023'; end if;
  if p_type not in ('worker', 'company', 'partner', 'sponsor') then
    raise exception 'tipo de conta inválido' using errcode = '22023';
  end if;

  if p_type = 'worker' or (p_type = 'partner' and p ->> 'document_type' = 'cpf') then
    v_doc := regexp_replace(coalesce(p ->> case when p_type = 'worker' then 'cpf' else 'document' end, ''), '\D', '', 'g');
    if not private.valid_cpf(v_doc) then raise exception 'CPF inválido' using errcode = '22023'; end if;
  else
    v_doc := upper(regexp_replace(coalesce(p ->> case when p_type = 'partner' then 'document' else 'cnpj' end, ''), '[^0-9A-Za-z]', '', 'g'));
    if not private.valid_cnpj(v_doc) then raise exception 'CNPJ inválido' using errcode = '22023'; end if;
  end if;

  v_address := private.create_address(p -> 'address');

  if p_type = 'worker' then
    begin
      insert into public.workers (user_id, full_name, cpf, phone, address_id)
      values (p_user, btrim(p ->> 'full_name'), v_doc,
              nullif(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), ''), v_address)
      returning id into v_id;
    exception when unique_violation then
      -- CPF de outro trabalhador ou conta que já tem perfil de trabalhador: mensagem genérica, sem o valor.
      raise exception 'Não foi possível concluir o cadastro.' using errcode = '23505';
    end;
  elsif p_type = 'company' then
    select c.id, c.registration_status, c.data_source into v_id, v_reg, v_src from public.companies c where c.cnpj = v_doc for update;
    if v_id is not null and v_reg <> 'registered' then
      -- D11: a primeira conta reivindica a empresa pré-cadastrada. Vira dona com vínculo 'pending' (default da 120000);
      -- o acesso a manifestações depende da verificação da equipe (130000).
      update public.companies
      set legal_name = btrim(p ->> 'legal_name'), trade_name = nullif(btrim(p ->> 'trade_name'), ''), address_id = v_address,
          created_by = p_user, registration_status = 'registered'
      where id = v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    elsif v_id is not null and v_src <> 'signup' then
      -- D11: empresa que veio de pré-cadastro e já foi reivindicada: a conta seguinte entra como membro 'pending', nunca
      -- como dona. Evita que quem reivindicou primeiro tranque a empresa verdadeira fora da plataforma; a equipe decide.
      -- Sem assinatura nova: a empresa já tem a da conta que reivindicou (subscriptions não tem unique por empresa).
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'member');
    else
      insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
      values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), v_doc, v_address, p_user)
      returning id into v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    end if;
  elsif p_type = 'partner' then
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type, v_doc,
      btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address
    )
    returning id into v_id;
    perform private.create_subscription('partner', p, null, v_id, null);
  else
    insert into public.sponsors (user_id, name, cnpj, address_id)
    values (p_user, btrim(p ->> 'name'), v_doc, v_address)
    returning id into v_id;
    perform private.create_subscription('sponsor', p, null, null, v_id);
  end if;
  return v_id;
end;
$$$s0$
]::text[]);

commit;
