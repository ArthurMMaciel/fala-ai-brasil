-- Teste de fumaça da lista de responsividade (TASK-0036, migration 20261110120000). Executa tudo e desfaz.
-- Rodar no banco local: npx supabase db query --local < supabase/tests/responsiveness_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := 'a1111111-1111-1111-1111-111111111111';
  ca uuid := 'a2222222-2222-2222-2222-222222222222';
  cb uuid := 'a3333333-3333-3333-3333-333333333333';
  cc uuid := 'a4444444-4444-4444-4444-444444444444';
  cd uuid := 'a5555555-5555-5555-5555-555555555555';
  addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}';
  v_worker uuid; co_a uuid; co_b uuid; co_c uuid; co_d uuid; v_id uuid; v_seq text; r record; spec record; i int;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'rw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Trabalhador Lista', 'cpf', '39053344705', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', ca, 'authenticated', 'authenticated', 'rca@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Zz Teste Alfa Ltda', 'cnpj', '11222333000181', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', cb, 'authenticated', 'authenticated', 'rcb@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Zz Teste Beta Ltda', 'cnpj', '45723174000110', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', cc, 'authenticated', 'authenticated', 'rcc@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Zz Teste Charlie Ltda', 'cnpj', '11444777000161', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', cd, 'authenticated', 'authenticated', 'rcd@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Zz Teste Delta Ltda', 'cnpj', '12ABC34501DE35', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now());
  select id into v_worker from public.workers where user_id = w;
  select company_id into co_a from public.company_users where user_id = ca;
  select company_id into co_b from public.company_users where user_id = cb;
  select company_id into co_c from public.company_users where user_id = cc;
  select company_id into co_d from public.company_users where user_id = cd;

  -- Casos: criados há 10 dias, liberados há 5 dias; resposta 'hours' depois da liberação.
  -- Alfa: 5 liberadas, 4 respondidas em 48 h (limites: 80% e 48 h). Beta: 5, 3 em 49 h (60%, acima de 48 h).
  -- Charlie: 2 liberadas (abaixo do corte). Delta: 3 liberadas, nenhuma respondida, mais 1 em revisão (não conta).
  for spec in select * from (values (co_a, 5, 4, 48), (co_b, 5, 3, 49), (co_c, 2, 2, 10), (co_d, 3, 0, 0)) as t(company, total, answered, hours) loop
    for i in 1..spec.total loop
      insert into public.complaints (worker_id, company_id, category, title, status, created_at)
      values (v_worker, spec.company, 'Carga de trabalho', 'Caso de teste ' || i, case when i <= spec.answered then 'answered' else 'shared' end::public.complaint_status, now() - interval '10 days')
      returning id into v_id;
      insert into public.complaint_events (complaint_id, status, actor, note, created_at) values (v_id, 'shared', 'platform', 'Liberada.', now() - interval '5 days');
      if i <= spec.answered then
        insert into public.company_responses (complaint_id, company_id, content, created_at)
        values (v_id, spec.company, 'Resposta institucional de teste.', now() - interval '5 days' + make_interval(hours => spec.hours));
      end if;
    end loop;
  end loop;
  insert into public.complaints (worker_id, company_id, category, title, status) values (v_worker, co_d, 'Carga de trabalho', 'Em revisão', 'in_review');

  -- Limites das faixas.
  res := res || jsonb_build_object('faixa de resposta nos limites',
    private.response_band(80) = 'high' and private.response_band(79.99) = 'medium' and private.response_band(50) = 'medium' and private.response_band(49.99) = 'low');
  res := res || jsonb_build_object('faixa de tempo nos limites',
    private.response_time_band(48) = 'fast' and private.response_time_band(48.01) = 'regular' and private.response_time_band(168) = 'regular'
    and private.response_time_band(168.01) = 'slow' and private.response_time_band(null) = 'none');
  res := res || jsonb_build_object('lista pública sem contagem, taxa ou horas',
    pg_get_function_result('public.company_responsiveness()'::regprocedure) !~* 'received|released|answered|rate|hours');

  -- Trabalhador vê a lista: só faixas, corte de 3, ordem por nome.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  select string_agg(t.name, ',' order by t.ord) into v_seq
  from public.company_responsiveness() with ordinality as t(company_id, name, city, state, response_band, response_time_band, satisfaction_band, is_mine, ord)
  where t.company_id in (co_a, co_b, co_c, co_d);
  res := res || jsonb_build_object('ordem por nome e corte de 3', v_seq = 'Zz Teste Alfa Ltda,Zz Teste Beta Ltda,Zz Teste Delta Ltda');
  res := res || jsonb_build_object('Alfa: high e fast (liberação, não criação)',
    exists (select 1 from public.company_responsiveness() where company_id = co_a and response_band = 'high' and response_time_band = 'fast'));
  res := res || jsonb_build_object('Beta: medium e regular',
    exists (select 1 from public.company_responsiveness() where company_id = co_b and response_band = 'medium' and response_time_band = 'regular'));
  res := res || jsonb_build_object('Delta: low e none, em revisão fora da conta',
    exists (select 1 from public.company_responsiveness() where company_id = co_d and response_band = 'low' and response_time_band = 'none'));
  res := res || jsonb_build_object('satisfação nula e nada marcado como meu para o trabalhador',
    not exists (select 1 from public.company_responsiveness() where satisfaction_band is not null or is_mine));
  res := res || jsonb_build_object('trabalhador não tem números próprios', (select count(*) from public.my_company_responsiveness()) = 0);

  -- Empresa Alfa: is_mine só nela; números exatos só dela.
  perform set_config('request.jwt.claims', json_build_object('sub', ca, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('is_mine só na própria empresa',
    (select count(*) from public.company_responsiveness() where is_mine) = 1
    and exists (select 1 from public.company_responsiveness() where company_id = co_a and is_mine));
  select * into r from public.my_company_responsiveness();
  res := res || jsonb_build_object('Alfa vê os próprios números exatos',
    r.company_id = co_a and r.released = 5 and r.answered = 4 and r.response_rate = 80 and r.avg_first_response_hours = 48
    and r.response_band = 'high' and r.response_time_band = 'fast' and r.listed);
  res := res || jsonb_build_object('Alfa não vê números de outra empresa', (select count(*) from public.my_company_responsiveness()) = 1);

  -- Charlie: fora da lista, mas vê os próprios números com listed = false.
  perform set_config('request.jwt.claims', json_build_object('sub', cc, 'role', 'authenticated')::text, true);
  select * into r from public.my_company_responsiveness();
  res := res || jsonb_build_object('Charlie abaixo do corte vê os próprios números',
    r.company_id = co_c and r.released = 2 and r.answered = 2 and not r.listed and r.response_band = 'high');

  -- Anônimo não executa.
  execute 'reset role';
  execute 'set local role anon';
  begin
    perform public.company_responsiveness();
    res := res || jsonb_build_object('anônimo barrado', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('anônimo barrado', true); end;
  begin
    perform private.company_response_stats();
    res := res || jsonb_build_object('estatística interna fechada', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('estatística interna fechada', true); end;

  execute 'reset role';
  raise exception 'RESULTADOS %', res;
end $$;
