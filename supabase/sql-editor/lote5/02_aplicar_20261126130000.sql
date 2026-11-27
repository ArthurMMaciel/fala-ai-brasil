-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/pending/20261126130000_avisos_por_evento_e_aviso_automatico.sql. Não editar à mão.
-- Passo 02 de 02. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 02_conferir_20261126130000.sql (todas as linhas com ok = true).
-- AVISO: depois deste passo, publique a versão nova da send-notifications; a aprovação de aviso à empresa não cadastrada passa a gerar envio automático.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261126130000') then
    raise exception 'A migration 20261126130000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261126120000') then
    raise exception 'Falta a 20261126120000 (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261126130000_avisos_por_evento_e_aviso_automatico.sql (19 instruções) ========
-- ADR-0020 e ADR-0023, revisão de 2026-11-26 (pedido do Gestor; aplicação depende da aprovação do responsável).
-- Duas mudanças na fila de avisos (20261123130000), sem tocar no conteúdo dos relatos:
--
-- 1) Motivo do aviso (coluna reason), para a send-notifications escolher um texto curto por evento:
--      worker_update  -> 'update' (qualquer novidade na manifestação, feita por outra pessoa que não o trabalhador);
--      company_update -> 'released' (liberação), 'closed' (encerramento), 'response_returned' (resposta devolvida);
--                        'update' fica para as linhas criadas antes desta migration (texto genérico).
--    O motivo é um código fixo; nada de protocolo, categoria, empresa ou texto.
--
-- 2) Aviso automático à empresa não cadastrada (kind 'company_notice'), depois da aprovação humana:
--    - ops_decide_notice continua com todas as travas e não muda. A aprovação (company_notices 'approved') põe uma linha
--      na fila por gatilho, com notice_id; o e-mail de destino NÃO fica na fila: é resolvido no envio
--      (contato indicado pelo trabalhador ou e-mail da Receita) e conferido de novo (opt-out, aviso ainda aprovado,
--      empresa ainda não cadastrada nem bloqueada, manifestação existente, Receita diferente de contato possivelmente
--      envolvido). Se não passar, a linha vira
--      'suppressed' e o aviso fica 'approved' para a equipe decidir (marcar devolvido à mão).
--    - Enviado: company_notices vira 'sent' (sent_by nulo = envio automático). Falha definitiva: 'bounced'.
--    - Conta no teto de 300 mensagens por dia, como os demais.
--    - notification_claim ganha p_include_notices (padrão false): a versão da função já publicada (que não conhece o tipo)
--      nunca recebe avisos de empresa; a nova versão pede true. Aplicar esta migration ANTES de publicar a função nova.
--    - ops_mark_notice_sent (marcação manual) retira da fila o envio pendente e recusa enquanto o envio estiver em curso.
--    Muda a regra "nada automático para contato ou Receita" da ADR-0023: o envio passa a ser automático, a decisão
--    continua humana, um aviso por manifestação e no máximo um por empresa a cada 30 dias.
--
-- Rollback: supabase/tests/rollback/20261126130000_rollback.sql.

set local lock_timeout = '5s';

-- 1) Colunas e regras da fila.
alter table private.notification_outbox
  add column reason text not null default 'update',
  add column notice_id uuid references public.company_notices (id) on delete cascade;

alter table private.notification_outbox drop constraint notification_outbox_kind_check;
alter table private.notification_outbox drop constraint notification_outbox_check;
alter table private.notification_outbox
  add constraint notification_outbox_kind_check check (kind in ('worker_update', 'company_update', 'company_notice')),
  add constraint notification_outbox_check check (
    (kind = 'worker_update' and worker_id is not null and company_id is null and notice_id is null)
    or (kind = 'company_update' and company_id is not null and worker_id is null and notice_id is null)
    or (kind = 'company_notice' and notice_id is not null and company_id is not null and worker_id is null)),
  add constraint notification_outbox_reason_check check (
    (kind = 'worker_update' and reason = 'update')
    or (kind = 'company_update' and reason in ('update', 'released', 'closed', 'response_returned'))
    or (kind = 'company_notice' and reason = 'notice'));
