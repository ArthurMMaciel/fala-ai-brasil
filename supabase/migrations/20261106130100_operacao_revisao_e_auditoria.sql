-- ADR-0010: fila de revisão da equipe, decisões auditadas, acesso excepcional ao original e números agregados.
-- Trabalhador "solicita revisão" (in_review); a equipe libera (shared), pede ajuste (adjustment_requested) ou retém (held).
-- A empresa continua vendo só shared/answered/closed; nenhum evento de revisão aparece para ela.

-- 1) Trilha de decisões (sem conteúdo do relato) e registro de acesso ao original.
create table public.complaint_reviews (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.complaints (id) on delete cascade,
  reviewer_id uuid references auth.users (id) on delete set null,
  decision text not null check (decision in ('released', 'adjustment_requested', 'held')),
  reason text check (reason is null or char_length(reason) <= 500),
  created_at timestamptz not null default now()
);
create index complaint_reviews_complaint_idx on public.complaint_reviews (complaint_id, created_at);

create table public.original_access_log (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.complaints (id) on delete cascade,
  reviewer_id uuid references auth.users (id) on delete set null,
  justification text not null check (char_length(btrim(justification)) between 10 and 500),
  created_at timestamptz not null default now()
);
create index original_access_log_complaint_idx on public.original_access_log (complaint_id, created_at);

alter table public.complaint_reviews enable row level security;
alter table public.original_access_log enable row level security;
revoke all on public.complaint_reviews, public.original_access_log from public, anon, authenticated;

-- 2) Trabalhador: enviar agora significa pedir revisão.
create or replace function public.create_complaint(p jsonb, p_share boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_worker uuid;
  v_id uuid;
  v_shared text := nullif(btrim(p ->> 'shared_content'), '');
begin
  select id into v_worker from public.workers where user_id = auth.uid();
  if v_worker is null then raise exception 'Somente trabalhadores podem registrar manifestações.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.companies where id = (p ->> 'company_id')::uuid) then
    raise exception 'Empresa não encontrada.' using errcode = 'P0001';
  end if;
  if p_share and v_shared is null then raise exception 'Escreva a versão que poderá ser compartilhada com a empresa.' using errcode = 'P0001'; end if;

  insert into public.complaints (worker_id, company_id, category, title, incident_period, recurrence, expected_outcomes, status)
  values (
    v_worker, (p ->> 'company_id')::uuid, btrim(p ->> 'category'), btrim(p ->> 'title'),
    nullif(btrim(p ->> 'incident_period'), ''), nullif(btrim(p ->> 'recurrence'), ''),
    coalesce(array(select jsonb_array_elements_text(p -> 'expected_outcomes')), '{}'),
    case when p_share then 'in_review'::public.complaint_status else 'received'::public.complaint_status end
  )
  returning id into v_id;
  insert into public.complaint_originals (complaint_id, original_content) values (v_id, btrim(p ->> 'original_content'));
  insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'received', 'worker', 'Manifestação registrada.');
  if p_share then
    insert into public.complaint_shared_versions (complaint_id, shared_content) values (v_id, v_shared);
    insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'in_review', 'worker', 'Revisão solicitada. A equipe confere a versão antes de liberar à empresa.');
  end if;
  return v_id;
end;
$$;

-- Guardada ou devolvida para ajuste: o trabalhador (re)envia a versão e volta para a fila.
create or replace function public.share_complaint(p_id uuid, p_shared text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status public.complaint_status;
begin
  if not public.owns_complaint(p_id) then raise exception 'Manifestação não encontrada.' using errcode = 'P0001'; end if;
  select status into v_status from public.complaints where id = p_id;
  if v_status not in ('received', 'adjustment_requested') then raise exception 'Esta manifestação já está em revisão, liberada ou encerrada.' using errcode = 'P0001'; end if;
  if char_length(btrim(coalesce(p_shared, ''))) < 10 then raise exception 'Escreva a versão compartilhável com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.complaint_shared_versions (complaint_id, shared_content) values (p_id, btrim(p_shared))
  on conflict (complaint_id) do update set shared_content = excluded.shared_content, confirmed_by_worker_at = now();
  update public.complaints set status = 'in_review' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, 'in_review', 'worker', case when v_status = 'adjustment_requested' then 'Versão ajustada e enviada para nova revisão.' else 'Revisão solicitada. A equipe confere a versão antes de liberar à empresa.' end);
