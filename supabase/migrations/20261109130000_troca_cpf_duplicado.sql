-- Troca de CPF pela equipe (ops_change_document, ramo worker_cpf): recusa CPF de outro trabalhador.
-- public.workers.cpf não tem restrição de unicidade (só companies.cnpj tem), então o update nunca gera unique_violation:
-- a checagem é explícita, antes do update. O tratamento de unique_violation fica também, para o caso de um índice
-- único ser criado depois (decisão à parte, ver TASK-0037).
-- Só create or replace: mesma assinatura, mesmas permissões; nenhuma tabela, política ou dado muda.
-- Rollback: reaplicar a definição de 20261108120000_meu_perfil.sql.

create or replace function public.ops_change_document(p_entity text, p_id uuid, p_new_value text, p_justification text, p_evidence_ref text)
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
    if exists (select 1 from public.workers where cpf = v_value and id <> p_id) then
      raise exception 'Já existe um trabalhador com este CPF.' using errcode = 'P0001';
    end if;
    begin
      update public.workers set cpf = v_value where id = p_id;
    exception when unique_violation then raise exception 'Já existe um trabalhador com este CPF.' using errcode = 'P0001'; end;
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
