-- declare: u_w uuid := 'ebbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; u_c uuid := 'eccccccc-cccc-cccc-cccc-cccccccccccc'; u_op uuid := 'eddddddd-dddd-dddd-dddd-dddddddddddd'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_api text := '98765001987643'; cnpj_pf text := '98765002987698'; cnpj_man text := '98765003987632'; cnpj_extra text := '98765004987687'; cnpj_reg text := '98765005987621'; co_reg uuid; co_api uuid; co_pf uuid; co_man uuid; cp1 uuid; cp2 uuid; cp3 uuid; cp4 uuid; cp5 uuid; cp6 uuid; cp7 uuid; cp8 uuid; co_extra uuid; n1 uuid; n int; r record; base jsonb;
-- Verificações da ADR-0023/ADR-0017 (20261118120000 e 20261118130000, revista após a revisão do DevOps) na transação
-- de teste. Imprime só contagens e nomes. CNPJs e CPF de teste (dígitos válidos); se algum existir em produção, para
-- antes de criar dados. CNPJs conferidos como inexistentes na Minha Receita e na BrasilAPI em 2026-11-18 (só o código HTTP 404).
if exists (select 1 from public.companies where cnpj in (cnpj_api, cnpj_pf, cnpj_man, cnpj_extra, cnpj_reg))
   or exists (select 1 from public.workers where cpf = '27182818205') then
  raise exception 'Valor de teste já existe em produção; troque os CNPJs/CPF do teste.';
end if;
if exists (select 1 from public.companies where registration_status <> 'registered') then
  falhas := falhas || jsonb_build_object('empresa existente fora de registered', true);
end if;
base := jsonb_build_object('category', 'Carga de trabalho', 'title', 'Tx caso', 'original_content', 'Tx relato original.',
                           'shared_content', 'Tx versao compartilhavel.');

insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-ew@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Empresa Trabalhador', 'cpf', '27182818205', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-ec@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Empresa Cadastrada Ltda', 'cnpj', cnpj_reg, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-eop@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);
select company_id into co_reg from public.company_users where user_id = u_c;
if (select registration_status || '/' || data_source from public.companies where id = co_reg) is distinct from 'registered/signup' then
  falhas := falhas || jsonb_build_object('cadastro normal não nasce registered/signup', true);
end if;

-- Edge Function simulada (service_role): grava o cache; pessoa física sem nome; não lê e-mails nem avisos.
execute 'set local role service_role';
perform public.cnpj_cache_put(cnpj_api, false, 'Tx Empresa Api Ltda', 'Tx Api', 'ATIVA', 'Campinas', 'sp', '6201501', '206-2', 'minhareceita', 'Receita@Tx-Api.invalid');
perform public.cnpj_cache_put(cnpj_pf, true, 'Fulano Tx da Silva', null, 'ATIVA', 'Campinas', 'SP', '111301', '2135', 'brasilapi', 'fulano@tx.invalid');
perform public.cnpj_cache_put(cnpj_extra, false, 'Tx Empresa Receita Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', 'receita@tx-extra.invalid');
if not public.cnpj_quota_take(u_w) then falhas := falhas || jsonb_build_object('cota da função recusou a 1ª', true); end if;
begin
  select count(*) into n from public.complaint_contacts;
  falhas := falhas || jsonb_build_object('service_role lê complaint_contacts', n);
exception when insufficient_privilege then null; end;
begin
  select count(*) into n from public.company_notices;
  falhas := falhas || jsonb_build_object('service_role lê company_notices', n);
exception when insufficient_privilege then null; end;
begin
  select count(*) into n from private.cnpj_cache;
  falhas := falhas || jsonb_build_object('service_role lê o cache direto', n);
exception when insufficient_privilege then null; end;
execute 'reset role';
select * into r from private.cnpj_cache where cnpj = cnpj_pf;
if r.legal_name is not null or r.trade_name is not null or r.email is not null or not r.natural_person or r.main_cnae is distinct from '0111301' then
  falhas := falhas || jsonb_build_object('cache de pessoa física com nome, e-mail ou CNAE errado', true);
end if;
if (select email from private.cnpj_cache where cnpj = cnpj_api) is distinct from 'receita@tx-api.invalid' then
  falhas := falhas || jsonb_build_object('cache sem o e-mail da Receita normalizado', true);