end;
$$;

-- Encerrar antes da liberação conta como retirada (cancelada), não como encerramento com a empresa.
create or replace function public.close_complaint(p_id uuid, p_feedback public.complaint_feedback)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status public.complaint_status; v_withdraw boolean;
begin
  if not public.owns_complaint(p_id) then raise exception 'Manifestação não encontrada.' using errcode = 'P0001'; end if;
  select status into v_status from public.complaints where id = p_id;
  if v_status in ('closed', 'canceled') then raise exception 'Esta manifestação já foi encerrada.' using errcode = 'P0001'; end if;
  v_withdraw := v_status in ('received', 'in_review', 'adjustment_requested', 'held');
  update public.complaints
    set status = case when v_withdraw then 'canceled'::public.complaint_status else 'closed'::public.complaint_status end,
        worker_feedback = case when v_withdraw then null else p_feedback end, closed_at = now()
    where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, case when v_withdraw then 'canceled'::public.complaint_status else 'closed'::public.complaint_status end, 'worker',
          case when v_withdraw then 'Manifestação retirada antes de chegar à empresa.' else 'Trabalhador encerrou o acompanhamento.' end);
end;
$$;

-- Empresa: linha do tempo só com eventos de depois da liberação.
create or replace function public.get_company_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select 'event', e.status, e.actor, e.note, e.created_at from public.complaint_events e
  join public.complaints c on c.id = e.complaint_id
  where e.complaint_id = p_id and c.status in ('shared', 'answered', 'closed') and public.is_company_user(c.company_id)
    and e.status in ('shared', 'answered', 'closed')
  union all
  select 'response', null, 'company', r.content, r.created_at from public.company_responses r
  join public.complaints c on c.id = r.complaint_id
  where r.complaint_id = p_id and public.is_company_user(c.company_id)
  order by 5;
$$;

-- 3) Equipe: lista de manifestações sem identidade do trabalhador.
create function public.ops_list_complaints(p_status text default null)
returns table (id uuid, protocol text, company_id uuid, company_name text, category text, title text, status public.complaint_status,
               shared_content text, incident_period text, recurrence text, expected_outcomes text[], created_at timestamptz,
               updated_at timestamptz, responses integer, last_decision text, last_decision_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select c.id, c.protocol, c.company_id, coalesce(co.trade_name, co.legal_name), c.category, c.title, c.status,
         s.shared_content, c.incident_period, c.recurrence, c.expected_outcomes, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select rv.decision from public.complaint_reviews rv where rv.complaint_id = c.id order by rv.created_at desc limit 1),
         (select max(rv.created_at) from public.complaint_reviews rv where rv.complaint_id = c.id)
  from public.complaints c
  join public.companies co on co.id = c.company_id
  left join public.complaint_shared_versions s on s.complaint_id = c.id
  where p_status is null or c.status::text = p_status
  order by case when c.status = 'in_review' then 0 when c.status = 'held' then 1 else 2 end, c.updated_at desc;
end;
$$;

-- Decisão da equipe: libera, pede ajuste (motivo vai ao trabalhador) ou retém (motivo fica só na trilha).
create function public.ops_decide_complaint(p_id uuid, p_decision text, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status public.complaint_status; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select status into v_status from public.complaints where id = p_id;
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

-- Acesso excepcional ao relato original: exige justificativa e fica registrado.
create function public.ops_read_original(p_id uuid, p_justification text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_text text;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_justification, ''))) < 10 then raise exception 'Informe a justificativa com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  select original_content into v_text from public.complaint_originals where complaint_id = p_id;
  if v_text is null then raise exception 'Manifestação não encontrada.' using errcode = 'P0001'; end if;
  insert into public.original_access_log (complaint_id, reviewer_id, justification) values (p_id, auth.uid(), btrim(left(p_justification, 500)));
  return v_text;
end;
$$;

