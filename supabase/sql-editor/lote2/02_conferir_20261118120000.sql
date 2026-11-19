-- Conferência do lote 2, passo 02 (20261118120000, estrutura da empresa pré-cadastrada). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261118120000')),
  (2, 'companies com registration_status e data_source',
      (select count(*) = 2 from information_schema.columns where table_schema = 'public' and table_name = 'companies'
       and column_name in ('registration_status', 'data_source'))),
  (3, 'todas as empresas existentes continuam registered/signup',
      not exists (select 1 from public.companies where registration_status <> 'registered' or data_source <> 'signup')),
  (4, 'tabelas novas criadas',
      to_regclass('private.company_preregistrations') is not null and to_regclass('private.cnpj_cache') is not null
      and to_regclass('private.cnpj_lookup_quota') is not null and to_regclass('public.complaint_contacts') is not null
      and to_regclass('public.company_notices') is not null and to_regclass('private.notice_opt_outs') is not null),
  (5, 'contatos e avisos com RLS e trilha guardada',
      (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('public.complaint_contacts'), to_regclass('public.company_notices')))
      and exists (select 1 from pg_trigger where tgname = 'company_notices_guard' and not tgisinternal)),
  (6, 'ninguém lê contatos e avisos direto (nem a chave da Edge Function)',
      not has_table_privilege('service_role', 'public.complaint_contacts', 'select')
      and not has_table_privilege('service_role', 'public.company_notices', 'select')
      and not has_table_privilege('authenticated', 'public.complaint_contacts', 'select')
      and not has_table_privilege('anon', 'public.complaint_contacts', 'select')),
  (8, 'contato do trabalhador com e-mail e/ou telefone; cache e aviso com o e-mail da Receita e a origem do destino',
      (select count(*) = 1 from information_schema.columns where table_schema = 'public' and table_name = 'complaint_contacts' and column_name = 'phone')
      and (select count(*) = 1 from information_schema.columns where table_schema = 'private' and table_name = 'cnpj_cache' and column_name = 'email')
      and (select count(*) = 1 from information_schema.columns where table_schema = 'public' and table_name = 'company_notices' and column_name = 'destination_source')
      and to_regclass('private.complaint_notice_consents') is not null),
  (7, 'RPCs do cache só para a service_role',
      coalesce(has_function_privilege('service_role', to_regprocedure('public.cnpj_cache_get(text)'), 'execute'), false)
      and not coalesce(has_function_privilege('authenticated', to_regprocedure('public.cnpj_cache_put(text,boolean,text,text,text,text,text,text,text,text,text)'), 'execute'), true)
      and not coalesce(has_function_privilege('anon', to_regprocedure('public.cnpj_quota_take(uuid)'), 'execute'), true))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
