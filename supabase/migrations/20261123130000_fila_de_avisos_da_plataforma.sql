-- ADR-0020, revisão de 2026-11-23 (responsável, "Aprovo"): avisos só para contas da plataforma — o trabalhador dono do
-- relato e os usuários verificados da empresa —, com texto genérico e sem contato externo automático.
-- Fila (outbox), gatilhos que a alimentam, interface da Edge Function send-notifications (só service_role) e opt-out do
-- trabalhador. A porta 465 abriu no teste de 2026-11-24 ({"tls":true,"code":"220"}); plano em docs/runbooks/EMAIL_NOTIFICATIONS.md.
--
-- Regras:
--   - nada de e-mail, nome, texto, protocolo, empresa ou categoria na fila: só o tipo, o destinatário por id e a chave de
--     deduplicação. O e-mail é resolvido no envio (notification_claim): trabalhador -> auth.users; empresa -> vínculos
--     'verified'. Nunca complaint_contacts nem e-mail da Receita.
--   - worker_update: um por evento da linha do tempo que NÃO foi feito pelo próprio trabalhador (actor <> 'worker').
--     Trabalhador com avisos desligados (workers.email_updates = false): a linha nasce 'suppressed'.
--   - company_update: só nos eventos visíveis à empresa (revisão de 2026-11-23): liberação ('shared'), encerramento pelo
--     trabalhador ('closed') e devolução da resposta (company_responses -> 'returned'; sem evento, gatilho próprio).
--   - Envio: teto de 300 mensagens por dia (dia de Brasília); novas tentativas em 5 min, 30 min, 2 h, 6 h e 24 h, e na
--     falha seguinte 'failed'; 'sending' parado há mais de 30 min volta a 'pending' (queda entre envio e marcação: duplicata
--     rara, aceita com texto genérico); 'sent' e 'suppressed' com mais de 90 dias são apagados (D10, proposta).
--   - Lembretes de 7 e 15 dias (D5) ficam fora.
--
-- Rollback (sem dependentes): drop trigger complaint_events_notify on public.complaint_events; drop trigger
--   company_responses_notify on public.company_responses; drop function private.enqueue_notification(),
--   private.enqueue_response_returned(), public.notification_claim(integer), public.notification_mark(uuid, text, text, integer),
--   public.set_worker_email_updates(boolean), public.my_email_updates(), public.ops_notification_stats();
--   drop table private.notification_outbox;
--   alter table public.workers drop column email_updates.

set local lock_timeout = '5s';

-- Opt-out do trabalhador (D8): o mínimo, uma coluna. Padrão ligado (aviso de serviço, texto genérico); a base legal e o
-- padrão continuam como decisão do responsável com o advogado (ADR-0020, pendência 5).
alter table public.workers add column email_updates boolean not null default true;

create table private.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('worker_update', 'company_update')),
  worker_id uuid references public.workers (id) on delete cascade,
  company_id uuid references public.companies (id) on delete cascade,
  dedupe_key text not null unique check (char_length(dedupe_key) <= 120),
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed', 'suppressed')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  last_attempt_at timestamptz,  -- última marcação (sent, retry ou release), para as contagens da Operação
  messages_sent integer not null default 0 check (messages_sent >= 0),  -- e-mails entregues por esta linha (teto diário)
  last_error_code text check (last_error_code is null or last_error_code ~ '^[a-z0-9_]{1,40}$'),  -- código curto, nunca texto do servidor
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  check ((kind = 'worker_update' and worker_id is not null and company_id is null)
         or (kind = 'company_update' and company_id is not null and worker_id is null))
);
create index notification_outbox_due_idx on private.notification_outbox (next_attempt_at) where status = 'pending';
create index notification_outbox_sent_idx on private.notification_outbox (sent_at) where status = 'sent';
alter table private.notification_outbox enable row level security;
revoke all on private.notification_outbox from public, anon, authenticated, service_role;

-- Alimenta a fila a partir da linha do tempo. Não lê nem copia conteúdo do evento.
create function private.enqueue_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_worker uuid; v_company uuid; v_updates boolean;
begin
  select c.worker_id, c.company_id, w.email_updates into v_worker, v_company, v_updates
  from public.complaints c join public.workers w on w.id = c.worker_id where c.id = new.complaint_id;
  if v_worker is null then return new; end if;
  if new.actor <> 'worker' then  -- a própria ação do trabalhador não o avisa
    insert into private.notification_outbox (kind, worker_id, dedupe_key, status)
    values ('worker_update', v_worker, 'worker_update:' || new.id, case when v_updates then 'pending' else 'suppressed' end)
    on conflict (dedupe_key) do nothing;
  end if;
  -- Empresa: liberação (pela equipe) e encerramento (pelo trabalhador). 'closed' só existe depois de liberada.
  if (new.status = 'shared' and new.actor <> 'worker') or new.status = 'closed' then
    insert into private.notification_outbox (kind, company_id, dedupe_key)
    values ('company_update', v_company, 'company_update:' || new.id)
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.enqueue_notification() from public, anon, authenticated, service_role;

create trigger complaint_events_notify after insert on public.complaint_events
  for each row execute function private.enqueue_notification();

-- Devolução da resposta à empresa (ADR-0013 D2: sem evento na linha do tempo do trabalhador).
create function private.enqueue_response_returned()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.review_status = 'returned' and old.review_status is distinct from 'returned' then
    insert into private.notification_outbox (kind, company_id, dedupe_key)
    values ('company_update', new.company_id, 'company_update:response_returned:' || new.id)
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.enqueue_response_returned() from public, anon, authenticated, service_role;

