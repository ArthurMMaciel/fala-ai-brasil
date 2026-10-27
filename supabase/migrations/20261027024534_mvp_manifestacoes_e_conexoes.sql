-- Modelo v3 aprovado pelo responsável em 2026-10-27 (ADR-0009 / TASK-0022).
-- Manifestações com relato original separado da versão compartilhável revisada pelo trabalhador.
-- A empresa nunca lê o original nem o identificador do trabalhador: acesso apenas por funções que omitem esses campos.

create type public.complaint_status as enum ('received', 'shared', 'answered', 'closed', 'canceled');
create type public.complaint_actor as enum ('worker', 'company', 'platform');
create type public.complaint_feedback as enum ('yes', 'partial', 'no');
create type public.connection_stage as enum ('company_interest', 'partner_contacted', 'client');

create sequence public.complaint_protocol_seq start 1001;

create table public.complaints (
  id uuid primary key default gen_random_uuid(),
  protocol text not null unique default ('EAB-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY') || '-' || lpad(nextval('public.complaint_protocol_seq')::text, 4, '0')),
  worker_id uuid not null references public.workers (id) on delete cascade,
  company_id uuid not null references public.companies (id) on delete cascade,
  category text not null check (char_length(category) between 2 and 80),
  title text not null check (char_length(title) between 3 and 140),
  incident_period text check (incident_period is null or char_length(incident_period) <= 80),
  recurrence text check (recurrence is null or char_length(recurrence) <= 80),
  expected_outcomes text[] not null default '{}',
  status public.complaint_status not null default 'received',
  worker_feedback public.complaint_feedback,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);
create index complaints_worker_idx on public.complaints (worker_id);
create index complaints_company_idx on public.complaints (company_id, status);

-- Relato original: somente o próprio trabalhador lê.
create table public.complaint_originals (
  complaint_id uuid primary key references public.complaints (id) on delete cascade,
  original_content text not null check (char_length(original_content) between 10 and 5000)
);

-- Versão compartilhável revisada e confirmada pelo trabalhador; é o único texto que a empresa recebe.
create table public.complaint_shared_versions (
  complaint_id uuid primary key references public.complaints (id) on delete cascade,
  shared_content text not null check (char_length(shared_content) between 10 and 5000),
  confirmed_by_worker_at timestamptz not null default now()
);

create table public.complaint_events (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.complaints (id) on delete cascade,
  status public.complaint_status not null,
  actor public.complaint_actor not null,
  note text not null check (char_length(note) between 2 and 500),
  created_at timestamptz not null default now()
);
create index complaint_events_complaint_idx on public.complaint_events (complaint_id, created_at);

create table public.company_responses (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.complaints (id) on delete cascade,
  company_id uuid not null references public.companies (id) on delete cascade,
  author_user_id uuid references auth.users (id) on delete set null,
  content text not null check (char_length(content) between 10 and 5000),
  created_at timestamptz not null default now()
);
create index company_responses_complaint_idx on public.company_responses (complaint_id, created_at);

create table public.partner_connections (
  partner_id uuid not null references public.partners (id) on delete cascade,
  company_id uuid not null references public.companies (id) on delete cascade,
  stage public.connection_stage not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (partner_id, company_id)
);
create index partner_connections_company_idx on public.partner_connections (company_id);

create trigger complaints_touch before update on public.complaints for each row execute function public.touch_updated_at();
create trigger partner_connections_touch before update on public.partner_connections for each row execute function public.touch_updated_at();

alter table public.complaints enable row level security;
alter table public.complaint_originals enable row level security;
alter table public.complaint_shared_versions enable row level security;
alter table public.complaint_events enable row level security;
alter table public.company_responses enable row level security;
alter table public.partner_connections enable row level security;

create function public.owns_complaint(p_complaint uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.complaints c join public.workers w on w.id = c.worker_id
    where c.id = p_complaint and w.user_id = auth.uid()
  );
