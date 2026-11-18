-- declare: u_ca uuid := 'f6666666-6666-6666-6666-666666666666'; u_cam uuid := 'f7777777-7777-7777-7777-777777777777'; u_cb uuid := 'f8888888-8888-8888-8888-888888888888'; u_p1 uuid := 'f9999999-9999-9999-9999-999999999999'; u_p2 uuid := 'faaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; u_op uuid := 'fbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_a text := '98765006987676'; cnpj_b text := '98765007987610'; co_a uuid; co_b uuid; p1 uuid; p2 uuid; n int;
-- Verificações da aba Contratados (20261118150000) na transação de teste. CNPJs de teste conferidos como inexistentes
-- (404 na Minha Receita e na BrasilAPI em 2026-11-18); CPFs de teste com dígitos válidos, só dentro da transação.
if exists (select 1 from public.companies where cnpj in (cnpj_a, cnpj_b)) then
  raise exception 'Valor de teste já existe em produção; troque os CNPJs do teste.';
end if;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_ca, 'authenticated', 'authenticated', 'tx-kca@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Contratante Alfa Ltda', 'cnpj', cnpj_a, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_cb, 'authenticated', 'authenticated', 'tx-kcb@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Contratante Beta Ltda', 'cnpj', cnpj_b, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_p1, 'authenticated', 'authenticated', 'tx-kp1@teste.invalid', jsonb_build_object('signup_type', 'partner', 'signup', jsonb_build_object('display_name', 'Tx Parceira Um', 'document_type', 'cpf', 'document', '27182818205', 'specialty', 'Mediação', 'contact_email', 'Contato@Parceira-Um.invalid', 'contact_phone', '(11) 99999-0000', 'plan_id', 'partner-presence', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_p2, 'authenticated', 'authenticated', 'tx-kp2@teste.invalid', jsonb_build_object('signup_type', 'partner', 'signup', jsonb_build_object('display_name', 'Tx Parceira Dois', 'document_type', 'cpf', 'document', '31415926590', 'specialty', 'Ergonomia', 'contact_email', 'contato@parceira-dois.invalid', 'contact_phone', '1133330000', 'plan_id', 'partner-presence', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_cam, 'authenticated', 'authenticated', 'tx-kcam@teste.invalid', '{}', now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-kop@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);
select company_id into co_a from public.company_users where user_id = u_ca;
select company_id into co_b from public.company_users where user_id = u_cb;
select id into p1 from public.partners where user_id = u_p1;
select id into p2 from public.partners where user_id = u_p2;
insert into public.company_users (company_id, user_id, role) values (co_a, u_cam, 'member');  -- membro pending
if (select contact_email || '/' || contact_phone from public.partners where id = p1) is distinct from 'contato@parceira-um.invalid/11999990000' then
  falhas := falhas || jsonb_build_object('cadastro de parceiro não normalizou o contato', true);
end if;
-- Cadastro novo de parceiro sem contato é recusado.
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', 'fccccccc-cccc-cccc-cccc-cccccccccccc', 'authenticated', 'authenticated', 'tx-kp3@teste.invalid', jsonb_build_object('signup_type', 'partner', 'signup', jsonb_build_object('display_name', 'Tx Parceira Sem Contato', 'document_type', 'cpf', 'document', '27182818205', 'specialty', 'Mediação', 'plan_id', 'partner-presence', 'subscription_mode', 'trial', 'address', addr)), now(), now());
  falhas := falhas || jsonb_build_object('parceiro cadastrado sem contato', true);
exception when others then null; end;

-- Equipe verifica os donos de Alfa e Beta.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_verify_representative(co_a, u_ca, 'verified', 'callback', 'Tx ligação ao telefone do site', null);
perform public.ops_verify_representative(co_b, u_cb, 'verified', 'callback', 'Tx ligação ao telefone do site', null);

-- Membro pending não pede contato; verificado pede.
perform set_config('request.jwt.claims', json_build_object('sub', u_cam, 'role', 'authenticated')::text, true);
begin
  perform public.company_request_partner(p1);
  falhas := falhas || jsonb_build_object('vínculo pending pede contato a parceiro', true);
exception when others then
  if sqlerrm not like '%ainda não foi verificado%' then falhas := falhas || jsonb_build_object('mensagem do pending', sqlerrm); end if;
end;
perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
perform public.company_request_partner(p1);
perform public.company_request_partner(p2);
if (select count(*) from public.partner_connections where company_id = co_a and stage = 'company_interest') <> 2 then
  falhas := falhas || jsonb_build_object('pedido do verificado não gravou', true);
end if;

-- Parceiros: um marca cliente, outro só contatado.
perform set_config('request.jwt.claims', json_build_object('sub', u_p1, 'role', 'authenticated')::text, true);
if (select contact_email is not distinct from (select contact_email from public.companies where id = co_a)
    from public.list_partner_companies() where id = co_a) is distinct from true then
  falhas := falhas || jsonb_build_object('parceiro não vê a empresa que pediu contato', true);
end if;
perform public.partner_set_connection(co_a, 'client');
-- Parceira Um edita o próprio contato pela função; inválido, vazio e update direto são recusados.
perform public.update_partner_contact('contato@parceira-um.invalid', '11 99999-0000');
begin
  perform public.update_partner_contact('sem-arroba', '11999990000');
  falhas := falhas || jsonb_build_object('contato de parceiro com e-mail inválido aceito', true);
exception when others then null; end;
begin
  perform public.update_partner_contact('contato@parceira-um.invalid', null);
  falhas := falhas || jsonb_build_object('contato de parceiro sem telefone aceito', true);
exception when others then null; end;
begin
  update public.partners set contact_email = 'direto@tx.invalid' where user_id = u_p1;
  falhas := falhas || jsonb_build_object('update direto do contato do parceiro', true);
exception when insufficient_privilege then null; end;
perform set_config('request.jwt.claims', json_build_object('sub', u_p2, 'role', 'authenticated')::text, true);
-- Parceira Dois só muda o próprio contato.
perform public.update_partner_contact('invasor@tx.invalid', '1100000000');
perform public.partner_set_connection(co_a, 'partner_contacted');

-- Contratados: só o verificado de Alfa vê só a Parceira Um.
perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_my_contracted_partners()) <> 1
   or (select partner_id from public.list_my_contracted_partners() limit 1) is distinct from p1 then
  falhas := falhas || jsonb_build_object('Contratados da empresa verificada errado', true);
end if;
if (select contact_email || '/' || contact_phone from public.list_my_contracted_partners() limit 1)
   is distinct from 'contato@parceira-um.invalid/11999990000' then
  falhas := falhas || jsonb_build_object('Contratados sem o contato do parceiro (ou alterado por outro parceiro)', true);
end if;
-- O diretório de parceiros continua sem contato.
if exists (select 1 from pg_proc where oid = to_regprocedure('public.list_partner_directory()') and prosrc like '%contact_%') then
  falhas := falhas || jsonb_build_object('diretório de parceiros mostra contato', true);
end if;
perform set_config('request.jwt.claims', json_build_object('sub', u_cam, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_my_contracted_partners()) <> 0 then falhas := falhas || jsonb_build_object('pending vê Contratados', true); end if;
perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_my_contracted_partners()) <> 0 then falhas := falhas || jsonb_build_object('outra empresa vê Contratados', true); end if;
perform set_config('request.jwt.claims', json_build_object('sub', u_p1, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_my_contracted_partners()) <> 0 then falhas := falhas || jsonb_build_object('parceiro vê Contratados de empresa', true); end if;

execute 'reset role';
execute 'set local role anon';
begin
  perform public.update_partner_contact('a@b.invalid', '1100000000');
  falhas := falhas || jsonb_build_object('anon executa update_partner_contact', true);
exception when insufficient_privilege then null; end;
begin
  perform public.list_my_contracted_partners();
  falhas := falhas || jsonb_build_object('anon executa list_my_contracted_partners', true);
exception when insufficient_privilege then null; end;
execute 'reset role';
res := res || jsonb_build_object('verificações de Contratados', 'executadas');
