-- Conferência do lote 2, passo 03 (20261118130000, funções da empresa pré-cadastrada e do aviso). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261118130000')),
  (2, 'create_complaint com empresa pelo CNPJ, contato e checagem da pausa',
      (select prosrc like '%company_cnpj%' and prosrc like '%notice_contact%' and prosrc like '%assert_pilot_open%'
       from pg_proc where oid = to_regprocedure('public.create_complaint(jsonb,boolean)'))),
  (3, 'busca por CNPJ só de cadastradas',
      (select prosrc like '%registration_status = ''registered''%' from pg_proc where oid = to_regprocedure('public.find_company_by_cnpj(text)'))),
  (4, 'sem pré-cadastro chamável por cliente',
      to_regprocedure('public.preregister_company(text)') is null
      and to_regprocedure('public.preregister_company_manual(text,text,text,text)') is null
      and not coalesce(has_function_privilege('authenticated', to_regprocedure('private.preregister_company(text,jsonb)'), 'execute'), true)),
  (5, 'funções da equipe existem',
      to_regprocedure('public.ops_list_pending_companies()') is not null
      and to_regprocedure('public.ops_review_company(uuid,text,text,boolean)') is not null
      and to_regprocedure('public.ops_list_notice_candidates()') is not null
      and to_regprocedure('public.ops_decide_notice(uuid,text,text,text)') is not null
      and to_regprocedure('public.ops_mark_notice_sent(uuid,text)') is not null
      and to_regprocedure('public.ops_add_opt_out(text)') is not null
      and to_regprocedure('public.ops_purge_expired_contacts()') is not null
      and to_regprocedure('public.my_complaint_companies()') is not null
      and to_regprocedure('public.ops_complaint_contact(uuid)') is not null
      and to_regprocedure('public.my_complaint_contact(uuid)') is not null),
  (6, 'aviso exige a troca do gate e o consentimento do trabalhador no relato',
      (select prosrc like '%is_verified_company_user%' and prosrc like '%complaint_notice_consents%'
       from pg_proc where oid = to_regprocedure('public.ops_decide_notice(uuid,text,text,text)'))
      and (select prosrc like '%notice_consent%' from pg_proc where oid = to_regprocedure('public.create_complaint(jsonb,boolean)'))),
  (7, 'anon não executa busca nem decisões',
      not coalesce(has_function_privilege('anon', to_regprocedure('public.find_company_by_cnpj(text)'), 'execute'), true)
      and not coalesce(has_function_privilege('anon', to_regprocedure('public.ops_decide_notice(uuid,text,text,text)'), 'execute'), true))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
