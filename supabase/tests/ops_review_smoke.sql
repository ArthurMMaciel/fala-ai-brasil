-- Teste de fumaça da revisão humana (ADR-0010, migrations 20261106130000/130100). Executa tudo e desfaz.
-- Rodar: npx supabase db query --linked < supabase/tests/ops_review_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := '81111111-1111-1111-1111-111111111111';
  c uuid := '82222222-2222-2222-2222-222222222222';
  a uuid := '83333333-3333-3333-3333-333333333333';
  v_company uuid; v_id uuid; v_id2 uuid; v_id3 uuid; v_text text; n int;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'w8@teste.invalid', '{"signup_type":"worker","signup":{"full_name":"W","cpf":"52998224725","phone":"41987654321","address":{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', c, 'authenticated', 'authenticated', 'c8@teste.invalid', '{"signup_type":"company","signup":{"legal_name":"Empresa Revisão Ltda","cnpj":"12ABC34501DE35","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"A","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', a, 'authenticated', 'authenticated', 'a8@teste.invalid', '{}', now(), now());
  insert into private.platform_admins (user_id) values (a);
  select cu.company_id into v_company from public.company_users cu where cu.user_id = c;
  res := res || jsonb_build_object('cnpj alfanumérico aceito', (select cnpj = '12ABC34501DE35' from public.companies where id = v_company));
  res := res || jsonb_build_object('telefone do trabalhador gravado', (select phone = '41987654321' from public.workers where user_id = w));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  v_id := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Carga de trabalho', 'title', 'Demandas fora do horário', 'original_content', 'Meu gestor Fulano manda mensagens às 23h.', 'shared_content', 'O relato descreve mensagens frequentes fora do horário.'), true);
  res := res || jsonb_build_object('envio entra em revisão', (select status = 'in_review' from public.complaints where id = v_id));

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('empresa não vê em revisão', (select count(*) from public.list_company_complaints()) = 0);
  begin
    perform public.ops_list_complaints();
    res := res || jsonb_build_object('empresa barrada na fila', false);
  exception when others then res := res || jsonb_build_object('empresa barrada na fila', true); end;

  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from public.ops_list_complaints('in_review') where id = v_id;
  res := res || jsonb_build_object('equipe vê na fila', n = 1);
  begin
    perform public.ops_decide_complaint(v_id, 'adjustment_requested', 'curto');
    res := res || jsonb_build_object('ajuste exige motivo', false);
  exception when others then res := res || jsonb_build_object('ajuste exige motivo', true); end;
  perform public.ops_decide_complaint(v_id, 'adjustment_requested', 'A versão cita o nome do gestor; retire antes.');
  res := res || jsonb_build_object('ajuste muda status', exists (select 1 from public.ops_list_complaints('adjustment_requested') where id = v_id));

  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  perform public.share_complaint(v_id, 'O relato descreve mensagens frequentes fora do horário combinado.');
  res := res || jsonb_build_object('trabalhador reenvia ajuste', (select status = 'in_review' from public.complaints where id = v_id));

  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin
    perform public.ops_read_original(v_id, 'curto');
    res := res || jsonb_build_object('original exige justificativa', false);
  exception when others then res := res || jsonb_build_object('original exige justificativa', true); end;
  v_text := public.ops_read_original(v_id, 'Avaliar risco descrito no relato antes de liberar.');
  res := res || jsonb_build_object('acesso ao original registrado', v_text like '%Fulano%' and (select count(*) from public.ops_complaint_timeline(v_id) where kind = 'access') = 1);
  perform public.ops_decide_complaint(v_id, 'released', null);
  res := res || jsonb_build_object('liberação muda status', exists (select 1 from public.ops_list_complaints('shared') where id = v_id));
  res := res || jsonb_build_object('decisões auditadas', (select count(*) from public.ops_complaint_timeline(v_id) where kind = 'review') = 2);
  res := res || jsonb_build_object('métricas sem erro', (public.ops_metrics() ->> 'workers') is not null);
  -- 20261106140000: decisão repetida é recusada e a leitura do status trava a linha.
  begin
    perform public.ops_decide_complaint(v_id, 'released', null);
    res := res || jsonb_build_object('decisão repetida recusada', false);
  exception when others then res := res || jsonb_build_object('decisão repetida recusada', true); end;
  res := res || jsonb_build_object('decisão trava a linha', pg_get_functiondef('public.ops_decide_complaint(uuid, text, text)'::regprocedure) ilike '%for update%');
  res := res || jsonb_build_object('uma decisão de liberação', (select count(*) from public.ops_complaint_timeline(v_id) where kind = 'review' and content like 'Decisão: liberar%') = 1);

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('empresa vê após liberar', (select count(*) from public.list_company_complaints()) = 1);
  res := res || jsonb_build_object('empresa não vê eventos de revisão', not exists (select 1 from public.get_company_complaint_timeline(v_id) where status in ('in_review', 'adjustment_requested', 'held')));
  res := res || jsonb_build_object('empresa não lê o original', not exists (select 1 from public.list_company_complaints() where shared_content like '%Fulano%'));

  -- 20261106140000: ranking conta a primeira resposta a partir da liberação, não da criação.
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  v_id2 := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Carga de trabalho', 'title', 'Metas sem prazo', 'original_content', 'Relato fictício número dois para o ranking.', 'shared_content', 'Versão fictícia número dois para o ranking.'), true);
  v_id3 := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Carga de trabalho', 'title', 'Escala sem folga', 'original_content', 'Relato fictício número três para o ranking.', 'shared_content', 'Versão fictícia número três para o ranking.'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.ops_decide_complaint(v_id2, 'released', null);
  perform public.ops_decide_complaint(v_id3, 'released', null);
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.respond_complaint(v_id, 'Resposta institucional fictícia ao caso um.');
  perform public.respond_complaint(v_id2, 'Resposta institucional fictícia ao caso dois.');
  perform public.respond_complaint(v_id3, 'Resposta institucional fictícia ao caso três.');
  execute 'reset role';
  -- Criadas há 48 h, liberadas há 2 h, respondidas agora: o ranking deve mostrar 2 h, não 48 h.
  update public.complaints set created_at = now() - interval '48 hours' where id in (v_id, v_id2, v_id3);
  update public.complaint_events set created_at = now() - interval '2 hours' where complaint_id in (v_id, v_id2, v_id3) and status = 'shared';
  execute 'set local role authenticated';
  select avg_first_response_hours into n from public.company_ranking() where company_id = v_company;
  res := res || jsonb_build_object('ranking conta a partir da liberação', n = 2);

  execute 'reset role';
  raise exception 'RESULTADOS %', res;
end $$;
