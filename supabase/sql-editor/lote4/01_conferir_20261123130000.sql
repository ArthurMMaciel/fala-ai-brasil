-- Conferência do lote 4, passo 01 (20261123130000, fila de avisos). Só leitura. Deu certo se TODAS as linhas tiverem ok = true.
-- Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261123130000')),
  (2, 'fila criada, com RLS e sem acesso de fora',
      (select relrowsecurity from pg_class where oid = to_regclass('private.notification_outbox'))
      and not has_table_privilege('service_role', 'private.notification_outbox', 'select')
      and not has_table_privilege('authenticated', 'private.notification_outbox', 'select')),
  (3, 'fila sem coluna de conteúdo',
      not exists (select 1 from information_schema.columns where table_schema = 'private' and table_name = 'notification_outbox'
                  and column_name in ('email', 'body', 'content', 'subject', 'protocol', 'title', 'note'))),
  (4, 'gatilhos em complaint_events e company_responses',
      (select count(*) = 2 from pg_trigger where tgname in ('complaint_events_notify', 'company_responses_notify') and not tgisinternal)),
  (5, 'reserva e marcação só para a service_role',
      coalesce(has_function_privilege('service_role', to_regprocedure('public.notification_claim(integer)'), 'execute'), false)
      and not coalesce(has_function_privilege('authenticated', to_regprocedure('public.notification_claim(integer)'), 'execute'), true)
      and not coalesce(has_function_privilege('anon', to_regprocedure('public.notification_mark(uuid,text,text,integer)'), 'execute'), true)),
  (6, 'opt-out do trabalhador (coluna e funções)',
      (select count(*) = 1 from information_schema.columns where table_schema = 'public' and table_name = 'workers' and column_name = 'email_updates')
      and to_regprocedure('public.set_worker_email_updates(boolean)') is not null
      and to_regprocedure('public.my_email_updates()') is not null),
  (7, 'contagens da fila só para a equipe',
      to_regprocedure('public.ops_notification_stats()') is not null
      and not coalesce(has_function_privilege('anon', to_regprocedure('public.ops_notification_stats()'), 'execute'), true))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
-- Informativo: a fila acumula até o agendamento (passo 02) ser criado.
-- select status, count(*) from private.notification_outbox group by 1;