create trigger company_responses_notify after update of review_status on public.company_responses
  for each row execute function private.enqueue_response_returned();

-- Interface da Edge Function (service_role). Reserva um lote e devolve uma linha por destinatário, com o e-mail
-- resolvido agora e o saldo do teto diário. Linhas sem destinatário viram 'suppressed' aqui.
create function public.notification_claim(p_limit integer default 50)
returns table (outbox_id uuid, kind text, email text, remaining_today integer)
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
    order by o.created_at
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    for update skip locked
  ) s;
  if v_ids is null then return; end if;
  update private.notification_outbox set status = 'sending', claimed_at = now() where id = any (v_ids);

  -- Sem destinatário (trabalhador desligou os avisos depois; empresa sem vínculo verificado): 'suppressed'.
  update private.notification_outbox o set status = 'suppressed', claimed_at = null
  where o.id = any (v_ids) and (
    (o.kind = 'worker_update' and not exists (
       select 1 from public.workers w join auth.users u on u.id = w.user_id
       where w.id = o.worker_id and w.email_updates and u.email is not null))
    or (o.kind = 'company_update' and not exists (
       select 1 from public.company_users cu join auth.users u on u.id = cu.user_id
       where cu.company_id = o.company_id and cu.verification_status = 'verified' and u.email is not null)));

  return query
  select o.id, o.kind, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.workers w on w.id = o.worker_id
  join auth.users u on u.id = w.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'worker_update' and w.email_updates and u.email is not null
  union all
  select o.id, o.kind, lower(u.email)::text, v_remaining
  from private.notification_outbox o
  join public.company_users cu on cu.company_id = o.company_id and cu.verification_status = 'verified'
  join auth.users u on u.id = cu.user_id
  where o.id = any (v_ids) and o.status = 'sending' and o.kind = 'company_update' and u.email is not null;
end;
$$;

-- Resultado de uma linha: 'sent' (p_messages = e-mails entregues), 'retry' (falha; nova tentativa ou 'failed'),
-- 'release' (volta a 'pending' sem gastar tentativa: erro de autenticação SMTP ou teto do dia).
create function public.notification_mark(p_id uuid, p_result text, p_error_code text default null, p_messages integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_attempts integer; v_code text := case when p_error_code ~ '^[a-z0-9_]{1,40}$' then p_error_code end;
begin
  if p_result = 'sent' then
    update private.notification_outbox
    set status = 'sent', sent_at = now(), messages_sent = greatest(coalesce(p_messages, 0), 0), claimed_at = null, last_error_code = null,
        last_attempt_at = now()
    where id = p_id and status = 'sending';
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
    where id = p_id;
  elsif p_result = 'release' then
    update private.notification_outbox set status = 'pending', claimed_at = null, last_error_code = v_code, last_attempt_at = now()
    where id = p_id and status = 'sending';
  else
    raise exception 'Resultado inválido.' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.notification_claim(integer), public.notification_mark(uuid, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.notification_claim(integer), public.notification_mark(uuid, text, text, integer) to service_role;

-- Contagens para a Operação (só a equipe; sem e-mail nem destinatário). Parada por senha: smtp_auth; por cota ou
-- limite do Gmail: smtp_quota e smtp_421 — contadas pela última marcação nas últimas 24 h.
create function public.ops_notification_stats()
returns table (pending integer, sending integer, failed integer, sent_24h integer, messages_24h integer,
               stopped_auth_24h integer, stopped_quota_24h integer, last_sent_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return query
  select (count(*) filter (where o.status = 'pending'))::int,
         (count(*) filter (where o.status = 'sending'))::int,
         (count(*) filter (where o.status = 'failed'))::int,
         (count(*) filter (where o.status = 'sent' and o.sent_at > now() - interval '24 hours'))::int,
         coalesce(sum(o.messages_sent) filter (where o.status = 'sent' and o.sent_at > now() - interval '24 hours'), 0)::int,
         (count(*) filter (where o.last_error_code = 'smtp_auth' and o.last_attempt_at > now() - interval '24 hours'))::int,
         (count(*) filter (where o.last_error_code in ('smtp_quota', 'smtp_421') and o.last_attempt_at > now() - interval '24 hours'))::int,
         max(o.sent_at)
  from private.notification_outbox o;
end;
$$;
revoke all on function public.ops_notification_stats() from public, anon, service_role;
grant execute on function public.ops_notification_stats() to authenticated;

-- Opt-out em Meu perfil (só o próprio trabalhador). Desligado: avisos novos nascem 'suppressed' e os pendentes não saem.
create function public.set_worker_email_updates(p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_enabled is null then raise exception 'Valor inválido.' using errcode = 'P0001'; end if;
  update public.workers set email_updates = p_enabled where user_id = auth.uid();
  if not found then raise exception 'Somente trabalhadores têm esta preferência.' using errcode = 'P0001'; end if;
end;
$$;
create function public.my_email_updates()
returns boolean language sql stable security definer set search_path = '' as $$
  select email_updates from public.workers where user_id = auth.uid();
$$;
revoke all on function public.set_worker_email_updates(boolean), public.my_email_updates() from public, anon, service_role;
grant execute on function public.set_worker_email_updates(boolean), public.my_email_updates() to authenticated;
