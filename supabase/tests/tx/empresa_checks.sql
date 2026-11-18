-- declare: u_w uuid := 'ebbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; u_c uuid := 'eccccccc-cccc-cccc-cccc-cccccccccccc'; u_op uuid := 'eddddddd-dddd-dddd-dddd-dddddddddddd'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_api text := '27182818000129'; cnpj_pf text := '31415926000171'; cnpj_man text := '16180339000157'; cnpj_extra text := '57721566000120'; cnpj_reg text := '14142135000104'; co_reg uuid; co_api uuid; co_pf uuid; co_man uuid; cp1 uuid; cp2 uuid; cp3 uuid; cp4 uuid; cp5 uuid; n1 uuid; n int; r record;
-- Verificações da ADR-0023/ADR-0017 (20261118120000 e 20261118130000) na transação de teste. Imprime só contagens e nomes.
-- Os CNPJs e o CPF são de teste (dígitos válidos); se algum existir em produção, o teste para antes de criar dados.
if exists (select 1 from public.companies where cnpj in (cnpj_api, cnpj_pf, cnpj_man, cnpj_extra, cnpj_reg))
   or exists (select 1 from public.workers where cpf = '27182818205') then
  raise exception 'Valor de teste já existe em produção; troque os CNPJs/CPF do teste.';
end if;
if exists (select 1 from public.companies where registration_status <> 'registered') then
  falhas := falhas || jsonb_build_object('empresa existente fora de registered', true);
end if;

insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-ew@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Empresa Trabalhador', 'cpf', '27182818205', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-ec@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Empresa Cadastrada Ltda', 'cnpj', cnpj_reg, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-eop@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);
select company_id into co_reg from public.company_users where user_id = u_c;
if (select registration_status || '/' || data_source from public.companies where id = co_reg) is distinct from 'registered/signup' then
  falhas := falhas || jsonb_build_object('cadastro normal não nasce registered/signup', true);
end if;

-- Edge Function simulada (service_role): grava o cache; pessoa física fica sem nome; authenticated não grava.
execute 'set local role service_role';
perform public.cnpj_cache_put(cnpj_api, false, 'Tx Empresa Api Ltda', 'Tx Api', 'ATIVA', 'Campinas', 'sp', '6201501', '206-2', 'minhareceita');
perform public.cnpj_cache_put(cnpj_pf, true, 'Fulano Tx da Silva', null, 'ATIVA', 'Campinas', 'SP', '111301', '2135', 'brasilapi');
if not public.cnpj_quota_take(u_w) then falhas := falhas || jsonb_build_object('cota da função recusou a 1ª', true); end if;
execute 'reset role';
select * into r from private.cnpj_cache where cnpj = cnpj_pf;
if r.legal_name is not null or r.trade_name is not null or not r.natural_person or r.main_cnae is distinct from '0111301' then
  falhas := falhas || jsonb_build_object('cache de pessoa física com nome ou CNAE errado', true);
end if;
if (select state from private.cnpj_cache where cnpj = cnpj_api) is distinct from 'SP' then
  falhas := falhas || jsonb_build_object('cache sem normalizar UF', true);
end if;

execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
begin
  perform public.cnpj_cache_put(cnpj_extra, false, 'Forjada Ltda', null, null, null, null, null, null, 'minhareceita');
  falhas := falhas || jsonb_build_object('authenticated grava no cache', true);
exception when insufficient_privilege then null; end;
begin
  perform public.find_company_by_cnpj('11.111.111/1111-11');
  falhas := falhas || jsonb_build_object('busca aceita CNPJ inválido', true);
exception when others then null; end;
if (select count(*) from public.find_company_by_cnpj(cnpj_extra)) <> 0 then falhas := falhas || jsonb_build_object('busca acha CNPJ inexistente', true); end if;
begin
  perform public.preregister_company(cnpj_extra);
  falhas := falhas || jsonb_build_object('pré-cadastro sem cache', true);
exception when others then
  if sqlerrm not like 'Dados da empresa indisponíveis%' then falhas := falhas || jsonb_build_object('mensagem sem cache', sqlerrm); end if;
end;

-- Pré-cadastro pela API (cache) e pelo manual; pessoa física vai para o manual.
co_api := public.preregister_company(cnpj_api);
if public.preregister_company(cnpj_api) is distinct from co_api then falhas := falhas || jsonb_build_object('pré-cadastro repetido não devolve a mesma', true); end if;
begin
  perform public.preregister_company(cnpj_pf);
  falhas := falhas || jsonb_build_object('pessoa física pré-cadastrada pela API', true);
