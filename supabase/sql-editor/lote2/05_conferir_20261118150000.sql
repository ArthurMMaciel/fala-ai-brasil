-- Conferência do lote 2, passo 05 (20261118150000, aba Contratados). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261118150000')),
  (6, 'parceiro tem contato próprio, editável só por ele',
      (select count(*) = 2 from information_schema.columns where table_schema = 'public' and table_name = 'partners'
       and column_name in ('contact_email', 'contact_phone'))
      and has_column_privilege('authenticated', 'public.partners', 'contact_email', 'update')),
  (2, 'Contratados só para vínculo verificado',
      (select prosrc like '%verification_status = ''verified''%' and prosrc like '%''client''%'
       from pg_proc where oid = to_regprocedure('public.list_my_contracted_partners()'))),
  (3, 'pedido de contato a parceiro só por vínculo verificado',
      (select prosrc like '%verification_status = ''verified''%' from pg_proc where oid = to_regprocedure('public.company_request_partner(uuid)'))),
  (4, 'anon não executa Contratados',
      not coalesce(has_function_privilege('anon', to_regprocedure('public.list_my_contracted_partners()'), 'execute'), true)),
  (5, 'as cinco do lote 2 registradas',
      (select count(*) = 5 from supabase_migrations.schema_migrations
       where version in ('20261117130000', '20261118120000', '20261118130000', '20261118140000', '20261118150000')))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
