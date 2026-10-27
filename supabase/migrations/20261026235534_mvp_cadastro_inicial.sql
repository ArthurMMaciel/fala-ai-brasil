-- ADR-0009 / TASK-0022: cadastro inicial do MVP.
-- Cliente nunca insere diretamente; o trigger em auth.users cria tudo em uma transação.

create type public.persona as enum ('worker', 'company', 'partner', 'sponsor');
create type public.organization_kind as enum ('company', 'partner', 'sponsor');
create type public.member_role as enum ('owner', 'member');
create type public.subscription_mode as enum ('trial', 'monthly', 'annual');
create type public.subscription_status as enum ('trialing', 'pending', 'active', 'expired');

-- Catálogo espelha src/commercial.ts; valores demonstrativos.
create table public.plans (
  id text primary key,
  audience public.organization_kind not null,
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

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  persona public.persona not null,
  full_name text not null check (char_length(full_name) between 1 and 160),
  cpf text check (cpf ~ '^\d{11}$'),
  postal_code text not null check (postal_code ~ '^\d{8}$'),
  street text not null check (char_length(street) between 1 and 200),
  street_number text not null check (char_length(street_number) between 1 and 20),
  complement text check (complement is null or char_length(complement) <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint worker_requires_cpf check (persona <> 'worker' or cpf is not null)
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  kind public.organization_kind not null,
  display_name text not null check (char_length(display_name) between 1 and 160),
  cnpj text check (cnpj ~ '^\d{14}$'),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint company_requires_cnpj check (kind <> 'company' or cnpj is not null)
);

create table public.organization_members (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.member_role not null default 'member',
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);
create index organization_members_user_idx on public.organization_members (user_id);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  plan_id text not null references public.plans (id),
  mode public.subscription_mode not null,
  status public.subscription_status not null,
  next_billing_at timestamptz,
  paid_cents integer not null default 0 check (paid_cents >= 0),
  created_at timestamptz not null default now()
);
create index subscriptions_organization_idx on public.subscriptions (organization_id);

-- Evita recursão de RLS ao consultar vínculos dentro de políticas.
create function public.is_org_member(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id = org and m.user_id = auth.uid()
  );
$$;

alter table public.plans enable row level security;
alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.subscriptions enable row level security;

create policy plans_read on public.plans for select to anon, authenticated using (true);
create policy profiles_read_own on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy organizations_read_member on public.organizations for select to authenticated using (public.is_org_member(id));
create policy members_read_own on public.organization_members for select to authenticated using (user_id = (select auth.uid()));
create policy subscriptions_read_member on public.subscriptions for select to authenticated using (public.is_org_member(organization_id));

-- Privilégios mínimos: leitura conforme RLS; atualização só de campos editáveis do próprio perfil.
revoke all on public.plans, public.profiles, public.organizations, public.organization_members, public.subscriptions from anon, authenticated;
grant select on public.plans to anon, authenticated;
grant select on public.profiles, public.organizations, public.organization_members, public.subscriptions to authenticated;
grant update (full_name, postal_code, street, street_number, complement) on public.profiles to authenticated;
revoke execute on function public.is_org_member(uuid) from public, anon;
grant execute on function public.is_org_member(uuid) to authenticated;

create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at before update on public.profiles
  for each row execute function public.touch_updated_at();

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_persona public.persona;
  v_plan public.plans%rowtype;
  v_mode public.subscription_mode;
  v_org uuid;
begin
  begin
    v_persona := (meta ->> 'persona')::public.persona;
  exception when others then
    raise exception 'persona inválida' using errcode = '22023';
  end;
  if v_persona is null then
    raise exception 'persona obrigatória' using errcode = '22023';
  end if;

  insert into public.profiles (id, persona, full_name, cpf, postal_code, street, street_number, complement)
  values (
    new.id,
    v_persona,
    btrim(meta ->> 'full_name'),
    case when v_persona = 'worker' then regexp_replace(meta ->> 'cpf', '\D', '', 'g') end,
    regexp_replace(meta ->> 'postal_code', '\D', '', 'g'),
    btrim(meta ->> 'street'),
    btrim(meta ->> 'street_number'),
    nullif(btrim(meta ->> 'complement'), '')
  );

  if v_persona <> 'worker' then
    select * into v_plan from public.plans where id = meta ->> 'plan_id';
    if not found or v_plan.audience::text <> v_persona::text then
      raise exception 'plano incompatível com a persona' using errcode = '22023';
    end if;
    begin
      v_mode := (meta ->> 'subscription_mode')::public.subscription_mode;
    exception when others then
      raise exception 'modalidade inválida' using errcode = '22023';
    end;
    if v_mode is null then
      raise exception 'modalidade obrigatória' using errcode = '22023';
    end if;

    insert into public.organizations (kind, display_name, cnpj, created_by)
    values (
      v_persona::text::public.organization_kind,
      btrim(meta ->> 'full_name'),
      case when v_persona = 'company' then regexp_replace(meta ->> 'cnpj', '\D', '', 'g') end,
      new.id
    )
    returning id into v_org;

    insert into public.organization_members (organization_id, user_id, role) values (v_org, new.id, 'owner');

    -- Trial: um mês de calendário (interval '1 month' ajusta fim de mês). Pagamento continua simulado.
    insert into public.subscriptions (organization_id, plan_id, mode, status, next_billing_at)
    values (
      v_org,
      v_plan.id,
      v_mode,
      case when v_mode = 'trial' then 'trialing'::public.subscription_status else 'pending'::public.subscription_status end,
      case when v_mode = 'trial' then now() + interval '1 month' end
    );
  end if;

  -- CPF, CNPJ e endereço não devem circular no JWT (user_metadata).
  update auth.users
  set raw_user_meta_data = jsonb_build_object('persona', v_persona, 'full_name', btrim(meta ->> 'full_name'))
  where id = new.id;

  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