end if;
if exists (select 1 from information_schema.routines where routine_schema = 'public' and routine_name = 'cnpj_cache_get')
   and (select prosrc like '%c.email%' from pg_proc where oid = to_regprocedure('public.cnpj_cache_get(text)')) then
  falhas := falhas || jsonb_build_object('cnpj_cache_get devolve o e-mail da Receita', true);
end if;

-- Trabalhador.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
begin
  perform public.cnpj_cache_put(cnpj_extra, false, 'Forjada Ltda', null, null, null, null, null, null, 'minhareceita', null);
  falhas := falhas || jsonb_build_object('authenticated grava no cache', true);
exception when insufficient_privilege then null; end;
begin
  perform public.find_company_by_cnpj('11.111.111/1111-11');
  falhas := falhas || jsonb_build_object('busca aceita CNPJ inválido', true);
exception when others then null; end;
if (select count(*) from public.find_company_by_cnpj(cnpj_reg)) <> 1 then falhas := falhas || jsonb_build_object('busca não acha a cadastrada', true); end if;
if (select count(*) from public.find_company_by_cnpj(cnpj_api)) <> 0 then falhas := falhas || jsonb_build_object('busca acha CNPJ não cadastrado', true); end if;
-- Sem cache e sem dados manuais: recusa antes de qualquer gravação.
begin
  perform public.create_complaint(base || jsonb_build_object('company_cnpj', '98765009987600'), true);
  falhas := falhas || jsonb_build_object('relato por CNPJ sem cache nem dados manuais', true);
exception when others then
  if sqlerrm not like 'Informe o nome da empresa%' then falhas := falhas || jsonb_build_object('mensagem sem dados manuais', sqlerrm); end if;
end;
-- Validação do contato não depende da empresa.
begin
  perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_api,
    'notice_contact', jsonb_build_object('email', 'rh@tx.invalid', 'possibly_involved', false, 'consent', false)), true);
  falhas := falhas || jsonb_build_object('contato sem consentimento aceito', true);
exception when others then null; end;
begin
  perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_api,
    'notice_contact', jsonb_build_object('email', 'rh@tx.invalid', 'consent', true)), true);
  falhas := falhas || jsonb_build_object('contato sem possibly_involved aceito', true);
exception when others then null; end;
begin
  perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_api,
    'notice_contact', jsonb_build_object('possibly_involved', false, 'consent', true)), true);
  falhas := falhas || jsonb_build_object('contato sem e-mail nem telefone aceito', true);
exception when others then null; end;
begin
  perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_api,
    'notice_contact', jsonb_build_object('phone', '123', 'possibly_involved', false, 'consent', true)), true);
  falhas := falhas || jsonb_build_object('telefone de contato inválido aceito', true);
exception when others then null; end;
begin
  perform public.create_complaint(jsonb_build_object('company_cnpj', cnpj_api, 'category', 'Carga de trabalho', 'title', 'Tx sem compartilhar',
    'original_content', 'Tx relato original.', 'notice_contact', jsonb_build_object('email', 'rh@tx.invalid', 'possibly_involved', false, 'consent', true)), false);
  falhas := falhas || jsonb_build_object('contato aceito sem compartilhar', true);
exception when others then null; end;
-- Três relatos pelo CNPJ do cache: o primeiro cria a pré-cadastrada, os seguintes entram nela.
cp1 := public.create_complaint(base || jsonb_build_object('company_cnpj', '98.765.001/9876-43',
  'notice_contact', jsonb_build_object('email', ' RH@Tx-Api.invalid ', 'possibly_involved', false, 'consent', true)), true);
cp2 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_api,
  'notice_contact', jsonb_build_object('email', 'chefe@tx-api.invalid', 'possibly_involved', true, 'consent', true)), true);
cp3 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_api,
  'notice_contact', jsonb_build_object('email', 'ouvidoria@tx-api.invalid', 'possibly_involved', false, 'consent', true)), true);
-- Quarto relato por CNPJ no dia: recusado, exista a empresa ou não.
begin
  perform public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_man,
    'company_manual', jsonb_build_object('name', 'Tx Empresa Manual Ltda', 'city', 'Santos', 'state', 'SP')), true);
  falhas := falhas || jsonb_build_object('cota de relato por CNPJ não barrou o 4º', true);
