-- declare: u_w uuid := 'efffffff-ffff-ffff-ffff-ffffffffffff'; u_c1 uuid := 'f1111111-1111-1111-1111-111111111111'; u_c2 uuid := 'f2222222-2222-2222-2222-222222222222'; u_c3 uuid := 'f3333333-3333-3333-3333-333333333333'; u_op uuid := 'f4444444-4444-4444-4444-444444444444'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_pre text := '16180339000157'; cnpj_reg text := '14142135000104'; co uuid; cp uuid; r record;
-- Verificações da reivindicação (20261118140000, ADR-0012 D11) depois da troca do gate e das migrations 1 e 2, na
-- transação de teste. Os CNPJs e o CPF são de teste; se existirem em produção, o teste para antes de criar dados.
if exists (select 1 from public.companies where cnpj in (cnpj_pre, cnpj_reg)) or exists (select 1 from public.workers where cpf = '31415926590') then
  raise exception 'Valor de teste já existe em produção; troque os CNPJs/CPF do teste.';
end if;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-rw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Reivindica Trabalhador', 'cpf', '31415926590', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_c3, 'authenticated', 'authenticated', 'tx-rc3@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Cadastro Direto Ltda', 'cnpj', cnpj_reg, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-rop@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);

-- Trabalhador pré-cadastra e relata; equipe libera.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
cp := public.create_complaint(jsonb_build_object('company_cnpj', cnpj_pre, 'category', 'Carga de trabalho', 'title', 'Tx caso reivindicação',
  'original_content', 'Tx relato original.', 'shared_content', 'Tx versao compartilhavel.',
  'company_manual', jsonb_build_object('name', 'Tx Nome Digitado Pelo Trabalhador', 'city', 'Santos', 'state', 'SP')), true);
execute 'reset role';
select company_id into co from public.complaints where id = cp;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_decide_complaint(cp, 'released', null);
execute 'reset role';

-- Primeira conta da empresa reivindica.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_c1, 'authenticated', 'authenticated', 'tx-rc1@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Empresa Reivindicada Ltda', 'cnpj', '16.180.339/0001-57', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
select c.registration_status, c.legal_name, c.address_id, c.created_by into r from public.companies c where c.id = co;
if r.registration_status is distinct from 'registered' or r.legal_name is distinct from 'Tx Empresa Reivindicada Ltda'
   or r.address_id is null or r.created_by is distinct from u_c1 then
  falhas := falhas || jsonb_build_object('reivindicação não passou a empresa a registered com os dados do cadastro', true);
end if;
select cu.role::text as role, cu.verification_status into r from public.company_users cu where cu.company_id = co and cu.user_id = u_c1;
if r.role is distinct from 'owner' or r.verification_status is distinct from 'pending' then
  falhas := falhas || jsonb_build_object('quem reivindica não é owner pending', true);
end if;
if (select count(*) from public.companies where cnpj = cnpj_pre) <> 1 then falhas := falhas || jsonb_build_object('empresa duplicada', true); end if;

-- Pending não vê o caso liberado (gate 130000).
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_c1, 'role', 'authenticated')::text, true);
if exists (select 1 from public.list_company_complaints() l where l.id = cp) then
  falhas := falhas || jsonb_build_object('reivindicação sem verificação vê o caso', true);
end if;
execute 'reset role';

-- Segunda conta: membro pending, nunca dona.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_c2, 'authenticated', 'authenticated', 'tx-rc2@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Outra Razao', 'cnpj', cnpj_pre, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
select cu.role::text as role, cu.verification_status into r from public.company_users cu where cu.company_id = co and cu.user_id = u_c2;
if r.role is distinct from 'member' or r.verification_status is distinct from 'pending' then
  falhas := falhas || jsonb_build_object('segunda conta não entrou como member pending', true);
end if;
if (select count(*) from public.subscriptions where company_id = co) <> 1 then
  falhas := falhas || jsonb_build_object('assinatura duplicada para a mesma empresa', true);
end if;
if (select legal_name from public.companies where id = co) is distinct from 'Tx Empresa Reivindicada Ltda' then
  falhas := falhas || jsonb_build_object('segunda conta trocou os dados da empresa', true);
end if;

-- Empresa de cadastro direto: CNPJ repetido continua recusado.
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', 'tx-rc4@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Repetida', 'cnpj', cnpj_reg, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
  falhas := falhas || jsonb_build_object('CNPJ de cadastro direto aceito duas vezes', true);
exception when others then null; end;
-- Trabalhador continua se cadastrando normalmente (outro ramo da função).
if not exists (select 1 from public.workers where user_id = u_w) then falhas := falhas || jsonb_build_object('cadastro de trabalhador quebrou', true); end if;
-- A empresa reivindicada sai da fila de pré-cadastradas.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
if exists (select 1 from public.ops_list_pending_companies() p where p.company_id = co) then
  falhas := falhas || jsonb_build_object('reivindicada continua na fila de pré-cadastradas', true);
end if;
execute 'reset role';
res := res || jsonb_build_object('verificações da reivindicação', 'executadas');
