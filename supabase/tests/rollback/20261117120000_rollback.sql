-- Rollback R3 da 20261117120000 (estrutura do representante verificado, ADR-0012). SQL Editor de produção, arquivo
-- INTEIRO, uma vez. Exige antes: R1 (a pausa usa private.block_trail_change) e a 20261117130000 não aplicada
-- (se ela estiver aplicada, primeiro 20261117130000_rollback.sql, como migration nova).
-- Efeito: somem o estado de verificação dos vínculos e a trilha das decisões; a versão sai de schema_migrations.
-- Trilha: se houver decisões gravadas, exporte antes (select * from public.representative_verifications; e
-- select company_id, user_id, verification_status, verified_at from public.company_users; -> Download CSV) e troque
-- false por true em v_exportei. Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
declare v_exportei boolean := false;
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117120000') then
    raise exception 'A 20261117120000 não está registrada. Nada foi feito.';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117130000')
     or exists (select 1 from pg_proc where prosrc like '%is_verified_company_user%' and proname <> 'is_verified_company_user') then
    raise exception 'A troca do gate (20261117130000) está aplicada; desfaça-a antes. Nada foi feito.';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117150000')
     or exists (select 1 from pg_trigger where tgfoid = 'private.block_trail_change()'::regprocedure
                and tgname <> 'representative_verifications_immutable') then
    raise exception 'Outra tabela usa private.block_trail_change (rode o R1 da 150000 antes). Nada foi feito.';
  end if;
  if not v_exportei and (exists (select 1 from public.representative_verifications)
                         or exists (select 1 from public.company_users where verification_status <> 'pending')) then
    raise exception 'Há decisões de verificação gravadas. Exporte e marque v_exportei = true. Nada foi feito.';
  end if;
end $trava$;

drop function public.ops_verify_representative(uuid, uuid, text, text, text, text),
  public.ops_list_representatives(text), public.ops_representative_history(uuid), public.is_verified_company_user(uuid);
drop table public.representative_verifications;
drop function private.block_trail_change();
alter table public.company_users drop column verified_at, drop column verification_status;
delete from supabase_migrations.schema_migrations where version = '20261117120000';

commit;
-- Conferir: select to_regclass('public.representative_verifications') is null as ok_tabela,
--   not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'company_users'
--               and column_name = 'verification_status') as ok_coluna;
