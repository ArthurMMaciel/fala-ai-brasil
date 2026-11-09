-- ADR-0014 / TASK-0037: "Meu perfil" do trabalhador e da empresa (aprovado pelo responsável em 2026-11-08).
-- - Edição só por RPC validada; o update direto nas tabelas sai (vai no mesmo PR do front novo).
-- - CPF, CNPJ e razão social travados: troca só por quem tem o privilégio private.document_officers (decisão C4:
--   só o responsável, mediante documento), com motivo e referência do documento conferido. platform_admin não basta.
-- - Trilha sem valores em profile_change_log (só nomes dos campos).
-- - Dígitos verificadores de CPF e CNPJ (inclusive alfanumérico) validados no banco, também no cadastro.
-- - Correção: membros da empresa deixam de alterar o endereço dela (a política addresses_update usava owns_address,
--   que aceita qualquer vínculo). owns_address continua valendo para leitura: o membro lê, só o dono altera.
-- Rollback: ver o fim do arquivo.

-- 1) Validação de documentos.
create function private.valid_cpf(p text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare d int[]; s int; dv int; i int;
begin
  if p is null or p !~ '^[0-9]{11}$' or p ~ '^(.)\1{10}$' then return false; end if;
  d := array(select substr(p, g, 1)::int from generate_series(1, 11) g);
  s := 0; for i in 1..9 loop s := s + d[i] * (11 - i); end loop;
  dv := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  if dv <> d[10] then return false; end if;
  s := 0; for i in 1..10 loop s := s + d[i] * (12 - i); end loop;
  dv := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  return dv = d[11];
end;
$$;

-- CNPJ numérico ou alfanumérico (Receita, 2026): valor de cada posição = código ASCII − 48; DVs numéricos.
create function private.valid_cnpj(p text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare v int[]; w1 int[] := '{5,4,3,2,9,8,7,6,5,4,3,2}'; w2 int[] := '{6,5,4,3,2,9,8,7,6,5,4,3,2}'; s int; dv int; i int;
begin
  if p is null or p !~ '^[0-9A-Z]{12}[0-9]{2}$' or p ~ '^(.)\1{13}$' then return false; end if;
  v := array(select ascii(substr(p, g, 1)) - 48 from generate_series(1, 14) g);
  s := 0; for i in 1..12 loop s := s + v[i] * w1[i]; end loop;
  dv := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  if dv <> v[13] then return false; end if;
  s := 0; for i in 1..13 loop s := s + v[i] * w2[i]; end loop;
  dv := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  return dv = v[14];
end;
$$;
revoke all on function private.valid_cpf(text), private.valid_cnpj(text) from public, anon, authenticated;

-- Cadastro passa a recusar documento com dígito verificador inválido (antes só no navegador).
create or replace function private.create_profile(p_user uuid, p_type text, p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_address uuid;
  v_id uuid;
  v_doc text;
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
    insert into public.workers (user_id, full_name, cpf, phone, address_id)
    values (p_user, btrim(p ->> 'full_name'), v_doc,
            nullif(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), ''), v_address)
    returning id into v_id;
  elsif p_type = 'company' then
    insert into public.companies (legal_name, trade_name, cnpj, address_id, created_by)
    values (btrim(p ->> 'legal_name'), nullif(btrim(p ->> 'trade_name'), ''), v_doc, v_address, p_user)
    returning id into v_id;
    insert into public.company_users (company_id, user_id, role) values (v_id, p_user, 'owner');
    perform private.create_subscription('company', p, v_id, null, null);
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

-- 2) Trilha sem valores: quem alterou, quais campos e quando.
create table public.profile_change_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users (id) on delete set null,
  entity_type text not null check (entity_type in ('worker', 'company')),
  entity_id uuid not null,
  fields text[] not null check (cardinality(fields) > 0),
  source text not null check (source in ('self', 'platform')),
  justification text check (justification is null or char_length(justification) between 10 and 500),
  evidence_ref text check (evidence_ref is null or char_length(evidence_ref) between 3 and 200),
  created_at timestamptz not null default now(),
  check (source = 'self' or (justification is not null and evidence_ref is not null))
);
create index profile_change_log_entity_idx on public.profile_change_log (entity_id, created_at);
alter table public.profile_change_log enable row level security;
revoke all on public.profile_change_log from public, anon, authenticated;

