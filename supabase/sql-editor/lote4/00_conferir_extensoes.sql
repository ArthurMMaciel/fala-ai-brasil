-- Lote 4, passo 00: conferir as extensões antes de tudo. Só leitura.
-- Habilite pg_cron e pg_net no painel (Database > Extensions, ou Integrations > Cron), como manda o runbook
-- docs/runbooks/EMAIL_NOTIFICATIONS.md. O Vault (supabase_vault) já vem habilitado nos projetos do Supabase.
-- Deu certo se TODAS as linhas tiverem ok = true.
with c(n, verificacao, ok) as (values
  (1, 'pg_cron habilitada', exists (select 1 from pg_extension where extname = 'pg_cron')),
  (2, 'pg_net habilitada', exists (select 1 from pg_extension where extname = 'pg_net')),
  (3, 'Vault habilitado', exists (select 1 from pg_extension where extname = 'supabase_vault'))
)
select n, verificacao, ok from c
union all select 99, 'RESULTADO GERAL', bool_and(ok) from c
order by n;
