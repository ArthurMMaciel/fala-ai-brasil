-- Teste de fumaça do desempate das linhas do tempo (migration 20261109120000). Executa tudo e desfaz.
-- Rodar: npx supabase db query --local < supabase/tests/timeline_order_smoke.sql
-- Cada passo grava itens na mesma transação (mesmo created_at). Entre passos, o teste recua 1 minuto o que já existe,
-- simulando transações separadas; dentro de cada passo vale o desempate.
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := '91111111-1111-1111-1111-111111111111';
  c uuid := '92222222-2222-2222-2222-222222222222';
  a uuid := '93333333-3333-3333-3333-333333333333';
  v_company uuid; v_id uuid; v_seq text; v_n int;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'w9@teste.invalid', '{"signup_type":"worker","signup":{"full_name":"W","cpf":"11144477735","phone":"41987654321","address":{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', c, 'authenticated', 'authenticated', 'c9@teste.invalid', '{"signup_type":"company","signup":{"legal_name":"Empresa Linha do Tempo Ltda","cnpj":"11222333000181","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"A","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', a, 'authenticated', 'authenticated', 'a9@teste.invalid', '{}', now(), now());
  insert into private.platform_admins (user_id) values (a);
  select cu.company_id into v_company from public.company_users cu where cu.user_id = c;

  -- Passo 1 (trabalhador): eventos received e in_review na mesma transação.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  v_id := public.create_complaint(jsonb_build_object('company_id', v_company, 'category', 'Carga de trabalho', 'title', 'Ordem da linha do tempo', 'original_content', 'Relato original fictício.', 'shared_content', 'Versão compartilhável fictícia.'), true);
  execute 'reset role';
  update public.complaint_events set created_at = created_at - interval '1 minute' where complaint_id = v_id;

  -- Passo 2 (equipe): decisão e evento adjustment_requested na mesma transação.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.ops_decide_complaint(v_id, 'adjustment_requested', 'Retire o detalhe que identifica a equipe.');
  execute 'reset role';
  update public.complaint_events set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.complaint_reviews set created_at = created_at - interval '1 minute' where complaint_id = v_id;

  -- Passo 3 (trabalhador): reenvio.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  perform public.share_complaint(v_id, 'Versão compartilhável fictícia, ajustada.');
  execute 'reset role';
  update public.complaint_events set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.complaint_reviews set created_at = created_at - interval '1 minute' where complaint_id = v_id;

  -- Passo 4 (equipe): consulta ao original, numa transação; liberação, na seguinte.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.ops_read_original(v_id, 'Conferir o risco antes de liberar.');
  execute 'reset role';
  update public.complaint_events set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.complaint_reviews set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.original_access_log set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.ops_decide_complaint(v_id, 'released', null);
  execute 'reset role';
  update public.complaint_events set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.complaint_reviews set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.original_access_log set created_at = created_at - interval '1 minute' where complaint_id = v_id;

  -- Passo 5 (empresa): resposta e evento answered na mesma transação.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.respond_complaint(v_id, 'Resposta institucional fictícia.');
  execute 'reset role';
  update public.complaint_events set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.complaint_reviews set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.original_access_log set created_at = created_at - interval '1 minute' where complaint_id = v_id;
  update public.company_responses set created_at = created_at - interval '1 minute' where complaint_id = v_id;

  -- Passo 6 (trabalhador): encerramento.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  perform public.close_complaint(v_id, 'yes');

  -- Equipe: sequência completa.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select string_agg(t.kind || coalesce(':' || t.status::text, ''), ',' order by t.ord) into v_seq
  from public.ops_complaint_timeline(v_id) with ordinality as t(kind, status, actor, content, created_at, ord);
  res := res || jsonb_build_object('equipe: ordem completa',
    v_seq = 'event:received,event:in_review,review,event:adjustment_requested,event:in_review,access,review,event:shared,response,event:answered,event:closed');
  if v_seq is distinct from 'event:received,event:in_review,review,event:adjustment_requested,event:in_review,access,review,event:shared,response,event:answered,event:closed' then
    res := res || jsonb_build_object('equipe: sequência obtida', v_seq);
  end if;

  -- Empresa: só o que vem depois da liberação, na mesma regra.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select string_agg(t.kind || coalesce(':' || t.status::text, ''), ',' order by t.ord) into v_seq
  from public.get_company_complaint_timeline(v_id) with ordinality as t(kind, status, actor, content, created_at, ord);
  res := res || jsonb_build_object('empresa: ordem e recorte', v_seq = 'event:shared,response,event:answered,event:closed');
  if v_seq is distinct from 'event:shared,response,event:answered,event:closed' then
    res := res || jsonb_build_object('empresa: sequência obtida', v_seq);
  end if;

  -- Tudo na mesma transação (sem recuo): a ordem continua determinística e a causa vem antes do evento.
  execute 'reset role';
  update public.complaint_events set created_at = now() where complaint_id = v_id;
  update public.complaint_reviews set created_at = now() where complaint_id = v_id;
  update public.original_access_log set created_at = now() where complaint_id = v_id;
  update public.company_responses set created_at = now() where complaint_id = v_id;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select string_agg(t.kind || coalesce(':' || t.status::text, ''), ',' order by t.ord) into v_seq
  from public.ops_complaint_timeline(v_id) with ordinality as t(kind, status, actor, content, created_at, ord);
  res := res || jsonb_build_object('empate total: tipo e depois enum',
    v_seq = 'review,review,response,access,event:received,event:in_review,event:in_review,event:adjustment_requested,event:shared,event:answered,event:closed');

  -- Outra conta não lê a linha do tempo da equipe.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  begin
    perform public.ops_complaint_timeline(v_id);
    res := res || jsonb_build_object('empresa barrada na linha da equipe', false);
  exception when others then res := res || jsonb_build_object('empresa barrada na linha da equipe', true); end;

  execute 'reset role';
  select count(*) into v_n from jsonb_array_elements(res) e, jsonb_each(e) kv where kv.value is distinct from 'true'::jsonb;
  res := res || jsonb_build_object('falhas', v_n);
  raise exception 'RESULTADOS %', res;
end $$;
