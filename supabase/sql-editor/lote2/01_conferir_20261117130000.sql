-- Conferência do lote 2, passo 01 (20261117130000, troca do gate). Só leitura. Deu certo se TODAS as linhas tiverem ok = true.
-- Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261117130000')),
  (2, 'casos da empresa só para vínculo verificado (lista e linha do tempo)',
      (select bool_and(prosrc like '%is_verified_company_user%') from pg_proc
       where oid in (to_regprocedure('public.list_company_complaints()'), to_regprocedure('public.get_company_complaint_timeline(uuid)')))),
  (3, 'resposta da empresa só por vínculo verificado',
      (select prosrc like '%is_verified_company_user%' from pg_proc where oid = to_regprocedure('public.respond_complaint(uuid,text)'))),
  (4, 'números da própria empresa só para vínculo verificado',
      (select bool_and(prosrc like '%verified%') from pg_proc
       where oid in (to_regprocedure('public.company_responsiveness()'), to_regprocedure('public.my_company_responsiveness()'),
                     to_regprocedure('public.my_company_satisfaction()')))),
  (5, 'vínculo recusado ou revogado não edita o perfil da empresa',
      (select prosrc like '%revogado%' from pg_proc where oid = to_regprocedure('public.update_company_profile(uuid,jsonb)'))),
  (6, 'há pelo menos um representante verificado',
      exists (select 1 from public.company_users where verification_status = 'verified'))
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
-- Informativo (não entra no resultado): vínculos por estado. Empresas com caso liberado e nenhum verificado ficam sem ver
-- os casos até a verificação.
-- select verification_status, count(*) from public.company_users group by 1;