$$;
revoke execute on function public.owns_complaint(uuid) from public, anon;
grant execute on function public.owns_complaint(uuid) to authenticated;

-- Leitura direta das tabelas só para o trabalhador dono; empresa e parceiro usam as funções abaixo.
create policy complaints_read_worker on public.complaints for select to authenticated using (public.owns_complaint(id));
create policy originals_read_worker on public.complaint_originals for select to authenticated using (public.owns_complaint(complaint_id));
create policy shared_read_worker on public.complaint_shared_versions for select to authenticated using (public.owns_complaint(complaint_id));
create policy events_read_worker on public.complaint_events for select to authenticated using (public.owns_complaint(complaint_id));
create policy responses_read_worker on public.company_responses for select to authenticated using (public.owns_complaint(complaint_id));
create policy connections_read_partner on public.partner_connections for select to authenticated
  using (exists (select 1 from public.partners p where p.id = partner_id and p.user_id = (select auth.uid())));
create policy connections_read_company on public.partner_connections for select to authenticated using (public.is_company_user(company_id));

revoke all on public.complaints, public.complaint_originals, public.complaint_shared_versions, public.complaint_events,
  public.company_responses, public.partner_connections from anon, authenticated;
grant select on public.complaints, public.complaint_originals, public.complaint_shared_versions, public.complaint_events,
  public.company_responses, public.partner_connections to authenticated;

-- Diretório de empresas (nome e cidade) para o trabalhador escolher e o parceiro prospectar.
create function public.list_company_directory()
returns table (id uuid, name text, city text, state text)
language sql stable security definer set search_path = '' as $$
  select c.id, coalesce(c.trade_name, c.legal_name), a.city, a.state
  from public.companies c join public.addresses a on a.id = c.address_id
  where auth.uid() is not null
  order by 2;
$$;

-- Trabalhador cria a manifestação; com p_share a versão revisada segue para a empresa.
create function public.create_complaint(p jsonb, p_share boolean)
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
  if p_share and v_shared is null then raise exception 'Revise a versão que será compartilhada com a empresa.' using errcode = 'P0001'; end if;

  insert into public.complaints (worker_id, company_id, category, title, incident_period, recurrence, expected_outcomes, status)
  values (
    v_worker, (p ->> 'company_id')::uuid, btrim(p ->> 'category'), btrim(p ->> 'title'),
    nullif(btrim(p ->> 'incident_period'), ''), nullif(btrim(p ->> 'recurrence'), ''),
    coalesce(array(select jsonb_array_elements_text(p -> 'expected_outcomes')), '{}'),
    case when p_share then 'shared'::public.complaint_status else 'received'::public.complaint_status end
  )
  returning id into v_id;
  insert into public.complaint_originals (complaint_id, original_content) values (v_id, btrim(p ->> 'original_content'));
  insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'received', 'worker', 'Manifestação registrada.');
  if p_share then
    insert into public.complaint_shared_versions (complaint_id, shared_content) values (v_id, v_shared);
    insert into public.complaint_events (complaint_id, status, actor, note) values (v_id, 'shared', 'worker', 'Versão compartilhável confirmada e enviada à empresa.');
  end if;
  return v_id;
end;
$$;

-- Trabalhador compartilha depois uma manifestação guardada, ou encerra/avalia o retorno.
create function public.share_complaint(p_id uuid, p_shared text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.owns_complaint(p_id) then raise exception 'Manifestação não encontrada.' using errcode = 'P0001'; end if;
  if (select status from public.complaints where id = p_id) <> 'received' then raise exception 'Esta manifestação já foi compartilhada ou encerrada.' using errcode = 'P0001'; end if;
  insert into public.complaint_shared_versions (complaint_id, shared_content) values (p_id, btrim(p_shared));
  update public.complaints set status = 'shared' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note) values (p_id, 'shared', 'worker', 'Versão compartilhável confirmada e enviada à empresa.');
end;
$$;

