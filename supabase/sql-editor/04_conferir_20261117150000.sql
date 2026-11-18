-- Conferência do passo 04 (20261117150000). Só leitura. Deu certo se TODAS as linhas tiverem ok = true.
-- Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261117150000')),
  (2, 'piloto começa aberto (pilot_state = open)', public.pilot_state() = 'open'),
  (3, 'trilha pilot_state_log com RLS e imutável',
      (select relrowsecurity from pg_class where oid = to_regclass('public.pilot_state_log'))
      and exists (select 1 from pg_trigger where tgname = 'pilot_state_log_immutable' and not tgisinternal)),
  (4, 'create_complaint checa a pausa',
      (select prosrc like '%assert_pilot_open%' from pg_proc where oid = to_regprocedure('public.create_complaint(jsonb,boolean)'))),
  (5, 'site (anon) lê o estado', coalesce(has_function_privilege('anon', to_regprocedure('public.pilot_state()'), 'execute'), false)),
  (6, 'anon não pausa',
      not coalesce(has_function_privilege('anon', to_regprocedure('public.ops_set_pilot_state(text,text)'), 'execute'), true)),
  (7, 'as quatro migrations do lote registradas e a 130000 não',
      (select count(*) = 4 from supabase_migrations.schema_migrations
       where version in ('20261109180000', '20261117120000', '20261117140000', '20261117150000'))
      and not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117130000'))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
