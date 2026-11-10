-- Teste de fumaça da resposta revisada pela equipe (TASK-0035 / ADR-0013; migrations 20261109160000, 140000 e 150000).
-- Executa tudo e desfaz. Rodar no banco local: npx supabase db query --local < supabase/tests/response_review_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := 'b1111111-1111-1111-1111-111111111111';
  w2 uuid := 'b2222222-2222-2222-2222-222222222222';
  c uuid := 'b3333333-3333-3333-3333-333333333333';
  c2 uuid := 'b4444444-4444-4444-4444-444444444444';
  a uuid := 'b5555555-5555-5555-5555-555555555555';
  addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}';
  v_company uuid; v_id uuid; v_id2 uuid; r1 uuid; r2 uuid; r3 uuid; n int; ok boolean; v_text text;
  summary text := 'A empresa informa que revisou a escala da equipe e vai limitar mensagens fora do horário.';
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'rrw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Trabalhadora Resposta', 'cpf', '39053344705', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', w2, 'authenticated', 'authenticated', 'rrw2@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Outro Trabalhador', 'cpf', '11144477735', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', c, 'authenticated', 'authenticated', 'rrc@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Empresa Resposta Ltda', 'cnpj', '11222333000181', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', c2, 'authenticated', 'authenticated', 'rrc2@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Outra Empresa Ltda', 'cnpj', '45723174000110', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', a, 'authenticated', 'authenticated', 'rra@teste.invalid', '{}', now(), now());
  insert into private.platform_admins (user_id) values (a);
  select company_id into v_company from public.company_users where user_id = c;
  res := res || jsonb_build_object('nova resposta nasce em revisão (default)',
    (select column_default like '%in_review%' from information_schema.columns where table_schema = 'public' and table_name = 'company_responses' and column_name = 'review_status'));

  -- Manifestação liberada à empresa (fluxo da ADR-0010).
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  v_id := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Carga de trabalho', 'title', 'Mensagens fora do horário', 'original_content', 'Relato original fictício.', 'shared_content', 'Versão compartilhável fictícia.'), true);
  v_id2 := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Carga de trabalho', 'title', 'Segundo caso', 'original_content', 'Relato original fictício dois.', 'shared_content', 'Versão compartilhável fictícia dois.'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.ops_decide_complaint(v_id, 'released', null);
  perform public.ops_decide_complaint(v_id2, 'released', null);

  -- 1) Empresa responde: fica em revisão e o trabalhador não lê.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.respond_complaint(v_id, 'Primeira resposta institucional, inadequada.');
  perform public.respond_complaint(v_id2, 'Resposta ao segundo caso, ainda em revisão.');
  res := res || jsonb_build_object('caso em revisão de resposta continua na lista da empresa',
    exists (select 1 from public.list_company_complaints() where id = v_id and status = 'answer_in_review'));
  begin
    perform public.respond_complaint(v_id, 'Segunda resposta enquanto a primeira está em revisão.');
    res := res || jsonb_build_object('segunda resposta com uma em revisão recusada', false);
  exception when others then res := res || jsonb_build_object('segunda resposta com uma em revisão recusada', sqlerrm = 'Já existe uma resposta em revisão pela equipe.'); end;

  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('trabalhador não lê resposta em revisão', (select count(*) from public.company_responses where complaint_id = v_id) = 0);
  res := res || jsonb_build_object('trabalhador vê o evento de resposta em revisão',
    exists (select 1 from public.complaint_events where complaint_id = v_id and status = 'answer_in_review'));

  -- 2) Equipe: devolução exige motivo; volta a 'shared'; o trabalhador não vê a devolução.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select response_id into r1 from public.ops_list_responses('in_review') where complaint_id = v_id;
  begin
    perform public.ops_decide_response(r1, 'returned', null, 'curto');
    res := res || jsonb_build_object('devolução exige motivo', false);
  exception when others then res := res || jsonb_build_object('devolução exige motivo', true); end;
  perform public.ops_decide_response(r1, 'returned', null, 'A resposta cita a área do trabalhador; retire a referência.');
  res := res || jsonb_build_object('devolução volta o caso a shared', exists (select 1 from public.ops_list_complaints('shared') where id = v_id));
  begin
    perform public.ops_decide_response(r1, 'released', summary, null);
    res := res || jsonb_build_object('decisão repetida recusada', false);
  exception when others then res := res || jsonb_build_object('decisão repetida recusada', true); end;

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('empresa lê o motivo da devolução',
    exists (select 1 from public.get_company_complaint_timeline(v_id) where kind = 'response_review' and content like 'Resposta devolvida para ajuste: A resposta cita%'));
  begin
    perform public.ops_decide_response(r1, 'released', summary, null);
    res := res || jsonb_build_object('empresa não decide pela equipe', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('empresa não decide pela equipe', true); end;

  -- 3) Nova resposta; liberação exige descrição; o trabalhador lê resposta e descrição.
  perform public.respond_complaint(v_id, 'Resposta institucional revisada pela empresa.');
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select response_id into r2 from public.ops_list_responses('in_review') where complaint_id = v_id;
  begin
    perform public.ops_decide_response(r2, 'released', 'curta demais', null);
    res := res || jsonb_build_object('liberação exige descrição de 30 caracteres', false);
  exception when others then res := res || jsonb_build_object('liberação exige descrição de 30 caracteres', true); end;
  perform public.ops_decide_response(r2, 'released', summary, null);
  res := res || jsonb_build_object('liberação muda o caso para answered', exists (select 1 from public.ops_list_complaints('answered') where id = v_id));

  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  select count(*), bool_and(content = 'Resposta institucional revisada pela empresa.' and worker_summary = summary) into n, ok
  from public.company_responses where complaint_id = v_id;
  res := res || jsonb_build_object('trabalhador lê só a liberada, com a descrição (3B)', n = 1 and ok);
  res := res || jsonb_build_object('devolução não aparece para o trabalhador',
    not exists (select 1 from public.complaint_events where complaint_id = v_id and note ilike '%devolvid%'));

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('empresa vê a liberação, mas não a descrição',
    exists (select 1 from public.get_company_complaint_timeline(v_id) where kind = 'response_review' and content = 'Resposta liberada ao trabalhador.')
    and not exists (select 1 from public.get_company_complaint_timeline(v_id) where content like '%limitar mensagens%'));
  perform set_config('request.jwt.claims', json_build_object('sub', c2, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('outra empresa não vê nada', (select count(*) from public.get_company_complaint_timeline(v_id)) = 0);

  -- 4) Avaliação: só o dono, só liberada, uma vez; a empresa vê só agregado com 3 ou mais.
  perform set_config('request.jwt.claims', json_build_object('sub', w2, 'role', 'authenticated')::text, true);
  begin
    perform public.rate_response(r2, 'yes');
    res := res || jsonb_build_object('outro trabalhador não avalia', false);
  exception when others then res := res || jsonb_build_object('outro trabalhador não avalia', true); end;
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  begin
    perform public.rate_response(r1, 'yes');
    res := res || jsonb_build_object('resposta devolvida não é avaliada', false);
  exception when others then res := res || jsonb_build_object('resposta devolvida não é avaliada', true); end;
  perform public.rate_response(r2, 'partial', 'Ajudou em parte.');
  begin
    perform public.rate_response(r2, 'yes');
    res := res || jsonb_build_object('avaliação só uma vez', false);
  exception when others then res := res || jsonb_build_object('avaliação só uma vez', sqlerrm = 'Você já avaliou esta resposta.'); end;
  res := res || jsonb_build_object('trabalhador vê a própria avaliação', (select count(*) from public.my_response_ratings(v_id)) = 1);

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('empresa: contagem e faixa nulas abaixo de 3 avaliações',
    exists (select 1 from public.my_company_satisfaction() where company_id = v_company and ratings is null and satisfaction_band is null));
  begin
    perform count(*) from public.response_ratings;
    res := res || jsonb_build_object('tabela de avaliações fechada', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('tabela de avaliações fechada', true); end;
  begin
    perform count(*) from public.company_response_reviews;
    res := res || jsonb_build_object('trilha de revisão fechada', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('trilha de revisão fechada', true); end;
  res := res || jsonb_build_object('satisfação fora da lista pública no piloto',
    not exists (select 1 from public.company_responsiveness() where satisfaction_band is not null));

  -- 5) Correção da descrição com motivo; o trabalhador vê a nova e a data.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin
    perform public.ops_correct_response_summary(r2, summary || ' Corrigida.', 'curto');
    res := res || jsonb_build_object('correção exige motivo', false);
  exception when others then res := res || jsonb_build_object('correção exige motivo', true); end;
  perform public.ops_correct_response_summary(r2, summary || ' Corrigida.', 'Ajuste de clareza no texto ao trabalhador.');
  res := res || jsonb_build_object('linha da equipe com devolução, liberação e correção',
    (select count(*) from public.ops_complaint_timeline(v_id) where kind = 'response_review') = 3);
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('trabalhador vê a descrição corrigida e a data',
    exists (select 1 from public.company_responses where id = r2 and worker_summary like '%Corrigida.' and summary_corrected_at is not null));

  -- 6) Prazo e taxa: só resposta liberada conta (o segundo caso está em revisão).
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('métricas da equipe com a fila de respostas', (public.ops_metrics() ->> 'responses_in_review')::int >= 1);
  execute 'reset role';
  res := res || jsonb_build_object('estatística: 2 liberadas, 1 respondida (em revisão não conta)',
    coalesce((select released = 2 and answered = 1 from private.company_response_stats() where company_id = v_company), false));

  raise exception 'RESULTADOS %', res;
end $$;
