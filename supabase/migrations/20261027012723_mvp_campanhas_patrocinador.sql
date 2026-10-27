-- TASK-0022 / ADR-0009: campanhas de patrocinadores, aprovadas pelo responsável em 2026-10-27.
-- Regras: tipo definido pelo plano; assinatura em trial ou ativa; uma campanha ativa por vez;
-- revisão da plataforma antes de publicar; sem segmentação de público nem acesso a relatos.

create type public.campaign_kind as enum ('content', 'event', 'study');
create type public.campaign_status as enum ('draft', 'submitted', 'approved', 'rejected');

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  sponsor_id uuid not null references public.sponsors (id) on delete cascade,
  subscription_id uuid not null references public.subscriptions (id) on delete restrict,
  kind public.campaign_kind not null,
  title text not null check (char_length(title) between 3 and 120),
  description text not null check (char_length(description) between 10 and 2000),
  cta_url text check (cta_url is null or cta_url ~ '^https://'),
  starts_at date not null,
  ends_at date not null,
  status public.campaign_status not null default 'draft',
  review_note text check (review_note is null or char_length(review_note) <= 1000),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campaign_period check (ends_at >= starts_at)
);
create index campaigns_sponsor_idx on public.campaigns (sponsor_id);
create trigger campaigns_touch before update on public.campaigns for each row execute function public.touch_updated_at();

alter table public.campaigns enable row level security;
create policy campaigns_read_own on public.campaigns for select to authenticated
  using (exists (select 1 from public.sponsors s where s.id = sponsor_id and s.user_id = (select auth.uid())));
-- Rascunho pode ser descartado; demais estados ficam no histórico.
create policy campaigns_delete_draft on public.campaigns for delete to authenticated
  using (status = 'draft' and exists (select 1 from public.sponsors s where s.id = sponsor_id and s.user_id = (select auth.uid())));

revoke all on public.campaigns from anon, authenticated;
grant select, delete on public.campaigns to authenticated;

-- Tipo de campanha permitido por plano de patrocínio.
create function private.campaign_kind_for_plan(p_plan text)
returns public.campaign_kind language sql immutable set search_path = '' as $$
  select case p_plan
    when 'sponsor-content' then 'content'::public.campaign_kind
    when 'sponsor-event' then 'event'::public.campaign_kind
    when 'sponsor-study' then 'study'::public.campaign_kind
  end;
$$;

-- Assinatura vigente do patrocinador da conta atual (trial ou ativa, dentro do período).
create function private.current_sponsor_subscription()
returns table (sponsor_id uuid, subscription_id uuid, plan_id text)
language sql stable security definer set search_path = '' as $$
  select s.id, sub.id, sub.plan_id
  from public.sponsors s
  join public.subscriptions sub on sub.sponsor_id = s.id
  where s.user_id = auth.uid()
    and sub.status in ('trialing', 'active')
    and (sub.next_billing_at is null or sub.next_billing_at > now())
  order by sub.created_at desc
  limit 1;
$$;

create function private.assert_single_active_campaign(p_sponsor uuid, p_ignore uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.campaigns
    where sponsor_id = p_sponsor and id is distinct from p_ignore
      and status in ('draft', 'submitted', 'approved') and ends_at >= current_date
  ) then
    raise exception 'Você já tem uma campanha ativa. Conclua, aguarde o fim ou descarte o rascunho antes de criar outra.' using errcode = 'P0001';
  end if;
end;
$$;

-- Cria campanha como rascunho ou já enviada para revisão.
create function public.create_campaign(p jsonb, p_submit boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_sub record;
  v_kind public.campaign_kind;
  v_id uuid;
  v_starts date := (p ->> 'starts_at')::date;
  v_ends date := (p ->> 'ends_at')::date;
begin
  if auth.uid() is null then raise exception 'não autenticado' using errcode = '42501'; end if;
  select * into v_sub from private.current_sponsor_subscription();
  if not found then
    raise exception 'Sua assinatura precisa estar em período gratuito ou ativa para criar campanhas.' using errcode = 'P0001';
  end if;
  v_kind := private.campaign_kind_for_plan(v_sub.plan_id);
  if v_kind is null then raise exception 'Seu plano não permite campanhas.' using errcode = 'P0001'; end if;
  if (p ->> 'kind') is not null and (p ->> 'kind') <> v_kind::text then
    raise exception 'Seu plano permite apenas campanhas deste tipo: %.', v_kind using errcode = 'P0001';
  end if;
  if v_starts is null or v_ends is null or v_starts < current_date then
    raise exception 'Informe um período que comece hoje ou depois.' using errcode = 'P0001';
  end if;
  perform private.assert_single_active_campaign(v_sub.sponsor_id, null);

  insert into public.campaigns (sponsor_id, subscription_id, kind, title, description, cta_url, starts_at, ends_at, status, submitted_at)
  values (
    v_sub.sponsor_id, v_sub.subscription_id, v_kind, btrim(p ->> 'title'), btrim(p ->> 'description'),
    nullif(btrim(p ->> 'cta_url'), ''), v_starts, v_ends,
    case when p_submit then 'submitted'::public.campaign_status else 'draft'::public.campaign_status end,
    case when p_submit then now() end
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Envia um rascunho próprio para revisão da plataforma.
create function public.submit_campaign(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_sponsor uuid;
begin
  select c.sponsor_id into v_sponsor from public.campaigns c join public.sponsors s on s.id = c.sponsor_id
  where c.id = p_id and s.user_id = auth.uid() and c.status = 'draft';
  if not found then raise exception 'Rascunho não encontrado.' using errcode = 'P0001'; end if;
  if not exists (select 1 from private.current_sponsor_subscription()) then
    raise exception 'Sua assinatura precisa estar em período gratuito ou ativa para enviar campanhas.' using errcode = 'P0001';
  end if;
  update public.campaigns set status = 'submitted', submitted_at = now() where id = p_id;
end;
$$;

revoke execute on function public.create_campaign(jsonb, boolean), public.submit_campaign(uuid) from public, anon;
grant execute on function public.create_campaign(jsonb, boolean), public.submit_campaign(uuid) to authenticated;
