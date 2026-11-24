-- Conferência do lote 3, passo 01 (20261123120000, título sem conteúdo para a empresa). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261123120000')),
  (2, 'lista da empresa devolve só "Manifestação " + protocolo como título',
      (select prosrc like '%''Manifestação '' || c.protocol%' and prosrc not like '%c.title%'
       from pg_proc where oid = to_regprocedure('public.list_company_complaints()'))),
  (3, 'lista da empresa continua só para vínculo verificado',
      (select prosrc like '%is_verified_company_user%' from pg_proc where oid = to_regprocedure('public.list_company_complaints()'))),
  (4, 'anon não executa a lista da empresa',
      not coalesce(has_function_privilege('anon', to_regprocedure('public.list_company_complaints()'), 'execute'), true))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
