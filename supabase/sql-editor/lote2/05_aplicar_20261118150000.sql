-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/pending/20261118150000_empresa_contratados.sql. Não editar à mão.
-- Passo 05 de 05. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 05_conferir_20261118150000.sql (todas as linhas com ok = true).
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261118150000') then
    raise exception 'A migration 20261118150000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118140000') then
    raise exception 'Falta a 20261118140000 (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261118150000_empresa_contratados.sql (6 instruções) ========
-- Fluxo 2 do teste ponta a ponta (pedido do Gestor, 2026-11-18): a empresa vê, na aba "Contratados", os parceiros que a
-- marcaram como cliente (partner_connections.stage = 'client').
-- Coerente com a troca do gate (20261117130000): só vínculo verificado.
--   0) Contato do parceiro (modelo aprovado pelo responsável em 2026-11-18: "Colunas de contato"): partners ganha
--      contact_email e contact_phone, opcionais, com o mesmo formato de companies. O próprio parceiro edita (policy
--      partners_update já restringe à própria linha; grant só dessas colunas). Ninguém mais lê partners direto
--      (partners_read: só a própria linha); o diretório não mostra o contato.
--   1) list_my_contracted_partners(): parceiros com stage 'client' para as empresas em que a conta tem vínculo verified,
--      com os dados do diretório e o contato do parceiro (o parceiro escolheu marcar a empresa como cliente).
--   2) company_request_partner passa a exigir vínculo verified: com a D11 (20261118140000) qualquer conta entra como
--      membro pending de uma empresa cadastrada, e o pedido de contato libera ao parceiro o e-mail e o telefone de contato
--      da empresa (list_partner_companies, estágio company_interest). Sem verificação, uma conta não confirmada falaria em
--      nome da empresa e exporia o contato dela.
--
-- Rollback: drop function public.list_my_contracted_partners(); reaplicar company_request_partner de
--   20261027024534_mvp_manifestacoes_e_conexoes.sql; revoke update (contact_email, contact_phone) on public.partners from
--   authenticated; alter table public.partners drop column contact_email, drop column contact_phone (exportar antes).

