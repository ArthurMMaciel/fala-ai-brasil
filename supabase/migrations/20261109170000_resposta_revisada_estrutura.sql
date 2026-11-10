-- TASK-0035 / ADR-0013 (aceita em 2026-11-08), passo (b): estrutura e funções, SEM mudar o comportamento para o usuário.
-- respond_complaint continua liberando a resposta na hora (agora gravando review_status = 'released'); a revisão passa
-- a valer no passo (d), 20261109180000, depois do front tolerante (passo c).
-- Decisões: 3B (trabalhador vê a descrição da equipe e a resposta revisada); a empresa vê estado e motivo de devolução,
-- nunca a descrição; avaliação por resposta liberada (partial = 0,5), fora do ranking no piloto, visível só à equipe e,
-- agregada, à própria empresa; prazo do ranking conta até o envio da primeira resposta que foi liberada.
-- Rollback: com o passo (d) ainda não aplicado, reaplicar as definições anteriores das funções alteradas e dropar as
-- funções e tabelas novas; as colunas novas de company_responses podem ficar (não quebram nada).

-- 1) Estado de cada resposta.
alter table public.company_responses
  add column review_status text not null default 'released' check (review_status in ('in_review', 'released', 'returned')),
  add column worker_summary text check (worker_summary is null or char_length(worker_summary) between 30 and 1000),
  add column released_at timestamptz,
  add column summary_corrected_at timestamptz;
update public.company_responses set released_at = created_at where review_status = 'released' and released_at is null;
create index company_responses_review_idx on public.company_responses (review_status, created_at);

-- 2) Trilha das decisões da equipe sobre respostas (separada de complaint_reviews, que é a liberação à empresa).
create table public.company_response_reviews (
  id uuid primary key default gen_random_uuid(),
  response_id uuid not null references public.company_responses (id) on delete cascade,
  reviewer_id uuid references auth.users (id) on delete set null,
  decision text not null check (decision in ('released', 'returned', 'summary_corrected')),
  worker_summary text check (worker_summary is null or char_length(worker_summary) between 30 and 1000),
  reason text check (reason is null or char_length(reason) between 10 and 500),
  created_at timestamptz not null default now(),
  check (decision <> 'released' or worker_summary is not null),
  check (decision = 'released' or reason is not null)
);
create index company_response_reviews_response_idx on public.company_response_reviews (response_id, created_at);
alter table public.company_response_reviews enable row level security;
revoke all on public.company_response_reviews from public, anon, authenticated;

-- 3) Avaliação do trabalhador, uma por resposta liberada. O comentário só a equipe lê.
create table public.response_ratings (
  response_id uuid primary key references public.company_responses (id) on delete cascade,
  worker_id uuid not null references public.workers (id) on delete cascade,
  rating public.complaint_feedback not null,
  comment text check (comment is null or char_length(comment) <= 300),
  created_at timestamptz not null default now()
);
alter table public.response_ratings enable row level security;
revoke all on public.response_ratings from public, anon, authenticated;

-- 4) Resposta da empresa: comportamento atual (liberada na hora), agora com os campos de revisão preenchidos.
create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_company_user(v_company) or v_status not in ('shared', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status, released_at)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'released', now());
  update public.complaints set status = 'answered' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note) values (p_id, 'answered', 'company', 'Empresa enviou uma resposta institucional.');
end;
$$;

