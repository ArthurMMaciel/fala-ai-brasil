-- Conferência do passo 03 (20261117140000). Só leitura. Deu certo se TODAS as linhas tiverem ok = true.
-- Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261117140000')),
  (2, 'tabelas criadas (legal_documents, legal_acceptances com RLS)',
      to_regclass('private.legal_documents') is not null
      and (select relrowsecurity from pg_class where oid = to_regclass('public.legal_acceptances'))),
  (3, 'aceites imutáveis (gatilho)',
      exists (select 1 from pg_trigger where tgname = 'legal_acceptances_immutable' and not tgisinternal)),
  (4, 'cinco funções existem',
      to_regprocedure('public.my_legal_status()') is not null
      and to_regprocedure('public.record_legal_acceptance(text,text)') is not null
      and to_regprocedure('public.ops_publish_legal_version(text,text,text)') is not null
      and to_regprocedure('public.ops_legal_acceptance_stats()') is not null
      and to_regprocedure('private.assert_legal_current()') is not null),
  (5, 'nenhuma versão publicada ainda (ninguém fica com aceite pendente)',
      (select count(*) = 0 from private.legal_documents)),
  (6, 'gate desligado: nenhuma função chama assert_legal_current',
      not exists (select 1 from pg_proc where prosrc ilike '%assert_legal_current%' and proname <> 'assert_legal_current')),
  (7, 'anon não executa my_legal_status',
      not coalesce(has_function_privilege('anon', to_regprocedure('public.my_legal_status()'), 'execute'), true))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
