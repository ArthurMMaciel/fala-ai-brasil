-- Rollback do lote 3, passo 01 (20261123120000, título sem conteúdo para a empresa). SQL Editor de produção, arquivo
-- INTEIRO, uma vez. Só com decisão registrada: volta a mandar à empresa o título do relato original.
-- A versão sai de schema_migrations. Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261123120000') then
    raise exception 'A 20261123120000 não está registrada. Nada foi feito.';
  end if;
end $trava$;

-- list_company_complaints de 20261117130000, literal.
create or replace function public.list_company_complaints()
returns table (id uuid, protocol text, category text, title text, status public.complaint_status, shared_content text,
               created_at timestamptz, updated_at timestamptz, responses integer, last_response_at timestamptz, worker_feedback public.complaint_feedback)
language sql stable security definer set search_path = '' as $$
  select c.id, c.protocol, c.category, c.title, c.status, s.shared_content, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select max(r.created_at) from public.company_responses r where r.complaint_id = c.id),
         c.worker_feedback
  from public.complaints c
  join public.complaint_shared_versions s on s.complaint_id = c.id
  where c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
  order by c.created_at desc;
$$;

delete from supabase_migrations.schema_migrations where version = '20261123120000';

commit;
