-- ADR-0023 (aceita em 2026-11-17) e ADR-0017 (aceita em 2026-11-17), migration 1 de 2: estrutura.
-- Só aditiva. Não muda acesso de ninguém: tabelas novas sem grant para anon/authenticated; companies só ganha colunas.
-- Funciona com ou sem a Edge Function cnpj-lookup: sem ela, o cache fica vazio e o pré-cadastro segue pelo manual
-- (plano B); a cota vale para o pré-cadastro (banco) e para a busca (função).
-- Desvio registrado em relação ao ERD da ADR-0023: os dados de origem da empresa pré-cadastrada (município, UF,
-- situação, CNAE, natureza, provedor) ficam em private.company_preregistrations, e não em companies, para não expô-los
-- a quem lê companies e para não gravar quem criou a empresa (companies.created_by fica nulo: gravar o trabalhador
-- ligaria a conta ao empregador).
-- Sem enum novo: estados em text + check.
-- service_role (chave da Edge Function) sem acesso direto a nenhuma tabela nova: só às três RPCs do cache e da cota. Os
-- e-mails indicados (complaint_contacts) e os avisos ficam fora do alcance dela (revisão do DevOps, 2026-11-18).
-- Revisão de 2026-11-19 (responsável, "Isso, confirmo"): contato do trabalhador vale para qualquer empresa, com e-mail
-- e/ou telefone; o cache guarda também o e-mail da Receita (só para a equipe, destino alternativo do aviso); o aviso
-- registra a origem do destino (worker ou receita).
--
-- Rollback (antes da migration 2): drop function public.cnpj_cache_get(text), public.cnpj_cache_put(text, boolean, text, text,
--   text, text, text, text, text, text, text), public.cnpj_quota_take(uuid), private.take_quota(uuid, text, integer);
--   drop table private.notice_opt_outs, public.company_notices, public.complaint_contacts, private.company_preregistrations,
--   private.cnpj_lookup_quota, private.cnpj_cache; drop function private.company_notice_guard();
--   alter table public.companies drop constraint companies_address_when_registered, drop column data_source,
--   drop column registration_status;  -- e só então: alter column address_id set not null (exige nenhuma empresa sem endereço).

set local lock_timeout = '5s';

-- 1) Empresa pré-cadastrada: existe sem cadastro próprio, sem endereço completo e sem vínculo (ADR-0012 D9).
alter table public.companies
  add column registration_status text not null default 'registered'
    check (registration_status in ('registered', 'pre_registered', 'pending_check')),
  add column data_source text not null default 'signup'
    check (data_source in ('signup', 'cnpj_api', 'manual')),
  alter column address_id drop not null,
  add constraint companies_address_when_registered check (registration_status <> 'registered' or address_id is not null);

-- Dados de origem e conferência da equipe. Uma linha por empresa pré-cadastrada; não guarda quem a criou.
create table private.company_preregistrations (
  company_id uuid primary key references public.companies (id) on delete cascade,
  original_name text check (original_name is null or char_length(original_name) between 1 and 160),  -- razão social do pré-cadastro, guardada para a verificação depois da reivindicação
  city text check (city is null or char_length(btrim(city)) between 2 and 80),
  state text check (state is null or state ~ '^[A-Z]{2}$'),
  cadastral_situation text check (cadastral_situation is null or char_length(cadastral_situation) <= 40),
  main_cnae text check (main_cnae is null or main_cnae ~ '^[0-9]{7}$'),
  legal_nature text check (legal_nature is null or legal_nature ~ '^[0-9]{3,4}$'),
  natural_person boolean not null default false,  -- MEI ou empresário individual: o aviso à empresa é recusado
  provider text check (provider is null or provider in ('minhareceita', 'brasilapi')),
  fetched_at timestamptz,
  review_decision text check (review_decision is null or review_decision in ('confirmed', 'blocked')),
  review_reason text check (review_reason is null or char_length(btrim(review_reason)) between 10 and 300),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (review_decision is distinct from 'blocked' or review_reason is not null)
);
revoke all on private.company_preregistrations from public, anon, authenticated, service_role;

