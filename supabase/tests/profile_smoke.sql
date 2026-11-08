-- Teste de fumaça do "Meu perfil" (ADR-0014, migration 20261108120000). Executa tudo e desfaz.
-- Rodar no banco local: npx supabase db query --local < supabase/tests/profile_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := '91111111-1111-1111-1111-111111111111';
  w2 uuid := '92222222-2222-2222-2222-222222222222';
  c uuid := '93333333-3333-3333-3333-333333333333';
  m uuid := '94444444-4444-4444-4444-444444444444';
  a uuid := '95555555-5555-5555-5555-555555555555';
  bad uuid := '96666666-6666-6666-6666-666666666666';
  o uuid := '97777777-7777-7777-7777-777777777777';
  addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}';
  v_worker uuid; v_company uuid; v_company_addr uuid; ok boolean; n int;
begin
  -- 1) Dígitos verificadores no banco.
  res := res || jsonb_build_object('cpf válido aceito', private.valid_cpf('52998224725'));
  res := res || jsonb_build_object('cpf com dígito errado recusado', not private.valid_cpf('52998224724'));
  res := res || jsonb_build_object('cpf repetido recusado', not private.valid_cpf('11111111111'));
  res := res || jsonb_build_object('cnpj alfanumérico válido aceito', private.valid_cnpj('12ABC34501DE35'));
  res := res || jsonb_build_object('cnpj numérico válido aceito', private.valid_cnpj('11444777000161'));
  res := res || jsonb_build_object('cnpj com dígito errado recusado', not private.valid_cnpj('11444777000162'));

  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'w9@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Trabalhadora Perfil', 'cpf', '529.982.247-25', 'phone', '41987654321', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', w2, 'authenticated', 'authenticated', 'w10@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Outro Trabalhador', 'cpf', '11144477735', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', c, 'authenticated', 'authenticated', 'c9@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Empresa Perfil Ltda', 'cnpj', '11.444.777/0001-61', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', m, 'authenticated', 'authenticated', 'm9@teste.invalid', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', a, 'authenticated', 'authenticated', 'a9@teste.invalid', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', o, 'authenticated', 'authenticated', 'o9@teste.invalid', '{}', now(), now());
  insert into private.platform_admins (user_id) values (a);
  insert into private.document_officers (user_id) values (o);
  select id into v_worker from public.workers where user_id = w;
  select company_id into v_company from public.company_users where user_id = c;
  select address_id into v_company_addr from public.companies where id = v_company;
  insert into public.company_users (company_id, user_id, role) values (v_company, m, 'member');

  begin
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', bad, 'authenticated', 'authenticated', 'bad9@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Inválido', 'cpf', '52998224724', 'address', addr)), now(), now());
    res := res || jsonb_build_object('cadastro com cpf inválido recusado', false);
  exception when others then res := res || jsonb_build_object('cadastro com cpf inválido recusado', true); end;

  execute 'set local role authenticated';

  -- 2) Trabalhador.
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  perform public.update_worker_profile(jsonb_build_object('full_name', '  Trabalhadora Perfil Silva ', 'phone', '(41) 3333-4444',
    'address', addr || '{"city":"Curitiba","state":"pr","number":"200"}'));
  res := res || jsonb_build_object('trabalhador altera nome, telefone e endereço',
    (select w.full_name = 'Trabalhadora Perfil Silva' and w.phone = '4133334444' and ad.city = 'Curitiba' and ad.state = 'PR'
     from public.workers w join public.addresses ad on ad.id = w.address_id where w.user_id = auth.uid()));
  begin
    perform public.update_worker_profile('{"cpf":"11144477735"}');
    res := res || jsonb_build_object('cpf no perfil recusado', false);
  exception when others then res := res || jsonb_build_object('cpf no perfil recusado', sqlerrm like '%só pode ser alterado pela equipe%'); end;
  begin
    perform public.update_worker_profile('{"phone":"4112345"}');
    res := res || jsonb_build_object('telefone inválido recusado', false);
  exception when others then res := res || jsonb_build_object('telefone inválido recusado', true); end;
  begin
    perform public.update_worker_profile(jsonb_build_object('address', addr || '{"zip_code":"123"}'));
    res := res || jsonb_build_object('cep inválido recusado', false);
  exception when others then res := res || jsonb_build_object('cep inválido recusado', true); end;
  begin
    perform public.update_worker_profile(jsonb_build_object('address', addr || '{"state":"São"}'));
    res := res || jsonb_build_object('uf inválida recusada', false);
  exception when others then res := res || jsonb_build_object('uf inválida recusada', true); end;
  begin
    update public.workers set full_name = 'Direto' where user_id = auth.uid();
    res := res || jsonb_build_object('update direto em workers negado', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('update direto em workers negado', true); end;
  perform public.update_worker_profile(jsonb_build_object('full_name', 'Trabalhadora Perfil Silva'));

  perform set_config('request.jwt.claims', json_build_object('sub', w2, 'role', 'authenticated')::text, true);
  perform public.update_worker_profile('{"full_name":"Outro Nome"}');
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  begin
    perform public.update_worker_profile('{"full_name":"Empresa tentando"}');
    res := res || jsonb_build_object('empresa não usa perfil de trabalhador', false);
  exception when others then res := res || jsonb_build_object('empresa não usa perfil de trabalhador', true); end;

  -- 3) Empresa: dono edita; membro só lê; CNPJ e razão social travados.
  perform public.update_company_profile(v_company, jsonb_build_object('trade_name', 'Perfil', 'contact_email', ' RH@Perfil.Invalid ', 'contact_phone', '41999990000',
    'address', addr || '{"number":"300"}'));
  res := res || jsonb_build_object('dono altera fantasia, contato e endereço',
    (select co.trade_name = 'Perfil' and co.contact_email = 'rh@perfil.invalid' and co.contact_phone = '41999990000' and ad.number = '300'
     from public.companies co join public.addresses ad on ad.id = co.address_id where co.id = v_company));
  begin
    perform public.update_company_profile(v_company, '{"legal_name":"Outra Razão"}');
    res := res || jsonb_build_object('razão social travada', false);
  exception when others then res := res || jsonb_build_object('razão social travada', true); end;
  begin
    perform public.update_company_profile(v_company, '{"cnpj":"45723174000110"}');
    res := res || jsonb_build_object('cnpj travado', false);
  exception when others then res := res || jsonb_build_object('cnpj travado', true); end;
  begin
    perform public.update_company_profile(v_company, '{"contact_email":"sem-arroba"}');
    res := res || jsonb_build_object('e-mail de contato inválido recusado', false);
  exception when others then res := res || jsonb_build_object('e-mail de contato inválido recusado', true); end;
  begin
    update public.companies set trade_name = 'Direto' where id = v_company;
    res := res || jsonb_build_object('update direto em companies negado', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('update direto em companies negado', true); end;

  perform set_config('request.jwt.claims', json_build_object('sub', m, 'role', 'authenticated')::text, true);
  begin
    perform public.update_company_profile(v_company, '{"trade_name":"Membro"}');
    res := res || jsonb_build_object('membro não edita a empresa', false);
  exception when others then res := res || jsonb_build_object('membro não edita a empresa', true); end;
  res := res || jsonb_build_object('membro lê o endereço da empresa', (select count(*) from public.addresses where id = v_company_addr) = 1);
  begin
    update public.addresses set number = '999' where id = v_company_addr;
    res := res || jsonb_build_object('membro não altera endereço direto', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('membro não altera endereço direto', true); end;

  -- 4) Equipe: troca de documento com justificativa; trilha sem valores e fechada.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  begin
    perform public.ops_change_document('company_cnpj', v_company, '45723174000110', 'Correção pedida pela empresa.', 'Contrato social 2026');
    res := res || jsonb_build_object('empresa não troca documento pela equipe', false);
  exception when others then res := res || jsonb_build_object('empresa não troca documento pela equipe', true); end;
  begin
    perform count(*) from public.profile_change_log;
    res := res || jsonb_build_object('trilha fechada para authenticated', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('trilha fechada para authenticated', true); end;

  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin
    perform public.ops_change_document('company_cnpj', v_company, '45723174000110', 'Correção pedida pela empresa por ofício.', 'Ofício 12/2026');
    res := res || jsonb_build_object('admin sem privilégio de documentos recusado', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('admin sem privilégio de documentos recusado', true); end;

  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  begin
    perform public.ops_change_document('company_cnpj', v_company, '45723174000110', 'curta', 'Ofício 12/2026');
    res := res || jsonb_build_object('troca exige motivo', false);
  exception when others then res := res || jsonb_build_object('troca exige motivo', true); end;
  begin
    perform public.ops_change_document('company_cnpj', v_company, '45723174000110', 'Correção pedida pela empresa por ofício.', '');
    res := res || jsonb_build_object('troca exige referência do documento', false);
  exception when others then res := res || jsonb_build_object('troca exige referência do documento', true); end;
  begin
    perform public.ops_change_document('company_cnpj', v_company, '11444777000162', 'Correção pedida pela empresa por ofício.', 'Ofício 12/2026');
    res := res || jsonb_build_object('troca valida dígitos', false);
  exception when others then res := res || jsonb_build_object('troca valida dígitos', true); end;
  perform public.ops_change_document('company_cnpj', v_company, '45.723.174/0001-10', 'Correção pedida pela empresa por ofício.', 'Ofício 12/2026');
  perform public.ops_change_document('company_legal_name', v_company, 'Empresa Perfil Serviços Ltda', 'Alteração contratual registrada na Junta.', 'Contrato social, 3ª alteração');
  perform public.ops_change_document('worker_cpf', v_worker, '111.444.777-35', 'Erro de digitação confirmado com a trabalhadora.', 'Documento de identidade conferido');
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('equipe troca documentos',
    (select cnpj = '45723174000110' and legal_name = 'Empresa Perfil Serviços Ltda' from public.companies where id = v_company)
    and (select cpf = '11144477735' from public.workers where id = v_worker));

  select count(*) into n from public.ops_profile_changes(v_worker);
  res := res || jsonb_build_object('trilha do trabalhador: 1 própria + 1 da equipe (repetição sem mudança não grava)', n = 2);
  select fields @> '{full_name,phone,address.city,address.state,address.number}' into ok from public.ops_profile_changes(v_worker) where source = 'self';
  res := res || jsonb_build_object('trilha registra nomes dos campos', ok);
  res := res || jsonb_build_object('trilha da troca com quem, motivo e referência',
    (select count(*) from public.ops_profile_changes(v_company) where source = 'platform' and justification is not null and evidence_ref is not null and actor_user_id = o) = 2);
  res := res || jsonb_build_object('trilha sem valores',
    not exists (select 1 from public.ops_profile_changes(v_company) where array_to_string(fields, ',') ~ '[0-9]{8}|@|Perfil'));

  execute 'reset role';
  raise exception 'RESULTADOS %', res;
end $$;