create function public.close_complaint(p_id uuid, p_feedback public.complaint_feedback)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status public.complaint_status;
begin
  if not public.owns_complaint(p_id) then raise exception 'Manifestação não encontrada.' using errcode = 'P0001'; end if;
  select status into v_status from public.complaints where id = p_id;
  if v_status in ('closed', 'canceled') then raise exception 'Esta manifestação já foi encerrada.' using errcode = 'P0001'; end if;
  update public.complaints
    set status = case when v_status = 'received' then 'canceled'::public.complaint_status else 'closed'::public.complaint_status end,
        worker_feedback = p_feedback, closed_at = now()
    where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, case when v_status = 'received' then 'canceled'::public.complaint_status else 'closed'::public.complaint_status end, 'worker',
          case when v_status = 'received' then 'Manifestação cancelada antes de ser compartilhada.' else 'Trabalhador encerrou o acompanhamento.' end);
end;
$$;

-- Visão da empresa: somente manifestações compartilhadas, sem original e sem identificador do trabalhador.
create function public.list_company_complaints()
returns table (id uuid, protocol text, category text, title text, status public.complaint_status, shared_content text,
               created_at timestamptz, updated_at timestamptz, responses integer, last_response_at timestamptz, worker_feedback public.complaint_feedback)
language sql stable security definer set search_path = '' as $$
  select c.id, c.protocol, c.category, c.title, c.status, s.shared_content, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select max(r.created_at) from public.company_responses r where r.complaint_id = c.id),
         c.worker_feedback
  from public.complaints c
  join public.complaint_shared_versions s on s.complaint_id = c.id
  where c.status in ('shared', 'answered', 'closed') and public.is_company_user(c.company_id)
  order by c.created_at desc;
$$;

create function public.get_company_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select 'event', e.status, e.actor, e.note, e.created_at from public.complaint_events e
  join public.complaints c on c.id = e.complaint_id
  where e.complaint_id = p_id and c.status in ('shared', 'answered', 'closed') and public.is_company_user(c.company_id) and e.status <> 'received'
  union all
  select 'response', null, 'company', r.content, r.created_at from public.company_responses r
  join public.complaints c on c.id = r.complaint_id
  where r.complaint_id = p_id and public.is_company_user(c.company_id)
  order by 5;
$$;

create function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id;
  if v_company is null or not public.is_company_user(v_company) or v_status not in ('shared', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content) values (p_id, v_company, auth.uid(), btrim(p_content));
  update public.complaints set status = 'answered' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note) values (p_id, 'answered', 'company', 'Empresa enviou uma resposta institucional.');
end;
$$;