-- 3) Endereço: valida como no cadastro e devolve os campos alterados (prefixo "address.").
create function private.update_address(p_address uuid, a jsonb)
returns text[] language plpgsql security definer set search_path = '' as $$
declare
  o public.addresses%rowtype;
  v_zip text := regexp_replace(coalesce(a ->> 'zip_code', ''), '\D', '', 'g');
  v_type text := btrim(coalesce(a ->> 'street_type', ''));
  v_street text := btrim(coalesce(a ->> 'street_name', ''));
  v_number text := btrim(coalesce(a ->> 'number', ''));
  v_complement text := nullif(btrim(coalesce(a ->> 'complement', '')), '');
  v_neighborhood text := nullif(btrim(coalesce(a ->> 'neighborhood', '')), '');
  v_city text := btrim(coalesce(a ->> 'city', ''));
  v_state text := upper(btrim(coalesce(a ->> 'state', '')));
  v_changed text[] := '{}';
begin
  if a is null or jsonb_typeof(a) <> 'object' then raise exception 'Informe o endereço completo.' using errcode = 'P0001'; end if;
  if v_zip !~ '^[0-9]{8}$' then raise exception 'Informe um CEP válido com 8 dígitos.' using errcode = 'P0001'; end if;
  if v_type not in (select unnest(enum_range(null::public.street_type))::text) then raise exception 'Selecione o tipo de logradouro.' using errcode = 'P0001'; end if;
  if char_length(v_street) not between 1 and 200 then raise exception 'Informe a rua ou avenida.' using errcode = 'P0001'; end if;
  if char_length(v_number) not between 1 and 20 then raise exception 'Informe o número.' using errcode = 'P0001'; end if;
  if char_length(coalesce(v_complement, '')) > 100 then raise exception 'O complemento pode ter até 100 caracteres.' using errcode = 'P0001'; end if;
  if char_length(coalesce(v_neighborhood, '')) > 120 then raise exception 'O bairro pode ter até 120 caracteres.' using errcode = 'P0001'; end if;
  if char_length(v_city) not between 1 and 120 then raise exception 'Informe a cidade.' using errcode = 'P0001'; end if;
  if v_state !~ '^[A-Z]{2}$' then raise exception 'Informe a UF com 2 letras.' using errcode = 'P0001'; end if;

  select * into o from public.addresses where id = p_address for update;
  if o.zip_code is distinct from v_zip then v_changed := v_changed || 'address.zip_code'::text; end if;
  if o.street_type::text is distinct from v_type then v_changed := v_changed || 'address.street_type'::text; end if;
  if o.street_name is distinct from v_street then v_changed := v_changed || 'address.street_name'::text; end if;
  if o.number is distinct from v_number then v_changed := v_changed || 'address.number'::text; end if;
  if o.complement is distinct from v_complement then v_changed := v_changed || 'address.complement'::text; end if;
  if o.neighborhood is distinct from v_neighborhood then v_changed := v_changed || 'address.neighborhood'::text; end if;
  if o.city is distinct from v_city then v_changed := v_changed || 'address.city'::text; end if;
  if o.state is distinct from v_state then v_changed := v_changed || 'address.state'::text; end if;

  if cardinality(v_changed) > 0 then
    update public.addresses
      set zip_code = v_zip, street_type = v_type::public.street_type, street_name = v_street, number = v_number,
          complement = v_complement, neighborhood = v_neighborhood, city = v_city, state = v_state
      where id = p_address;
  end if;
  return v_changed;
end;
$$;
revoke all on function private.update_address(uuid, jsonb) from public, anon, authenticated;

