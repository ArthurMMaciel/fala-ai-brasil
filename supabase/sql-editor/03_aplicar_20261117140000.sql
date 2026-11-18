-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/migrations/20261117140000_aceite_termos_privacidade.sql. Não editar à mão.
-- Passo 03 de 04. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 03_conferir_20261117140000.sql (todas as linhas com ok = true).
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117140000') then
    raise exception 'A migration 20261117140000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117120000') then
    raise exception 'Falta a 20261117120000 (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261117140000_aceite_termos_privacidade.sql (18 instruções) ========
-- ADR-0022: registro do aceite dos termos de uso e do aviso de privacidade, com versão e re-aceite.
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
);
create unique index legal_documents_one_current on private.legal_documents (document) where is_current;
revoke all on private.legal_documents from public, anon, authenticated;

-- 2) Aceites: só inserção pelo próprio usuário via função; a única alteração aceita é o set null da exclusão da conta.
create table public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  document text not null,
  version text not null,
  accepted_at timestamptz not null default now(),
  foreign key (document, version) references private.legal_documents (document, version) on delete restrict,
  unique (user_id, document, version)
);
create index legal_acceptances_doc_idx on public.legal_acceptances (document, version);
alter table public.legal_acceptances enable row level security;
revoke all on public.legal_acceptances from public, anon, authenticated;

create function private.legal_acceptance_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.user_id is not null and new.user_id is null
     and new.id = old.id and new.document = old.document and new.version = old.version and new.accepted_at = old.accepted_at then
    return new;  -- exclusão da conta (on delete set null)
  end if;
  raise exception 'Registro de aceite não pode ser alterado nem apagado.' using errcode = 'P0001';
end;
$$;
revoke all on function private.legal_acceptance_guard() from public, anon, authenticated;
create trigger legal_acceptances_immutable before update or delete on public.legal_acceptances
  for each row execute function private.legal_acceptance_guard();

-- 3) Situação do próprio usuário: uma linha por documento com versão vigente.
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
$$;

-- 4) Aceite: só da versão vigente; repetido não duplica. Mesma mensagem para documento ou versão inválidos.
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
$$;

-- 5) Publicação de versão nova pela equipe: vira a vigente e todos voltam a ter aceite pendente.
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
$$;

-- 6) Contagens para a equipe, sem lista de pessoas.
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
$$;

-- 7) Gate, ainda não usado por nenhuma função.
create function private.assert_legal_current()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (select 1 from private.legal_documents d
             where d.is_current and not exists (select 1 from public.legal_acceptances a
                                                where a.user_id = auth.uid() and a.document = d.document and a.version = d.version)) then
    raise exception 'Aceite a versão atual dos termos e do aviso de privacidade para continuar.' using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function private.assert_legal_current() from public, anon, authenticated;

revoke execute on function public.my_legal_status(), public.record_legal_acceptance(text, text),
  public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats() from public, anon;
grant execute on function public.my_legal_status(), public.record_legal_acceptance(text, text),
  public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats() to authenticated;
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261117140000', 'aceite_termos_privacidade', array[
$s0$-- ADR-0022: registro do aceite dos termos de uso e do aviso de privacidade, com versão e re-aceite.
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
)$s0$,
$s0$create unique index legal_documents_one_current on private.legal_documents (document) where is_current$s0$,
$s0$revoke all on private.legal_documents from public, anon, authenticated$s0$,
$s0$-- 2) Aceites: só inserção pelo próprio usuário via função; a única alteração aceita é o set null da exclusão da conta.
create table public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  document text not null,
  version text not null,
  accepted_at timestamptz not null default now(),
  foreign key (document, version) references private.legal_documents (document, version) on delete restrict,
  unique (user_id, document, version)
)$s0$,
$s0$create index legal_acceptances_doc_idx on public.legal_acceptances (document, version)$s0$,
$s0$alter table public.legal_acceptances enable row level security$s0$,
$s0$revoke all on public.legal_acceptances from public, anon, authenticated$s0$,
$s0$create function private.legal_acceptance_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.user_id is not null and new.user_id is null
     and new.id = old.id and new.document = old.document and new.version = old.version and new.accepted_at = old.accepted_at then
    return new;  -- exclusão da conta (on delete set null)
  end if;
  raise exception 'Registro de aceite não pode ser alterado nem apagado.' using errcode = 'P0001';
end;
$$$s0$,
$s0$revoke all on function private.legal_acceptance_guard() from public, anon, authenticated$s0$,
$s0$create trigger legal_acceptances_immutable before update or delete on public.legal_acceptances
  for each row execute function private.legal_acceptance_guard()$s0$,
$s0$-- 3) Situação do próprio usuário: uma linha por documento com versão vigente.
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
$$$s0$,
$s0$-- 4) Aceite: só da versão vigente; repetido não duplica. Mesma mensagem para documento ou versão inválidos.
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
$$$s0$,
$s0$-- 5) Publicação de versão nova pela equipe: vira a vigente e todos voltam a ter aceite pendente.
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
$$$s0$,
$s0$-- 6) Contagens para a equipe, sem lista de pessoas.
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
$$$s0$,
$s0$-- 7) Gate, ainda não usado por nenhuma função.
create function private.assert_legal_current()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (select 1 from private.legal_documents d
             where d.is_current and not exists (select 1 from public.legal_acceptances a
                                                where a.user_id = auth.uid() and a.document = d.document and a.version = d.version)) then
    raise exception 'Aceite a versão atual dos termos e do aviso de privacidade para continuar.' using errcode = 'P0001';
  end if;
end;
$$$s0$,
$s0$revoke all on function private.assert_legal_current() from public, anon, authenticated$s0$,
$s0$revoke execute on function public.my_legal_status(), public.record_legal_acceptance(text, text),
  public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats() from public, anon$s0$,
$s0$grant execute on function public.my_legal_status(), public.record_legal_acceptance(text, text),
  public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats() to authenticated$s0$
]::text[]);

commit;
