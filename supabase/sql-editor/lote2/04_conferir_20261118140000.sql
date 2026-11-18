-- Conferência do lote 2, passo 04 (20261118140000, reivindicação da empresa pré-cadastrada no cadastro). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261118140000')),
  (2, 'cadastro de empresa reivindica a pré-cadastrada',
      (select prosrc like '%registration_status = ''registered''%' and prosrc like '%''member''%'
       from pg_proc where oid = to_regprocedure('private.create_profile(uuid,text,jsonb)'))),
  (3, 'cadastro de trabalhador mantém a mensagem genérica de CPF',
      (select prosrc like '%Não foi possível concluir o cadastro.%' from pg_proc where oid = to_regprocedure('private.create_profile(uuid,text,jsonb)'))),
  (4, 'as quatro primeiras do lote 2 registradas',
      (select count(*) = 4 from supabase_migrations.schema_migrations
       where version in ('20261117130000', '20261118120000', '20261118130000', '20261118140000')))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