-- Ranking calculado: só empresas com pelo menos 3 manifestações compartilhadas (evita comparação injusta e reidentificação).
create function public.company_ranking()
returns table (company_id uuid, name text, city text, state text, received integer, response_rate integer, avg_first_response_hours integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  with base as (
    select c.company_id, c.id, c.created_at,
           (select min(r.created_at) from public.company_responses r where r.complaint_id = c.id) as first_response
    from public.complaints c where c.status in ('shared', 'answered', 'closed')
  )
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state,
         count(*)::int,
         round(100.0 * count(b.first_response) / count(*))::int,
         round(avg(extract(epoch from (b.first_response - b.created_at)) / 3600) filter (where b.first_response is not null))::int,
         public.is_company_user(co.id)
  from base b join public.companies co on co.id = b.company_id join public.addresses a on a.id = co.address_id
  where auth.uid() is not null
  group by co.id, co.trade_name, co.legal_name, a.city, a.state
  having count(*) >= 3
  order by 6 desc, 7 asc nulls last;
$$;

-- Hub de parceiros: empresas com o estágio da conexão do parceiro logado.
create function public.list_partner_companies()
returns table (id uuid, name text, legal_name text, city text, state text, stage public.connection_stage)
language sql stable security definer set search_path = '' as $$
  select c.id, coalesce(c.trade_name, c.legal_name), c.legal_name, a.city, a.state, pc.stage
  from public.companies c
  join public.addresses a on a.id = c.address_id
  join public.partners p on p.user_id = auth.uid()
  left join public.partner_connections pc on pc.company_id = c.id and pc.partner_id = p.id
  order by 2;
$$;

create function public.partner_set_connection(p_company uuid, p_stage public.connection_stage)
returns void language plpgsql security definer set search_path = '' as $$
declare v_partner uuid;
begin
  select id into v_partner from public.partners where user_id = auth.uid();
  if v_partner is null then raise exception 'Somente parceiros podem registrar contatos.' using errcode = 'P0001'; end if;
  if p_stage = 'company_interest' then raise exception 'Estágio inválido.' using errcode = 'P0001'; end if;
  insert into public.partner_connections (partner_id, company_id, stage) values (v_partner, p_company, p_stage)
  on conflict (partner_id, company_id) do update set stage = case
    when public.partner_connections.stage = 'client' then 'client'::public.connection_stage else excluded.stage end;
end;
$$;

-- Empresa sinaliza interesse em um parceiro do diretório (não sobrescreve estágio mais avançado).
create function public.company_request_partner(p_partner uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid;
begin
  select company_id into v_company from public.company_users where user_id = auth.uid() order by created_at limit 1;
  if v_company is null then raise exception 'Somente empresas podem sinalizar interesse.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.partners where id = p_partner) then raise exception 'Parceiro não encontrado.' using errcode = 'P0001'; end if;
  insert into public.partner_connections (partner_id, company_id, stage) values (p_partner, v_company, 'company_interest')
  on conflict (partner_id, company_id) do nothing;
end;
$$;

-- Diretório de parceiros passa a indicar se a empresa logada já sinalizou interesse.
drop function public.list_partner_directory();
create function public.list_partner_directory()
returns table (id uuid, display_name text, specialty text, description text, avatar_path text, city text, state text, requested boolean)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name, p.specialty, p.description, m.storage_path, a.city, a.state,
         exists (select 1 from public.partner_connections pc join public.company_users cu on cu.company_id = pc.company_id
                 where pc.partner_id = p.id and cu.user_id = auth.uid())
  from public.partners p
  join public.addresses a on a.id = p.address_id
  left join public.media m on m.id = p.avatar_media_id
  where exists (select 1 from public.company_users cu where cu.user_id = auth.uid())
  order by p.display_name;
$$;

-- Patrocinadores com campanha aprovada e vigente aparecem na landing pública.
create function public.list_public_sponsors()
returns table (id uuid, name text, campaign_title text, campaign_kind public.campaign_kind)
language sql stable security definer set search_path = '' as $$
  select distinct on (s.id) s.id, s.name, c.title, c.kind
  from public.sponsors s join public.campaigns c on c.sponsor_id = s.id
  where c.status = 'approved' and c.ends_at >= (now() at time zone 'America/Sao_Paulo')::date
  order by s.id, c.starts_at;
$$;

revoke execute on function public.list_company_directory(), public.create_complaint(jsonb, boolean), public.share_complaint(uuid, text),
  public.close_complaint(uuid, public.complaint_feedback), public.list_company_complaints(), public.get_company_complaint_timeline(uuid),
  public.respond_complaint(uuid, text), public.company_ranking(), public.list_partner_companies(),
  public.partner_set_connection(uuid, public.connection_stage), public.company_request_partner(uuid), public.list_partner_directory()
  from public, anon;
grant execute on function public.list_company_directory(), public.create_complaint(jsonb, boolean), public.share_complaint(uuid, text),
  public.close_complaint(uuid, public.complaint_feedback), public.list_company_complaints(), public.get_company_complaint_timeline(uuid),
  public.respond_complaint(uuid, text), public.company_ranking(), public.list_partner_companies(),
  public.partner_set_connection(uuid, public.connection_stage), public.company_request_partner(uuid), public.list_partner_directory()
  to authenticated;
revoke execute on function public.list_public_sponsors() from public;
grant execute on function public.list_public_sponsors() to anon, authenticated;
