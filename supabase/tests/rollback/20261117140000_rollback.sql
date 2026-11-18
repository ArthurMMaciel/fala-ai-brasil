-- Rollback R2 da 20261117140000 (aceite dos termos, ADR-0022). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Só vale enquanto o gate do aceite estiver desligado (nenhuma função chama assert_legal_current).
-- Efeito: somem versões publicadas e aceites gravados; a versão sai de schema_migrations.
-- Aceites são prova (LGPD art. 8º, § 2º): se houver linhas, exporte as duas tabelas antes
-- (select * from public.legal_acceptances; select * from private.legal_documents; -> Download CSV) e troque false por true
-- em v_exportei. Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
declare v_exportei boolean := false;
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117140000') then
    raise exception 'A 20261117140000 não está registrada. Nada foi feito.';
  end if;
  if exists (select 1 from pg_proc where prosrc ilike '%assert_legal_current%' and proname <> 'assert_legal_current') then
    raise exception 'O gate do aceite está ligado em alguma função; desligue por migration antes. Nada foi feito.';
  end if;
  if not v_exportei and (exists (select 1 from public.legal_acceptances) or exists (select 1 from private.legal_documents)) then
    raise exception 'Há versões ou aceites gravados. Exporte e marque v_exportei = true. Nada foi feito.';
  end if;
end $trava$;

drop function public.my_legal_status(), public.record_legal_acceptance(text, text),
  public.ops_publish_legal_version(text, text, text), public.ops_legal_acceptance_stats(), private.assert_legal_current();
drop table public.legal_acceptances;
drop table private.legal_documents;
drop function private.legal_acceptance_guard();
delete from supabase_migrations.schema_migrations where version = '20261117140000';

commit;
-- Conferir: select to_regclass('public.legal_acceptances') is null and to_regclass('private.legal_documents') is null as ok;
