-- ADR-0020, revisão de 2026-11-23 (responsável, "Aprovo"): avisos só para contas da plataforma — o trabalhador dono do
-- relato e os usuários verificados da empresa —, com texto genérico e sem contato externo automático.
-- Esta migration cria SÓ a fila (outbox) e o gatilho que a alimenta. A função de envio NÃO existe ainda: depende do teste
-- da porta 465 (ADR-0020 D2), preparado pelo DevOps para 2026-11-24. Até lá a fila só acumula; nada é enviado.
--
-- Regras:
--   - nada de e-mail, nome, texto, protocolo, empresa ou categoria na fila: só o tipo, o destinatário por id e a chave de
--     deduplicação. O e-mail é resolvido no momento do envio (worker -> auth.users; empresa -> vínculos 'verified').
--   - worker_update: um por evento da linha do tempo que NÃO foi feito pelo próprio trabalhador (actor <> 'worker').
--   - company_new_case: um por manifestação, quando a equipe a libera à empresa (evento 'shared' que não é do trabalhador).
--     Empresa sem usuário verificado: a linha fica e o envio a marca 'suppressed' (resolvido no envio).
--   - Lembretes de 7 e 15 dias (ADR-0020 D5) e opt-out do trabalhador (D8) ficam fora desta migration.
--   - Retenção (D10, proposta): linhas 'sent' e 'suppressed' apagadas depois de 90 dias, pela rotina da função de envio.
--
-- Rollback: drop trigger complaint_events_notify on public.complaint_events; drop function private.enqueue_notification();
--   drop table private.notification_outbox;

set local lock_timeout = '5s';

create table private.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('worker_update', 'company_new_case')),
  worker_id uuid references public.workers (id) on delete cascade,
  company_id uuid references public.companies (id) on delete cascade,
  dedupe_key text not null unique check (char_length(dedupe_key) <= 120),
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed', 'suppressed')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  last_error_code text check (last_error_code is null or last_error_code ~ '^[a-z_]{1,40}$'),  -- código curto, nunca texto do servidor
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  check ((kind = 'worker_update' and worker_id is not null and company_id is null)
         or (kind = 'company_new_case' and company_id is not null and worker_id is null))
);
create index notification_outbox_due_idx on private.notification_outbox (next_attempt_at) where status = 'pending';
alter table private.notification_outbox enable row level security;
revoke all on private.notification_outbox from public, anon, authenticated, service_role;

-- Alimenta a fila a partir da linha do tempo. Não lê nem copia conteúdo do evento.
create function private.enqueue_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_worker uuid; v_company uuid;
begin
  if new.actor = 'worker' then return new; end if;  -- a própria ação do trabalhador não o avisa
  select worker_id, company_id into v_worker, v_company from public.complaints where id = new.complaint_id;
  if v_worker is null then return new; end if;
  insert into private.notification_outbox (kind, worker_id, dedupe_key)
  values ('worker_update', v_worker, 'worker_update:' || new.id)
  on conflict (dedupe_key) do nothing;
  if new.status = 'shared' then
    insert into private.notification_outbox (kind, company_id, dedupe_key)
    values ('company_new_case', v_company, 'company_new_case:' || new.complaint_id)
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.enqueue_notification() from public, anon, authenticated, service_role;

create trigger complaint_events_notify after insert on public.complaint_events
  for each row execute function private.enqueue_notification();
