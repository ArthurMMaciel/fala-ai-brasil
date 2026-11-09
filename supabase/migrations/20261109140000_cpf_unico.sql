-- CPF único por trabalhador (decisão do responsável em 2026-11-09; TASK-0037).
-- 1) Restrição workers_cpf_key. A coluna já é NOT NULL e só aceita 11 dígitos (check), e todo caminho de escrita grava
--    só dígitos, então não há expressão de normalização nem índice parcial. O ADD CONSTRAINT pega ACCESS EXCLUSIVE em
--    workers enquanto cria o índice (8 linhas no remoto em 2026-11-09, sem duplicados: milissegundos).
-- 2) private.create_profile (usado pelo gatilho do signUp e por public.add_profile) captura unique_violation no insert de
--    workers e relança mensagem genérica com o mesmo código 23505, sem DETAIL nem nome de restrição: o CPF não aparece no
--    erro devolvido nem no log do banco. O signUp continua 500 genérico no Auth; add_profile continua 23505 para o front.
-- ops_change_document (20261109130000) não muda: o exists e o handler de unique_violation já cobrem a troca pela equipe.
-- Rollback: alter table public.workers drop constraint workers_cpf_key; e reaplicar private.create_profile de
-- 20261108120000_meu_perfil.sql. Nenhum dado é alterado.

alter table public.workers add constraint workers_cpf_key unique (cpf);

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