-- 4) Trabalhador edita nome, telefone e endereço. Atualização parcial: só as chaves enviadas.
create function public.update_worker_profile(p jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  w public.workers%rowtype;
  v_name text; v_phone text; v_changed text[] := '{}';
begin
  select * into w from public.workers where user_id = auth.uid() for update;
  if w.id is null then raise exception 'Somente trabalhadores podem editar este perfil.' using errcode = 'P0001'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Nada para atualizar.' using errcode = 'P0001'; end if;
  if p ? 'cpf' then raise exception 'O CPF só pode ser alterado pela equipe.' using errcode = 'P0001'; end if;

  if p ? 'full_name' then
    v_name := btrim(coalesce(p ->> 'full_name', ''));
    if char_length(v_name) not between 2 and 160 then raise exception 'Informe o nome completo.' using errcode = 'P0001'; end if;
    if v_name is distinct from w.full_name then
      update public.workers set full_name = v_name where id = w.id; v_changed := v_changed || 'full_name'::text;
    end if;
  end if;
  if p ? 'phone' then
    v_phone := regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g');
    if v_phone !~ '^[1-9][0-9](9[0-9]{8}|[2-5][0-9]{7})$' then
      raise exception 'Informe um telefone válido com DDD: celular com 9 dígitos ou fixo com 8.' using errcode = 'P0001';
    end if;
    if v_phone is distinct from w.phone then
      update public.workers set phone = v_phone where id = w.id; v_changed := v_changed || 'phone'::text;
    end if;
  end if;
  if p ? 'address' then v_changed := v_changed || private.update_address(w.address_id, p -> 'address'); end if;

  if cardinality(v_changed) > 0 then
    insert into public.profile_change_log (actor_user_id, entity_type, entity_id, fields, source)
    values (auth.uid(), 'worker', w.id, v_changed, 'self');
  end if;
end;
$$;

-- 5) Dono da empresa edita nome fantasia, contato e endereço. Membro só lê. CNPJ e razão social: só a equipe.
create function public.update_company_profile(p_company uuid, p jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.companies%rowtype;
  v_trade text; v_email text; v_phone text; v_changed text[] := '{}';
begin
  if not public.is_company_owner(p_company) then
    raise exception 'Só o responsável pela conta da empresa pode alterar estes dados.' using errcode = 'P0001';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Nada para atualizar.' using errcode = 'P0001'; end if;
  if p ? 'cnpj' or p ? 'legal_name' then raise exception 'CNPJ e razão social só podem ser alterados pela equipe.' using errcode = 'P0001'; end if;
  select * into c from public.companies where id = p_company for update;

  if p ? 'trade_name' then
    v_trade := nullif(btrim(coalesce(p ->> 'trade_name', '')), '');
    if char_length(coalesce(v_trade, '')) > 160 then raise exception 'O nome fantasia pode ter até 160 caracteres.' using errcode = 'P0001'; end if;
    if v_trade is distinct from c.trade_name then
      update public.companies set trade_name = v_trade where id = p_company; v_changed := v_changed || 'trade_name'::text;
    end if;
  end if;
  if p ? 'contact_email' then
    v_email := nullif(lower(btrim(coalesce(p ->> 'contact_email', ''))), '');
    if v_email is not null and (v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254) then
      raise exception 'Informe um e-mail de contato válido.' using errcode = 'P0001';
    end if;
    if v_email is distinct from c.contact_email then
      update public.companies set contact_email = v_email where id = p_company; v_changed := v_changed || 'contact_email'::text;
    end if;
  end if;
  if p ? 'contact_phone' then
    v_phone := nullif(regexp_replace(coalesce(p ->> 'contact_phone', ''), '\D', '', 'g'), '');
    if v_phone is not null and v_phone !~ '^[1-9][0-9](9[0-9]{8}|[2-5][0-9]{7})$' then
      raise exception 'Informe um telefone válido com DDD: celular com 9 dígitos ou fixo com 8.' using errcode = 'P0001';
    end if;
    if v_phone is distinct from c.contact_phone then
      update public.companies set contact_phone = v_phone where id = p_company; v_changed := v_changed || 'contact_phone'::text;
    end if;
  end if;
  if p ? 'address' then v_changed := v_changed || private.update_address(c.address_id, p -> 'address'); end if;

  if cardinality(v_changed) > 0 then
    insert into public.profile_change_log (actor_user_id, entity_type, entity_id, fields, source)
    values (auth.uid(), 'company', p_company, v_changed, 'self');
  end if;
end;
$$;

-- 6) Troca de CPF, CNPJ ou razão social (decisão C4): privilégio próprio, separado de platform_admin,
--    concedido só à conta do responsável por script operacional (nunca pelo cadastro público). Exige motivo e
--    referência curta do documento conferido; o arquivo não é guardado. A trilha não guarda valores (C3).
create table private.document_officers (
  user_id uuid primary key references auth.users (id) on delete cascade,
  granted_at timestamptz not null default now()
);
revoke all on private.document_officers from public, anon, authenticated;

