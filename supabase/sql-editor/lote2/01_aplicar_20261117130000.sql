-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/pending/20261117130000_representante_verificado_gate.sql. Não editar à mão.
-- Passo 01 de 05. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 01_conferir_20261117130000.sql (todas as linhas com ok = true).
-- AVISO: a partir deste passo, só representante verificado vê manifestações e responde; confira antes a fila da Operação.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261117130000') then
    raise exception 'A migration 20261117130000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261117150000') then
    raise exception 'Falta a 20261117150000 (passo anterior). Nada foi feito.';
  end if;
  if not exists (select 1 from public.company_users where verification_status = 'verified') then
    raise exception 'Nenhum representante verificado. Verifique antes as empresas reais na fila da Operação: depois deste passo, só vínculo verificado vê manifestações. Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261117130000_representante_verificado_gate.sql (8 instruções) ========
-- ADR-0012 (recorte do piloto), parte 2 de 2: troca do gate. Só o vínculo 'verified' vê e responde manifestações
-- e vê os próprios números; o vínculo 'pending', 'rejected' ou 'revoked' continua com portal, perfil e diretório.
-- Depende da 20261109180000 (respond_complaint com revisão) e da 20261117120000.
-- Fica em supabase/pending/ até o Front publicar a fila de verificação; só então é movida para supabase/migrations/.
-- Corpos copiados das últimas definições (170000, 150000, 180000), com is_company_user -> is_verified_company_user
-- e o filtro verification_status = 'verified' nas duas funções de números próprios. Mesmas assinaturas: os grants seguem.
--
-- ATENÇÃO na aplicação: todo vínculo existente nasce 'pending' pela 20261117120000. Depois desta migration, nenhuma
-- empresa vê manifestação até a equipe verificar o representante (ops_verify_representative).
--
-- Também: update_company_profile recusa vínculo 'rejected' ou 'revoked' (ajuste aceito pelo Gestor em 17/11, dentro da ADR-0012).
--
-- Rollback: reaplicar os mesmos blocos trocando is_verified_company_user por is_company_user e retirando o filtro
-- verification_status (texto pronto em supabase/tests/rollback/20261117130000_rollback.sql). Isso reabre o risco do
-- representante não verificado; só com decisão registrada.

create or replace function public.list_company_complaints()
returns table (id uuid, protocol text, category text, title text, status public.complaint_status, shared_content text,
               created_at timestamptz, updated_at timestamptz, responses integer, last_response_at timestamptz, worker_feedback public.complaint_feedback)
language sql stable security definer set search_path = '' as $$
  select c.id, c.protocol, c.category, c.title, c.status, s.shared_content, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select max(r.created_at) from public.company_responses r where r.complaint_id = c.id),
         c.worker_feedback
  from public.complaints c
  join public.complaint_shared_versions s on s.complaint_id = c.id
  where c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
  order by c.created_at desc;
$$;

create or replace function public.get_company_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.kind, t.status, t.actor, t.content, t.created_at
  from (
    select 'event'::text as kind, e.status, e.actor, e.note as content, e.created_at, 4 as kind_rank, e.id
    from public.complaint_events e
    join public.complaints c on c.id = e.complaint_id
    where e.complaint_id = p_id and c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
      and e.status in ('shared', 'answered', 'closed')
    union all
    select 'response'::text, null::public.complaint_status, 'company'::public.complaint_actor, r.content, r.created_at, 2, r.id
    from public.company_responses r
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and public.is_verified_company_user(c.company_id)
    union all
    select 'response_review'::text, null::public.complaint_status, 'platform'::public.complaint_actor,
           case rv.decision when 'released' then 'Resposta liberada ao trabalhador.' else 'Resposta devolvida para ajuste: ' || rv.reason end,
           rv.created_at, 1, rv.id
    from public.company_response_reviews rv
    join public.company_responses r on r.id = rv.response_id
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and rv.decision in ('released', 'returned') and public.is_verified_company_user(c.company_id)
  ) t
  order by t.created_at, t.kind_rank, t.status nulls first, t.id;
$$;

create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_verified_company_user(v_company) or v_status not in ('shared', 'answer_in_review', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if v_status = 'answer_in_review' or exists (select 1 from public.company_responses where complaint_id = p_id and review_status = 'in_review') then
    raise exception 'Já existe uma resposta em revisão pela equipe.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'in_review');
  update public.complaints set status = 'answer_in_review' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, 'answer_in_review', 'company', 'A empresa respondeu. A equipe revisa a resposta antes de você receber.');
end;
$$;