create unique index notification_outbox_notice_idx on private.notification_outbox (notice_id) where notice_id is not null;

-- 2) Gatilhos com o motivo. Mesmas regras de 20261123130000; só o reason é novo.
create or replace function private.enqueue_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_worker uuid; v_company uuid; v_updates boolean;
begin
  select c.worker_id, c.company_id, w.email_updates into v_worker, v_company, v_updates
  from public.complaints c join public.workers w on w.id = c.worker_id where c.id = new.complaint_id;
  if v_worker is null then return new; end if;
  if new.actor <> 'worker' then  -- a própria ação do trabalhador não o avisa
    insert into private.notification_outbox (kind, worker_id, dedupe_key, status, reason)
    values ('worker_update', v_worker, 'worker_update:' || new.id, case when v_updates then 'pending' else 'suppressed' end, 'update')
    on conflict (dedupe_key) do nothing;
  end if;
  -- Empresa: liberação (pela equipe) e encerramento (pelo trabalhador). 'closed' só existe depois de liberada.
  if (new.status = 'shared' and new.actor <> 'worker') or new.status = 'closed' then
    insert into private.notification_outbox (kind, company_id, dedupe_key, reason)
    values ('company_update', v_company, 'company_update:' || new.id, case when new.status = 'closed' then 'closed' else 'released' end)
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$;

create or replace function private.enqueue_response_returned()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.review_status = 'returned' and old.review_status is distinct from 'returned' then
    insert into private.notification_outbox (kind, company_id, dedupe_key, reason)
    values ('company_update', new.company_id, 'company_update:response_returned:' || new.id, 'response_returned')
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$;

-- Aprovação do aviso (ops_decide_notice) -> fila. Só a aprovação; a recusa não gera nada.
create function private.enqueue_company_notice()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' then
    insert into private.notification_outbox (kind, company_id, notice_id, dedupe_key, reason)
    values ('company_notice', new.company_id, new.id, 'company_notice:' || new.id, 'notice')
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.enqueue_company_notice() from public, anon, authenticated, service_role;
create trigger company_notices_enqueue after insert on public.company_notices
  for each row execute function private.enqueue_company_notice();

-- Destino de um aviso de empresa, conferido no envio. Nulo = não enviar. Não grava nada.
create function private.company_notice_destination(p_notice uuid)
returns text language sql stable security definer set search_path = '' as $$
  select d.email
  from public.company_notices n
  join public.companies co on co.id = n.company_id
  cross join lateral (
    select case n.destination_source
             when 'worker' then (select k.email from public.complaint_contacts k
                                 where k.id = n.contact_id and not k.possibly_involved)
             when 'receita' then (select cc.email from private.cnpj_cache cc where cc.cnpj = co.cnpj and not cc.natural_person)
           end as email
  ) d
  where n.id = p_notice and n.status = 'approved' and co.registration_status <> 'registered'
    and n.complaint_id is not null  -- manifestação apagada com a conta: não avisa
    and not exists (select 1 from private.company_preregistrations pr
                    where pr.company_id = n.company_id and (pr.review_decision = 'blocked' or coalesce(pr.natural_person, false)))
    and d.email is not null
    and not exists (select 1 from private.notice_opt_outs o where o.email_hash = private.email_hash(d.email))
    and not (n.destination_source = 'receita' and exists (
      select 1 from public.complaint_contacts k
      where k.complaint_id = n.complaint_id and k.possibly_involved and k.email = lower(d.email)));
$$;
revoke all on function private.company_notice_destination(uuid) from public, anon, authenticated, service_role;