create function public.ops_change_document(p_entity text, p_id uuid, p_new_value text, p_justification text, p_evidence_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_just text := btrim(coalesce(p_justification, '')); v_ref text := btrim(coalesce(p_evidence_ref, '')); v_value text;
begin
  if not exists (select 1 from private.document_officers where user_id = auth.uid()) then
    raise exception 'acesso negado' using errcode = '42501';
  end if;
  if char_length(v_just) not between 10 and 500 then raise exception 'Informe o motivo com 10 a 500 caracteres.' using errcode = 'P0001'; end if;
  if char_length(v_ref) not between 3 and 200 then raise exception 'Informe a referência do documento conferido (3 a 200 caracteres).' using errcode = 'P0001'; end if;

  if p_entity = 'worker_cpf' then
    v_value := regexp_replace(coalesce(p_new_value, ''), '\D', '', 'g');
    if not private.valid_cpf(v_value) then raise exception 'CPF inválido.' using errcode = 'P0001'; end if;
    update public.workers set cpf = v_value where id = p_id;
    if not found then raise exception 'Trabalhador não encontrado.' using errcode = 'P0001'; end if;
    insert into public.profile_change_log (actor_user_id, entity_type, entity_id, fields, source, justification, evidence_ref)
    values (auth.uid(), 'worker', p_id, '{cpf}', 'platform', v_just, v_ref);
  elsif p_entity = 'company_cnpj' then
    v_value := upper(regexp_replace(coalesce(p_new_value, ''), '[^0-9A-Za-z]', '', 'g'));
    if not private.valid_cnpj(v_value) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
    begin
      update public.companies set cnpj = v_value where id = p_id;
    exception when unique_violation then raise exception 'Já existe uma empresa com este CNPJ.' using errcode = 'P0001'; end;
    if not found then raise exception 'Empresa não encontrada.' using errcode = 'P0001'; end if;
    insert into public.profile_change_log (actor_user_id, entity_type, entity_id, fields, source, justification, evidence_ref)
    values (auth.uid(), 'company', p_id, '{cnpj}', 'platform', v_just, v_ref);
  elsif p_entity = 'company_legal_name' then
    v_value := btrim(coalesce(p_new_value, ''));
    if char_length(v_value) not between 2 and 160 then raise exception 'Informe a razão social.' using errcode = 'P0001'; end if;
    update public.companies set legal_name = v_value where id = p_id;
    if not found then raise exception 'Empresa não encontrada.' using errcode = 'P0001'; end if;
    insert into public.profile_change_log (actor_user_id, entity_type, entity_id, fields, source, justification, evidence_ref)
    values (auth.uid(), 'company', p_id, '{legal_name}', 'platform', v_just, v_ref);
  else
    raise exception 'Tipo de alteração inválido.' using errcode = 'P0001';
  end if;
end;
$$;

-- Trilha de um trabalhador ou empresa, para a equipe (sem valores).
create function public.ops_profile_changes(p_entity_id uuid)
returns table (entity_type text, fields text[], source text, justification text, evidence_ref text, actor_user_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() and not exists (select 1 from private.document_officers where user_id = auth.uid()) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select l.entity_type, l.fields, l.source, l.justification, l.evidence_ref, l.actor_user_id, l.created_at
  from public.profile_change_log l where l.entity_id = p_entity_id order by l.created_at desc;
end;
$$;

revoke execute on function public.update_worker_profile(jsonb), public.update_company_profile(uuid, jsonb),
  public.ops_change_document(text, uuid, text, text, text), public.ops_profile_changes(uuid) from public, anon;
grant execute on function public.update_worker_profile(jsonb), public.update_company_profile(uuid, jsonb),
  public.ops_change_document(text, uuid, text, text, text), public.ops_profile_changes(uuid) to authenticated;

-- 7) Fim do update direto (vai junto com o front que usa as RPCs).
drop policy workers_update on public.workers;
drop policy companies_update on public.companies;
drop policy addresses_update on public.addresses;
revoke update on public.workers, public.companies, public.addresses from authenticated;

-- Concessão do privilégio de documentos (fora do cadastro e fora das migrations; rodar uma vez, pelo SQL Editor,
-- com o id da conta do responsável conferido no painel de Auth):
--   insert into private.document_officers (user_id) values ('<id da conta do responsável>');
-- Revogação: delete from private.document_officers where user_id = '<id>';

-- Rollback (só com decisão registrada):
--   grant update (full_name, phone) on public.workers to authenticated;
--   grant update (legal_name, trade_name, contact_email, contact_phone) on public.companies to authenticated;
--   grant update (zip_code, street_type, street_name, number, complement, neighborhood, city, state) on public.addresses to authenticated;
--   recriar workers_update, companies_update e addresses_update como em 20261027002812;
--   reaplicar private.create_profile de 20261106120000. As RPCs e a trilha podem ficar.
