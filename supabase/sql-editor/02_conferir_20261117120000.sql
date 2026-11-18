-- Conferência do passo 02 (20261117120000). Só leitura. Deu certo se TODAS as linhas tiverem ok = true.
-- Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261117120000')),
  (2, 'company_users tem verification_status e verified_at',
      (select count(*) = 2 from information_schema.columns
       where table_schema = 'public' and table_name = 'company_users' and column_name in ('verification_status', 'verified_at'))),
  (3, 'tabela representative_verifications com RLS',
      (select relrowsecurity from pg_class where oid = to_regclass('public.representative_verifications'))),
  (4, 'trilha imutável (gatilho)',
      exists (select 1 from pg_trigger where tgname = 'representative_verifications_immutable' and not tgisinternal)),
  (5, 'quatro funções novas existem',
      to_regprocedure('public.is_verified_company_user(uuid)') is not null
      and to_regprocedure('public.ops_list_representatives(text)') is not null
      and to_regprocedure('public.ops_verify_representative(uuid,uuid,text,text,text,text)') is not null
      and to_regprocedure('public.ops_representative_history(uuid)') is not null),
  (6, 'anon não executa as funções da equipe',
      not coalesce(has_function_privilege('anon', to_regprocedure('public.ops_verify_representative(uuid,uuid,text,text,text,text)'), 'execute'), true)
      and not coalesce(has_function_privilege('anon', to_regprocedure('public.ops_list_representatives(text)'), 'execute'), true)),
  (7, 'acesso das empresas às manifestações não mudou (gate 130000 ausente)',
      not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117130000')
      and (select prosrc not like '%is_verified_company_user%' from pg_proc where oid = to_regprocedure('public.list_company_complaints()')))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
-- Informativo (não entra no resultado): todos os vínculos existentes devem estar 'pending'.
-- select verification_status, count(*) from public.company_users group by 1;