-- Linha do tempo completa para a equipe (eventos e respostas, sem identidade).
create function public.ops_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select 'event'::text, e.status, e.actor, e.note, e.created_at from public.complaint_events e where e.complaint_id = p_id
  union all
  select 'response'::text, null::public.complaint_status, 'company'::public.complaint_actor, r.content, r.created_at from public.company_responses r where r.complaint_id = p_id
  union all
  select 'review'::text, null::public.complaint_status, 'platform'::public.complaint_actor,
         case rv.decision when 'released' then 'Decisão: liberar' when 'adjustment_requested' then 'Decisão: pedir ajuste' else 'Decisão: reter' end
         || coalesce(' · ' || rv.reason, ''), rv.created_at
  from public.complaint_reviews rv where rv.complaint_id = p_id
  union all
  select 'access'::text, null::public.complaint_status, 'platform'::public.complaint_actor, 'Relato original consultado · ' || a.justification, a.created_at
  from public.original_access_log a where a.complaint_id = p_id
  order by 5;
end;
$$;

-- Empresas cadastradas com volume e resposta (para a equipe).
create function public.ops_list_companies()
returns table (id uuid, name text, legal_name text, city text, state text, created_at timestamptz, users integer,
               complaints integer, released integer, answered integer, has_contact boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), co.legal_name, a.city, a.state, co.created_at,
         (select count(*)::int from public.company_users cu where cu.company_id = co.id),
         (select count(*)::int from public.complaints c where c.company_id = co.id and c.status not in ('received', 'canceled')),
         (select count(*)::int from public.complaints c where c.company_id = co.id and c.status in ('shared', 'answered', 'closed')),
         (select count(*)::int from public.complaints c where c.company_id = co.id and c.status in ('answered', 'closed')),
         (co.contact_email is not null or co.contact_phone is not null)
  from public.companies co join public.addresses a on a.id = co.address_id
  order by 2;
end;
$$;

-- Números agregados para os painéis da equipe (sem nenhum dado individual).
create function public.ops_metrics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select jsonb_build_object(
    'by_status', coalesce((select jsonb_object_agg(status, total) from (select status::text, count(*) as total from public.complaints group by status) s), '{}'::jsonb),
    'workers', (select count(*) from public.workers),
    'companies', (select count(*) from public.companies),
    'partners', (select count(*) from public.partners),
    'sponsors', (select count(*) from public.sponsors),
    'complaints_30d', (select count(*) from public.complaints where created_at > now() - interval '30 days'),
    'contacts_waiting', (select count(*) from public.contact_solicitations where status = 'waiting_contact'),
    'avg_hours_to_review', (select round(avg(extract(epoch from (rv.first_at - e.first_at)) / 3600)::numeric, 1)
       from (select complaint_id, min(created_at) as first_at from public.complaint_events where status = 'in_review' group by complaint_id) e
       join (select complaint_id, min(created_at) as first_at from public.complaint_reviews group by complaint_id) rv using (complaint_id)),
    'avg_hours_to_company_response', (select round(avg(extract(epoch from (r.first_at - e.first_at)) / 3600)::numeric, 1)
       from (select complaint_id, min(created_at) as first_at from public.complaint_events where status = 'shared' group by complaint_id) e
       join (select complaint_id, min(created_at) as first_at from public.company_responses group by complaint_id) r using (complaint_id)),
    'weekly', coalesce((select jsonb_agg(jsonb_build_object('week', to_char(w, 'DD/MM'), 'total', total) order by w)
       from (select date_trunc('week', created_at) as w, count(*) as total from public.complaints
             where created_at > now() - interval '8 weeks' group by 1) x), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

revoke execute on function public.ops_list_complaints(text), public.ops_decide_complaint(uuid, text, text), public.ops_read_original(uuid, text),
  public.ops_complaint_timeline(uuid), public.ops_list_companies(), public.ops_metrics() from public, anon;
grant execute on function public.ops_list_complaints(text), public.ops_decide_complaint(uuid, text, text), public.ops_read_original(uuid, text),
  public.ops_complaint_timeline(uuid), public.ops_list_companies(), public.ops_metrics() to authenticated;

-- 4) Conta da equipe criada pelo painel do Supabase ("Add user") não traz tipo de cadastro: cria só o usuário,
--    sem perfil de trabalhador/empresa. O acesso de equipe vem de private.platform_admins.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  if coalesce(meta ->> 'signup_type', '') = '' then return new; end if;
  perform private.create_profile(new.id, meta ->> 'signup_type', meta -> 'signup');
  -- Documentos e endereço não devem circular no JWT (user_metadata).
  update auth.users set raw_user_meta_data = jsonb_build_object('full_name', meta ->> 'full_name') where id = new.id;
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