-- 2) Cache de dados públicos de pessoa jurídica (ADR-0017 D4 a D6, com a aceitação: não é apagado, é renovado).
-- Não registra quem consultou. Pessoa física fica só com a marca, sem nome e sem e-mail.
create table private.cnpj_cache (
  cnpj text primary key check (cnpj ~ '^[0-9A-Z]{12}[0-9]{2}$'),
  natural_person boolean not null,
  legal_name text check (legal_name is null or char_length(legal_name) between 1 and 160),
  trade_name text check (trade_name is null or char_length(trade_name) <= 160),
  cadastral_situation text check (cadastral_situation is null or char_length(cadastral_situation) <= 40),
  city text check (city is null or char_length(city) <= 80),
  state text check (state is null or state ~ '^[A-Z]{2}$'),
  main_cnae text check (main_cnae is null or main_cnae ~ '^[0-9]{7}$'),
  legal_nature text check (legal_nature is null or legal_nature ~ '^[0-9]{3,4}$'),
  provider text not null check (provider in ('minhareceita', 'brasilapi')),
  fetched_at timestamptz not null default now(),
  -- E-mail do cadastro da Receita: destino alternativo do aviso, visível só para a equipe (revisão de 2026-11-19).
  email text check (email is null or (char_length(email) <= 254 and email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  check (not natural_person or (legal_name is null and trade_name is null and email is null)),
  check (natural_person or legal_name is not null)
);
revoke all on private.cnpj_cache from public, anon, authenticated, service_role;

-- 3) Cota por conta, sem o CNPJ (ADR-0017 D9). 'minute'/'day': busca pela função; 'prereg_day': pré-cadastro no banco.
create table private.cnpj_lookup_quota (
  user_id uuid not null,
  window_kind text not null check (window_kind in ('minute', 'day', 'prereg_day')),
  window_start timestamptz not null,
  lookups integer not null default 0 check (lookups >= 0),
  primary key (user_id, window_kind, window_start)
);
revoke all on private.cnpj_lookup_quota from public, anon, authenticated, service_role;

-- Conta uma tentativa e diz se ainda está dentro do limite. Apaga as janelas da conta com mais de 2 dias.
create function private.take_quota(p_user uuid, p_kind text, p_limit integer)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_start timestamptz; v_count integer;
begin
  if p_user is null or p_kind not in ('minute', 'day', 'prereg_day') then return false; end if;
  v_start := date_trunc(case when p_kind = 'minute' then 'minute' else 'day' end, now());
  delete from private.cnpj_lookup_quota where user_id = p_user and window_start < now() - interval '2 days';
  insert into private.cnpj_lookup_quota as q (user_id, window_kind, window_start, lookups) values (p_user, p_kind, v_start, 1)
  on conflict (user_id, window_kind, window_start) do update set lookups = q.lookups + 1
  returning lookups into v_count;
  return v_count <= p_limit;
end;
$$;
revoke all on function private.take_quota(uuid, text, integer) from public, anon, authenticated, service_role;

-- 4) Interface da Edge Function (service_role). O esquema private não é exposto pela API; estas três ficam em public,
-- executáveis só pela service_role. A assinatura de cnpj_cache_put é a lista branca: nada fora dela entra.
create function public.cnpj_cache_get(p_cnpj text)
returns table (natural_person boolean, legal_name text, trade_name text, cadastral_situation text, city text, state text,
               main_cnae text, legal_nature text, provider text, fetched_at timestamptz, stale boolean)
language sql stable security definer set search_path = '' as $$
  select c.natural_person, c.legal_name, c.trade_name, c.cadastral_situation, c.city, c.state, c.main_cnae, c.legal_nature,
         c.provider, c.fetched_at, c.fetched_at < now() - interval '30 days'
  from private.cnpj_cache c where c.cnpj = upper(regexp_replace(coalesce(p_cnpj, ''), '[^0-9A-Za-z]', '', 'g'));
$$;

