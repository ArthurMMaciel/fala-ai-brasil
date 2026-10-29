-- Teste de fumaça de conteúdos do parceiro e contato da empresa (migration 20261029050000). Executa tudo e desfaz.
-- Rodar: npx supabase db query --linked < supabase/tests/content_contact_smoke.sql
do $$
declare
  res jsonb := '[]'::jsonb;
  w uuid := '71111111-1111-1111-1111-111111111111';
  c uuid := '72222222-2222-2222-2222-222222222222';
  c2 uuid := '73333333-3333-3333-3333-333333333333';
  p uuid := '74444444-4444-4444-4444-444444444444';
  v_company uuid; v_company2 uuid; v_partner uuid; ok boolean;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', w, 'authenticated', 'authenticated', 'w5@teste.invalid', '{"signup_type":"worker","signup":{"full_name":"W","cpf":"52998224725","address":{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', c, 'authenticated', 'authenticated', 'c5@teste.invalid', '{"signup_type":"company","signup":{"legal_name":"Empresa Smoke Ltda","cnpj":"45723174000110","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"A","number":"1","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', c2, 'authenticated', 'authenticated', 'c6@teste.invalid', '{"signup_type":"company","signup":{"legal_name":"Outra Smoke Ltda","cnpj":"04252011000110","plan_id":"company-essential","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"B","number":"2","city":"São Paulo","state":"SP"}}}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', p, 'authenticated', 'authenticated', 'p5@teste.invalid', '{"signup_type":"partner","signup":{"display_name":"P","document_type":"cpf","document":"52998224725","specialty":"X","plan_id":"partner-presence","subscription_mode":"trial","address":{"zip_code":"01310100","street_type":"street","street_name":"C","number":"3","city":"São Paulo","state":"SP"}}}', now(), now());
  select cu.company_id into v_company from public.company_users cu where cu.user_id = c;
  select cu.company_id into v_company2 from public.company_users cu where cu.user_id = c2;
  select pa.id into v_partner from public.partners pa where pa.user_id = p;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  begin
    insert into public.media (partner_id, kind, external_url, title, published_at) values (v_partner, 'video', 'https://vimeo.com/1', 'Palestra', now());
    res := res || jsonb_build_object('plano Presença não publica conteúdo', false);
  exception when others then res := res || jsonb_build_object('plano Presença não publica conteúdo', true); end;

  execute 'reset role';
  update public.subscriptions set plan_id = 'partner-national' where partner_id = v_partner;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  insert into public.media (partner_id, kind, external_url, title, caption, published_at) values (v_partner, 'video', 'https://vimeo.com/1', 'Palestra', 'Sobre pausas', now());
  res := res || jsonb_build_object('plano Nacional publica conteúdo', (select count(*) from public.media where partner_id = v_partner and title is not null) = 1);

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('empresa vê conteúdos do parceiro', (select count(*) from public.list_partner_contents(v_partner)) = 1);
  res := res || jsonb_build_object('empresa não lê media diretamente', (select count(*) from public.media) = 0);
  update public.companies set contact_email = 'contato@smoke.invalid', contact_phone = '41999990000' where id = v_company;
  perform public.company_request_partner(v_partner);
  perform set_config('request.jwt.claims', json_build_object('sub', c2, 'role', 'authenticated')::text, true);
  update public.companies set contact_email = 'outra@smoke.invalid' where id = v_company2;

  perform set_config('request.jwt.claims', json_build_object('sub', w, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('trabalhador não vê conteúdos', (select count(*) from public.list_partner_contents(v_partner)) = 0);

  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  res := res || jsonb_build_object('parceiro vê contato de quem demonstrou interesse', exists (select 1 from public.list_partner_companies() where id = v_company and contact_email = 'contato@smoke.invalid'));
  res := res || jsonb_build_object('parceiro não vê contato sem vínculo', exists (select 1 from public.list_partner_companies() where id = v_company2 and contact_email is null));
  begin
    update public.companies set contact_email = 'invasao@smoke.invalid' where id = v_company;
    res := res || jsonb_build_object('parceiro não altera contato da empresa', not exists (select 1 from public.companies where contact_email = 'invasao@smoke.invalid'));
  exception when others then res := res || jsonb_build_object('parceiro não altera contato da empresa', true); end;

  execute 'reset role';
  raise exception 'RESULTADOS %', res;
end $$;
