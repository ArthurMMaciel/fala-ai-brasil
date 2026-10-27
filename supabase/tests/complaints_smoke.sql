-- Teste de fumaça de manifestações e conexões (modelo v3). Executa tudo e desfaz: o resultado vem na mensagem RESULTADOS.
-- Rodar: npx supabase db query --linked < supabase/tests/complaints_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := '61111111-1111-1111-1111-111111111111';
  c uuid := '62222222-2222-2222-2222-222222222222';
  c2 uuid := '63333333-3333-3333-3333-333333333333';
  p uuid := '64444444-4444-4444-4444-444444444444';
  v_company uuid; v_partner uuid; shared_id uuid; private_id uuid; ok boolean; n int;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'w3@teste.invalid', '{"signup_type":"worker","signup":{"full_name":"W","cpf":"52998224725","address":{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', c, 'authenticated', 'authenticated', 'c3@teste.invalid', '{"signup_type":"company","signup":{"legal_name":"Empresa Smoke Ltda","cnpj":"45723174000110","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"A","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', c2, 'authenticated', 'authenticated', 'c4@teste.invalid', '{"signup_type":"company","signup":{"legal_name":"Outra Smoke Ltda","cnpj":"04252011000110","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"B","number":"2","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', p, 'authenticated', 'authenticated', 'p3@teste.invalid', '{"signup_type":"partner","signup":{"display_name":"P","document_type":"cpf","document":"52998224725","specialty":"X","plan_id":"partner-presence","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"C","number":"3","city":"São Paulo","state":"SP"}}}', now(), now());
  select cu.company_id into v_company from public.company_users cu where cu.user_id = c;
  select pa.id into v_partner from public.partners pa where pa.user_id = p;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  shared_id := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Carga de trabalho', 'title', 'Demandas fora do horário', 'original_content', 'Meu gestor Fulano manda mensagens às 23h.', 'shared_content', 'O relato descreve demandas frequentes fora do horário combinado.', 'expected_outcomes', jsonb_build_array('Receber uma resposta')), true);
  private_id := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Convivência', 'title', 'Guardada sem compartilhar', 'original_content', 'Texto que não deve chegar à empresa.'), false);
  res := res || jsonb_build_object('protocolo gerado', (select protocol like 'EAB-____-____' from public.complaints where id = shared_id));
  res := res || jsonb_build_object('trabalhador vê as próprias', (select count(*) from public.complaints) = 2 and (select count(*) from public.complaint_originals) = 2);

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from public.list_company_complaints();
  res := res || jsonb_build_object('empresa vê só a compartilhada', n = 1);
  res := res || jsonb_build_object('empresa não lê tabelas diretamente', (select count(*) from public.complaints) = 0 and (select count(*) from public.complaint_originals) = 0);
  ok := not exists (select 1 from public.list_company_complaints() where shared_content like '%Fulano%');
  res := res || jsonb_build_object('original não vaza para a empresa', ok);
  begin
    perform public.respond_complaint(private_id, 'Tentativa de responder manifestação não compartilhada.');
    res := res || jsonb_build_object('empresa não responde não compartilhada', false);
  exception when others then res := res || jsonb_build_object('empresa não responde não compartilhada', true); end;
  perform public.respond_complaint(shared_id, 'Recebemos e vamos revisar os combinados de horário com a equipe.');
  res := res || jsonb_build_object('resposta muda status', (select status = 'answered' from public.list_company_complaints() where id = shared_id));
  perform public.company_request_partner(v_partner);

  perform set_config('request.jwt.claims', json_build_object('sub', c2, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('outra empresa não vê', (select count(*) from public.list_company_complaints()) = 0 and (select count(*) from public.get_company_complaint_timeline(shared_id)) = 0);

  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('trabalhador vê a resposta', (select count(*) from public.company_responses where complaint_id = shared_id) = 1);
  perform public.close_complaint(shared_id, 'partial');
  res := res || jsonb_build_object('trabalhador encerra com avaliação', (select status = 'closed' and worker_feedback = 'partial' from public.complaints where id = shared_id));

  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('parceiro vê interesse da empresa', exists (select 1 from public.list_partner_companies() where id = v_company and stage = 'company_interest'));
  perform public.partner_set_connection(v_company, 'client');
  res := res || jsonb_build_object('parceiro marca cliente', exists (select 1 from public.list_partner_companies() where id = v_company and stage = 'client'));
  res := res || jsonb_build_object('parceiro não lê manifestações', (select count(*) from public.list_company_complaints()) = 0 and (select count(*) from public.complaints) = 0);

  execute 'reset role';
  raise exception 'RESULTADOS %', res;
end $$;
