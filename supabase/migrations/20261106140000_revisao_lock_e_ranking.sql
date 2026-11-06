-- ADR-0010 / TASK-0031: correções do pacote da revisão humana (aprovadas em 2026-11-06).
-- Só create or replace de funções: nenhuma tabela, coluna, enum, política ou permissão muda.
-- Rollback: reaplicar as definições de 20261106130100 (ops_decide_complaint) e 20261027024534 (company_ranking).

-- 1) Decisão da equipe trava a linha da manifestação antes de conferir o status.
--    Duas pessoas decidindo ao mesmo tempo: a segunda espera a primeira terminar, relê o status já alterado e recebe erro,
--    em vez de gravar uma segunda decisão e um segundo evento.
create or replace function public.ops_decide_complaint(p_id uuid, p_decision text, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status public.complaint_status; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select status into v_status from public.complaints where id = p_id for update;
  if v_status is null then raise exception 'Manifestação não encontrada.' using errcode = 'P0001'; end if;
  if v_status not in ('in_review', 'held') then raise exception 'Só manifestações em revisão ou retidas podem receber decisão.' using errcode = 'P0001'; end if;
  if p_decision not in ('released', 'adjustment_requested', 'held') then raise exception 'Decisão inválida.' using errcode = 'P0001'; end if;
  if p_decision in ('adjustment_requested', 'held') and (v_reason is null or char_length(v_reason) < 10) then
    raise exception 'Explique o motivo com pelo menos 10 caracteres.' using errcode = 'P0001';
  end if;
  if char_length(coalesce(v_reason, '')) > 500 then raise exception 'O motivo pode ter até 500 caracteres.' using errcode = 'P0001'; end if;
  if p_decision = 'released' and not exists (select 1 from public.complaint_shared_versions where complaint_id = p_id) then
    raise exception 'Não há versão compartilhável para liberar.' using errcode = 'P0001';
  end if;

  insert into public.complaint_reviews (complaint_id, reviewer_id, decision, reason) values (p_id, auth.uid(), p_decision, v_reason);
  if p_decision = 'released' then
    update public.complaints set status = 'shared' where id = p_id;
    insert into public.complaint_events (complaint_id, status, actor, note) values (p_id, 'shared', 'platform', 'Versão revisada e liberada para a empresa.');
  elsif p_decision = 'adjustment_requested' then
    update public.complaints set status = 'adjustment_requested' where id = p_id;
    insert into public.complaint_events (complaint_id, status, actor, note) values (p_id, 'adjustment_requested', 'platform', 'Ajuste solicitado pela equipe: ' || v_reason);
  else
    update public.complaints set status = 'held' where id = p_id;
    insert into public.complaint_events (complaint_id, status, actor, note) values (p_id, 'held', 'platform', 'Manifestação em análise pela equipe antes de qualquer contato com a empresa.');
  end if;
end;
$$;

-- 2) Ranking mede o tempo de primeira resposta a partir da liberação à empresa (primeiro evento "shared"),
--    e não da criação: o tempo em revisão pela equipe não conta contra a empresa.
--    Casos antigos sem evento "shared" usam a data de criação, como antes.
create or replace function public.company_ranking()
returns table (company_id uuid, name text, city text, state text, received integer, response_rate integer, avg_first_response_hours integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  with base as (
    select c.company_id, c.id,
           coalesce((select min(e.created_at) from public.complaint_events e where e.complaint_id = c.id and e.status = 'shared'), c.created_at) as released_at,
           (select min(r.created_at) from public.company_responses r where r.complaint_id = c.id) as first_response
    from public.complaints c where c.status in ('shared', 'answered', 'closed')
  )
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state,
         count(*)::int,
         round(100.0 * count(b.first_response) / count(*))::int,
         round(avg(extract(epoch from (b.first_response - b.released_at)) / 3600) filter (where b.first_response is not null))::int,
         public.is_company_user(co.id)
  from base b join public.companies co on co.id = b.company_id join public.addresses a on a.id = co.address_id
  where auth.uid() is not null
  group by co.id, co.trade_name, co.legal_name, a.city, a.state
  having count(*) >= 3
  order by 6 desc, 7 asc nulls last;
$$;
