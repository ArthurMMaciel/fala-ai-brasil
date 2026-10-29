-- Conteúdos do parceiro e contato da empresa (aprovado pelo responsável em 2026-10-29, ADR-0009).

-- 1) Conteúdos: reaproveita public.media. Linha com título = conteúdo publicado; sem título = foto de perfil.
alter table public.media
  add column title text check (title is null or char_length(btrim(title)) between 1 and 120),
  add column caption text check (caption is null or char_length(caption) <= 1000),
  add column published_at timestamptz;

create index media_partner_content_idx on public.media (partner_id, published_at desc) where title is not null;

-- Planos que incluem "Conteúdo no perfil": Profissional e Nacional, com assinatura vigente.
create function public.partner_has_content_plan(p_partner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.subscriptions s
                 where s.partner_id = p_partner and s.plan_id in ('partner-professional', 'partner-national')
                   and s.status in ('trialing', 'pending', 'active'));
$$;
revoke execute on function public.partner_has_content_plan(uuid) from public, anon;
grant execute on function public.partner_has_content_plan(uuid) to authenticated;

-- Inserção: só o próprio parceiro; conteúdo (com título) exige plano com conteúdo.
drop policy media_insert on public.media;
create policy media_insert on public.media for insert to authenticated
  with check (
    exists (select 1 from public.partners p where p.id = partner_id and p.user_id = (select auth.uid()))
    and (title is null or public.partner_has_content_plan(partner_id))
  );
create policy media_update on public.media for update to authenticated
  using (exists (select 1 from public.partners p where p.id = partner_id and p.user_id = (select auth.uid())))
  with check (title is not null and public.partner_has_content_plan(partner_id));

grant insert (title, caption, published_at) on public.media to authenticated;
grant update (title, caption) on public.media to authenticated;

-- Empresas veem os conteúdos publicados de um parceiro (mesma regra do diretório: só membros de empresa).
create function public.list_partner_contents(p_partner uuid)
returns table (id uuid, kind public.media_kind, storage_path text, external_url text, title text, caption text, published_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select m.id, m.kind, m.storage_path, m.external_url, m.title, m.caption, m.published_at
  from public.media m
  where m.partner_id = p_partner and m.title is not null
    and public.partner_has_content_plan(p_partner)
    and exists (select 1 from public.company_users cu where cu.user_id = auth.uid())
  order by m.published_at desc nulls last;
$$;
revoke execute on function public.list_partner_contents(uuid) from public, anon;
grant execute on function public.list_partner_contents(uuid) to authenticated;

-- 2) Contato da empresa: opcional, preenchido pelo dono da conta da empresa.
alter table public.companies
  add column contact_email text check (contact_email is null or contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add column contact_phone text check (contact_phone is null or contact_phone ~ '^\d{10,11}$');
grant update (contact_email, contact_phone) on public.companies to authenticated;

-- O parceiro só recebe o contato de empresas que demonstraram interesse nele ou que são clientes dele.
drop function public.list_partner_companies();
create function public.list_partner_companies()
returns table (id uuid, name text, legal_name text, city text, state text, stage public.connection_stage, contact_email text, contact_phone text)
language sql stable security definer set search_path = '' as $$
  select c.id, coalesce(c.trade_name, c.legal_name), c.legal_name, a.city, a.state, pc.stage,
         case when pc.stage in ('company_interest', 'client') then c.contact_email end,
         case when pc.stage in ('company_interest', 'client') then c.contact_phone end
  from public.companies c
  join public.addresses a on a.id = c.address_id
  join public.partners p on p.user_id = auth.uid()
  left join public.partner_connections pc on pc.company_id = c.id and pc.partner_id = p.id
  order by 2;
$$;
revoke execute on function public.list_partner_companies() from public, anon;
grant execute on function public.list_partner_companies() to authenticated;