-- 3) Interface da Edge Function. A assinatura muda (p_include_notices e a coluna reason): drop e create.
drop function public.notification_claim(integer);
create function public.notification_claim(p_limit integer default 50, p_include_notices boolean default false)
returns table (outbox_id uuid, kind text, reason text, email text, remaining_today integer)
language plpgsql security definer set search_path = '' as $$
declare
  v_day_start timestamptz := (date_trunc('day', now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo';
  v_remaining integer;
  v_ids uuid[];
begin
  -- Manutenção: reserva perdida (queda entre envio e marcação) e retenção.
  update private.notification_outbox set status = 'pending', claimed_at = null
  where status = 'sending' and claimed_at < now() - interval '30 minutes';
  delete from private.notification_outbox
  where status in ('sent', 'suppressed') and coalesce(sent_at, created_at) < now() - interval '90 days';

  v_remaining := 300 - coalesce((select sum(messages_sent) from private.notification_outbox
                                 where status = 'sent' and sent_at >= v_day_start), 0);
  if v_remaining <= 0 then return; end if;

  select array_agg(id) into v_ids from (
    select o.id from private.notification_outbox o
    where o.status = 'pending' and o.next_attempt_at <= now()
      and (o.kind <> 'company_notice' or coalesce(p_include_notices, false))
    order by o.created_at
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    for update skip locked
  ) s;
  if v_ids is null then return; end if;
  update private.notification_outbox set status = 'sending', claimed_at = now() where id = any (v_ids);

  -- Sem destinatário: 'suppressed'. Aviso de empresa que não passa na conferência fica 'approved' em company_notices.
  update private.notification_outbox o set status = 'suppressed', claimed_at = null
  where o.id = any (v_ids) and (
    (o.kind = 'worker_update' and not exists (
       select 1 from public.workers w join auth.users u on u.id = w.user_id
       where w.id = o.worker_id and w.email_updates and u.email is not null))
    or (o.kind = 'company_update' and not exists (
       select 1 from public.company_users cu join auth.users u on u.id = cu.user_id
       where cu.company_id = o.company_id and cu.verification_status = 'verified' and u.email is not null))
    or (o.kind = 'company_notice' and private.company_notice_destination(o.notice_id) is null));

  return query
  select o.id, o.kind, o.reason, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.workers w on w.id = o.worker_id
  join auth.users u on u.id = w.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'worker_update' and w.email_updates and u.email is not null
  union all
  select o.id, o.kind, o.reason, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.company_users cu on cu.company_id = o.company_id and cu.verification_status = 'verified'
  join auth.users u on u.id = cu.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'company_update' and u.email is not null
  union all
  select o.id, o.kind, o.reason, lower(private.company_notice_destination(o.notice_id)), v_remaining
  from private.notification_outbox o
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'company_notice';
end;
$$;

-- Mesmo comportamento de 20261123130000, mais o reflexo em company_notices para o tipo company_notice:
-- 'sent' -> aviso 'sent' (sent_by nulo: envio automático); falha definitiva ('failed') -> aviso 'bounced'.
create or replace function public.notification_mark(p_id uuid, p_result text, p_error_code text default null, p_messages integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_attempts integer; v_code text := case when p_error_code ~ '^[a-z0-9_]{1,40}$' then p_error_code end;
        v_notice uuid; v_status text;
begin
  if p_result = 'sent' then
    update private.notification_outbox
    set status = 'sent', sent_at = now(), messages_sent = greatest(coalesce(p_messages, 0), 0), claimed_at = null, last_error_code = null,
        last_attempt_at = now()
    where id = p_id and status = 'sending'
    returning notice_id into v_notice;
    if v_notice is not null then
      update public.company_notices set status = 'sent', sent_at = now() where id = v_notice and status = 'approved';
    end if;
  elsif p_result = 'retry' then
    update private.notification_outbox set attempts = attempts + 1 where id = p_id and status = 'sending'
    returning attempts into v_attempts;
    if v_attempts is null then return; end if;
    update private.notification_outbox
    set status = case when v_attempts > 5 then 'failed' else 'pending' end,
        next_attempt_at = now() + case v_attempts when 1 then interval '5 minutes' when 2 then interval '30 minutes'
                                                  when 3 then interval '2 hours' when 4 then interval '6 hours'
                                                  else interval '24 hours' end,
        last_error_code = v_code, claimed_at = null, last_attempt_at = now()
    where id = p_id
    returning notice_id, status into v_notice, v_status;
    if v_notice is not null and v_status = 'failed' then
      update public.company_notices set status = 'bounced' where id = v_notice and status = 'approved';
    end if;
  elsif p_result = 'release' then
    update private.notification_outbox set status = 'pending', claimed_at = null, last_error_code = v_code, last_attempt_at = now()
    where id = p_id and status = 'sending';
  else
    raise exception 'Resultado inválido.' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.notification_claim(integer, boolean) from public, anon, authenticated;
grant execute on function public.notification_claim(integer, boolean) to service_role;

-- 4) Marcação manual pela equipe: mesma regra de 20261118130000; tira da fila o envio automático pendente e recusa
-- enquanto ele estiver em curso (evita aviso em dobro).
create or replace function public.ops_mark_notice_sent(p_notice uuid, p_outcome text default 'sent')
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select status into v_status from public.company_notices where id = p_notice for update;
  if v_status is null then raise exception 'Aviso não encontrado.' using errcode = 'P0001'; end if;
  if exists (select 1 from private.notification_outbox where notice_id = p_notice and status = 'sending') then
    raise exception 'O envio automático deste aviso está em curso. Tente de novo em alguns minutos.' using errcode = 'P0001';
  end if;
  if p_outcome = 'sent' and v_status = 'approved' then
    update public.company_notices set status = 'sent', sent_by = auth.uid(), sent_at = now() where id = p_notice;
  elsif p_outcome = 'bounced' and v_status in ('approved', 'sent') then
    update public.company_notices set status = 'bounced' where id = p_notice;
  else
    raise exception 'Mudança não permitida a partir do estado atual.' using errcode = 'P0001';
  end if;
  update private.notification_outbox set status = 'suppressed', claimed_at = null
  where notice_id = p_notice and status = 'pending';
end;
$$;
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261126130000', 'avisos_por_evento_e_aviso_automatico', array[
$s0$-- ADR-0020 e ADR-0023, revisão de 2026-11-26 (pedido do Gestor; aplicação depende da aprovação do responsável).
-- Duas mudanças na fila de avisos (20261123130000), sem tocar no conteúdo dos relatos:
--
-- 1) Motivo do aviso (coluna reason), para a send-notifications escolher um texto curto por evento:
--      worker_update  -> 'update' (qualquer novidade na manifestação, feita por outra pessoa que não o trabalhador);
--      company_update -> 'released' (liberação), 'closed' (encerramento), 'response_returned' (resposta devolvida);
--                        'update' fica para as linhas criadas antes desta migration (texto genérico).
--    O motivo é um código fixo; nada de protocolo, categoria, empresa ou texto.
--
-- 2) Aviso automático à empresa não cadastrada (kind 'company_notice'), depois da aprovação humana:
--    - ops_decide_notice continua com todas as travas e não muda. A aprovação (company_notices 'approved') põe uma linha
--      na fila por gatilho, com notice_id; o e-mail de destino NÃO fica na fila: é resolvido no envio
--      (contato indicado pelo trabalhador ou e-mail da Receita) e conferido de novo (opt-out, aviso ainda aprovado,
--      empresa ainda não cadastrada nem bloqueada, manifestação existente, Receita diferente de contato possivelmente
--      envolvido). Se não passar, a linha vira
--      'suppressed' e o aviso fica 'approved' para a equipe decidir (marcar devolvido à mão).
--    - Enviado: company_notices vira 'sent' (sent_by nulo = envio automático). Falha definitiva: 'bounced'.
--    - Conta no teto de 300 mensagens por dia, como os demais.
--    - notification_claim ganha p_include_notices (padrão false): a versão da função já publicada (que não conhece o tipo)
--      nunca recebe avisos de empresa; a nova versão pede true. Aplicar esta migration ANTES de publicar a função nova.
--    - ops_mark_notice_sent (marcação manual) retira da fila o envio pendente e recusa enquanto o envio estiver em curso.
--    Muda a regra "nada automático para contato ou Receita" da ADR-0023: o envio passa a ser automático, a decisão
--    continua humana, um aviso por manifestação e no máximo um por empresa a cada 30 dias.
--
-- Rollback: supabase/tests/rollback/20261126130000_rollback.sql.

