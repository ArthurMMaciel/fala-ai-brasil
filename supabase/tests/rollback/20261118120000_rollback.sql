-- Rollback do lote 2, passo 02 (20261118120000, estrutura da empresa pré-cadastrada). SQL Editor de produção, arquivo
-- INTEIRO, uma vez. Exige antes: rollback das 20261118140000 e 20261118130000.
-- Recusa se houver empresa fora de registered: ela tem relatos ligados e não tem endereço, e address_id não pode voltar
-- a ser obrigatório. Nesse caso, a decisão (apagar relatos, completar cadastro) é do responsável, fora deste script.
-- Contatos indicados, trilha de avisos, opt-outs e o cache são apagados: exporte antes, se tiverem linhas
-- (select * de public.complaint_contacts, public.company_notices, private.notice_opt_outs, private.cnpj_cache ->
-- Download CSV), e troque false por true em v_exportei. A versão sai de schema_migrations.
-- Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
declare v_exportei boolean := false;
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118120000') then
    raise exception 'A 20261118120000 não está registrada. Nada foi feito.';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version in ('20261118130000', '20261118140000')) then
    raise exception 'Desfaça antes as 20261118140000 e 20261118130000. Nada foi feito.';
  end if;
  if exists (select 1 from public.companies where registration_status <> 'registered') then
    raise exception 'Há empresa pré-cadastrada com relatos ligados. Decisão do responsável antes do rollback. Nada foi feito.';
  end if;
  if not v_exportei and (exists (select 1 from public.complaint_contacts) or exists (select 1 from public.company_notices)
                         or exists (select 1 from private.notice_opt_outs) or exists (select 1 from private.cnpj_cache)) then
    raise exception 'Há contatos, avisos, opt-outs ou cache gravados. Exporte e marque v_exportei = true. Nada foi feito.';
  end if;
end $trava$;

-- A trilha de avisos é imutável: o gatilho sai antes do drop da tabela.
drop trigger company_notices_guard on public.company_notices;
drop function public.cnpj_cache_get(text), public.cnpj_cache_put(text, boolean, text, text, text, text, text, text, text, text, text),
  public.cnpj_quota_take(uuid), private.take_quota(uuid, text, integer);
drop table public.company_notices;
drop table public.complaint_contacts;
drop table private.notice_opt_outs, private.company_preregistrations, private.cnpj_lookup_quota, private.cnpj_cache;
drop function private.company_notice_guard();
alter table public.companies drop constraint companies_address_when_registered, drop column data_source,
  drop column registration_status, alter column address_id set not null;
delete from supabase_migrations.schema_migrations where version = '20261118120000';

commit;
-- Conferir: select to_regclass('public.complaint_contacts') is null as ok_tabela,
--   not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'companies'
--               and column_name = 'registration_status') as ok_coluna;
