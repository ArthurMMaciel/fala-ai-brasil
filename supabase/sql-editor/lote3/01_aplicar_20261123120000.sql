-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/pending/20261123120000_titulo_sem_conteudo_para_empresa.sql. Não editar à mão.
-- Passo 01 de 01. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 01_conferir_20261123120000.sql (todas as linhas com ok = true).
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261123120000') then
    raise exception 'A migration 20261123120000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118150000') then
    raise exception 'Falta a 20261118150000 (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261123120000_titulo_sem_conteudo_para_empresa.sql (1 instruções) ========
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
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261123120000', 'titulo_sem_conteudo_para_empresa', array[
$s0$-- Achado de privacidade no teste em produção (EAB-2026-1067), opção (a) aprovada pelo responsável em 2026-11-23 ("Aprovo").
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
$$$s0$
]::text[]);

commit;