exception when others then
  if sqlerrm not like 'Limite de relatos por CNPJ%' then falhas := falhas || jsonb_build_object('mensagem da cota', sqlerrm); end if;
end;
if (select count(*) from public.find_company_by_cnpj(cnpj_api)) <> 0 then
  falhas := falhas || jsonb_build_object('busca revela a pré-cadastrada', true);
end if;
execute 'reset role';
delete from private.cnpj_lookup_quota where user_id = u_w;  -- zera a cota para seguir o teste
select id into co_api from public.companies where cnpj = cnpj_api;
if (select count(distinct company_id) from public.complaints where id in (cp1, cp2, cp3)) <> 1
   or (select registration_status || '/' || data_source || '/' || coalesce(created_by::text, 'null') from public.companies where id = co_api)
      is distinct from 'pre_registered/cnpj_api/null' then
  falhas := falhas || jsonb_build_object('pré-cadastrada pelo cache errada ou duplicada', true);
end if;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
-- Pessoa física (cache com a marca) e manual: exigem os dados manuais e nascem pending_check.
cp4 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_pf,
  'company_manual', jsonb_build_object('name', 'Tx Nome Digitado', 'city', 'Campinas', 'state', 'sp'),
  'notice_contact', jsonb_build_object('email', 'pessoa@tx.invalid', 'possibly_involved', false, 'consent', true)), true);
cp5 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_man,
  'company_manual', jsonb_build_object('name', 'Tx Empresa Manual Ltda', 'city', 'Santos', 'state', 'SP'),
  'notice_contact', jsonb_build_object('email', 'saiu@tx-man.invalid', 'possibly_involved', false, 'consent', true)), true);
-- Empresa cadastrada, por id ou por CNPJ: relato aceito e contato gravado (segundo canal para a equipe).
cp6 := public.create_complaint(base || jsonb_build_object('company_id', co_reg,
  'notice_contact', jsonb_build_object('email', 'rh@tx-reg.invalid', 'possibly_involved', false, 'consent', true)), true);
cp7 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_reg,
  'company_manual', jsonb_build_object('name', 'Outro Nome', 'city', 'Santos', 'state', 'SP'),
  'notice_contact', jsonb_build_object('phone', '(11) 3333-0000', 'possibly_involved', false, 'consent', true)), true);
-- Fora das listas.
execute 'reset role';
select id into co_pf from public.companies where cnpj = cnpj_pf;
select id into co_man from public.companies where cnpj = cnpj_man;
if (select company_id from public.complaints where id = cp7) is distinct from co_reg
   or (select legal_name from public.companies where id = co_reg) is distinct from 'Tx Empresa Cadastrada Ltda' then
  falhas := falhas || jsonb_build_object('relato por CNPJ de cadastrada não entrou nela ou mudou o nome', true);
end if;
if (select count(*) from public.complaint_contacts where complaint_id in (cp6, cp7)) <> 2
   or (select phone from public.complaint_contacts where complaint_id = cp7) is distinct from '1133330000'
   or (select email from public.complaint_contacts where complaint_id = cp7) is not null then
  falhas := falhas || jsonb_build_object('contato da empresa cadastrada não gravado como enviado', true);
end if;
-- Relato sem contato numa empresa com e-mail da Receita (destino alternativo); zera a cota antes.
delete from private.cnpj_lookup_quota where user_id = u_w;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
cp8 := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_extra), true);
-- O trabalhador lê o próprio contato; a empresa cadastrada não lê o contato do relato contra ela.
if (select email from public.my_complaint_contact(cp6)) is distinct from 'rh@tx-reg.invalid' then
  falhas := falhas || jsonb_build_object('trabalhador não lê o próprio contato', true);
end if;
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
if exists (select 1 from public.my_complaint_contact(cp6)) then
  falhas := falhas || jsonb_build_object('empresa lê o contato do relato', true);
end if;
begin
  perform public.ops_complaint_contact(cp6);
  falhas := falhas || jsonb_build_object('empresa usa ops_complaint_contact', true);
exception when others then null; end;
execute 'reset role';
select company_id into co_extra from public.complaints where id = cp8;
select pr.natural_person, co.registration_status into r from public.companies co join private.company_preregistrations pr on pr.company_id = co.id where co.id = co_pf;
if r.natural_person is distinct from true or r.registration_status is distinct from 'pending_check' then
  falhas := falhas || jsonb_build_object('pessoa física manual sem a marca ou fora de pending_check', true);
