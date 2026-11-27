-- Conferência do lote 5, passo 02 (20261126130000, motivo do aviso e aviso automático à empresa não cadastrada). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261126130000')),
  (2, 'fila com motivo e aviso (reason, notice_id), sem e-mail',
      (select count(*) = 2 from information_schema.columns where table_schema = 'private' and table_name = 'notification_outbox'
         and column_name in ('reason', 'notice_id'))
      and not exists (select 1 from information_schema.columns where table_schema = 'private' and table_name = 'notification_outbox'
         and column_name in ('email', 'destination'))),
  (3, 'tipo company_notice aceito', (select pg_get_constraintdef(oid) like '%company_notice%' from pg_constraint
      where conname = 'notification_outbox_kind_check' and conrelid = 'private.notification_outbox'::regclass)),
  (4, 'aprovação do aviso entra na fila (gatilho)', exists (select 1 from pg_trigger where tgname = 'company_notices_enqueue' and not tgisinternal)),
  (5, 'reserva nova só para a função de envio',
      to_regprocedure('public.notification_claim(integer,boolean)') is not null
      and to_regprocedure('public.notification_claim(integer)') is null
      and has_function_privilege('service_role', to_regprocedure('public.notification_claim(integer,boolean)'), 'execute')
      and not has_function_privilege('authenticated', to_regprocedure('public.notification_claim(integer,boolean)'), 'execute')
      and not has_function_privilege('anon', to_regprocedure('public.notification_claim(integer,boolean)'), 'execute')),
  (6, 'resultado do envio reflete no aviso', (select prosrc like '%company_notices%' from pg_proc
      where oid = to_regprocedure('public.notification_mark(uuid,text,text,integer)'))),
  (7, 'marcação manual tira o envio da fila', (select prosrc like '%notification_outbox%' from pg_proc
      where oid = to_regprocedure('public.ops_mark_notice_sent(uuid,text)'))),
  (8, 'nenhum aviso preso em envio', not exists (select 1 from private.notification_outbox where status = 'sending'
      and claimed_at < now() - interval '30 minutes'))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
