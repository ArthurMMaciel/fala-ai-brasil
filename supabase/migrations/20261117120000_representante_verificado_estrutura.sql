-- ADR-0012 (recorte do piloto, V1 + C1 + R3), parte 1 de 2: estrutura da verificação do representante.
-- Não muda acesso a manifestações; a troca do gate fica na 20261117130000.
-- Todo vínculo existente e todo cadastro novo nasce 'pending' (default da coluna; o cliente só tem SELECT em company_users).
-- A verificação é feita pela equipe por ligação ao telefone público da empresa ('callback') ou por documento de
-- representação conferido fora da plataforma ('document_review'); nenhum arquivo é guardado.
-- Sem enum novo: estados em text + check, para tudo rodar numa transação só.
--
-- Rollback (antes da 20261117130000): drop function public.ops_verify_representative(uuid, uuid, text, text, text, text),
--   public.ops_list_representatives(text), public.ops_representative_history(uuid), public.is_verified_company_user(uuid);
--   drop table public.representative_verifications; drop function private.block_trail_change();
--   alter table public.company_users drop column verified_at, drop column verification_status;
--   Antes do drop da tabela, exportar a trilha.

-- 1) Estado do vínculo.
alter table public.company_users
  add column verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected', 'revoked')),
  add column verified_at timestamptz;

-- 2) Histórico das decisões: só inserção, sobrevive à exclusão da conta (sem FK para auth.users).
create table public.representative_verifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  user_id uuid not null,
  decision text not null check (decision in ('verified', 'rejected', 'revoked')),
  method text check (method is null or method in ('callback', 'document_review')),
  evidence_ref text check (evidence_ref is null or char_length(btrim(evidence_ref)) between 3 and 200),
  reason text check (reason is null or char_length(btrim(reason)) between 10 and 500),
  reviewer_id uuid not null,
  created_at timestamptz not null default now(),
  check (decision <> 'verified' or (method is not null and evidence_ref is not null)),
  check (decision = 'verified' or reason is not null)
);
create index representative_verifications_company_idx on public.representative_verifications (company_id, created_at);
alter table public.representative_verifications enable row level security;
revoke all on public.representative_verifications from public, anon, authenticated;

-- Trilha imutável (lacuna 2 da TASK-0009): nem o dono altera ou apaga por engano; retenção futura troca este gatilho.
create function private.block_trail_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Registro de auditoria não pode ser alterado nem apagado.' using errcode = 'P0001';
end;
$$;
revoke all on function private.block_trail_change() from public, anon, authenticated;
create trigger representative_verifications_immutable before update or delete on public.representative_verifications
  for each row execute function private.block_trail_change();

-- 3) Gate novo (usado pela 20261117130000).
create function public.is_verified_company_user(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.company_users
                 where company_id = p_company and user_id = auth.uid() and verification_status = 'verified');
$$;
revoke execute on function public.is_verified_company_user(uuid) from public, anon;
grant execute on function public.is_verified_company_user(uuid) to authenticated;

-- 4) Fila da equipe: e-mail de login para a ligação de conferência; nada de manifestação.
create function public.ops_list_representatives(p_status text default 'pending')
returns table (company_id uuid, company_name text, cnpj text, user_id uuid, email text, role public.member_role,
               verification_status text, linked_at timestamptz, verified_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select co.id, coalesce(co.trade_name, co.legal_name), co.cnpj, cu.user_id, u.email::text, cu.role,
         cu.verification_status, cu.created_at, cu.verified_at
  from public.company_users cu
  join public.companies co on co.id = cu.company_id
  left join auth.users u on u.id = cu.user_id
  where p_status is null or cu.verification_status = p_status
  order by cu.created_at;
end;
$$;

-- 5) Decisão da equipe. Transições: pending|rejected -> verified|rejected; verified -> revoked; revoked -> verified.
create function public.ops_verify_representative(p_company uuid, p_user uuid, p_decision text,
                                                 p_method text default null, p_evidence_ref text default null, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
  v_method text := nullif(btrim(coalesce(p_method, '')), '');
  v_ref text := nullif(btrim(coalesce(p_evidence_ref, '')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select verification_status into v_status from public.company_users
  where company_id = p_company and user_id = p_user for update;
  if v_status is null then raise exception 'Vínculo não encontrado.' using errcode = 'P0001'; end if;
  if p_decision not in ('verified', 'rejected', 'revoked') then raise exception 'Decisão inválida.' using errcode = 'P0001'; end if;
  if not ((v_status in ('pending', 'rejected') and p_decision in ('verified', 'rejected'))
          or (v_status = 'verified' and p_decision = 'revoked')
          or (v_status = 'revoked' and p_decision = 'verified')) then
    raise exception 'Transição não permitida a partir do estado atual.' using errcode = 'P0001';
  end if;
  if p_decision = 'verified' then
    if v_method is null or v_method not in ('callback', 'document_review') then
      raise exception 'Informe o método: ligação ou documento conferido.' using errcode = 'P0001';
    end if;
    if v_ref is null or char_length(v_ref) not between 3 and 200 then
      raise exception 'Informe a referência da conferência (3 a 200 caracteres, sem número de documento).' using errcode = 'P0001';
    end if;
  elsif v_reason is null or char_length(v_reason) not between 10 and 500 then
    raise exception 'Informe o motivo (10 a 500 caracteres).' using errcode = 'P0001';
  end if;

  insert into public.representative_verifications (company_id, user_id, decision, method, evidence_ref, reason, reviewer_id)
  values (p_company, p_user, p_decision,
          case when p_decision = 'verified' then v_method end,
          case when p_decision = 'verified' then v_ref end,
          v_reason, auth.uid());
  update public.company_users
  set verification_status = p_decision, verified_at = case when p_decision = 'verified' then now() else verified_at end
  where company_id = p_company and user_id = p_user;
end;
$$;

-- 6) Histórico para a equipe.
create function public.ops_representative_history(p_company uuid)
returns table (user_id uuid, decision text, method text, evidence_ref text, reason text, reviewer_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select v.user_id, v.decision, v.method, v.evidence_ref, v.reason, v.reviewer_id, v.created_at
  from public.representative_verifications v where v.company_id = p_company order by v.created_at;
end;
$$;

revoke execute on function public.ops_list_representatives(text), public.ops_verify_representative(uuid, uuid, text, text, text, text),
  public.ops_representative_history(uuid) from public, anon;
grant execute on function public.ops_list_representatives(text), public.ops_verify_representative(uuid, uuid, text, text, text, text),
  public.ops_representative_history(uuid) to authenticated;