set local lock_timeout = '5s'$s0$,
$s0$-- 1) Colunas e regras da fila.
alter table private.notification_outbox
  add column reason text not null default 'update',
  add column notice_id uuid references public.company_notices (id) on delete cascade$s0$,
$s0$alter table private.notification_outbox drop constraint notification_outbox_kind_check$s0$,
$s0$alter table private.notification_outbox drop constraint notification_outbox_check$s0$,
$s0$alter table private.notification_outbox
  add constraint notification_outbox_kind_check check (kind in ('worker_update', 'company_update', 'company_notice')),
  add constraint notification_outbox_check check (
    (kind = 'worker_update' and worker_id is not null and company_id is null and notice_id is null)
    or (kind = 'company_update' and company_id is not null and worker_id is null and notice_id is null)
    or (kind = 'company_notice' and notice_id is not null and company_id is not null and worker_id is null)),
  add constraint notification_outbox_reason_check check (
    (kind = 'worker_update' and reason = 'update')
    or (kind = 'company_update' and reason in ('update', 'released', 'closed', 'response_returned'))
    or (kind = 'company_notice' and reason = 'notice'))$s0$,
$s0$create unique index notification_outbox_notice_idx on private.notification_outbox (notice_id) where notice_id is not null$s0$,
$s0$-- 2) Gatilhos com o motivo. Mesmas regras de 20261123130000; só o reason é novo.
create or replace function private.enqueue_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_worker uuid; v_company uuid; v_updates boolean;
begin
  select c.worker_id, c.company_id, w.email_updates into v_worker, v_company, v_updates
  from public.complaints c join public.workers w on w.id = c.worker_id where c.id = new.complaint_id;
  if v_worker is null then return new; end if;
  if new.actor <> 'worker' then  -- a própria ação do trabalhador não o avisa
    insert into private.notification_outbox (kind, worker_id, dedupe_key, status, reason)
    values ('worker_update', v_worker, 'worker_update:' || new.id, case when v_updates then 'pending' else 'suppressed' end, 'update')
    on conflict (dedupe_key) do nothing;
  end if;
  -- Empresa: liberação (pela equipe) e encerramento (pelo trabalhador). 'closed' só existe depois de liberada.
  if (new.status = 'shared' and new.actor <> 'worker') or new.status = 'closed' then
    insert into private.notification_outbox (kind, company_id, dedupe_key, reason)
    values ('company_update', v_company, 'company_update:' || new.id, case when new.status = 'closed' then 'closed' else 'released' end)
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$$s0$,
$s0$create or replace function private.enqueue_response_returned()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.review_status = 'returned' and old.review_status is distinct from 'returned' then
    insert into private.notification_outbox (kind, company_id, dedupe_key, reason)
    values ('company_update', new.company_id, 'company_update:response_returned:' || new.id, 'response_returned')
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$$s0$,
$s0$-- Aprovação do aviso (ops_decide_notice) -> fila. Só a aprovação; a recusa não gera nada.
create function private.enqueue_company_notice()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' then
    insert into private.notification_outbox (kind, company_id, notice_id, dedupe_key, reason)
    values ('company_notice', new.company_id, new.id, 'company_notice:' || new.id, 'notice')
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$$s0$,
$s0$revoke all on function private.enqueue_company_notice() from public, anon, authenticated, service_role$s0$,
$s0$create trigger company_notices_enqueue after insert on public.company_notices
  for each row execute function private.enqueue_company_notice()$s0$,
