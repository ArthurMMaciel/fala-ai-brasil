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
