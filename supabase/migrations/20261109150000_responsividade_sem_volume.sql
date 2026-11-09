-- TASK-0036: lista de responsividade sem número de manifestações e sem posição.
-- 1) private.company_response_stats(): números por empresa (liberadas, respondidas, taxa, tempo médio), mesma regra de
--    company_ranking (20261106140000): o tempo conta a partir do primeiro evento 'shared'. Só para as funções abaixo.
-- 2) public.company_responsiveness(): para qualquer autenticado; só faixas, corte de 3 liberadas, ordem por nome.
-- 3) public.my_company_responsiveness(): números exatos só das empresas do próprio usuário (company_users).
-- company_ranking() fica até o front novo estar em produção; revoke e drop em migration seguinte.
-- Nenhuma tabela, coluna ou política muda. Rollback: drop das três funções.

create function private.company_response_stats()
returns table (company_id uuid, released integer, answered integer, rate numeric, avg_hours numeric)
language sql stable security definer set search_path = '' as $$
  with base as (
    select c.company_id,
           coalesce((select min(e.created_at) from public.complaint_events e where e.complaint_id = c.id and e.status = 'shared'), c.created_at) as released_at,
           (select min(r.created_at) from public.company_responses r where r.complaint_id = c.id) as first_response
    from public.complaints c where c.status in ('shared', 'answered', 'closed')
  )
  select b.company_id, count(*)::int, count(b.first_response)::int,
         100.0 * count(b.first_response) / count(*),
         avg(extract(epoch from (b.first_response - b.released_at)) / 3600) filter (where b.first_response is not null)
  from base b group by b.company_id;
$$;
revoke all on function private.company_response_stats() from public, anon, authenticated;

create function private.response_band(p_rate numeric)
returns text language sql immutable set search_path = '' as $$
  select case when p_rate is null then null when p_rate >= 80 then 'high' when p_rate >= 50 then 'medium' else 'low' end;
$$;

create function private.response_time_band(p_hours numeric)
returns text language sql immutable set search_path = '' as $$
  select case when p_hours is null then 'none' when p_hours <= 48 then 'fast' when p_hours <= 168 then 'regular' else 'slow' end;
$$;
revoke all on function private.response_band(numeric), private.response_time_band(numeric) from public, anon, authenticated;

create function public.company_responsiveness()
returns table (company_id uuid, name text, city text, state text, response_band text, response_time_band text,
               satisfaction_band text, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state,
         private.response_band(s.rate), private.response_time_band(s.avg_hours),
         null::text, public.is_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$;

create function public.my_company_responsiveness()
returns table (company_id uuid, name text, released integer, answered integer, response_rate integer,
               avg_first_response_hours integer, response_band text, response_time_band text, listed boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name),
         coalesce(s.released, 0), coalesce(s.answered, 0),
         round(s.rate)::int, round(s.avg_hours)::int,
         private.response_band(s.rate),
         case when coalesce(s.released, 0) = 0 then null else private.response_time_band(s.avg_hours) end,
         coalesce(s.released, 0) >= 3
  from public.company_users cu
  join public.companies co on co.id = cu.company_id
  left join private.company_response_stats() s on s.company_id = co.id
  where cu.user_id = auth.uid()
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$;

revoke execute on function public.company_responsiveness(), public.my_company_responsiveness() from public, anon;
grant execute on function public.company_responsiveness(), public.my_company_responsiveness() to authenticated;
