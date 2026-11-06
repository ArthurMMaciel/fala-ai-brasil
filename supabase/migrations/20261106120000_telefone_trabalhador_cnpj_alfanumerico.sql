-- Telefone do trabalhador e CNPJ alfanumérico (pedido do responsável em 2026-11-05).
-- CNPJ: 12 posições 0-9/A-Z + 2 dígitos verificadores (Receita Federal, julho de 2026); numéricos continuam válidos.
-- Telefone: DDD + 8 (fixo) ou 9 (celular) dígitos, só números. Coluna opcional para não quebrar contas antigas;
-- o cadastro novo exige o telefone no app. Dado pessoal: nunca exposto à empresa (RLS de workers inalterada).

alter table public.workers
  add column phone text check (phone is null or phone ~ '^[1-9][0-9](9[0-9]{8}|[2-5][0-9]{7})$');
grant update (phone) on public.workers to authenticated;

alter table public.companies drop constraint companies_cnpj_check;
alter table public.companies add constraint companies_cnpj_check check (cnpj ~ '^[0-9A-Z]{12}[0-9]{2}$');
alter table public.sponsors drop constraint sponsors_cnpj_check;
alter table public.sponsors add constraint sponsors_cnpj_check check (cnpj ~ '^[0-9A-Z]{12}[0-9]{2}$');
alter table public.partners drop constraint partner_document_format;
alter table public.partners add constraint partner_document_format check (
  (document_type = 'cpf' and document ~ '^[0-9]{11}$') or (document_type = 'cnpj' and document ~ '^[0-9A-Z]{12}[0-9]{2}$')
);

-- Mesmo fluxo de antes; muda só a normalização do CNPJ (mantém letras, em maiúsculas) e grava o telefone.
create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
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
    insert into public.workers (user_id, full_name, cpf, phone, address_id)
    values (p_user, btrim(p ->> 'full_name'), regexp_replace(p ->> 'cpf', '\D', '', 'g'),
            nullif(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), ''), v_address)
    returning id into v_id;
  elsif p_type = 'company' then
    insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
    values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), upper(regexp_replace(p ->> 'cnpj', '[^0-9A-Za-z]', '', 'g')), v_address, p_user)
    returning id into v_id;
    insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
    perform private.create_subscription('company', p, v_id, null, null);
  elsif p_type = 'partner' then
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type,
      case when p ->> 'document_type' = 'cnpj' then upper(regexp_replace(p ->> 'document', '[^0-9A-Za-z]', '', 'g'))
           else regexp_replace(p ->> 'document', '\D', '', 'g') end,
      btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address
    )
    returning id into v_id;
    perform private.create_subscription('partner', p, null, v_id, null);
  else
    insert into public.sponsors (user_id, name, cnpj, address_id)
    values (p_user, btrim(p ->> 'name'), upper(regexp_replace(p ->> 'cnpj', '[^0-9A-Za-z]', '', 'g')), v_address)
    returning id into v_id;
    perform private.create_subscription('sponsor', p, null, null, v_id);
  end if;
  return v_id;
end;
$$;
