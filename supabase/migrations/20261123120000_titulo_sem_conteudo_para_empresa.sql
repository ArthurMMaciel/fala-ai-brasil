-- Achado de privacidade no teste em produção (EAB-2026-1067), opção (a) aprovada pelo responsável em 2026-11-23 ("Aprovo").
-- complaints.title é escrito na etapa do relato ORIGINAL e não passa pela revisão da versão compartilhável; a empresa o
-- recebia como título da manifestação (lista, detalhe, fila de atenção e PDF). Aplica a regra de que o original nunca sai
-- para a empresa (ADR-0010): list_company_complaints passa a devolver, na mesma coluna title, só 'Manifestação ' || protocolo.
-- Mesma assinatura e mesmos grants; o Front não precisa mudar. Trabalhador e equipe continuam vendo o título original.
-- Era a única função da empresa que devolvia complaints.title (conferido em 2026-11-23).
--
-- Rollback: reaplicar list_company_complaints de 20261117130000_representante_verificado_gate.sql.

create or replace function public.list_company_complaints()
returns table (id uuid, protocol text, category text, title text, status public.complaint_status, shared_content text,
               created_at timestamptz, updated_at timestamptz, responses integer, last_response_at timestamptz, worker_feedback public.complaint_feedback)
language sql stable security definer set search_path = '' as $$
  select c.id, c.protocol, c.category, 'Manifestação ' || c.protocol, c.status, s.shared_content, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select max(r.created_at) from public.company_responses r where r.complaint_id = c.id),
         c.worker_feedback
  from public.complaints c
  join public.complaint_shared_versions s on s.complaint_id = c.id
  where c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
  order by c.created_at desc;
$$;
