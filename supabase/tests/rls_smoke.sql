-- Teste de fumaça do cadastro e RLS (ADR-0009). Executa tudo e desfaz: o resultado vem na mensagem de erro RESULTADOS.
-- Rodar: npx supabase db query --linked < supabase/tests/rls_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := '11111111-1111-1111-1111-111111111111';
  c uuid := '22222222-2222-2222-2222-222222222222';
  p uuid := '33333333-3333-3333-3333-333333333333';
  ok boolean;
  detail text;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'w@teste.invalid',
   '{"full_name":"Worker Teste","signup_type":"worker","signup":{"full_name":"Worker Teste","cpf":"52998224725","address":{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1000","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', c, 'authenticated', 'authenticated', 'c@teste.invalid',
   '{"full_name":"Empresa Teste","signup_type":"company","signup":{"legal_name":"Empresa Teste Ltda","cnpj":"11222333000181","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"Augusta","number":"10","city":"São Paulo","state":"sp"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', p, 'authenticated', 'authenticated', 'p@teste.invalid',
   '{"full_name":"Parceira Teste","signup_type":"partner","signup":{"display_name":"Parceira Teste","document_type":"cpf","document":"52998224725","specialty":"Psicologia organizacional","plan_id":"partner-presence","subscription_mode":"monthly","address":{"zip_code":"80010000","street_type":"street","street_name":"XV de Novembro","number":"1","city":"Curitiba","state":"PR"}}}', now(), now());

  ok := not exists (select 1 from auth.users where id in (w, c, p) and (raw_user_meta_data ? 'signup' or raw_user_meta_data ? 'signup_type'));
  res := res || jsonb_build_object('metadata sem documento', ok);
  ok := exists (select 1 from public.subscriptions s join public.companies co on co.id = s.company_id where co.cnpj = '11222333000181' and s.status = 'trialing');
  res := res || jsonb_build_object('empresa em trial', ok);
  ok := exists (select 1 from public.subscriptions s join public.partners pa on pa.id = s.partner_id where pa.user_id = p and s.status = 'pending');
  res := res || jsonb_build_object('parceira mensal pendente', ok);
  ok := exists (select 1 from public.addresses where state = 'SP' and street_name = 'Augusta');
  res := res || jsonb_build_object('UF normalizada', ok);

  begin
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', 'x@teste.invalid',
     '{"signup_type":"partner","signup":{"display_name":"X","document_type":"cpf","document":"52998224725","specialty":"Y","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"A","number":"1","city":"B","state":"SP"}}}', now(), now());
    res := res || jsonb_build_object('plano de outra audiência recusado', false);
  exception when others then
    res := res || jsonb_build_object('plano de outra audiência recusado', true);
  end;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  ok := (select count(*) from public.workers) = 1 and (select count(*) from public.companies) = 0 and (select count(*) from public.partners) = 0 and (select count(*) from public.subscriptions) = 0;
  res := res || jsonb_build_object('worker vê só o próprio cadastro', ok);
  ok := (select count(*) from public.addresses) = 1;
  res := res || jsonb_build_object('worker vê só o próprio endereço', ok);
  ok := (select count(*) from public.list_partner_directory()) = 0;
  res := res || jsonb_build_object('worker sem diretório', ok);
  perform public.add_profile('partner', '{"display_name":"Worker também parceira","document_type":"cpf","document":"52998224725","specialty":"Mediação","plan_id":"partner-presence","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"Teste","number":"2","city":"São Paulo","state":"SP"}}');
  select string_agg(profile_type, ',' order by profile_type) into detail from public.current_profiles();
  res := res || jsonb_build_object('vários perfis: ' || detail, detail = 'partner,worker');
  begin
    update public.workers set cpf = '00000000000';
    res := res || jsonb_build_object('cpf não editável pelo cliente', false);
  exception when insufficient_privilege then
    res := res || jsonb_build_object('cpf não editável pelo cliente', true);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  ok := (select count(*) from public.companies) = 1 and (select count(*) from public.subscriptions) = 1 and (select count(*) from public.workers) = 0;
  res := res || jsonb_build_object('empresa vê só a própria empresa', ok);
  select string_agg(display_name || '/' || city || '/' || state, '; ') into detail from public.list_partner_directory();
  res := res || jsonb_build_object('diretório: ' || coalesce(detail, '-'), (select count(*) from public.list_partner_directory()) = 2);

  execute 'reset role';
  raise exception 'RESULTADOS %', res;
end $$;
