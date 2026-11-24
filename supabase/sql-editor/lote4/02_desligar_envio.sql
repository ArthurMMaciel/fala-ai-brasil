-- Rollback do lote 4, passo 02: DESLIGA o envio já (runbook EMAIL_NOTIFICATIONS, "Desligar já"). As linhas continuam na
-- fila e voltam a sair quando o agendamento for recriado. Para contenção total: apagar a função
-- (functions delete send-notifications) e trocar a senha de app (PILOT_SUSPENSION).
select cron.unschedule('send-notifications')
where exists (select 1 from cron.job where jobname = 'send-notifications');

-- Conferir: deve voltar zero linhas.
-- select * from cron.job where jobname = 'send-notifications';
