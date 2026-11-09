-- Desempate da ordem nas linhas do tempo da equipe e da empresa.
-- Itens gravados na mesma transação têm o mesmo created_at (now() é fixo na transação) e saíam em ordem indefinida.
-- Critério, nesta ordem:
--   1) created_at;
--   2) tipo do item: review (decisão da equipe) = 1, response (resposta da empresa) = 2, access (consulta ao original) = 3, event = 4.
--      A causa vem antes do evento de status que ela gera (decisão → evento; resposta → evento 'answered');
--   3) entre eventos, a ordem do enum complaint_status:
--      received, in_review, adjustment_requested, held, shared, answered, closed, canceled;
--   4) id, só para a ordem ser estável quando tudo empata.
-- Só create or replace: mesma assinatura e mesmas colunas de saída; nenhuma tabela, política ou permissão muda.
-- Rollback: reaplicar as definições de 20261106130100_operacao_revisao_e_auditoria.sql.

create or replace function public.get_company_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.kind, t.status, t.actor, t.content, t.created_at
  from (
    select 'event'::text as kind, e.status, e.actor, e.note as content, e.created_at, 4 as kind_rank, e.id
    from public.complaint_events e
    join public.complaints c on c.id = e.complaint_id
    where e.complaint_id = p_id and c.status in ('shared', 'answered', 'closed') and public.is_company_user(c.company_id)
      and e.status in ('shared', 'answered', 'closed')
    union all
    select 'response'::text, null::public.complaint_status, 'company'::public.complaint_actor, r.content, r.created_at, 2, r.id
    from public.company_responses r
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and public.is_company_user(c.company_id)
  ) t
  order by t.created_at, t.kind_rank, t.status nulls first, t.id;
$$;

create or replace function public.ops_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select t.kind, t.status, t.actor, t.content, t.created_at
  from (
    select 'event'::text as kind, e.status, e.actor, e.note as content, e.created_at, 4 as kind_rank, e.id
    from public.complaint_events e where e.complaint_id = p_id
    union all
    select 'response'::text, null::public.complaint_status, 'company'::public.complaint_actor, r.content, r.created_at, 2, r.id
    from public.company_responses r where r.complaint_id = p_id
    union all
    select 'review'::text, null::public.complaint_status, 'platform'::public.complaint_actor,
           case rv.decision when 'released' then 'Decisão: liberar' when 'adjustment_requested' then 'Decisão: pedir ajuste' else 'Decisão: reter' end
           || coalesce(' · ' || rv.reason, ''), rv.created_at, 1, rv.id
    from public.complaint_reviews rv where rv.complaint_id = p_id
    union all
    select 'access'::text, null::public.complaint_status, 'platform'::public.complaint_actor, 'Relato original consultado · ' || a.justification, a.created_at, 3, a.id
    from public.original_access_log a where a.complaint_id = p_id
  ) t
  order by t.created_at, t.kind_rank, t.status nulls first, t.id;
end;
$$;