create function public.cnpj_cache_put(p_cnpj text, p_natural_person boolean, p_legal_name text, p_trade_name text,
                                      p_cadastral_situation text, p_city text, p_state text, p_main_cnae text,
                                      p_legal_nature text, p_provider text, p_email text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_cnpj text := upper(regexp_replace(coalesce(p_cnpj, ''), '[^0-9A-Za-z]', '', 'g'));
  v_np boolean := coalesce(p_natural_person, true);  -- sem a informação, trata como pessoa física (sem nome)
  v_cnae text := regexp_replace(coalesce(p_main_cnae, ''), '\D', '', 'g');  -- lpad só até 7: lpad corta o que passa
  v_nature text := nullif(regexp_replace(coalesce(p_legal_nature, ''), '\D', '', 'g'), '');
  v_state text := upper(nullif(btrim(p_state), ''));
  v_email text := lower(nullif(btrim(p_email), ''));
begin
  if not private.valid_cnpj(v_cnpj) then raise exception 'CNPJ inválido.' using errcode = 'P0001'; end if;
  -- Valores fora do formato viram nulo em vez de erro: o provedor não tem contrato estável.
  if not v_np and nullif(btrim(p_legal_name), '') is null then v_np := true; end if;
  insert into private.cnpj_cache as c (cnpj, natural_person, legal_name, trade_name, cadastral_situation, city, state,
                                       main_cnae, legal_nature, provider, fetched_at, email)
  values (v_cnpj, v_np,
          case when v_np then null else left(btrim(p_legal_name), 160) end,
          case when v_np then null else left(nullif(btrim(p_trade_name), ''), 160) end,
          left(nullif(btrim(p_cadastral_situation), ''), 40), left(nullif(btrim(p_city), ''), 80),
          case when v_state ~ '^[A-Z]{2}$' then v_state end,
          case when char_length(v_cnae) between 5 and 7 then lpad(v_cnae, 7, '0') end,
          case when v_nature ~ '^[0-9]{3,4}$' then v_nature end, p_provider, now(),
          case when not v_np and char_length(v_email) <= 254 and v_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v_email end)
  on conflict (cnpj) do update set
    natural_person = excluded.natural_person, legal_name = excluded.legal_name, trade_name = excluded.trade_name,
    cadastral_situation = excluded.cadastral_situation, city = excluded.city, state = excluded.state,
    main_cnae = excluded.main_cnae, legal_nature = excluded.legal_nature, provider = excluded.provider, fetched_at = now(),
    email = excluded.email;
end;
$$;

-- Cota da busca: 10 por minuto e 50 por dia por conta (ADR-0017 D9). Devolve false acima do limite.
create function public.cnpj_quota_take(p_user uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  return private.take_quota(p_user, 'minute', 10) and private.take_quota(p_user, 'day', 50);
end;
$$;

revoke all on function public.cnpj_cache_get(text),
  public.cnpj_cache_put(text, boolean, text, text, text, text, text, text, text, text, text),
  public.cnpj_quota_take(uuid) from public, anon, authenticated;
grant execute on function public.cnpj_cache_get(text),
  public.cnpj_cache_put(text, boolean, text, text, text, text, text, text, text, text, text),
  public.cnpj_quota_take(uuid) to service_role;

-- 5) Contato indicado pelo trabalhador na manifestação (ADR-0012 D4; revisão de 2026-11-19): um por manifestação, para
-- qualquer empresa, cadastrada ou não; e-mail e/ou telefone. Não é representante. A empresa nunca lê; só o trabalhador
-- dono e a equipe. Na empresa não cadastrada, é o destino do aviso; na cadastrada, segundo canal para a equipe.
create table public.complaint_contacts (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null unique references public.complaints (id) on delete cascade,
  email text check (email is null or (char_length(email) <= 254 and email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  phone text check (phone is null or phone ~ '^\d{10,11}$'),
  check (email is not null or phone is not null),
  possibly_involved boolean not null,
  worker_consented boolean not null check (worker_consented),
  status text not null default 'candidate' check (status in ('candidate', 'verified', 'rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.complaint_contacts enable row level security;
revoke all on public.complaint_contacts from public, anon, authenticated, service_role;

-- 6) Avisos: decisão da equipe e envio. Só inserção; a única mudança aceita é approved -> sent|bounced, sent -> bounced e o
-- set null das chaves (contato apagado pela retenção, manifestação apagada com a conta).
create table public.company_notices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  complaint_id uuid references public.complaints (id) on delete set null,
  contact_id uuid references public.complaint_contacts (id) on delete set null,
  status text not null check (status in ('approved', 'sent', 'rejected', 'bounced')),
  destination_source text check (destination_source is null or destination_source in ('worker', 'receita')),  -- nulo na recusa
  reason text check (reason is null or char_length(btrim(reason)) between 10 and 300),
  decided_by uuid not null,
  decided_at timestamptz not null default now(),
  sent_by uuid,
  sent_at timestamptz,
  check (status <> 'rejected' or reason is not null),
  check (status = 'rejected' or destination_source is not null)
);
create unique index company_notices_one_active on public.company_notices (complaint_id) where status in ('approved', 'sent');
create index company_notices_company_idx on public.company_notices (company_id, decided_at);
alter table public.company_notices enable row level security;
revoke all on public.company_notices from public, anon, authenticated, service_role;

create function private.company_notice_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.id = old.id and new.company_id = old.company_id and new.decided_by = old.decided_by
     and new.decided_at = old.decided_at and new.reason is not distinct from old.reason
     and new.destination_source is not distinct from old.destination_source then
    -- set null das chaves estrangeiras, sem outra mudança
    if new.status = old.status and new.sent_by is not distinct from old.sent_by and new.sent_at is not distinct from old.sent_at
       and (new.complaint_id is not distinct from old.complaint_id or new.complaint_id is null)
       and (new.contact_id is not distinct from old.contact_id or new.contact_id is null) then
      return new;
    end if;
    -- envio ou devolução
    if new.complaint_id is not distinct from old.complaint_id and new.contact_id is not distinct from old.contact_id
       and ((old.status = 'approved' and new.status in ('sent', 'bounced')) or (old.status = 'sent' and new.status = 'bounced')) then
      return new;
    end if;
  end if;
  raise exception 'Registro de aviso não pode ser alterado nem apagado.' using errcode = 'P0001';
end;
$$;
revoke all on function private.company_notice_guard() from public, anon, authenticated, service_role;
create trigger company_notices_guard before update or delete on public.company_notices
  for each row execute function private.company_notice_guard();

-- 7) Quem pediu para não receber avisos: só o hash do e-mail normalizado (ADR-0012 D8).
create table private.notice_opt_outs (
  email_hash text primary key check (email_hash ~ '^[0-9a-f]{64}$'),
  added_by uuid not null,
  created_at timestamptz not null default now()
);
revoke all on private.notice_opt_outs from public, anon, authenticated, service_role;