alter table public.partners
  add column contact_email text check (contact_email is null or (char_length(contact_email) <= 254 and contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  add column contact_phone text check (contact_phone is null or contact_phone ~ '^\d{10,11}$');
grant update (contact_email, contact_phone) on public.partners to authenticated;

create function public.list_my_contracted_partners()
returns table (partner_id uuid, company_id uuid, display_name text, specialty text, description text, avatar_path text,
               city text, state text, contact_email text, contact_phone text, since timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, pc.company_id, p.display_name, p.specialty, p.description, m.storage_path, a.city, a.state,
         p.contact_email, p.contact_phone, pc.updated_at
  from public.partner_connections pc
  join public.company_users cu on cu.company_id = pc.company_id and cu.user_id = auth.uid() and cu.verification_status = 'verified'
  join public.partners p on p.id = pc.partner_id
  join public.addresses a on a.id = p.address_id
  left join public.media m on m.id = p.avatar_media_id
  where pc.stage = 'client'
  order by p.display_name, p.id;
$$;
revoke execute on function public.list_my_contracted_partners() from public, anon, service_role;
grant execute on function public.list_my_contracted_partners() to authenticated;

-- Pedido de contato só por vínculo verificado; com mais de uma empresa verificada, a mais antiga (comportamento de antes).
create or replace function public.company_request_partner(p_partner uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid;
begin
  select company_id into v_company from public.company_users
  where user_id = auth.uid() and verification_status = 'verified' order by created_at limit 1;
  if v_company is null then
    if exists (select 1 from public.company_users where user_id = auth.uid()) then
      raise exception 'Seu vínculo com a empresa ainda não foi verificado pela equipe.' using errcode = 'P0001';
    end if;
    raise exception 'Somente empresas podem sinalizar interesse.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.partners where id = p_partner) then raise exception 'Parceiro não encontrado.' using errcode = 'P0001'; end if;
  insert into public.partner_connections (partner_id, company_id, stage) values (p_partner, v_company, 'company_interest')
  on conflict (partner_id, company_id) do nothing;
end;
$$;
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261118150000', 'empresa_contratados', array[
$s0$-- Fluxo 2 do teste ponta a ponta (pedido do Gestor, 2026-11-18): a empresa vê, na aba "Contratados", os parceiros que a
-- marcaram como cliente (partner_connections.stage = 'client').
-- Coerente com a troca do gate (20261117130000): só vínculo verificado.
--   0) Contato do parceiro (modelo aprovado pelo responsável em 2026-11-18: "Colunas de contato"): partners ganha
--      contact_email e contact_phone, opcionais, com o mesmo formato de companies. O próprio parceiro edita (policy
--      partners_update já restringe à própria linha; grant só dessas colunas). Ninguém mais lê partners direto
--      (partners_read: só a própria linha); o diretório não mostra o contato.
--   1) list_my_contracted_partners(): parceiros com stage 'client' para as empresas em que a conta tem vínculo verified,
--      com os dados do diretório e o contato do parceiro (o parceiro escolheu marcar a empresa como cliente).
--   2) company_request_partner passa a exigir vínculo verified: com a D11 (20261118140000) qualquer conta entra como
--      membro pending de uma empresa cadastrada, e o pedido de contato libera ao parceiro o e-mail e o telefone de contato
--      da empresa (list_partner_companies, estágio company_interest). Sem verificação, uma conta não confirmada falaria em
--      nome da empresa e exporia o contato dela.
--
-- Rollback: drop function public.list_my_contracted_partners(); reaplicar company_request_partner de
--   20261027024534_mvp_manifestacoes_e_conexoes.sql; revoke update (contact_email, contact_phone) on public.partners from
--   authenticated; alter table public.partners drop column contact_email, drop column contact_phone (exportar antes).

alter table public.partners
  add column contact_email text check (contact_email is null or (char_length(contact_email) <= 254 and contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  add column contact_phone text check (contact_phone is null or contact_phone ~ '^\d{10,11}$')$s0$,
$s0$grant update (contact_email, contact_phone) on public.partners to authenticated$s0$,
$s0$create function public.list_my_contracted_partners()
returns table (partner_id uuid, company_id uuid, display_name text, specialty text, description text, avatar_path text,
               city text, state text, contact_email text, contact_phone text, since timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, pc.company_id, p.display_name, p.specialty, p.description, m.storage_path, a.city, a.state,
         p.contact_email, p.contact_phone, pc.updated_at
  from public.partner_connections pc
  join public.company_users cu on cu.company_id = pc.company_id and cu.user_id = auth.uid() and cu.verification_status = 'verified'
  join public.partners p on p.id = pc.partner_id
  join public.addresses a on a.id = p.address_id
  left join public.media m on m.id = p.avatar_media_id
  where pc.stage = 'client'
  order by p.display_name, p.id;
$$$s0$,
$s0$revoke execute on function public.list_my_contracted_partners() from public, anon, service_role$s0$,
$s0$grant execute on function public.list_my_contracted_partners() to authenticated$s0$,
$s0$-- Pedido de contato só por vínculo verificado; com mais de uma empresa verificada, a mais antiga (comportamento de antes).
create or replace function public.company_request_partner(p_partner uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid;
begin
  select company_id into v_company from public.company_users
  where user_id = auth.uid() and verification_status = 'verified' order by created_at limit 1;
  if v_company is null then
    if exists (select 1 from public.company_users where user_id = auth.uid()) then
      raise exception 'Seu vínculo com a empresa ainda não foi verificado pela equipe.' using errcode = 'P0001';
    end if;
    raise exception 'Somente empresas podem sinalizar interesse.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.partners where id = p_partner) then raise exception 'Parceiro não encontrado.' using errcode = 'P0001'; end if;
  insert into public.partner_connections (partner_id, company_id, stage) values (p_partner, v_company, 'company_interest')
  on conflict (partner_id, company_id) do nothing;
end;
$$$s0$
]::text[]);

commit;
