-- Conferência do lote 5, passo 01 (20261126120000, até 3 contatos por manifestação). Só leitura.
-- Deu certo se TODAS as linhas tiverem ok = true. Um erro ao rodar esta consulta também quer dizer que não deu certo.
with c(n, verificacao, ok) as (values
  (1, 'versão registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261126120000')),
  (2, 'um contato por manifestação deixou de ser regra (unique removido)',
      not exists (select 1 from pg_constraint where conname = 'complaint_contacts_complaint_id_key')),
  (3, 'no máximo 3 contatos (gatilho)', exists (select 1 from pg_trigger where tgname = 'complaint_contacts_max3' and not tgisinternal)),
  (4, 'create_complaint aceita a lista e o formato antigo',
      (select prosrc like '%notice_contacts%' and prosrc like '%notice_contact''%' from pg_proc where oid = to_regprocedure('public.create_complaint(jsonb,boolean)'))),
  (5, 'decisão do aviso escolhe o contato (p_contact_id)', to_regprocedure('public.ops_decide_notice(uuid,text,text,text,uuid)') is not null
      and to_regprocedure('public.ops_decide_notice(uuid,text,text,text)') is null),
  (6, 'listas completas para equipe e trabalhador',
      to_regprocedure('public.ops_complaint_contacts_list(uuid)') is not null and to_regprocedure('public.my_complaint_contacts_list(uuid)') is not null
      and not coalesce(has_function_privilege('anon', to_regprocedure('public.my_complaint_contacts_list(uuid)'), 'execute'), true)),
  (7, 'funções de uma linha continuam (contato padrão)',
      to_regprocedure('public.ops_complaint_contact(uuid)') is not null and to_regprocedure('public.my_complaint_contact(uuid)') is not null)
)
select n, verificacao, coalesce(ok, false) as ok from c
union all select 99, 'RESULTADO GERAL', bool_and(coalesce(ok, false)) from c
order by n;