$s0$-- Destino de um aviso de empresa, conferido no envio. Nulo = não enviar. Não grava nada.
create function private.company_notice_destination(p_notice uuid)
returns text language sql stable security definer set search_path = '' as $$
  select d.email
  from public.company_notices n
  join public.companies co on co.id = n.company_id
  cross join lateral (
    select case n.destination_source
             when 'worker' then (select k.email from public.complaint_contacts k
                                 where k.id = n.contact_id and not k.possibly_involved)
             when 'receita' then (select cc.email from private.cnpj_cache cc where cc.cnpj = co.cnpj and not cc.natural_person)
           end as email
  ) d
  where n.id = p_notice and n.status = 'approved' and co.registration_status <> 'registered'
    and n.complaint_id is not null  -- manifestação apagada com a conta: não avisa
    and not exists (select 1 from private.company_preregistrations pr
                    where pr.company_id = n.company_id and (pr.review_decision = 'blocked' or coalesce(pr.natural_person, false)))
    and d.email is not null
    and not exists (select 1 from private.notice_opt_outs o where o.email_hash = private.email_hash(d.email))
    and not (n.destination_source = 'receita' and exists (
      select 1 from public.complaint_contacts k
      where k.complaint_id = n.complaint_id and k.possibly_involved and k.email = lower(d.email)));
