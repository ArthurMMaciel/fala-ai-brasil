-- Rollback do lote 2, passo 05 (20261118150000, aba Contratados). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Efeito: some list_my_contracted_partners; o cadastro de parceiro deixa de pedir contato; company_request_partner volta a aceitar vínculo não verificado; somem as
-- colunas de contato do parceiro. Se algum parceiro tiver contato preenchido, exporte antes (select id, contact_email,
-- contact_phone from public.partners where contact_email is not null or contact_phone is not null; -> Download CSV) e
-- troque false por true em v_exportei. Conexões gravadas ficam. A versão sai de schema_migrations.
-- Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
declare v_exportei boolean := false;
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118150000') then
    raise exception 'A 20261118150000 não está registrada. Nada foi feito.';
  end if;
  if not v_exportei and exists (select 1 from public.partners where contact_email is not null or contact_phone is not null) then
    raise exception 'Há contato de parceiro preenchido. Exporte e marque v_exportei = true. Nada foi feito.';
  end if;
end $trava$;

drop function public.list_my_contracted_partners();
-- company_request_partner de 20261027024534, literal.
create or replace function public.company_request_partner(p_partner uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid;
begin
  select company_id into v_company from public.company_users where user_id = auth.uid() order by created_at limit 1;
  if v_company is null then raise exception 'Somente empresas podem sinalizar interesse.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.partners where id = p_partner) then raise exception 'Parceiro não encontrado.' using errcode = 'P0001'; end if;
  insert into public.partner_connections (partner_id, company_id, stage) values (p_partner, v_company, 'company_interest')
  on conflict (partner_id, company_id) do nothing;
end;
$$;

drop function public.update_partner_contact(text, text);
-- private.create_profile de 20261118140000, literal (o cadastro de parceiro deixa de pedir contato).
create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
  v_doc text;
  v_reg text;
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
    insert into public.partners (user_id, display_name, document_type, document, specialty, description, address_id)
    values (
      p_user, btrim(p ->> 'display_name'), (p ->> 'document_type')::public.document_type, v_doc,
      btrim(p ->> 'specialty'), nullif(btrim(p ->> 'description'), ''), v_address
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
alter table public.partners drop column contact_email, drop column contact_phone;
delete from supabase_migrations.schema_migrations where version = '20261118150000';

commit;
