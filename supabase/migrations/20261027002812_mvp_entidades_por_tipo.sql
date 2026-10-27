-- ADR-0009 (revisão v2) / TASK-0022: entidades por tipo, endereço próprio e mídia de parceiros.
-- Substitui o modelo com coluna "persona" (20261026235534), ainda sem dados reais.

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();
drop table if exists public.subscriptions, public.organization_members, public.organizations, public.profiles, public.plans;
drop function if exists public.is_org_member(uuid);
drop type if exists public.persona, public.organization_kind;

create type public.plan_audience as enum ('company', 'partner', 'sponsor');
create type public.street_type as enum ('street', 'avenue', 'alley', 'boulevard', 'square', 'road', 'highway', 'other');
create type public.document_type as enum ('cpf', 'cnpj');
create type public.media_kind as enum ('image', 'video');

-- Catálogo espelha src/commercial.ts; valores demonstrativos.
create table public.plans (
  id text primary key,
  audience public.plan_audience not null,
  name text not null,
  monthly_cents integer check (monthly_cents is null or monthly_cents > 0)
);

insert into public.plans (id, audience, name, monthly_cents) values
  ('company-essential', 'company', 'Essencial', 150000),
  ('company-management', 'company', 'Gestão', 390000),
  ('company-multi', 'company', 'Multiunidade', null),
  ('partner-presence', 'partner', 'Presença', 24900),
  ('partner-professional', 'partner', 'Profissional', 49900),
  ('partner-national', 'partner', 'Nacional', 89900),
  ('sponsor-content', 'sponsor', 'Conteúdo', null),
  ('sponsor-event', 'sponsor', 'Evento', null),
  ('sponsor-study', 'sponsor', 'Estudo público', null);

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  zip_code text not null check (zip_code ~ '^\d{8}$'),
  street_type public.street_type not null,
  street_name text not null check (char_length(street_name) between 1 and 200),
  number text not null check (char_length(number) between 1 and 20),
  complement text check (complement is null or char_length(complement) <= 100),
  neighborhood text check (neighborhood is null or char_length(neighborhood) <= 120),
  city text not null check (char_length(city) between 1 and 120),
  state text not null check (state ~ '^[A-Z]{2}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  full_name text not null check (char_length(full_name) between 1 and 160),
  cpf text not null check (cpf ~ '^\d{11}$'),
  address_id uuid not null unique references public.addresses (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null check (char_length(legal_name) between 1 and 160),
  trade_name text check (trade_name is null or char_length(trade_name) <= 160),
  cnpj text not null unique check (cnpj ~ '^\d{14}$'),
  address_id uuid not null unique references public.addresses (id) on delete restrict,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.company_users (
  company_id uuid not null references public.companies (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.member_role not null default 'member',
  created_at timestamptz not null default now(),
  primary key (company_id, user_id)
);
create index company_users_user_idx on public.company_users (user_id);

create table public.partners (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 160),
  document_type public.document_type not null,
  document text not null,
  specialty text not null check (char_length(specialty) between 1 and 120),
  description text check (description is null or char_length(description) <= 2000),
  avatar_media_id uuid,
  address_id uuid not null unique references public.addresses (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint partner_document_format check (
    (document_type = 'cpf' and document ~ '^\d{11}$') or (document_type = 'cnpj' and document ~ '^\d{14}$')
  )
);

create table public.sponsors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 160),
  cnpj text not null check (cnpj ~ '^\d{14}$'),
  address_id uuid not null unique references public.addresses (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Imagens no bucket partner-media; vídeos somente por link externo (custo do plano gratuito).
create table public.media (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners (id) on delete cascade,
  kind public.media_kind not null,
  storage_path text,
  external_url text,
  mime_type text,
  size_bytes integer check (size_bytes is null or size_bytes between 1 and 5242880),
  created_at timestamptz not null default now(),
  constraint media_source check (
    (kind = 'image' and storage_path is not null and external_url is null and mime_type in ('image/jpeg', 'image/png', 'image/webp'))
    or (kind = 'video' and external_url ~ '^https://' and storage_path is null)
  )
);
create index media_partner_idx on public.media (partner_id);

alter table public.partners
  add constraint partners_avatar_media_fk foreign key (avatar_media_id) references public.media (id) on delete set null;

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies (id) on delete cascade,
  partner_id uuid references public.partners (id) on delete cascade,
  sponsor_id uuid references public.sponsors (id) on delete cascade,
  plan_id text not null references public.plans (id),
  mode public.subscription_mode not null,
  status public.subscription_status not null,
  next_billing_at timestamptz,
  paid_cents integer not null default 0 check (paid_cents >= 0),
  created_at timestamptz not null default now(),
  constraint subscription_single_owner check (num_nonnulls(company_id, partner_id, sponsor_id) = 1)
);
create index subscriptions_company_idx on public.subscriptions (company_id);
create index subscriptions_partner_idx on public.subscriptions (partner_id);
create index subscriptions_sponsor_idx on public.subscriptions (sponsor_id);

create trigger addresses_touch before update on public.addresses for each row execute function public.touch_updated_at();
create trigger workers_touch before update on public.workers for each row execute function public.touch_updated_at();
create trigger companies_touch before update on public.companies for each row execute function public.touch_updated_at();
create trigger partners_touch before update on public.partners for each row execute function public.touch_updated_at();
create trigger sponsors_touch before update on public.sponsors for each row execute function public.touch_updated_at();

-- Funções auxiliares de autorização (security definer evita recursão de RLS).
create function public.is_company_user(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.company_users where company_id = p_company and user_id = auth.uid());
$$;

create function public.is_company_owner(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.company_users where company_id = p_company and user_id = auth.uid() and role = 'owner');
$$;

create function public.owns_address(p_address uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.workers where address_id = p_address and user_id = auth.uid())
      or exists (select 1 from public.partners where address_id = p_address and user_id = auth.uid())
      or exists (select 1 from public.sponsors where address_id = p_address and user_id = auth.uid())
      or exists (
        select 1 from public.companies c join public.company_users cu on cu.company_id = c.id
        where c.address_id = p_address and cu.user_id = auth.uid()
      );
$$;

-- Avatar precisa ser uma imagem do próprio parceiro.
create function public.check_partner_avatar()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.avatar_media_id is not null and not exists (
    select 1 from public.media where id = new.avatar_media_id and partner_id = new.id and kind = 'image'
  ) then
    raise exception 'avatar inválido' using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger partners_check_avatar before update of avatar_media_id on public.partners
  for each row execute function public.check_partner_avatar();

alter table public.plans enable row level security;
alter table public.addresses enable row level security;
alter table public.workers enable row level security;
alter table public.companies enable row level security;
alter table public.company_users enable row level security;
alter table public.partners enable row level security;
alter table public.sponsors enable row level security;
alter table public.media enable row level security;
alter table public.subscriptions enable row level security;

create policy plans_read on public.plans for select to anon, authenticated using (true);
create policy addresses_read on public.addresses for select to authenticated using (public.owns_address(id));
create policy addresses_update on public.addresses for update to authenticated using (public.owns_address(id)) with check (public.owns_address(id));
create policy workers_read on public.workers for select to authenticated using (user_id = (select auth.uid()));
create policy workers_update on public.workers for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy companies_read on public.companies for select to authenticated using (public.is_company_user(id));
create policy companies_update on public.companies for update to authenticated using (public.is_company_owner(id)) with check (public.is_company_owner(id));
create policy company_users_read on public.company_users for select to authenticated using (user_id = (select auth.uid()));
create policy partners_read on public.partners for select to authenticated using (user_id = (select auth.uid()));
create policy partners_update on public.partners for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy sponsors_read on public.sponsors for select to authenticated using (user_id = (select auth.uid()));
create policy sponsors_update on public.sponsors for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy media_read on public.media for select to authenticated
  using (exists (select 1 from public.partners p where p.id = partner_id and p.user_id = (select auth.uid())));
create policy media_insert on public.media for insert to authenticated
  with check (exists (select 1 from public.partners p where p.id = partner_id and p.user_id = (select auth.uid())));
create policy media_delete on public.media for delete to authenticated
  using (exists (select 1 from public.partners p where p.id = partner_id and p.user_id = (select auth.uid())));
create policy subscriptions_read on public.subscriptions for select to authenticated using (
  (company_id is not null and public.is_company_user(company_id))
  or exists (select 1 from public.partners p where p.id = partner_id and p.user_id = (select auth.uid()))
  or exists (select 1 from public.sponsors s where s.id = sponsor_id and s.user_id = (select auth.uid()))
);

revoke all on public.plans, public.addresses, public.workers, public.companies, public.company_users,
  public.partners, public.sponsors, public.media, public.subscriptions from anon, authenticated;
grant select on public.plans to anon, authenticated;
grant select on public.addresses, public.workers, public.companies, public.company_users,
  public.partners, public.sponsors, public.media, public.subscriptions to authenticated;
grant update (zip_code, street_type, street_name, number, complement, neighborhood, city, state) on public.addresses to authenticated;
grant update (full_name) on public.workers to authenticated;
grant update (legal_name, trade_name) on public.companies to authenticated;
grant update (display_name, specialty, description, avatar_media_id) on public.partners to authenticated;
grant update (name) on public.sponsors to authenticated;
grant insert (partner_id, kind, storage_path, external_url, mime_type, size_bytes), delete on public.media to authenticated;

revoke execute on function public.is_company_user(uuid), public.is_company_owner(uuid), public.owns_address(uuid) from public, anon;
grant execute on function public.is_company_user(uuid), public.is_company_owner(uuid), public.owns_address(uuid) to authenticated;

-- Criação de perfis fica fora da API exposta; chamada pelo trigger de cadastro e por add_profile().
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.create_address(a jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if a is null then raise exception 'endereço obrigatório' using errcode = '22023'; end if;
  insert into public.addresses (zip_code, street_type, street_name, number, complement, neighborhood, city, state)
  values (
    regexp_replace(a ->> 'zip_code', '\D', '', 'g'),
    (a ->> 'street_type')::public.street_type,
    btrim(a ->> 'street_name'),
    btrim(a ->> 'number'),
    nullif(btrim(a ->> 'complement'), ''),
    nullif(btrim(a ->> 'neighborhood'), ''),
    btrim(a ->> 'city'),
    upper(btrim(a ->> 'state'))
  )
  returning id into v_id;
  return v_id;
end;
$$;

create function private.create_subscription(p_audience public.plan_audience, p jsonb, p_company uuid, p_partner uuid, p_sponsor uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_plan public.plans%rowtype;
  v_mode public.subscription_mode;
begin
  select * into v_plan from public.plans where id = p ->> 'plan_id';
  if not found or v_plan.audience <> p_audience then
    raise exception 'plano incompatível com o tipo de conta' using errcode = '22023';
  end if;
  v_mode := (p ->> 'subscription_mode')::public.subscription_mode;
  if v_mode is null then raise exception 'modalidade obrigatória' using errcode = '22023'; end if;
  -- Trial: um mês de calendário. Pagamento continua simulado (ADR-0005).
  insert into public.subscriptions (company_id, partner_id, sponsor_id, plan_id, mode, status, next_billing_at)
  values (
    p_company, p_partner, p_sponsor, v_plan.id, v_mode,
    case when v_mode = 'trial' then 'trialing'::public.subscription_status else 'pending'::public.subscription_status end,
    case when v_mode = 'trial' then now() + interval '1 month' end
  );
end;
$$;

create function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
begin
  if p_user is null then raise exception 'usuário obrigatório' using errcode = '22023'; end if;
  if p is null then raise exception 'dados do cadastro obrigatórios' using errcode = '22023'; end if;
  if p_type not in ('worker', 'company', 'partner', 'sponsor') then
    raise exception 'tipo de conta inválido' using errcode = '22023';
  end if;

  v_address := private.create_address(p -> 'address');

  if p_type = 'worker' then
    insert into public.workers (user_id, full_name, cpf, address_id)
    values (p_user, btrim(p ->> 'full_name'), regexp_replace(p ->> 'cpf', '\D', '', 'g'), v_address)
    returning id into v_id;
  elsif p_type = 'company' then
    insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
    values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), regexp_replace(p ->> 'cnpj', '\D', '', 'g'), v_address, p_user)
    returning id into v_id;
    insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
    perform private.create_subscription('company', p, v_id, null, null);
  elsif p_type = 'partner' then
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type,
      regexp_replace(p ->> 'document', '\D', '', 'g'), btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address
    )
    returning id into v_id;
    perform private.create_subscription('partner', p, null, v_id, null);
  else
    insert into public.sponsors (user_id, name, cnpj, address_id)
    values (p_user, btrim(p ->> 'name'), regexp_replace(p ->> 'cnpj', '\D', '', 'g'), v_address)
    returning id into v_id;
    perform private.create_subscription('sponsor', p, null, null, v_id);
  end if;
  return v_id;
end;
$$;

create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  perform private.create_profile(new.id, meta ->> 'signup_type', meta -> 'signup');
  -- Documentos e endereço não devem circular no JWT (user_metadata).
  update auth.users set raw_user_meta_data = jsonb_build_object('full_name', meta ->> 'full_name') where id = new.id;
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Conta já autenticada adiciona outro tipo de perfil (ex.: trabalhadora que também é parceira).
create function public.add_profile(p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'não autenticado' using errcode = '42501'; end if;
  return private.create_profile(auth.uid(), p_type, p);
end;
$$;
revoke execute on function public.add_profile(text, jsonb) from public, anon;
grant execute on function public.add_profile(text, jsonb) to authenticated;

-- Perfis da conta atual; o front decide o portal a partir daqui.
create function public.current_profiles()
returns table (profile_type text, profile_id uuid, display_name text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select 'worker', w.id, w.full_name, w.created_at from public.workers w where w.user_id = auth.uid()
  union all
  select 'company', c.id, coalesce(c.trade_name, c.legal_name), c.created_at
    from public.companies c join public.company_users cu on cu.company_id = c.id where cu.user_id = auth.uid()
  union all
  select 'partner', p.id, p.display_name, p.created_at from public.partners p where p.user_id = auth.uid()
  union all
  select 'sponsor', s.id, s.name, s.created_at from public.sponsors s where s.user_id = auth.uid()
  order by 4;
$$;
revoke execute on function public.current_profiles() from public, anon;
grant execute on function public.current_profiles() to authenticated;

-- Diretório de parceiros para empresas: sem documento nem endereço completo.
create function public.list_partner_directory()
returns table (id uuid, display_name text, specialty text, description text, avatar_path text, city text, state text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name, p.specialty, p.description, m.storage_path, a.city, a.state
  from public.partners p
  join public.addresses a on a.id = p.address_id
  left join public.media m on m.id = p.avatar_media_id
  where exists (select 1 from public.company_users cu where cu.user_id = auth.uid())
  order by p.display_name;
$$;
revoke execute on function public.list_partner_directory() from public, anon;
grant execute on function public.list_partner_directory() to authenticated;

-- Fotos públicas de perfil; escrita só na pasta do próprio parceiro (<partner_id>/arquivo).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('partner-media', 'partner-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy partner_media_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'partner-media'
  and (storage.foldername(name))[1] in (select p.id::text from public.partners p where p.user_id = (select auth.uid()))
);
create policy partner_media_delete on storage.objects for delete to authenticated using (
  bucket_id = 'partner-media'
  and (storage.foldername(name))[1] in (select p.id::text from public.partners p where p.user_id = (select auth.uid()))
);