exception when others then null; end;
co_pf := public.preregister_company_manual(cnpj_pf, 'Tx Nome Digitado', 'Campinas', 'sp');
co_man := public.preregister_company_manual(cnpj_man, 'Tx Empresa Manual Ltda', 'Santos', 'SP');
begin
  perform public.preregister_company_manual(cnpj_extra, 'Tx Quarta Empresa', 'Santos', 'SP');
  falhas := falhas || jsonb_build_object('cota de pré-cadastro não barrou a 4ª', true);
exception when others then
  if sqlerrm not like 'Limite de cadastros%' then falhas := falhas || jsonb_build_object('mensagem da cota', sqlerrm); end if;
end;
select count(*) into n from public.find_company_by_cnpj('27.182.818/0001-29') f where f.city = 'Campinas' and f.state = 'SP';
if n <> 1 then falhas := falhas || jsonb_build_object('busca não acha a pré-cadastrada com município', n); end if;
-- Fora das listas.
if exists (select 1 from public.list_company_directory() d where d.id in (co_api, co_pf, co_man)) then
  falhas := falhas || jsonb_build_object('pré-cadastrada no diretório', true);
end if;
if exists (select 1 from public.company_responsiveness() d where d.company_id in (co_api, co_pf, co_man)) then
  falhas := falhas || jsonb_build_object('pré-cadastrada na responsividade', true);
end if;
-- Contato do aviso.
begin
  perform public.create_complaint(jsonb_build_object('company_id', co_reg, 'category', 'Carga de trabalho', 'title', 'Tx caso cadastrada',
    'original_content', 'Tx relato original.', 'shared_content', 'Tx versao compartilhavel.',
    'notice_contact', jsonb_build_object('email', 'rh@tx.invalid', 'possibly_involved', false, 'consent', true)), true);
  falhas := falhas || jsonb_build_object('contato aceito para empresa cadastrada', true);
exception when others then null; end;
begin
  perform public.create_complaint(jsonb_build_object('company_id', co_api, 'category', 'Carga de trabalho', 'title', 'Tx sem consentimento',
    'original_content', 'Tx relato original.', 'shared_content', 'Tx versao compartilhavel.',
    'notice_contact', jsonb_build_object('email', 'rh@tx.invalid', 'possibly_involved', false, 'consent', false)), true);
  falhas := falhas || jsonb_build_object('contato sem consentimento aceito', true);
exception when others then null; end;
begin
  perform public.create_complaint(jsonb_build_object('company_id', co_api, 'category', 'Carga de trabalho', 'title', 'Tx sem resposta',
    'original_content', 'Tx relato original.', 'shared_content', 'Tx versao compartilhavel.',
    'notice_contact', jsonb_build_object('email', 'rh@tx.invalid', 'consent', true)), true);
  falhas := falhas || jsonb_build_object('contato sem possibly_involved aceito', true);
exception when others then null; end;
begin
  perform public.create_complaint(jsonb_build_object('company_id', co_api, 'category', 'Carga de trabalho', 'title', 'Tx sem compartilhar',
    'original_content', 'Tx relato original.', 'notice_contact', jsonb_build_object('email', 'rh@tx.invalid', 'possibly_involved', false, 'consent', true)), false);
  falhas := falhas || jsonb_build_object('contato aceito sem compartilhar', true);
exception when others then null; end;
cp1 := public.create_complaint(jsonb_build_object('company_id', co_api, 'category', 'Carga de trabalho', 'title', 'Tx caso um',
  'original_content', 'Tx relato original um.', 'shared_content', 'Tx versao um.',
  'notice_contact', jsonb_build_object('email', ' RH@Tx-Api.invalid ', 'possibly_involved', false, 'consent', true)), true);
cp2 := public.create_complaint(jsonb_build_object('company_id', co_api, 'category', 'Carga de trabalho', 'title', 'Tx caso dois',
  'original_content', 'Tx relato original dois.', 'shared_content', 'Tx versao dois.',
  'notice_contact', jsonb_build_object('email', 'chefe@tx-api.invalid', 'possibly_involved', true, 'consent', true)), true);
