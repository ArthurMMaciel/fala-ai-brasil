-- declare: u_w uuid := 'e5555555-5555-5555-5555-555555555555'; u_c uuid := 'e6666666-6666-6666-6666-666666666666'; u_op uuid := 'e7777777-7777-7777-7777-777777777777'; n int; r record;
-- Verificações da ADR-0022 (20261117140000) depois de aplicada na transação de teste. Imprime só contagens e nomes.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-aw@teste.invalid', '{}', now(), now()),
('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-ac@teste.invalid', '{}', now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-aop@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);

execute 'set local role authenticated';
-- Sem versão publicada: nada pendente; aceite recusado.
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
if (select count(*) from public.my_legal_status()) <> 0 then falhas := falhas || jsonb_build_object('pendência sem versão publicada', true); end if;
begin
  perform public.record_legal_acceptance('terms', 'tx-1');
  falhas := falhas || jsonb_build_object('aceite sem versão publicada', true);
exception when others then null; end;
begin
  perform public.ops_publish_legal_version('terms', 'tx-1', repeat('a', 64));
  falhas := falhas || jsonb_build_object('não equipe publica versão', true);
exception when others then null; end;

-- Equipe publica as duas.
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_publish_legal_version('terms', 'tx-1', repeat('a', 64));
perform public.ops_publish_legal_version('privacy', 'tx-1', repeat('b', 64));
begin
  perform public.ops_publish_legal_version('terms', 'tx-1', repeat('c', 64));
  falhas := falhas || jsonb_build_object('versão repetida publicada', true);
exception when others then null; end;

-- Usuário: pendente, aceita, repetição não duplica, versão errada recusada.
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
if (select count(*) from public.my_legal_status() where needs_acceptance) <> 2 then falhas := falhas || jsonb_build_object('não ficou pendente após publicar', true); end if;
perform public.record_legal_acceptance('terms', 'tx-1');
perform public.record_legal_acceptance('terms', 'tx-1');
perform public.record_legal_acceptance('privacy', 'tx-1');
if (select count(*) from public.my_legal_status() where needs_acceptance) <> 0 then falhas := falhas || jsonb_build_object('pendente após aceitar', true); end if;
begin
  perform public.record_legal_acceptance('terms', 'tx-0');
  falhas := falhas || jsonb_build_object('versão não vigente aceita', true);
exception when others then null; end;
begin
  perform public.record_legal_acceptance('outro', 'tx-1');
  falhas := falhas || jsonb_build_object('documento desconhecido aceito', true);
exception when others then null; end;
-- Leitura direta barrada; outro usuário não vê o aceite.
begin
  select count(*) into n from public.legal_acceptances;
  falhas := falhas || jsonb_build_object('leitura direta dos aceites', n);
exception when insufficient_privilege then null; end;
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
if (select count(*) from public.my_legal_status() where not needs_acceptance) <> 0 then falhas := falhas || jsonb_build_object('outro usuário herda aceite', true); end if;
begin
  perform public.ops_legal_acceptance_stats();
  falhas := falhas || jsonb_build_object('não equipe vê contagens', true);
exception when others then null; end;

-- Versão nova: re-aceite.
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_publish_legal_version('terms', 'tx-2', repeat('d', 64));
select * into r from public.ops_legal_acceptance_stats() where document = 'terms';
if r.version is distinct from 'tx-2' or r.accepted_count is distinct from 0 then falhas := falhas || jsonb_build_object('contagem após versão nova', true); end if;
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
select * into r from public.my_legal_status() where document = 'terms';
if r.needs_acceptance is distinct from true or r.accepted_version is distinct from 'tx-1' then falhas := falhas || jsonb_build_object('re-aceite não exigido após versão nova', true); end if;

-- Gate desligado: nenhuma função chama assert_legal_current.
execute 'reset role';
select count(*) into n from pg_proc p where p.prosrc ilike '%assert_legal_current%' and p.proname <> 'assert_legal_current';
if n <> 0 then falhas := falhas || jsonb_build_object('gate do aceite ligado em funções', n); end if;
-- Imutável, salvo o set null da exclusão da conta.
begin
  update public.legal_acceptances set version = 'tx-1' where user_id = u_w;
  falhas := falhas || jsonb_build_object('aceite alterável', true);
exception when others then null; end;
begin
  delete from public.legal_acceptances where user_id = u_w;
  falhas := falhas || jsonb_build_object('aceite apagável', true);
exception when others then null; end;
delete from auth.users where id = u_w;
if (select count(*) from public.legal_acceptances where user_id is null and document in ('terms', 'privacy') and version = 'tx-1') < 2 then
  falhas := falhas || jsonb_build_object('exclusão da conta não preservou o aceite', true);
end if;
-- Anon não executa.
execute 'set local role anon';
begin
  perform public.my_legal_status();
  falhas := falhas || jsonb_build_object('anon executa my_legal_status', true);
exception when insufficient_privilege then null; end;
res := res || jsonb_build_object('verificações do aceite', 'executadas');