-- 5) Fila da equipe.
create function public.ops_list_responses(p_status text default 'in_review')
returns table (response_id uuid, complaint_id uuid, protocol text, company_id uuid, company_name text, category text, title text,
               shared_content text, content text, review_status text, worker_summary text, created_at timestamptz,
               released_at timestamptz, waiting_hours numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select r.id, c.id, c.protocol, co.id, coalesce(co.trade_name, co.legal_name), c.category, c.title,
         s.shared_content, r.content, r.review_status, r.worker_summary, r.created_at, r.released_at,
         round((extract(epoch from (now() - r.created_at)) / 3600)::numeric, 1)
  from public.company_responses r
  join public.complaints c on c.id = r.complaint_id
  join public.companies co on co.id = r.company_id
  left join public.complaint_shared_versions s on s.complaint_id = c.id
  where p_status is null or r.review_status = p_status
  order by r.created_at;
end;
$$;

-- Decisão da equipe: libera (com descrição ao trabalhador) ou devolve (com motivo à empresa). Nunca edita o texto da empresa.
create function public.ops_decide_response(p_response uuid, p_decision text, p_summary text default null, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_review text; v_complaint uuid;
  v_summary text := nullif(btrim(coalesce(p_summary, '')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select review_status, complaint_id into v_review, v_complaint from public.company_responses where id = p_response for update;
  if v_review is null then raise exception 'Resposta não encontrada.' using errcode = 'P0001'; end if;
  if v_review <> 'in_review' then raise exception 'Só respostas em revisão podem receber decisão.' using errcode = 'P0001'; end if;
  perform 1 from public.complaints where id = v_complaint for update;

  if p_decision = 'released' then
    if v_summary is null or char_length(v_summary) not between 30 and 1000 then
      raise exception 'Escreva a descrição para o trabalhador com 30 a 1.000 caracteres.' using errcode = 'P0001';
    end if;
    update public.company_responses set review_status = 'released', worker_summary = v_summary, released_at = now() where id = p_response;
    insert into public.company_response_reviews (response_id, reviewer_id, decision, worker_summary) values (p_response, auth.uid(), 'released', v_summary);
    update public.complaints set status = 'answered' where id = v_complaint;
    insert into public.complaint_events (complaint_id, status, actor, note) values (v_complaint, 'answered', 'platform', 'Resposta da empresa revisada e liberada ao trabalhador.');
  elsif p_decision = 'returned' then
    if v_reason is null or char_length(v_reason) not between 10 and 500 then
      raise exception 'Explique à empresa o motivo da devolução com 10 a 500 caracteres.' using errcode = 'P0001';
    end if;
    update public.company_responses set review_status = 'returned' where id = p_response;
    insert into public.company_response_reviews (response_id, reviewer_id, decision, reason) values (p_response, auth.uid(), 'returned', v_reason);
    -- Volta ao estado anterior à resposta: 'answered' se já houve resposta liberada, senão 'shared'.
    -- Sem evento em complaint_events: a devolução não aparece para o trabalhador (ADR-0013, D2).
    update public.complaints
      set status = case when exists (select 1 from public.company_responses r where r.complaint_id = v_complaint and r.review_status = 'released')
                        then 'answered'::public.complaint_status else 'shared'::public.complaint_status end
      where id = v_complaint;
  else
    raise exception 'Decisão inválida.' using errcode = 'P0001';
  end if;
end;
$$;

-- Correção da descrição já liberada: motivo obrigatório, nova linha na trilha, data visível ao trabalhador.
create function public.ops_correct_response_summary(p_response uuid, p_summary text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_review text; v_summary text := btrim(coalesce(p_summary, '')); v_reason text := btrim(coalesce(p_reason, ''));
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select review_status into v_review from public.company_responses where id = p_response for update;
  if v_review is null then raise exception 'Resposta não encontrada.' using errcode = 'P0001'; end if;
  if v_review <> 'released' then raise exception 'Só a descrição de uma resposta liberada pode ser corrigida.' using errcode = 'P0001'; end if;
  if char_length(v_summary) not between 30 and 1000 then raise exception 'Escreva a descrição para o trabalhador com 30 a 1.000 caracteres.' using errcode = 'P0001'; end if;
  if char_length(v_reason) not between 10 and 500 then raise exception 'Informe o motivo da correção com 10 a 500 caracteres.' using errcode = 'P0001'; end if;
  update public.company_responses set worker_summary = v_summary, summary_corrected_at = now() where id = p_response;
  insert into public.company_response_reviews (response_id, reviewer_id, decision, worker_summary, reason)
  values (p_response, auth.uid(), 'summary_corrected', v_summary, v_reason);
end;
$$;

-- 6) Avaliação do trabalhador ("valeu a pena?"): só o dono, só resposta liberada, uma vez.
create function public.rate_response(p_response uuid, p_rating public.complaint_feedback, p_comment text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_complaint uuid; v_review text; v_worker uuid; v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
begin
  select r.complaint_id, r.review_status, c.worker_id into v_complaint, v_review, v_worker
  from public.company_responses r join public.complaints c on c.id = r.complaint_id where r.id = p_response;
  if v_complaint is null or not public.owns_complaint(v_complaint) or v_review <> 'released' then
    raise exception 'Resposta não disponível para avaliação.' using errcode = 'P0001';
  end if;
  if p_rating is null then raise exception 'Escolha uma avaliação.' using errcode = 'P0001'; end if;
  if char_length(coalesce(v_comment, '')) > 300 then raise exception 'O comentário pode ter até 300 caracteres.' using errcode = 'P0001'; end if;
  begin
    insert into public.response_ratings (response_id, worker_id, rating, comment) values (p_response, v_worker, p_rating, v_comment);
  exception when unique_violation then raise exception 'Você já avaliou esta resposta.' using errcode = 'P0001'; end;
end;
$$;

-- O trabalhador lê as próprias avaliações (para mostrar "já avaliada").
create function public.my_response_ratings(p_complaint uuid)
returns table (response_id uuid, rating public.complaint_feedback, comment text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select rr.response_id, rr.rating, rr.comment, rr.created_at
  from public.response_ratings rr join public.company_responses r on r.id = rr.response_id
  where r.complaint_id = p_complaint and public.owns_complaint(p_complaint);
$$;

-- A própria empresa vê só o agregado das avaliações, e só com 3 ou mais: abaixo disso, contagem e faixa nulas
-- (com 1 avaliação, a empresa saberia quem avaliou). Fora do ranking.
create function public.my_company_satisfaction()
returns table (company_id uuid, ratings integer, satisfaction_band text)
language sql stable security definer set search_path = '' as $$
  select cu.company_id, case when count(rr.response_id) < 3 then null else count(rr.response_id)::int end,
         case when count(rr.response_id) < 3 then null
              else private.response_band(100.0 * avg(case rr.rating when 'yes' then 1 when 'partial' then 0.5 else 0 end)) end
  from public.company_users cu
  left join public.company_responses r on r.company_id = cu.company_id
  left join public.response_ratings rr on rr.response_id = r.id
  where cu.user_id = auth.uid()
  group by cu.company_id;
$$;

-- 7) A empresa continua vendo o caso enquanto a resposta está em revisão.
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
  where c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_company_user(c.company_id)
  order by c.created_at desc;
$$;

-- Linha da empresa: eventos posteriores à liberação, as próprias respostas e o resultado da revisão
-- (liberada ou devolvida com motivo). Nunca a descrição da equipe. Mesmo critério de ordem da 20261109120000.
create or replace function public.get_company_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.kind, t.status, t.actor, t.content, t.created_at
  from (
    select 'event'::text as kind, e.status, e.actor, e.note as content, e.created_at, 4 as kind_rank, e.id
    from public.complaint_events e
    join public.complaints c on c.id = e.complaint_id
    where e.complaint_id = p_id and c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_company_user(c.company_id)
      and e.status in ('shared', 'answered', 'closed')
    union all
    select 'response'::text, null::public.complaint_status, 'company'::public.complaint_actor, r.content, r.created_at, 2, r.id
    from public.company_responses r
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and public.is_company_user(c.company_id)
    union all
    select 'response_review'::text, null::public.complaint_status, 'platform'::public.complaint_actor,
           case rv.decision when 'released' then 'Resposta liberada ao trabalhador.' else 'Resposta devolvida para ajuste: ' || rv.reason end,
           rv.created_at, 1, rv.id
    from public.company_response_reviews rv
    join public.company_responses r on r.id = rv.response_id
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and rv.decision in ('released', 'returned') and public.is_company_user(c.company_id)
  ) t
  order by t.created_at, t.kind_rank, t.status nulls first, t.id;
$$;

-- Linha da equipe: inclui as decisões sobre respostas.
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
    select 'response_review'::text, null::public.complaint_status, 'platform'::public.complaint_actor,
           case rr.decision when 'released' then 'Resposta liberada · ' || rr.worker_summary
                            when 'returned' then 'Resposta devolvida · ' || rr.reason
                            else 'Descrição corrigida · ' || rr.reason end, rr.created_at, 1, rr.id
    from public.company_response_reviews rr join public.company_responses r on r.id = rr.response_id where r.complaint_id = p_id
    union all
    select 'access'::text, null::public.complaint_status, 'platform'::public.complaint_actor, 'Relato original consultado · ' || a.justification, a.created_at, 3, a.id
    from public.original_access_log a where a.complaint_id = p_id
  ) t
  order by t.created_at, t.kind_rank, t.status nulls first, t.id;
end;
$$;

-- 8) Responsividade (TASK-0036): o caso em revisão de resposta continua liberado à empresa, e só conta como respondido
--    quando há resposta liberada; o prazo vai até o envio (created_at) da primeira resposta que foi liberada (ADR-0013, D6).
create or replace function private.company_response_stats()
returns table (company_id uuid, released integer, answered integer, rate numeric, avg_hours numeric)
language sql stable security definer set search_path = '' as $$
  with base as (
    select c.company_id,
           coalesce((select min(e.created_at) from public.complaint_events e where e.complaint_id = c.id and e.status = 'shared'), c.created_at) as released_at,
           (select min(r.created_at) from public.company_responses r where r.complaint_id = c.id and r.review_status = 'released') as first_response
    from public.complaints c where c.status in ('shared', 'answer_in_review', 'answered', 'closed')
  )
  select b.company_id, count(*)::int, count(b.first_response)::int,
         100.0 * count(b.first_response) / count(*),
         avg(extract(epoch from (b.first_response - b.released_at)) / 3600) filter (where b.first_response is not null)
  from base b group by b.company_id;
$$;

-- company_ranking (a ser removida depois do front da TASK-0036) passa a usar o mesmo cálculo, para não perder os casos
-- com resposta em revisão nem contar resposta não liberada enquanto ainda estiver no ar. Mesma assinatura e ordem.
create or replace function public.company_ranking()
returns table (company_id uuid, name text, city text, state text, received integer, response_rate integer, avg_first_response_hours integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state, s.released, round(s.rate)::int, round(s.avg_hours)::int,
         public.is_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by 6 desc, 7 asc nulls last;
$$;

-- 9) Contagens da equipe e métricas com a fila de respostas.
create or replace function public.ops_list_companies()
returns table (id uuid, name text, legal_name text, city text, state text, created_at timestamptz, users integer,
               complaints integer, released integer, answered integer, has_contact boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), co.legal_name, a.city, a.state, co.created_at,
         (select count(*)::int from public.company_users cu where cu.company_id = co.id),
         (select count(*)::int from public.complaints c where c.company_id = co.id and c.status not in ('received', 'canceled')),
         (select count(*)::int from public.complaints c where c.company_id = co.id and c.status in ('shared', 'answer_in_review', 'answered', 'closed')),
         (select count(*)::int from public.complaints c where c.company_id = co.id and c.status in ('answered', 'closed')),
         (co.contact_email is not null or co.contact_phone is not null)
  from public.companies co join public.addresses a on a.id = co.address_id
  order by 2;
end;
$$;

create or replace function public.ops_metrics()
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
    'responses_in_review', (select count(*) from public.company_responses where review_status = 'in_review'),
    'avg_hours_response_review', (select round(avg(extract(epoch from (rv.created_at - r.created_at)) / 3600)::numeric, 1)
       from public.company_response_reviews rv join public.company_responses r on r.id = rv.response_id
       where rv.decision in ('released', 'returned')),
    'weekly', coalesce((select jsonb_agg(jsonb_build_object('week', to_char(w, 'DD/MM'), 'total', total) order by w)
       from (select date_trunc('week', created_at) as w, count(*) as total from public.complaints
             where created_at > now() - interval '8 weeks' group by 1) x), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

revoke execute on function public.ops_list_responses(text), public.ops_decide_response(uuid, text, text, text),
  public.ops_correct_response_summary(uuid, text, text), public.rate_response(uuid, public.complaint_feedback, text),
  public.my_response_ratings(uuid), public.my_company_satisfaction() from public, anon;
grant execute on function public.ops_list_responses(text), public.ops_decide_response(uuid, text, text, text),
  public.ops_correct_response_summary(uuid, text, text), public.rate_response(uuid, public.complaint_feedback, text),
  public.my_response_ratings(uuid), public.my_company_satisfaction() to authenticated;
