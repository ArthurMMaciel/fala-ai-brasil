-- Datas de campanha seguem o calendário de São Paulo (o front envia a data local; current_date é UTC).

create or replace function private.assert_single_active_campaign(p_sponsor uuid, p_ignore uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.campaigns
    where sponsor_id = p_sponsor and id is distinct from p_ignore
      and status in ('draft', 'submitted', 'approved') and ends_at >= (now() at time zone 'America/Sao_Paulo')::date
  ) then
    raise exception 'Você já tem uma campanha ativa. Conclua, aguarde o fim ou descarte o rascunho antes de criar outra.' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.create_campaign(p jsonb, p_submit boolean default false)
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
  if v_starts is null or v_ends is null or v_starts < (now() at time zone 'America/Sao_Paulo')::date then
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
