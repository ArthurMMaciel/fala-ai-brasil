-- declare: u_w uuid := 'e8888888-8888-8888-8888-888888888888'; u_c uuid := 'e9999999-9999-9999-9999-999999999999'; u_op uuid := 'eaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; v_co uuid; v_cp uuid; n int;
-- Verificações da ADR-0021 (20261117150000) depois de aplicada na transação de teste. Funciona com ou sem a troca do gate
-- (a empresa do teste é verificada pela equipe quando a função existe).
if public.pilot_state() is distinct from 'open' then falhas := falhas || jsonb_build_object('estado inicial não é open', true); end if;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-pw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Pausa Trabalhador', 'cpf', '74682489070', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-pc@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Pausa Empresa Ltda', 'cnpj', '34028316000103', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-pop@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);
select company_id into v_co from public.company_users where user_id = u_c;

execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
v_cp := public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso antes da pausa',
  'original_content', 'Tx relato original antes da pausa.', 'shared_content', 'Tx versao compartilhavel antes da pausa.'), true);
begin
  perform public.ops_set_pilot_state('paused', 'Tx motivo de quem não é da equipe.');
  falhas := falhas || jsonb_build_object('trabalhador pausa o piloto', true);
exception when others then null; end;

perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
begin
  perform public.ops_set_pilot_state('paused', 'curto');
  falhas := falhas || jsonb_build_object('pausa com motivo curto', true);
exception when others then null; end;
perform public.ops_set_pilot_state('paused', 'Tx pausa de teste do piloto.');
if public.pilot_state() is distinct from 'paused' then falhas := falhas || jsonb_build_object('estado não mudou', true); end if;
-- Com o piloto pausado, a equipe ainda pede ajuste.
perform public.ops_decide_complaint(v_cp, 'adjustment_requested', 'Tx ajuste pedido durante a pausa.');

perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
begin
  perform public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso durante a pausa',
    'original_content', 'Tx relato original durante a pausa.', 'shared_content', 'Tx versao durante a pausa.'), true);
  falhas := falhas || jsonb_build_object('manifestação nova aceita na pausa', true);
exception when others then
  if sqlerrm not like 'Novas manifestações estão temporariamente suspensas%' then falhas := falhas || jsonb_build_object('mensagem da pausa diferente', true); end if;
end;
begin
  perform public.share_complaint(v_cp, 'Tx versao reenviada durante a pausa.');
exception when others then falhas := falhas || jsonb_build_object('ajuste bloqueado na pausa', true); end;
if (select count(*) from public.complaints where id = v_cp) <> 1 then falhas := falhas || jsonb_build_object('trabalhador não lê o próprio caso na pausa', true); end if;

perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_decide_complaint(v_cp, 'released', null);
if exists (select 1 from pg_proc where proname = 'ops_verify_representative') then
  execute 'select public.ops_verify_representative($1, $2, ''verified'', ''callback'', ''Tx ligação na pausa'', null)' using v_co, u_c;
end if;
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
begin
  perform public.respond_complaint(v_cp, 'Tx resposta da empresa durante a pausa.');
exception when others then falhas := falhas || jsonb_build_object('empresa não responde na pausa', true); end;

perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
begin
  perform public.close_complaint(v_cp, 'yes');
exception when others then falhas := falhas || jsonb_build_object('encerramento bloqueado na pausa', true); end;

perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
begin
  perform public.ops_set_pilot_state('paused', 'Tx pausa repetida no teste.');
  falhas := falhas || jsonb_build_object('pausa repetida aceita', true);
exception when others then null; end;
perform public.ops_set_pilot_state('open', 'Tx reabertura de teste do piloto.');
if (select count(*) from public.ops_pilot_state_log() where reason like 'Tx %') <> 2 then falhas := falhas || jsonb_build_object('trilha sem as 2 mudanças', true); end if;
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
begin
  perform public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso depois da pausa',
    'original_content', 'Tx relato original depois da pausa.', 'shared_content', 'Tx versao depois da pausa.'), true);
exception when others then falhas := falhas || jsonb_build_object('manifestação recusada após reabrir', true); end;

-- Anon lê o estado e não muda; trilha imutável.
execute 'reset role';
execute 'set local role anon';
if public.pilot_state() is distinct from 'open' then falhas := falhas || jsonb_build_object('anon não lê o estado', true); end if;
begin
  perform public.ops_set_pilot_state('paused', 'Tx anon tentando pausar.');
  falhas := falhas || jsonb_build_object('anon executa ops_set_pilot_state', true);
exception when insufficient_privilege then null; end;
execute 'reset role';
begin
  delete from public.pilot_state_log where reason like 'Tx %';
  falhas := falhas || jsonb_build_object('trilha da pausa apagável', true);
exception when others then null; end;
res := res || jsonb_build_object('verificações da pausa', 'executadas');
