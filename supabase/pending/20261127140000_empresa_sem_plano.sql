-- Conta de empresa gratuita e sem plano (decisão do responsável, repassada pelo Gestor em 2026-11-27; ADR-0026).
-- private.create_profile deixa de criar assinatura no ramo 'company': cadastro novo e reivindicação de empresa
-- pré-cadastrada. plan_id e subscription_mode enviados pelo front são ignorados nesse ramo; o front atual continua
-- funcionando. Parceiro e patrocinador não mudam (continuam com plano e create_subscription).
-- Nenhuma RLS, RPC, Edge Function ou agendamento depende de a empresa ter assinatura (análise do Back, 2026-11-27).
-- Assinaturas de empresa já existentes ficam como estão (nada as vence nem as lê no backend).
--
-- Corpo de 20261118150000; só o ramo 'company' muda (as duas chamadas a create_subscription saem).
-- Rollback: supabase/tests/rollback/20261127140000_rollback.sql (volta o corpo de 20261118150000).

set local lock_timeout = '5s';

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
    -- Conta de empresa gratuita e sem plano (20261127140000): nenhuma assinatura; plan_id e subscription_mode, se vierem
    -- do front, são ignorados neste ramo.
    select c.id, c.registration_status into v_id, v_reg from public.companies c where c.cnpj = v_doc for update;
    if v_id is not null and v_reg <> 'registered' then
      -- D11: a primeira conta reivindica a empresa pré-cadastrada. Vira dona com vínculo 'pending' (default da 120000);
      -- o acesso a manifestações depende da verificação da equipe (130000).
      update public.companies
      set legal_name = btrim(p ->> 'legal_name'), trade_name = nullif(btrim(p ->> 'trade_name'), ''), address_id = v_address,
          created_by = p_user, registration_status = 'registered'
      where id = v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
    elsif v_id is not null then
      -- D11: empresa já cadastrada, de qualquer origem: a conta entra como membro 'pending', nunca como dona. Evita que quem
      -- chegou primeiro tranque a empresa verdadeira fora da plataforma; a equipe decide na verificação.
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'member');
    else
      insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
      values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), v_doc, v_address, p_user)
      returning id into v_id;
      insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
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
