-- Teste de fumaça das campanhas de patrocinador (TASK-0022). Executa tudo e desfaz: o resultado vem na mensagem RESULTADOS.
-- Rodar: npx supabase db query --linked < supabase/tests/campaigns_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  sp uuid := '44444444-4444-4444-4444-444444444444';
  other uuid := '55555555-5555-5555-5555-555555555555';
  c1 uuid;
  ok boolean;
  msg text;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', sp, 'authenticated', 'authenticated', 'sp@teste.invalid',
   '{"signup_type":"sponsor","signup":{"name":"Patrocínio Teste","cnpj":"11444777000161","plan_id":"sponsor-event","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', other, 'authenticated', 'authenticated', 'o@teste.invalid',
   '{"signup_type":"sponsor","signup":{"name":"Outro Patrocínio","cnpj":"11444777000161","plan_id":"sponsor-content","subscription_mode":"monthly","address":{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"2","city":"São Paulo","state":"SP"}}}', now(), now());

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', sp, 'role', 'authenticated')::text, true);

  begin
    perform public.create_campaign(jsonb_build_object('kind', 'content', 'title', 'Conteúdo', 'description', 'Tipo diferente do plano', 'starts_at', current_date, 'ends_at', current_date + 7));
    res := res || jsonb_build_object('tipo fora do plano recusado', false);
  exception when others then res := res || jsonb_build_object('tipo fora do plano recusado', true); end;

  c1 := public.create_campaign(jsonb_build_object('title', 'Semana do cuidado', 'description', 'Evento aberto sobre saúde no trabalho.', 'starts_at', current_date, 'ends_at', current_date + 7), false);
  ok := (select kind = 'event' and status = 'draft' from public.campaigns where id = c1);
  res := res || jsonb_build_object('rascunho criado com tipo do plano', ok);

  begin
    perform public.create_campaign(jsonb_build_object('title', 'Segunda', 'description', 'Não deveria ser criada agora.', 'starts_at', current_date, 'ends_at', current_date + 3), true);
    res := res || jsonb_build_object('uma campanha ativa por vez', false);
  exception when others then res := res || jsonb_build_object('uma campanha ativa por vez', true); end;

  perform public.submit_campaign(c1);
  ok := (select status = 'submitted' and submitted_at is not null from public.campaigns where id = c1);
  res := res || jsonb_build_object('rascunho enviado para revisão', ok);

  begin
    update public.campaigns set status = 'approved' where id = c1;
    res := res || jsonb_build_object('patrocinador não aprova a própria campanha', false);
  exception when insufficient_privilege then res := res || jsonb_build_object('patrocinador não aprova a própria campanha', true); end;

  delete from public.campaigns where id = c1;
  ok := exists (select 1 from public.campaigns where id = c1);
  res := res || jsonb_build_object('enviada não pode ser excluída', ok);

  perform set_config('request.jwt.claims', json_build_object('sub', other, 'role', 'authenticated')::text, true);
  ok := (select count(*) from public.campaigns) = 0;
  res := res || jsonb_build_object('outro patrocinador não vê campanhas alheias', ok);
  begin
    perform public.create_campaign(jsonb_build_object('title', 'Pendente', 'description', 'Assinatura ainda pendente.', 'starts_at', current_date, 'ends_at', current_date + 3), true);
    res := res || jsonb_build_object('assinatura pendente bloqueia criação', false);
  exception when others then
    get stacked diagnostics msg = message_text;
    res := res || jsonb_build_object('assinatura pendente bloqueia criação', msg like 'Sua assinatura%');
  end;

  execute 'reset role';
  raise exception 'RESULTADOS %', res;
end $$;