create or replace function public.company_ranking()
returns table (company_id uuid, name text, city text, state text, received integer, response_rate integer, avg_first_response_hours integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state, s.released, round(s.rate)::int, round(s.avg_hours)::int,
         public.is_verified_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by 6 desc, 7 asc nulls last;
$$;

create or replace function public.company_responsiveness()
returns table (company_id uuid, name text, city text, state text, response_band text, response_time_band text,
               satisfaction_band text, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state,
         private.response_band(s.rate), private.response_time_band(s.avg_hours),
         null::text, public.is_verified_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$;

create or replace function public.my_company_responsiveness()
returns table (company_id uuid, name text, released integer, answered integer, response_rate integer,
               avg_first_response_hours integer, response_band text, response_time_band text, listed boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name),
         coalesce(s.released, 0), coalesce(s.answered, 0),
         round(s.rate)::int, round(s.avg_hours)::int,
         private.response_band(s.rate),
         case when coalesce(s.released, 0) = 0 then null else private.response_time_band(s.avg_hours) end,
         coalesce(s.released, 0) >= 3
  from public.company_users cu
  join public.companies co on co.id = cu.company_id
  left join private.company_response_stats() s on s.company_id = co.id
  where cu.user_id = auth.uid() and cu.verification_status = 'verified'
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$;

create or replace function public.my_company_satisfaction()
returns table (company_id uuid, ratings integer, satisfaction_band text)
language sql stable security definer set search_path = '' as $$
  select cu.company_id, case when count(rr.response_id) < 3 then null else count(rr.response_id)::int end,
         case when count(rr.response_id) < 3 then null
              else private.response_band(100.0 * avg(case rr.rating when 'yes' then 1 when 'partial' then 0.5 else 0 end)) end
  from public.company_users cu
  left join public.company_responses r on r.company_id = cu.company_id
  left join public.response_ratings rr on rr.response_id = r.id
  where cu.user_id = auth.uid() and cu.verification_status = 'verified'
  group by cu.company_id;
$$;

-- Vínculo recusado ou revogado também perde a edição do perfil da empresa (inclusive contato). 'pending' continua
-- editando para completar o cadastro. Corpo de 20261108120000 com a checagem nova depois da de dono.
create or replace function public.update_company_profile(p_company uuid, p jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.companies%rowtype;
  v_trade text; v_email text; v_phone text; v_changed text[] := '{}';
begin
  if not public.is_company_owner(p_company) then
    raise exception 'Só o responsável pela conta da empresa pode alterar estes dados.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.company_users where company_id = p_company and user_id = auth.uid()
             and verification_status in ('rejected', 'revoked')) then
    raise exception 'Vínculo com a empresa recusado ou revogado pela equipe.' using errcode = 'P0001';
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
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261117130000', 'representante_verificado_gate', array[
$s0$-- ADR-0012 (recorte do piloto), parte 2 de 2: troca do gate. Só o vínculo 'verified' vê e responde manifestações
-- e vê os próprios números; o vínculo 'pending', 'rejected' ou 'revoked' continua com portal, perfil e diretório.
-- Depende da 20261109180000 (respond_complaint com revisão) e da 20261117120000.
-- Fica em supabase/pending/ até o Front publicar a fila de verificação; só então é movida para supabase/migrations/.
-- Corpos copiados das últimas definições (170000, 150000, 180000), com is_company_user -> is_verified_company_user
-- e o filtro verification_status = 'verified' nas duas funções de números próprios. Mesmas assinaturas: os grants seguem.
--
-- ATENÇÃO na aplicação: todo vínculo existente nasce 'pending' pela 20261117120000. Depois desta migration, nenhuma
-- empresa vê manifestação até a equipe verificar o representante (ops_verify_representative).
--
-- Também: update_company_profile recusa vínculo 'rejected' ou 'revoked' (ajuste aceito pelo Gestor em 17/11, dentro da ADR-0012).
--
-- Rollback: reaplicar os mesmos blocos trocando is_verified_company_user por is_company_user e retirando o filtro
-- verification_status (texto pronto em supabase/tests/rollback/20261117130000_rollback.sql). Isso reabre o risco do
-- representante não verificado; só com decisão registrada.

create or replace function public.list_company_complaints()
returns table (id uuid, protocol text, category text, title text, status public.complaint_status, shared_content text,
               created_at timestamptz, updated_at timestamptz, responses integer, last_response_at timestamptz, worker_feedback public.complaint_feedback)
language sql stable security definer set search_path = '' as $$
  select c.id, c.protocol, c.category, c.title, c.status, s.shared_content, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select max(r.created_at) from public.company_responses r where r.complaint_id = c.id),
         c.worker_feedback
  from public.complaints c
  join public.complaint_shared_versions s on s.complaint_id = c.id
  where c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
  order by c.created_at desc;
$$$s0$,
$s0$create or replace function public.get_company_complaint_timeline(p_id uuid)
returns table (kind text, status public.complaint_status, actor public.complaint_actor, content text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.kind, t.status, t.actor, t.content, t.created_at
  from (
    select 'event'::text as kind, e.status, e.actor, e.note as content, e.created_at, 4 as kind_rank, e.id
    from public.complaint_events e
    join public.complaints c on c.id = e.complaint_id
    where e.complaint_id = p_id and c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
      and e.status in ('shared', 'answered', 'closed')
    union all
    select 'response'::text, null::public.complaint_status, 'company'::public.complaint_actor, r.content, r.created_at, 2, r.id
    from public.company_responses r
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and public.is_verified_company_user(c.company_id)
    union all
    select 'response_review'::text, null::public.complaint_status, 'platform'::public.complaint_actor,
           case rv.decision when 'released' then 'Resposta liberada ao trabalhador.' else 'Resposta devolvida para ajuste: ' || rv.reason end,
           rv.created_at, 1, rv.id
    from public.company_response_reviews rv
    join public.company_responses r on r.id = rv.response_id
    join public.complaints c on c.id = r.complaint_id
    where r.complaint_id = p_id and rv.decision in ('released', 'returned') and public.is_verified_company_user(c.company_id)
  ) t
  order by t.created_at, t.kind_rank, t.status nulls first, t.id;
$$$s0$,
$s0$create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_verified_company_user(v_company) or v_status not in ('shared', 'answer_in_review', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if v_status = 'answer_in_review' or exists (select 1 from public.company_responses where complaint_id = p_id and review_status = 'in_review') then
    raise exception 'Já existe uma resposta em revisão pela equipe.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'in_review');
  update public.complaints set status = 'answer_in_review' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, 'answer_in_review', 'company', 'A empresa respondeu. A equipe revisa a resposta antes de você receber.');
end;
$$$s0$,
$s0$create or replace function public.company_ranking()
returns table (company_id uuid, name text, city text, state text, received integer, response_rate integer, avg_first_response_hours integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state, s.released, round(s.rate)::int, round(s.avg_hours)::int,
         public.is_verified_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by 6 desc, 7 asc nulls last;
$$$s0$,
$s0$create or replace function public.company_responsiveness()
returns table (company_id uuid, name text, city text, state text, response_band text, response_time_band text,
               satisfaction_band text, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name), a.city, a.state,
         private.response_band(s.rate), private.response_time_band(s.avg_hours),
         null::text, public.is_verified_company_user(co.id)
  from private.company_response_stats() s
  join public.companies co on co.id = s.company_id
  join public.addresses a on a.id = co.address_id
  where auth.uid() is not null and s.released >= 3
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$$s0$,
$s0$create or replace function public.my_company_responsiveness()
returns table (company_id uuid, name text, released integer, answered integer, response_rate integer,
               avg_first_response_hours integer, response_band text, response_time_band text, listed boolean)
language sql stable security definer set search_path = '' as $$
  select co.id, coalesce(co.trade_name, co.legal_name),
         coalesce(s.released, 0), coalesce(s.answered, 0),
         round(s.rate)::int, round(s.avg_hours)::int,
         private.response_band(s.rate),
         case when coalesce(s.released, 0) = 0 then null else private.response_time_band(s.avg_hours) end,
         coalesce(s.released, 0) >= 3
  from public.company_users cu
  join public.companies co on co.id = cu.company_id
  left join private.company_response_stats() s on s.company_id = co.id
  where cu.user_id = auth.uid() and cu.verification_status = 'verified'
  order by lower(coalesce(co.trade_name, co.legal_name)), co.id;
$$$s0$,
$s0$create or replace function public.my_company_satisfaction()
returns table (company_id uuid, ratings integer, satisfaction_band text)
language sql stable security definer set search_path = '' as $$
  select cu.company_id, case when count(rr.response_id) < 3 then null else count(rr.response_id)::int end,
         case when count(rr.response_id) < 3 then null
              else private.response_band(100.0 * avg(case rr.rating when 'yes' then 1 when 'partial' then 0.5 else 0 end)) end
  from public.company_users cu
  left join public.company_responses r on r.company_id = cu.company_id
  left join public.response_ratings rr on rr.response_id = r.id
  where cu.user_id = auth.uid() and cu.verification_status = 'verified'
  group by cu.company_id;
$$$s0$,
$s0$-- Vínculo recusado ou revogado também perde a edição do perfil da empresa (inclusive contato). 'pending' continua
-- editando para completar o cadastro. Corpo de 20261108120000 com a checagem nova depois da de dono.
create or replace function public.update_company_profile(p_company uuid, p jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.companies%rowtype;
  v_trade text; v_email text; v_phone text; v_changed text[] := '{}';
begin
  if not public.is_company_owner(p_company) then
    raise exception 'Só o responsável pela conta da empresa pode alterar estes dados.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.company_users where company_id = p_company and user_id = auth.uid()
             and verification_status in ('rejected', 'revoked')) then
    raise exception 'Vínculo com a empresa recusado ou revogado pela equipe.' using errcode = 'P0001';
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
$$$s0$
]::text[]);

commit;