$$$s0$,
$s0$revoke all on function private.company_notice_destination(uuid) from public, anon, authenticated, service_role$s0$,
$s0$-- 3) Interface da Edge Function. A assinatura muda (p_include_notices e a coluna reason): drop e create.
drop function public.notification_claim(integer)$s0$,
$s0$create function public.notification_claim(p_limit integer default 50, p_include_notices boolean default false)
returns table (outbox_id uuid, kind text, reason text, email text, remaining_today integer)
language plpgsql security definer set search_path = '' as $$
declare
  v_day_start timestamptz := (date_trunc('day', now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo';
  v_remaining integer;
  v_ids uuid[];
begin
  -- Manutenção: reserva perdida (queda entre envio e marcação) e retenção.
  update private.notification_outbox set status = 'pending', claimed_at = null
  where status = 'sending' and claimed_at < now() - interval '30 minutes';
  delete from private.notification_outbox
  where status in ('sent', 'suppressed') and coalesce(sent_at, created_at) < now() - interval '90 days';

  v_remaining := 300 - coalesce((select sum(messages_sent) from private.notification_outbox
                                 where status = 'sent' and sent_at >= v_day_start), 0);
  if v_remaining <= 0 then return; end if;

  select array_agg(id) into v_ids from (
    select o.id from private.notification_outbox o
    where o.status = 'pending' and o.next_attempt_at <= now()
      and (o.kind <> 'company_notice' or coalesce(p_include_notices, false))
    order by o.created_at
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    for update skip locked
  ) s;
  if v_ids is null then return; end if;
  update private.notification_outbox set status = 'sending', claimed_at = now() where id = any (v_ids);

  -- Sem destinatário: 'suppressed'. Aviso de empresa que não passa na conferência fica 'approved' em company_notices.
  update private.notification_outbox o set status = 'suppressed', claimed_at = null
  where o.id = any (v_ids) and (
    (o.kind = 'worker_update' and not exists (
       select 1 from public.workers w join auth.users u on u.id = w.user_id
       where w.id = o.worker_id and w.email_updates and u.email is not null))
    or (o.kind = 'company_update' and not exists (
       select 1 from public.company_users cu join auth.users u on u.id = cu.user_id
       where cu.company_id = o.company_id and cu.verification_status = 'verified' and u.email is not null))
    or (o.kind = 'company_notice' and private.company_notice_destination(o.notice_id) is null));

  return query
  select o.id, o.kind, o.reason, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.workers w on w.id = o.worker_id
  join auth.users u on u.id = w.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'worker_update' and w.email_updates and u.email is not null
  union all
  select o.id, o.kind, o.reason, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.company_users cu on cu.company_id = o.company_id and cu.verification_status = 'verified'
  join auth.users u on u.id = cu.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'company_update' and u.email is not null
  union all
  select o.id, o.kind, o.reason, lower(private.company_notice_destination(o.notice_id)), v_remaining
  from private.notification_outbox o
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'company_notice';
end;
$$$s0$,
$s0$-- Mesmo comportamento de 20261123130000, mais o reflexo em company_notices para o tipo company_notice:
-- 'sent' -> aviso 'sent' (sent_by nulo: envio automático); falha definitiva ('failed') -> aviso 'bounced'.
create or replace function public.notification_mark(p_id uuid, p_result text, p_error_code text default null, p_messages integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_attempts integer; v_code text := case when p_error_code ~ '^[a-z0-9_]{1,40}$' then p_error_code end;
        v_notice uuid; v_status text;
begin
  if p_result = 'sent' then
    update private.notification_outbox
    set status = 'sent', sent_at = now(), messages_sent = greatest(coalesce(p_messages, 0), 0), claimed_at = null, last_error_code = null,
        last_attempt_at = now()
    where id = p_id and status = 'sending'
    returning notice_id into v_notice;
    if v_notice is not null then
      update public.company_notices set status = 'sent', sent_at = now() where id = v_notice and status = 'approved';
    end if;
  elsif p_result = 'retry' then
    update private.notification_outbox set attempts = attempts + 1 where id = p_id and status = 'sending'
    returning attempts into v_attempts;
    if v_attempts is null then return; end if;
    update private.notification_outbox
    set status = case when v_attempts > 5 then 'failed' else 'pending' end,
        next_attempt_at = now() + case v_attempts when 1 then interval '5 minutes' when 2 then interval '30 minutes'
                                                  when 3 then interval '2 hours' when 4 then interval '6 hours'
                                                  else interval '24 hours' end,
        last_error_code = v_code, claimed_at = null, last_attempt_at = now()
    where id = p_id
    returning notice_id, status into v_notice, v_status;
    if v_notice is not null and v_status = 'failed' then
      update public.company_notices set status = 'bounced' where id = v_notice and status = 'approved';
    end if;
  elsif p_result = 'release' then
    update private.notification_outbox set status = 'pending', claimed_at = null, last_error_code = v_code, last_attempt_at = now()
    where id = p_id and status = 'sending';
  else
    raise exception 'Resultado inválido.' using errcode = 'P0001';
  end if;
end;
$$$s0$,
$s0$revoke all on function public.notification_claim(integer, boolean) from public, anon, authenticated$s0$,
$s0$grant execute on function public.notification_claim(integer, boolean) to service_role$s0$,
$s0$-- 4) Marcação manual pela equipe: mesma regra de 20261118130000; tira da fila o envio automático pendente e recusa
-- enquanto ele estiver em curso (evita aviso em dobro).
create or replace function public.ops_mark_notice_sent(p_notice uuid, p_outcome text default 'sent')
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select status into v_status from public.company_notices where id = p_notice for update;
  if v_status is null then raise exception 'Aviso não encontrado.' using errcode = 'P0001'; end if;
  if exists (select 1 from private.notification_outbox where notice_id = p_notice and status = 'sending') then
    raise exception 'O envio automático deste aviso está em curso. Tente de novo em alguns minutos.' using errcode = 'P0001';
  end if;
  if p_outcome = 'sent' and v_status = 'approved' then
    update public.company_notices set status = 'sent', sent_by = auth.uid(), sent_at = now() where id = p_notice;
  elsif p_outcome = 'bounced' and v_status in ('approved', 'sent') then
    update public.company_notices set status = 'bounced' where id = p_notice;
  else
    raise exception 'Mudança não permitida a partir do estado atual.' using errcode = 'P0001';
  end if;
  update private.notification_outbox set status = 'suppressed', claimed_at = null
  where notice_id = p_notice and status = 'pending';
end;
$$$s0$
]::text[]);

commit;