end if;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
if (select count(*) from public.my_complaint_companies() m where m.company_id in (co_api, co_pf, co_man, co_reg) and m.name is not null) <> 4 then
  falhas := falhas || jsonb_build_object('trabalhador sem o nome das empresas dos próprios relatos', true);
end if;
if exists (select 1 from public.list_company_directory() d where d.id in (co_api, co_pf, co_man)) then
  falhas := falhas || jsonb_build_object('pré-cadastrada no diretório', true);
end if;
if exists (select 1 from public.company_responsiveness() d where d.company_id in (co_api, co_pf, co_man)) then
  falhas := falhas || jsonb_build_object('pré-cadastrada na responsividade', true);
end if;
-- O trabalhador não lê contatos nem avisos direto, e não decide aviso.
begin
  select count(*) into n from public.complaint_contacts;
  falhas := falhas || jsonb_build_object('trabalhador lê complaint_contacts', n);
exception when insufficient_privilege then null; end;
begin
  perform public.ops_decide_notice(cp1, 'approved', null);
  falhas := falhas || jsonb_build_object('trabalhador decide aviso', true);
exception when others then null; end;
-- Outra conta não vê as empresas dos relatos do trabalhador.
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
if exists (select 1 from public.my_complaint_companies() m where m.company_id in (co_api, co_pf, co_man)) then
  falhas := falhas || jsonb_build_object('outra conta vê empresas dos relatos do trabalhador', true);
end if;
-- A empresa cadastrada não vê nada da pré-cadastrada.
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
if exists (select 1 from public.list_company_complaints() l where l.id in (cp1, cp2, cp3, cp4, cp5)) then
  falhas := falhas || jsonb_build_object('outra empresa vê caso da pré-cadastrada', true);
end if;

-- Equipe.
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
if (select count(*) from public.ops_list_pending_companies() p where p.company_id in (co_api, co_pf, co_man)) <> 3 then
  falhas := falhas || jsonb_build_object('fila de empresas sem as 3', true);
end if;
if exists (select 1 from public.ops_list_companies() l where l.id in (co_api, co_pf, co_man)) then
  falhas := falhas || jsonb_build_object('pré-cadastrada em ops_list_companies', true);
end if;
select * into r from public.ops_list_notice_candidates() c where c.complaint_id = cp1;
if r.contact_email is distinct from 'rh@tx-api.invalid' or r.destination_source is distinct from 'worker'
   or r.receita_email is distinct from 'receita@tx-api.invalid' then
  falhas := falhas || jsonb_build_object('fila sem destino do trabalhador e e-mail da Receita', true);
end if;
select * into r from public.ops_list_notice_candidates() c where c.complaint_id = cp8;
if r.destination_email is distinct from 'receita@tx-extra.invalid' or r.destination_source is distinct from 'receita' then
  falhas := falhas || jsonb_build_object('fila sem o e-mail da Receita como destino alternativo', true);
end if;
if exists (select 1 from public.ops_list_notice_candidates() c where c.complaint_id in (cp6, cp7)) then
  falhas := falhas || jsonb_build_object('empresa cadastrada na fila de aviso', true);
end if;
if (select phone from public.ops_complaint_contact(cp7)) is distinct from '1133330000' then
  falhas := falhas || jsonb_build_object('equipe não vê o contato da empresa cadastrada', true);
end if;
perform public.ops_decide_complaint(cp1, 'released', null);
perform public.ops_decide_complaint(cp2, 'released', null);
perform public.ops_decide_complaint(cp3, 'released', null);
perform public.ops_decide_complaint(cp4, 'released', null);
perform public.ops_decide_complaint(cp5, 'released', null);
perform public.ops_decide_complaint(cp6, 'released', null);
perform public.ops_decide_complaint(cp8, 'released', null);
-- Sem a troca do gate (130000) o aviso é recusado; com ela, segue. Este teste roda com ou sem a 130000 na transação.
if not exists (select 1 from pg_proc where oid = to_regprocedure('public.list_company_complaints()') and prosrc like '%is_verified_company_user%') then
  begin
    perform public.ops_decide_notice(cp1, 'approved', null);
    falhas := falhas || jsonb_build_object('aviso aprovado sem a troca do gate', true);
  exception when others then null; end;
  res := res || jsonb_build_object('aviso', 'recusado sem a 130000 (esperado); travas de aprovação não exercitadas nesta rodada');
