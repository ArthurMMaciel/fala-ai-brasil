-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar empresa_sem_plano_checks.sql e as migrations.
-- Migrations: 20261127140000_empresa_sem_plano.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_a text := '98765001987643'; cnpj_b text := '98765004987687'; cnpj_c text := '98765005987621'; cnpj_s text := '98765009987600'; co uuid; n int; u1 uuid := 'f0000000-0000-0000-0000-000000000041'; u2 uuid := 'f0000000-0000-0000-0000-000000000042'; u3 uuid := 'f0000000-0000-0000-0000-000000000043'; u4 uuid := 'f0000000-0000-0000-0000-000000000044'; u5 uuid := 'f0000000-0000-0000-0000-000000000045'; u6 uuid := 'f0000000-0000-0000-0000-000000000046'; u7 uuid := 'f0000000-0000-0000-0000-000000000047';
begin
  begin  -- trava: nada pode commitar daqui para dentro
    -- Sem lock em 3 s, falha limpa em vez de enfileirar o site atrás do DDL. (statement_timeout não se aplica: o
    -- cronômetro começa no DO, que é a instrução de topo; um SET aqui dentro não o rearma.)
    execute 'set local lock_timeout = ''3s''';

    -- 20261127140000_empresa_sem_plano.sql (2 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261127140000') then
      res := res || jsonb_build_object('20261127140000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- Conta de empresa gratuita e sem plano (decisão do responsável, repassada pelo Gestor em 2026-11-27; ADR-0026).
-- private.create_profile deixa de criar assinatura no ramo 'company': cadastro novo e reivindicação de empresa
-- pré-cadastrada. plan_id e subscription_mode enviados pelo front são ignorados nesse ramo; o front atual continua
-- funcionando. Parceiro e patrocinador não mudam (continuam com plano e create_subscription).
-- Nenhuma RLS, RPC, Edge Function ou agendamento depende de a empresa ter assinatura (análise do Back, 2026-11-27).
-- Assinaturas de empresa já existentes ficam como estão (nada as vence nem as lê no backend).
--
-- Corpo de 20261118150000; só o ramo 'company' muda (as duas chamadas a create_subscription saem).
-- Rollback: supabase/tests/rollback/20261127140000_rollback.sql (volta o corpo de 20261118150000).

set local lock_timeout = '5s'$s0$;
      execute $s0$create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
  v_doc text;
  v_reg text;
  v_contact_email text;
  v_contact_phone text;
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
    -- Conta de empresa gratuita e sem plano (20261127140000): nenhuma assinatura; plan_id e subscription_mode, se vierem
    -- do front, são ignorados neste ramo.
    select c.id, c.registration_status into v_id, v_reg from public.companies c where c.cnpj = v_doc for update;
    if v_id is not null and v_reg <> 'registered' then
      -- D11: a primeira conta reivindica a empresa pré-cadastrada. Vira dona com vínculo 'pending' (default da 120000);
      -- o acesso a manifestações depende da verificação da equipe (130000).
      update public.companies
      set legal_name = btrim(p ->> 'legal_name'), trade_name = nullif(btrim(p ->> 'trade_name'), ''), address_id = v_address,
          created_by = p_user, registration_status = 'registered'
      where id = v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
    elsif v_id is not null then
      -- D11: empresa já cadastrada, de qualquer origem: a conta entra como membro 'pending', nunca como dona. Evita que quem
      -- chegou primeiro tranque a empresa verdadeira fora da plataforma; a equipe decide na verificação.
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'member');
    else
      insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
      values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), v_doc, v_address, p_user)
      returning id into v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
    end if;
  elsif p_type = 'partner' then
    -- Contato do parceiro, obrigatório no cadastro novo (responsável, 2026-11-18); aparece só em "Contratados".
    v_contact_email := lower(btrim(coalesce(p ->> 'contact_email', '')));
    v_contact_phone := regexp_replace(coalesce(p ->> 'contact_phone', ''), '\D', '', 'g');
    if char_length(v_contact_email) > 254 or v_contact_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'e-mail de contato inválido' using errcode = '22023';
    end if;
    if v_contact_phone !~ '^\d{10,11}$' then raise exception 'telefone de contato inválido' using errcode = '22023'; end if;
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id,
                                 contact_email, contact_phone)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type, v_doc,
      btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address, v_contact_email, v_contact_phone
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
$$$s0$;
      res := res || jsonb_build_object('20261127140000', 'aplicada na transação de teste');
    end if;

    -- Verificações (empresa_sem_plano_checks.sql)
    -- declare: addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_a text := '98765001987643'; cnpj_b text := '98765004987687'; cnpj_c text := '98765005987621'; cnpj_s text := '98765009987600'; co uuid; n int; u1 uuid := 'f0000000-0000-0000-0000-000000000041'; u2 uuid := 'f0000000-0000-0000-0000-000000000042'; u3 uuid := 'f0000000-0000-0000-0000-000000000043'; u4 uuid := 'f0000000-0000-0000-0000-000000000044'; u5 uuid := 'f0000000-0000-0000-0000-000000000045'; u6 uuid := 'f0000000-0000-0000-0000-000000000046'; u7 uuid := 'f0000000-0000-0000-0000-000000000047';
    -- Verificações de 20261127140000 (conta de empresa sem plano). CNPJs de teste conferidos como inexistentes (404 em
    -- 2026-11-18); CPF de teste só na transação.
    if exists (select 1 from public.companies where cnpj in (cnpj_a, cnpj_b, cnpj_c, cnpj_s)) or exists (select 1 from public.workers where cpf = '27182818205') then
      raise exception 'Valor de teste já existe; troque os CNPJs/CPF do teste.';
    end if;
    -- Empresa nova sem plan_id nem subscription_mode: cadastra e não cria assinatura.
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u1, 'authenticated', 'authenticated', 'tx-sp1@teste.invalid',
     jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Sem Plano A Ltda', 'cnpj', cnpj_a, 'address', addr)), now(), now());
    select company_id into co from public.company_users where user_id = u1 and role = 'owner';
    if co is null then falhas := falhas || jsonb_build_object('empresa sem plano não cadastrou', true); end if;
    if exists (select 1 from public.subscriptions where company_id = co) then falhas := falhas || jsonb_build_object('empresa sem plano ganhou assinatura', true); end if;
    -- Front atual (ainda manda plano): cadastra e também não cria assinatura.
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u2, 'authenticated', 'authenticated', 'tx-sp2@teste.invalid',
     jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Sem Plano B Ltda', 'cnpj', cnpj_b, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
    select company_id into co from public.company_users where user_id = u2 and role = 'owner';
    if co is null or exists (select 1 from public.subscriptions where company_id = co) then
      falhas := falhas || jsonb_build_object('empresa com plano no pedido: sem cadastro ou com assinatura', true);
    end if;
    -- Segunda conta na mesma empresa: membro pendente, sem assinatura.
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u3, 'authenticated', 'authenticated', 'tx-sp3@teste.invalid',
     jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Sem Plano B Ltda', 'cnpj', cnpj_b, 'address', addr)), now(), now());
    if (select role from public.company_users where user_id = u3) is distinct from 'member' then falhas := falhas || jsonb_build_object('segunda conta não virou membro', true); end if;
    -- Reivindicação de empresa pré-cadastrada: vira dona, sem assinatura.
    insert into public.companies (legal_name, cnpj, registration_status, data_source) values ('Tx Pre Cadastrada C Ltda', cnpj_c, 'pre_registered', 'manual')
    returning id into co;
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u4, 'authenticated', 'authenticated', 'tx-sp4@teste.invalid',
     jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Pre Cadastrada C Ltda', 'cnpj', cnpj_c, 'address', addr)), now(), now());
    if (select registration_status from public.companies where id = co) is distinct from 'registered'
       or (select role from public.company_users where user_id = u4) is distinct from 'owner'
       or exists (select 1 from public.subscriptions where company_id = co) then
      falhas := falhas || jsonb_build_object('reivindicação: não registrou, não virou dona ou ganhou assinatura', true);
    end if;
    -- Patrocinador continua com plano: sem plan_id é recusado; com plano, cria assinatura.
    begin
      insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      ('00000000-0000-0000-0000-000000000000', u5, 'authenticated', 'authenticated', 'tx-sp5@teste.invalid',
       jsonb_build_object('signup_type', 'sponsor', 'signup', jsonb_build_object('name', 'Tx Patrocinio', 'cnpj', cnpj_s, 'address', addr)), now(), now());
      falhas := falhas || jsonb_build_object('patrocinador sem plano aceito', true);
    exception when others then null; end;
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u6, 'authenticated', 'authenticated', 'tx-sp6@teste.invalid',
     jsonb_build_object('signup_type', 'sponsor', 'signup', jsonb_build_object('name', 'Tx Patrocinio', 'cnpj', cnpj_s,
       'plan_id', (select id from public.plans where audience = 'sponsor' order by id limit 1), 'subscription_mode', 'trial', 'address', addr)), now(), now());
    if not exists (select 1 from public.subscriptions s join public.sponsors sp on sp.id = s.sponsor_id where sp.user_id = u6) then
      falhas := falhas || jsonb_build_object('patrocinador com plano sem assinatura', true);
    end if;
    -- Trabalhador continua igual.
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u7, 'authenticated', 'authenticated', 'tx-sp7@teste.invalid',
     jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Sem Plano Trabalhador', 'cpf', '27182818205', 'address', addr)), now(), now());
    if not exists (select 1 from public.workers where user_id = u7) then falhas := falhas || jsonb_build_object('trabalhador não cadastrou', true); end if;
    res := res || jsonb_build_object('verificações de empresa sem plano', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
