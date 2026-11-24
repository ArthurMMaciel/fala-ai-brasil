-- Conferência do lote 4, passo 02 (agendamento). Só leitura. Rode uns 10 minutos depois de agendar.
-- Deu certo se as linhas 1 a 3 tiverem ok = true. As consultas informativas abaixo mostram as últimas rodadas.
with c(n, verificacao, ok) as (values
  (1, 'agendamento send-notifications ativo a cada 5 minutos',
      exists (select 1 from cron.job where jobname = 'send-notifications' and schedule = '*/5 * * * *' and active)),
  (2, 'rodou sem erro na última hora',
      exists (select 1 from cron.job_run_details d join cron.job j on j.jobid = d.jobid
              where j.jobname = 'send-notifications' and d.status = 'succeeded' and d.start_time > now() - interval '1 hour')),
  (3, 'a função respondeu 200 na última hora (401 = segredo do agendador diferente do NOTIFY_CRON_SECRET)',
      exists (select 1 from net._http_response where status_code = 200 and created > now() - interval '1 hour'))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;

-- Informativo (sem conteúdo): situação da fila.
-- select status, count(*), max(last_error_code) from private.notification_outbox group by 1;
-- Últimas respostas da função (o corpo traz só contagens):
-- select created, status_code, content from net._http_response order by created desc limit 5;
