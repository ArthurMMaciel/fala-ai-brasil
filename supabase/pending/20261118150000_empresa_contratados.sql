-- Fluxo 2 do teste ponta a ponta (pedido do Gestor, 2026-11-18): a empresa vê, na aba "Contratados", os parceiros que a
-- marcaram como cliente (partner_connections.stage = 'client').
-- Coerente com a troca do gate (20261117130000): só vínculo verificado.
--   0) Contato do parceiro (modelo aprovado pelo responsável em 2026-11-18: "Colunas de contato"): partners ganha
--      contact_email e contact_phone, com o mesmo formato de companies. O próprio parceiro edita por
--      update_partner_contact (normaliza e exige os dois; sem grant de update direto). Ninguém mais lê partners direto
--      (partners_read: só a própria linha); o diretório não mostra o contato.
--      Cadastro NOVO de parceiro exige os dois (decisão do responsável, 2026-11-18: "para cadastrar como parceiro deve
--      passar esses dados"): private.create_profile, corpo de 20261118140000, muda só o ramo 'partner' (campos
--      contact_email e contact_phone no payload). No banco as colunas aceitam nulo, por causa dos parceiros já existentes.
--      Depende de 20261118140000 (a trava de ordem do SQL Editor garante).
--   1) list_my_contracted_partners(): parceiros com stage 'client' para as empresas em que a conta tem vínculo verified,
--      com os dados do diretório e o contato do parceiro (o parceiro escolheu marcar a empresa como cliente).
--   2) company_request_partner passa a exigir vínculo verified: com a D11 (20261118140000) qualquer conta entra como
--      membro pending de uma empresa cadastrada, e o pedido de contato libera ao parceiro o e-mail e o telefone de contato
--      da empresa (list_partner_companies, estágio company_interest). Sem verificação, uma conta não confirmada falaria em
--      nome da empresa e exporia o contato dela.
--
-- Rollback: reaplicar private.create_profile de 20261118140000; drop function public.list_my_contracted_partners(); reaplicar company_request_partner de
--   20261027024534_mvp_manifestacoes_e_conexoes.sql; drop function public.update_partner_contact(text, text);
--   alter table public.partners drop column contact_email, drop column contact_phone (exportar antes).

alter table public.partners
  add column contact_email text check (contact_email is null or (char_length(contact_email) <= 254 and contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  add column contact_phone text check (contact_phone is null or contact_phone ~ '^\d{10,11}$');

-- O parceiro edita o próprio contato (Meu perfil). Os dois são obrigatórios e normalizados, como no cadastro.
create function public.update_partner_contact(p_contact_email text, p_contact_phone text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_contact_email, '')));
  v_phone text := regexp_replace(coalesce(p_contact_phone, ''), '\D', '', 'g');
begin
  if not exists (select 1 from public.partners where user_id = auth.uid()) then
    raise exception 'Somente parceiros podem editar o contato de parceiro.' using errcode = 'P0001';
  end if;
  if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Informe um e-mail de contato válido.' using errcode = 'P0001';
  end if;
  if v_phone !~ '^\d{10,11}$' then raise exception 'Informe um telefone de contato com DDD (10 ou 11 dígitos).' using errcode = 'P0001'; end if;
  update public.partners set contact_email = v_email, contact_phone = v_phone where user_id = auth.uid();
end;
$$;
revoke execute on function public.update_partner_contact(text, text) from public, anon, service_role;
grant execute on function public.update_partner_contact(text, text) to authenticated;

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

-- Cadastro de parceiro com contato obrigatório. Corpo de 20261118140000; só o ramo 'partner' muda.
create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
  v_doc text;
  v_reg text;
  v_contact_email text;
  v_contact_phone text;
begin
  if p_user is null then raise exception 'usuário obrigatório' using errcode = '22023'; end if;
  if p is null then raise exception 'dados do cadastro obrigatórios' using errcode = '22023'; end if;
  if p_type not in ('worker', 'company', 'partner', 'sponsor') then
    raise exception 'tipo de conta inválido' using errcode = '22023';
  end if;

  if p_type = 'worker' or (p_type = 'partner' and p ->> 'document_type' = 'cpf') then
    v_doc := regexp_replace(coalesce(p ->> case when p_type = 'worker' then 'cpf' else 'document' end, ''), '\D', '', 'g');
    if not private.valid_cpf(v_doc) then raise exception 'CPF inválido' using errcode = '22023'; end if;
  else
    v_doc := upper(regexp_replace(coalesce(p ->> case when p_type = 'partner' then 'document' else 'cnpj' end, ''), '[^0-9A-Za-z]', '', 'g'));
    if not private.valid_cnpj(v_doc) then raise exception 'CNPJ inválido' using errcode = '22023'; end if;
  end if;

  v_address := private.create_address(p -> 'address');

  if p_type = 'worker' then
    begin
      insert into public.workers (user_id, full_name, cpf, phone, address_id)
      values (p_user, btrim(p ->> 'full_name'), v_doc,
              nullif(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), ''), v_address)
      returning id into v_id;
    exception when unique_violation then
      -- CPF de outro trabalhador ou conta que já tem perfil de trabalhador: mensagem genérica, sem o valor.
      raise exception 'Não foi possível concluir o cadastro.' using errcode = '23505';
    end;
  elsif p_type = 'company' then
    select c.id, c.registration_status into v_id, v_reg from public.companies c where c.cnpj = v_doc for update;
    if v_id is not null and v_reg <> 'registered' then
      -- D11: a primeira conta reivindica a empresa pré-cadastrada. Vira dona com vínculo 'pending' (default da 120000);
      -- o acesso a manifestações depende da verificação da equipe (130000).
      update public.companies
      set legal_name = btrim(p ->> 'legal_name'), trade_name = nullif(btrim(p ->> 'trade_name'), ''), address_id = v_address,
          created_by = p_user, registration_status = 'registered'
      where id = v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    elsif v_id is not null then
      -- D11: empresa já cadastrada, de qualquer origem: a conta entra como membro 'pending', nunca como dona. Evita que quem
      -- chegou primeiro tranque a empresa verdadeira fora da plataforma; a equipe decide na verificação.
      -- Sem assinatura nova: a empresa já tem a da conta que reivindicou (subscriptions não tem unique por empresa).
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'member');
    else
      insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
      values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), v_doc, v_address, p_user)
      returning id into v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
      perform private.create_subscription('company', p, v_id, null, null);
    end if;
  elsif p_type = 'partner' then
    -- Contato do parceiro, obrigatório no cadastro novo (responsável, 2026-11-18); aparece só em "Contratados".
    v_contact_email := lower(btrim(coalesce(p ->> 'contact_email', '')));
    v_contact_phone := regexp_replace(coalesce(p ->> 'contact_phone', ''), '\D', '', 'g');
    if char_length(v_contact_email) > 254 or v_contact_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'e-mail de contato inválido' using errcode = '22023';
    end if;
    if v_contact_phone !~ '^\d{10,11}$' then raise exception 'telefone de contato inválido' using errcode = '22023'; end if;
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id,
                                 contact_email, contact_phone)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type, v_doc,
      btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address, v_contact_email, v_contact_phone
    )
    returning id into v_id;
    perform private.create_subscription('partner', p, null, v_id, null);
  else
    insert into public.sponsors (user_id, name, cnpj, address_id)
    values (p_user, btrim(p ->> 'name'), v_doc, v_address)
    returning id into v_id;
    perform private.create_subscription('sponsor', p, null, null, v_id);
  end if;
  return v_id;
end;
$$;
