-- TASK-0028 / ADR-0011: pedidos comerciais separados de relatos e de contas de empresas.
-- Provisionar integrantes da equipe em private.platform_admins por operação controlada.
create table if not exists private.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
revoke all on private.platform_admins from public, anon, authenticated;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.platform_admins where user_id = auth.uid());
$$;
revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

create table public.contact_solicitations (
  id uuid primary key default gen_random_uuid(),
  profile text not null check (profile in ('worker', 'company', 'partner', 'sponsor')),
  landing_origin text not null check (landing_origin in ('worker', 'company', 'partner', 'intelligence', 'sponsor')),
  full_name text not null check (char_length(btrim(full_name)) between 2 and 120),
  email text not null check (char_length(email) between 5 and 254 and email = lower(btrim(email))),
  phone text not null check (phone ~ '^[0-9]{10,11}$'),
  organization_name text check (organization_name is null or char_length(organization_name) between 2 and 120),
  status text not null default 'waiting_contact' check (status in ('waiting_contact', 'contacted')),
  created_at timestamptz not null default now(),
  contacted_at timestamptz,
  contacted_by uuid references auth.users(id),
  constraint contact_solicitations_contact_state check (
    (status = 'waiting_contact' and contacted_at is null and contacted_by is null)
    or (status = 'contacted' and contacted_at is not null and contacted_by is not null)
  )
);
create index contact_solicitations_queue_idx on public.contact_solicitations (status, created_at desc);
create index contact_solicitations_profile_idx on public.contact_solicitations (profile, created_at desc);
create index contact_solicitations_email_recent_idx on public.contact_solicitations (email, created_at desc);
alter table public.contact_solicitations enable row level security;
revoke all on public.contact_solicitations from public, anon, authenticated;

create or replace function public.submit_contact_solicitation(
  p_profile text, p_origin text, p_name text, p_email text, p_phone text, p_organization text default null,
  p_website text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_org text := nullif(btrim(coalesce(p_organization, '')), '');
begin
  -- Honeypot: mesma resposta de sucesso para não alimentar automações.
  if nullif(btrim(coalesce(p_website, '')), '') is not null then return; end if;
  if p_profile not in ('worker', 'company', 'partner', 'sponsor')
     or p_origin not in ('worker', 'company', 'partner', 'intelligence', 'sponsor')
     or (p_origin = 'intelligence' and p_profile <> 'company')
     or (p_origin <> 'intelligence' and p_origin <> p_profile)
     or char_length(v_name) not between 2 and 120
     or char_length(v_email) not between 5 and 254
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or v_phone !~ '^[0-9]{10,11}$'
     or (v_org is not null and char_length(v_org) not between 2 and 120)
  then raise exception 'dados de contato inválidos' using errcode = '22023'; end if;

  -- Uma solicitação por endereço em 15 minutos; não revela se o e-mail já consta.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email, 0));
  if exists (select 1 from public.contact_solicitations where email = v_email and created_at > now() - interval '15 minutes') then return; end if;
  insert into public.contact_solicitations (profile, landing_origin, full_name, email, phone, organization_name)
  values (p_profile, p_origin, v_name, v_email, v_phone, v_org);
end;
$$;
revoke all on function public.submit_contact_solicitation(text, text, text, text, text, text, text) from public;
grant execute on function public.submit_contact_solicitation(text, text, text, text, text, text, text) to anon, authenticated;

create or replace function public.list_contact_solicitations(p_status text default null, p_profile text default null)
returns table (id uuid, profile text, landing_origin text, full_name text, email text, phone text,
  organization_name text, status text, created_at timestamptz, contacted_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_status is not null and p_status not in ('waiting_contact', 'contacted') then raise exception 'filtro inválido' using errcode = '22023'; end if;
  if p_profile is not null and p_profile not in ('worker', 'company', 'partner', 'sponsor') then raise exception 'filtro inválido' using errcode = '22023'; end if;
  return query
    select c.id, c.profile, c.landing_origin, c.full_name, c.email, c.phone, c.organization_name,
      c.status, c.created_at, c.contacted_at
    from public.contact_solicitations c
    where (p_status is null or c.status = p_status) and (p_profile is null or c.profile = p_profile)
    order by c.created_at desc limit 200;
end;
$$;
revoke all on function public.list_contact_solicitations(text, text) from public, anon;
grant execute on function public.list_contact_solicitations(text, text) to authenticated;

create or replace function public.set_contact_solicitation_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_status not in ('waiting_contact', 'contacted') then raise exception 'status inválido' using errcode = '22023'; end if;
  update public.contact_solicitations
  set status = p_status,
      contacted_at = case when p_status = 'contacted' then now() else null end,
      contacted_by = case when p_status = 'contacted' then auth.uid() else null end
  where id = p_id and status <> p_status;
  if not found then
    if not exists (select 1 from public.contact_solicitations where id = p_id) then
      raise exception 'solicitação não encontrada' using errcode = 'P0002';
    end if;
  end if;
end;
$$;
revoke all on function public.set_contact_solicitation_status(uuid, text) from public, anon;
grant execute on function public.set_contact_solicitation_status(uuid, text) to authenticated;
