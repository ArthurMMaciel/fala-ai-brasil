-- Rollback do lote 4, passo 01 (20261123130000, fila de avisos e opt-out). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Exige antes: desligar o envio (lote4/02_desligar_envio.sql) e apagar a função send-notifications.
-- Efeito: some a fila (sem conteúdo, nada a exportar) e a preferência de avisos dos trabalhadores. Se algum trabalhador
-- tiver desligado os avisos, exporte antes (select user_id from public.workers where not email_updates; -> Download CSV)
-- e troque false por true em v_exportei. A versão sai de schema_migrations. Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
declare v_exportei boolean := false;
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261123130000') then
    raise exception 'A 20261123130000 não está registrada. Nada foi feito.';
  end if;
  if to_regclass('cron.job') is not null and exists (select 1 from cron.job where jobname = 'send-notifications') then
    raise exception 'Desligue o envio antes (lote4/02_desligar_envio.sql). Nada foi feito.';
  end if;
  if not v_exportei and exists (select 1 from public.workers where not email_updates) then
    raise exception 'Há trabalhadores com avisos desligados. Exporte e marque v_exportei = true. Nada foi feito.';
  end if;
end $trava$;

drop trigger complaint_events_notify on public.complaint_events;
drop trigger company_responses_notify on public.company_responses;
drop function private.enqueue_notification(), private.enqueue_response_returned(),
  public.notification_claim(integer), public.notification_mark(uuid, text, text, integer),
  public.set_worker_email_updates(boolean), public.my_email_updates(), public.ops_notification_stats();
drop table private.notification_outbox;
alter table public.workers drop column email_updates;
delete from supabase_migrations.schema_migrations where version = '20261123130000';

commit;
