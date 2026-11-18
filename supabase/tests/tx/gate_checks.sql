-- declare: u_w uuid := 'e1111111-1111-1111-1111-111111111111'; u_c uuid := 'e2222222-2222-2222-2222-222222222222'; u_c2 uuid := 'e3333333-3333-3333-3333-333333333333'; u_op uuid := 'e4444444-4444-4444-4444-444444444444'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; v_co uuid; v_cp uuid; n int; v_ok boolean;
-- Verificações da ADR-0012 (20261117120000 e 20261117130000) depois de aplicadas na transação de teste.
-- Imprime só contagens e nomes de verificação; nenhum dado real.

-- Estado real (contagens): quantos vínculos ficam 'pending' e perdem acesso a manifestações com a troca do gate.
select count(*) into n from public.company_users where verification_status = 'pending';
res := res || jsonb_build_object('vínculos reais que ficam pending', n);
select count(*) into n from public.company_users where verification_status <> 'pending';
if n > 0 then falhas := falhas || jsonb_build_object('vínculo real nasceu fora de pending', n); end if;

-- Montagem: trabalhador, empresa (dono + segundo membro, ambos pending) e equipe.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-w@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Trabalhador', 'cpf', '11144477735', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-c@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Empresa Gate Ltda', 'cnpj', '98765008987665', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_c2, 'authenticated', 'authenticated', 'tx-c2@teste.invalid', '{}', now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-op@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);
select company_id into v_co from public.company_users where user_id = u_c;
insert into public.company_users (company_id, user_id, role) values (v_co, u_c2, 'member');
if (select verification_status from public.company_users where user_id = u_c) is distinct from 'pending' then
  falhas := falhas || jsonb_build_object('cadastro novo não nasce pending', true);
end if;

execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
v_cp := public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso do gate',
  'original_content', 'Tx relato original do teste do gate.', 'shared_content', 'Tx versao compartilhavel do gate.'), true);
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_decide_complaint(v_cp, 'released', null);

-- Pending: não vê, não responde, sem números próprios; lê o próprio estado.
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_company_complaints() where id = v_cp) <> 0 then falhas := falhas || jsonb_build_object('pending vê caso liberado', true); end if;
if (select count(*) from public.get_company_complaint_timeline(v_cp)) <> 0 then falhas := falhas || jsonb_build_object('pending vê linha do tempo', true); end if;
if (select count(*) from public.my_company_responsiveness()) <> 0 then falhas := falhas || jsonb_build_object('pending vê números próprios', true); end if;
if (select count(*) from public.my_company_satisfaction()) <> 0 then falhas := falhas || jsonb_build_object('pending vê satisfação', true); end if;
if (select verification_status from public.company_users where company_id = v_co and user_id = u_c) is distinct from 'pending' then
  falhas := falhas || jsonb_build_object('empresa não lê o próprio estado', true);
end if;
begin
  perform public.respond_complaint(v_cp, 'Tx resposta de vínculo pending.');
  falhas := falhas || jsonb_build_object('pending responde', true);
exception when others then null; end;

begin
  perform public.update_company_profile(v_co, jsonb_build_object('trade_name', 'Tx nome do pending'));
exception when others then falhas := falhas || jsonb_build_object('pending não edita perfil: ' || sqlerrm, true); end;
-- A empresa não se autoverifica.
begin
  update public.company_users set verification_status = 'verified' where user_id = u_c;
  get diagnostics n = row_count;
  if n > 0 then falhas := falhas || jsonb_build_object('empresa altera o próprio estado', n); end if;
exception when insufficient_privilege then null; end;
begin
  perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação', null);
  falhas := falhas || jsonb_build_object('empresa usa função da equipe', true);
exception when others then null; end;

-- Equipe: validações e verificação.
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
if not exists (select 1 from public.ops_list_representatives('pending') where user_id = u_c) then falhas := falhas || jsonb_build_object('fila da equipe sem o pending', true); end if;
begin
  perform public.ops_verify_representative(v_co, u_c, 'verified', null, 'Tx ligação', null);
  falhas := falhas || jsonb_build_object('verificação sem método aceita', true);
exception when others then null; end;
begin
  perform public.ops_verify_representative(v_co, u_c, 'revoked', null, null, 'Tx motivo de revogação longo.');
  falhas := falhas || jsonb_build_object('revogar pending aceito', true);
exception when others then null; end;
perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação ao telefone público', null);

-- Verified vê e responde; o membro ainda pending continua sem ver.
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_company_complaints() where id = v_cp) <> 1 then falhas := falhas || jsonb_build_object('verified não vê caso liberado', true); end if;
if (select count(*) from public.my_company_responsiveness()) <> 1 then falhas := falhas || jsonb_build_object('verified sem números próprios', true); end if;
begin
  perform public.respond_complaint(v_cp, 'Tx resposta do representante verificado.');
exception when others then falhas := falhas || jsonb_build_object('verified não responde: ' || sqlerrm, true); end;
perform set_config('request.jwt.claims', json_build_object('sub', u_c2, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_company_complaints() where id = v_cp) <> 0 then falhas := falhas || jsonb_build_object('membro pending vê caso', true); end if;

-- Revogação tira o acesso.
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_verify_representative(v_co, u_c, 'revoked', null, null, 'Tx representante deixou a empresa.');
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
if (select count(*) from public.list_company_complaints() where id = v_cp) <> 0 then falhas := falhas || jsonb_build_object('revoked vê caso', true); end if;
if (select count(*) from public.get_company_complaint_timeline(v_cp)) <> 0 then falhas := falhas || jsonb_build_object('revoked vê linha do tempo', true); end if;
begin
  perform public.update_company_profile(v_co, jsonb_build_object('trade_name', 'Tx nome trocado por revogado'));
  falhas := falhas || jsonb_build_object('revoked edita perfil da empresa', true);
exception when others then null; end;

-- Anon não executa as funções novas.
execute 'reset role';
execute 'set local role anon';
begin
  perform public.is_verified_company_user(v_co);
  falhas := falhas || jsonb_build_object('anon executa is_verified_company_user', true);
exception when insufficient_privilege then null; end;
begin
  perform public.ops_list_representatives('pending');
  falhas := falhas || jsonb_build_object('anon executa ops_list_representatives', true);
exception when insufficient_privilege then null; end;

-- Trilha: 2 decisões e imutável até para o dono.
execute 'reset role';
select count(*) into n from public.representative_verifications where company_id = v_co;
if n <> 2 then falhas := falhas || jsonb_build_object('trilha com ' || n || ' decisões (esperado 2)', true); end if;
begin
  update public.representative_verifications set reason = 'Tx alteração indevida da trilha.' where company_id = v_co;
  falhas := falhas || jsonb_build_object('trilha alterável', true);
exception when others then null; end;
begin
  delete from public.representative_verifications where company_id = v_co;
  falhas := falhas || jsonb_build_object('trilha apagável', true);
exception when others then null; end;
res := res || jsonb_build_object('verificações do gate', 'executadas');
