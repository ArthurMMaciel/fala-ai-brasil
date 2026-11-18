-- Conferência do passo 01 (20261109180000). Só leitura. Deu certo se TODAS as linhas tiverem ok = true.
-- Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261109180000')),
  (2, 'resposta nova nasce em revisão (default in_review)',
      (select column_default from information_schema.columns
       where table_schema = 'public' and table_name = 'company_responses' and column_name = 'review_status') like '''in_review''%'),
  (3, 'respond_complaint manda para revisão',
      (select prosrc like '%answer_in_review%' from pg_proc where oid = to_regprocedure('public.respond_complaint(uuid,text)'))),
  (4, 'trabalhador só lê resposta liberada',
      (select qual like '%released%' from pg_policies where schemaname = 'public' and tablename = 'company_responses' and policyname = 'responses_read_worker'))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