cp3 := public.create_complaint(jsonb_build_object('company_id', co_api, 'category', 'Carga de trabalho', 'title', 'Tx caso tres',
  'original_content', 'Tx relato original tres.', 'shared_content', 'Tx versao tres.',
  'notice_contact', jsonb_build_object('email', 'ouvidoria@tx-api.invalid', 'possibly_involved', false, 'consent', true)), true);
cp4 := public.create_complaint(jsonb_build_object('company_id', co_pf, 'category', 'Carga de trabalho', 'title', 'Tx caso pessoa',
  'original_content', 'Tx relato original pessoa.', 'shared_content', 'Tx versao pessoa.',
  'notice_contact', jsonb_build_object('email', 'pessoa@tx.invalid', 'possibly_involved', false, 'consent', true)), true);
cp5 := public.create_complaint(jsonb_build_object('company_id', co_man, 'category', 'Carga de trabalho', 'title', 'Tx caso manual',
  'original_content', 'Tx relato original manual.', 'shared_content', 'Tx versao manual.',
  'notice_contact', jsonb_build_object('email', 'saiu@tx-man.invalid', 'possibly_involved', false, 'consent', true)), true);
-- O trabalhador não lê contatos nem avisos direto, e não decide aviso.
begin
  select count(*) into n from public.complaint_contacts;
  falhas := falhas || jsonb_build_object('trabalhador lê complaint_contacts', n);
exception when insufficient_privilege then null; end;
begin
  select count(*) into n from public.company_notices;
  falhas := falhas || jsonb_build_object('trabalhador lê company_notices', n);
exception when insufficient_privilege then null; end;
begin
  perform public.ops_decide_notice(cp1, 'approved', null);
  falhas := falhas || jsonb_build_object('trabalhador decide aviso', true);
exception when others then null; end;
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
if (select email from public.ops_list_notice_candidates() c where c.complaint_id = cp1) is distinct from 'rh@tx-api.invalid' then
  falhas := falhas || jsonb_build_object('e-mail não normalizado na fila', true);
end if;
begin
  perform public.ops_decide_notice(cp1, 'approved', null);
  falhas := falhas || jsonb_build_object('aviso antes da liberação', true);
exception when others then null; end;
perform public.ops_decide_complaint(cp1, 'released', null);
perform public.ops_decide_complaint(cp2, 'released', null);
perform public.ops_decide_complaint(cp3, 'released', null);
perform public.ops_decide_complaint(cp4, 'released', null);
perform public.ops_decide_complaint(cp5, 'released', null);
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
perform public.ops_decide_notice(cp3, 'rejected', 'Tx empresa já avisada neste mês.');
begin
  perform public.ops_decide_notice(cp3, 'rejected', 'Tx segunda decisão.');
  falhas := falhas || jsonb_build_object('aviso decidido duas vezes', true);
exception when others then null; end;
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
if (select status from public.company_notices where id = n1) is distinct from 'sent' then falhas := falhas || jsonb_build_object('aviso não ficou sent', true); end if;

-- Trilha imutável; retenção apaga o contato e mantém a trilha.
execute 'reset role';
begin
  update public.company_notices set reason = 'Tx alteração indevida.' where id = n1;
  falhas := falhas || jsonb_build_object('aviso alterável', true);
exception when others then null; end;
begin
  delete from public.company_notices where id = n1;
  falhas := falhas || jsonb_build_object('aviso apagável', true);
exception when others then null; end;
update public.complaints set status = 'closed', closed_at = now() - interval '91 days' where id = cp1;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
if public.ops_purge_expired_contacts() < 1 then falhas := falhas || jsonb_build_object('retenção não apagou contato vencido', true); end if;
execute 'reset role';
if (select contact_id from public.company_notices where id = n1) is not null or not exists (select 1 from public.company_notices where id = n1) then
  falhas := falhas || jsonb_build_object('trilha perdida ou contato preso após retenção', true);
end if;
if exists (select 1 from public.companies where id in (co_api, co_pf, co_man) and created_by is not null) then
  falhas := falhas || jsonb_build_object('pré-cadastrada grava quem criou', true);
end if;

-- Anon não executa.
execute 'set local role anon';
begin
  perform public.find_company_by_cnpj(cnpj_api);
  falhas := falhas || jsonb_build_object('anon busca CNPJ', true);
exception when insufficient_privilege then null; end;
begin
  perform public.cnpj_cache_get(cnpj_api);
  falhas := falhas || jsonb_build_object('anon lê o cache', true);
exception when insufficient_privilege then null; end;
res := res || jsonb_build_object('verificações da empresa pré-cadastrada', 'executadas');
