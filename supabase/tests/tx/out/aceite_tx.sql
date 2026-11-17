-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar aceite_checks.sql e as migrations.
-- Migrations: 20261117140000_aceite_termos_privacidade.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'e5555555-5555-5555-5555-555555555555'; u_c uuid := 'e6666666-6666-6666-6666-666666666666'; u_op uuid := 'e7777777-7777-7777-7777-777777777777'; n int; r record;
begin
  begin  -- trava: nada pode commitar daqui para dentro

    -- 20261117140000_aceite_termos_privacidade.sql (18 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117140000') then
      res := res || jsonb_build_object('20261117140000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0022: registro do aceite dos termos de uso e do aviso de privacidade, com versão e re-aceite.
-- Só aditiva. O gate (private.assert_legal_current nas funções de ação) fica DESLIGADO: a função existe, mas nenhuma
-- função a chama. Ela será ligada por migration própria depois que o texto do advogado (versão 1, prazo 24/11) for
-- publicado e o front tiver a tela de aceite.
-- Sem versão publicada, my_legal_status() não devolve linha e ninguém fica com aceite pendente.
-- Retenção após exclusão da conta: pendente com o advogado; por ora on delete set null (ADR-0022, proposta inicial).
--
-- Rollback (sem dependentes): exportar public.legal_acceptances e private.legal_documents; depois
--   drop function public.my_legal_status(), public.record_legal_acceptance(text, text),
--     public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats(), private.assert_legal_current();
--   drop table public.legal_acceptances; drop table private.legal_documents; drop function private.legal_acceptance_guard();

-- 1) Versões publicadas (só a equipe publica).
create table private.legal_documents (
  document text not null check (document in ('terms', 'privacy')),
  version text not null check (version ~ '^[0-9A-Za-z._-]{1,40}$'),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  is_current boolean not null default false,
  published_at timestamptz not null default now(),
  published_by uuid not null,
  primary key (document, version)
)$s0$;
      execute $s0$create unique index legal_documents_one_current on private.legal_documents (document) where is_current$s0$;
      execute $s0$revoke all on private.legal_documents from public, anon, authenticated$s0$;
      execute $s0$-- 2) Aceites: só inserção pelo próprio usuário via função; a única alteração aceita é o set null da exclusão da conta.
create table public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  document text not null,
  version text not null,
  accepted_at timestamptz not null default now(),
  foreign key (document, version) references private.legal_documents (document, version) on delete restrict,
  unique (user_id, document, version)
)$s0$;
      execute $s0$create index legal_acceptances_doc_idx on public.legal_acceptances (document, version)$s0$;
      execute $s0$alter table public.legal_acceptances enable row level security$s0$;
      execute $s0$revoke all on public.legal_acceptances from public, anon, authenticated$s0$;
      execute $s0$create function private.legal_acceptance_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.user_id is not null and new.user_id is null
     and new.id = old.id and new.document = old.document and new.version = old.version and new.accepted_at = old.accepted_at then
    return new;  -- exclusão da conta (on delete set null)
  end if;
  raise exception 'Registro de aceite não pode ser alterado nem apagado.' using errcode = 'P0001';
end;
$$$s0$;
      execute $s0$revoke all on function private.legal_acceptance_guard() from public, anon, authenticated$s0$;
      execute $s0$create trigger legal_acceptances_immutable before update or delete on public.legal_acceptances
  for each row execute function private.legal_acceptance_guard()$s0$;
      execute $s0$-- 3) Situação do próprio usuário: uma linha por documento com versão vigente.
create function public.my_legal_status()
returns table (document text, current_version text, accepted_version text, needs_acceptance boolean)
language sql stable security definer set search_path = '' as $$
  select d.document, d.version,
         (select a.version from public.legal_acceptances a
          where a.user_id = auth.uid() and a.document = d.document order by a.accepted_at desc limit 1),
         not exists (select 1 from public.legal_acceptances a
                     where a.user_id = auth.uid() and a.document = d.document and a.version = d.version)
  from private.legal_documents d
  where d.is_current and auth.uid() is not null
  order by d.document;
$$$s0$;
      execute $s0$-- 4) Aceite: só da versão vigente; repetido não duplica. Mesma mensagem para documento ou versão inválidos.
create function public.record_legal_acceptance(p_document text, p_version text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not exists (select 1 from private.legal_documents where document = p_document and version = p_version and is_current) then
    raise exception 'Versão do documento indisponível para aceite.' using errcode = 'P0001';
  end if;
  insert into public.legal_acceptances (user_id, document, version) values (auth.uid(), p_document, p_version)
  on conflict (user_id, document, version) do nothing;
end;
$$$s0$;
      execute $s0$-- 5) Publicação de versão nova pela equipe: vira a vigente e todos voltam a ter aceite pendente.
create function public.ops_publish_legal_version(p_document text, p_version text, p_content_hash text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_document not in ('terms', 'privacy') then raise exception 'Documento inválido.' using errcode = 'P0001'; end if;
  if p_version !~ '^[0-9A-Za-z._-]{1,40}$' then raise exception 'Versão inválida.' using errcode = 'P0001'; end if;
  if lower(p_content_hash) !~ '^[0-9a-f]{64}$' then raise exception 'Hash inválido (sha256 em hexadecimal).' using errcode = 'P0001'; end if;
  if exists (select 1 from private.legal_documents where document = p_document and version = p_version) then
    raise exception 'Versão já publicada.' using errcode = 'P0001';
  end if;
  update private.legal_documents set is_current = false where document = p_document and is_current;
  insert into private.legal_documents (document, version, content_hash, is_current, published_by)
  values (p_document, p_version, lower(p_content_hash), true, auth.uid());
end;
$$$s0$;
      execute $s0$-- 6) Contagens para a equipe, sem lista de pessoas.
create function public.ops_legal_acceptance_stats()
returns table (document text, version text, published_at timestamptz, accepted_count integer, pending_count integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select d.document, d.version, d.published_at,
         (select count(*)::int from public.legal_acceptances a where a.document = d.document and a.version = d.version and a.user_id is not null),
         (select count(*)::int from auth.users u
          where not exists (select 1 from public.legal_acceptances a where a.user_id = u.id and a.document = d.document and a.version = d.version))
  from private.legal_documents d where d.is_current order by d.document;
end;
$$$s0$;
      execute $s0$-- 7) Gate, ainda não usado por nenhuma função.
create function private.assert_legal_current()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (select 1 from private.legal_documents d
             where d.is_current and not exists (select 1 from public.legal_acceptances a
                                                where a.user_id = auth.uid() and a.document = d.document and a.version = d.version)) then
    raise exception 'Aceite a versão atual dos termos e do aviso de privacidade para continuar.' using errcode = 'P0001';
  end if;
end;
$$$s0$;
      execute $s0$revoke all on function private.assert_legal_current() from public, anon, authenticated$s0$;
      execute $s0$revoke execute on function public.my_legal_status(), public.record_legal_acceptance(text, text),
  public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats() from public, anon$s0$;
      execute $s0$grant execute on function public.my_legal_status(), public.record_legal_acceptance(text, text),
  public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats() to authenticated$s0$;
      res := res || jsonb_build_object('20261117140000', 'aplicada na transação de teste');
    end if;

    -- Verificações (aceite_checks.sql)
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
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
