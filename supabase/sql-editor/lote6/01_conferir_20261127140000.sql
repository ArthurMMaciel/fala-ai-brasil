-- Conferência do lote 6, passo 01 (20261127140000, conta de empresa sem plano). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with f as (select prosrc from pg_proc where oid = to_regprocedure('private.create_profile(uuid,text,jsonb)')),
c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261127140000')),
  (2, 'empresa não cria assinatura', (select prosrc not like '%create_subscription(''company''%' from f)),
  (3, 'parceiro e patrocinador continuam com assinatura',
      (select prosrc like '%create_subscription(''partner''%' and prosrc like '%create_subscription(''sponsor''%' from f)),
  (4, 'reivindicação de empresa pré-cadastrada continua', (select prosrc like '%registration_status = ''registered''%' from f))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
