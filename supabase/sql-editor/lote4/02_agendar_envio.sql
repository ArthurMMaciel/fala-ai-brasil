-- Lote 4, passo 02: agenda a send-notifications a cada 5 minutos. É o passo que LIGA o envio: rodar por ÚLTIMO, depois de
-- (runbook EMAIL_NOTIFICATIONS, ordem de publicação):
--   - passo 00 (extensões) e passo 01 (fila) conferidos;
--   - secrets da função criados pelo responsável no próprio terminal: GMAIL_USER, GMAIL_APP_PASSWORD e NOTIFY_CRON_SECRET;
--   - função publicada com --no-verify-jwt e testada com uma conta de teste do responsável;
--   - dois segredos criados pela tela do Vault no painel (não por SQL, para o valor não ficar no histórico do SQL Editor):
--       project_url        = https://<ref-de-producao>.supabase.co
--       notify_cron_secret = o mesmo valor de NOTIFY_CRON_SECRET
-- Este script não contém nenhum segredo: lê os dois pelo nome. Não é migration (não entra em schema_migrations).
-- Erro = nada foi feito; rode `rollback;` sozinho. Desligar: 02_desligar_envio.sql.
begin;

do $trava$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') or not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise exception 'Habilite pg_cron e pg_net no painel antes (passo 00). Nada foi feito.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261123130000') then
    raise exception 'A fila (20261123130000, passo 01) não está aplicada. Nada foi feito.';
  end if;
  if (select count(*) from vault.decrypted_secrets where name in ('project_url', 'notify_cron_secret')) <> 2 then
    raise exception 'Crie no Vault os segredos project_url e notify_cron_secret antes. Nada foi feito.';
  end if;
  if exists (select 1 from cron.job where jobname = 'send-notifications') then
    raise exception 'O agendamento send-notifications já existe. Nada foi feito.';
  end if;
end $trava$;

select cron.schedule(
  'send-notifications',
  '*/5 * * * *',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notify_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $job$
);

commit;
