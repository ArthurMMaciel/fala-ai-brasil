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