else
  n1 := public.ops_decide_notice(cp1, 'approved', null);
  begin
    perform public.ops_decide_notice(cp2, 'approved', null);
    falhas := falhas || jsonb_build_object('aviso a contato possivelmente envolvido', true);
  exception when others then null; end;
  begin
    perform public.ops_decide_notice(cp3, 'approved', null);
    falhas := falhas || jsonb_build_object('segundo aviso à mesma empresa em 30 dias', true);
  exception when others then
    if sqlerrm not like '%30 dias%' then falhas := falhas || jsonb_build_object('mensagem dos 30 dias', sqlerrm); end if;
  end;
  begin
    perform public.ops_decide_notice(cp4, 'approved', null);
    falhas := falhas || jsonb_build_object('aviso a empresa pending_check', true);
  exception when others then null; end;
  perform public.ops_review_company(co_pf, 'confirmed', null, null);
  begin
    perform public.ops_decide_notice(cp4, 'approved', null);
    falhas := falhas || jsonb_build_object('aviso a pessoa física', true);
  exception when others then null; end;
  perform public.ops_review_company(co_man, 'confirmed', null, null);
  perform public.ops_add_opt_out(' Saiu@tx-man.invalid');
  begin
    perform public.ops_decide_notice(cp5, 'approved', null);
    falhas := falhas || jsonb_build_object('aviso a e-mail em opt-out', true);
  exception when others then null; end;
  perform public.ops_mark_notice_sent(n1, 'sent');
  begin
    perform public.ops_mark_notice_sent(n1, 'sent');
    falhas := falhas || jsonb_build_object('envio marcado duas vezes', true);
  exception when others then null; end;
  begin
    perform public.ops_decide_notice(cp6, 'approved', null);
    falhas := falhas || jsonb_build_object('aviso a empresa cadastrada', true);
  exception when others then null; end;
  -- Sem contato do trabalhador: destino Receita, aprovado pela equipe.
  n1 := public.ops_decide_notice(cp8, 'approved', null);
  if (select destination_source from public.company_notices where id = n1) is distinct from 'receita'
     or (select contact_id from public.company_notices where id = n1) is not null then
    falhas := falhas || jsonb_build_object('aviso pela Receita sem a origem registrada', true);
  end if;
end if;
perform public.ops_decide_notice(cp3, 'rejected', 'Tx empresa já avisada neste mês.');
begin
  perform public.ops_decide_notice(cp3, 'rejected', 'Tx segunda decisão.');
  falhas := falhas || jsonb_build_object('aviso decidido duas vezes', true);
exception when others then null; end;

-- Trilha imutável; retenção apaga o contato vencido e mantém a trilha.
execute 'reset role';
select id into n1 from public.company_notices where complaint_id = cp3;
begin
  update public.company_notices set reason = 'Tx alteração indevida.' where id = n1;
  falhas := falhas || jsonb_build_object('aviso alterável', true);
exception when others then null; end;
begin
  delete from public.company_notices where id = n1;
  falhas := falhas || jsonb_build_object('aviso apagável', true);
exception when others then null; end;
update public.complaint_contacts set reviewed_at = now() - interval '91 days' where complaint_id = cp3;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
if public.ops_purge_expired_contacts() < 1 then falhas := falhas || jsonb_build_object('retenção não apagou contato vencido', true); end if;
execute 'reset role';
if not exists (select 1 from public.company_notices where id = n1 and contact_id is null) then
  falhas := falhas || jsonb_build_object('trilha perdida ou contato preso após retenção', true);
end if;

-- Anon não executa.
execute 'set local role anon';
begin
  perform public.find_company_by_cnpj(cnpj_reg);
  falhas := falhas || jsonb_build_object('anon busca CNPJ', true);
exception when insufficient_privilege then null; end;
begin
  perform public.cnpj_cache_get(cnpj_api);
  falhas := falhas || jsonb_build_object('anon lê o cache', true);
exception when insufficient_privilege then null; end;
res := res || jsonb_build_object('verificações da empresa pré-cadastrada', 'executadas');
