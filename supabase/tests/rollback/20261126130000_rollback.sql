-- Rollback de 20261126130000 (motivo do aviso e aviso automático à empresa não cadastrada). SQL Editor de produção,
-- arquivo INTEIRO, uma vez. Volta a fila e as funções às versões de 20261123130000 e 20261118130000.
-- Linhas da fila do tipo company_notice que ainda não saíram são apagadas (os avisos continuam 'approved' em
-- company_notices, para a equipe enviar à mão como antes). A versão sai de schema_migrations.
-- Antes: publicar de novo a versão anterior da send-notifications (a nova cai sozinha na chamada antiga, sem avisos).
-- Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261126130000') then
    raise exception 'A 20261126130000 não está registrada. Nada foi feito.';
  end if;
  if exists (select 1 from private.notification_outbox where kind = 'company_notice' and status = 'sending') then
    raise exception 'Há aviso de empresa em envio agora. Espere alguns minutos e rode de novo. Nada foi feito.';
  end if;
end $trava$;

drop trigger company_notices_enqueue on public.company_notices;
drop function private.enqueue_company_notice();
delete from private.notification_outbox where kind = 'company_notice';

drop function public.notification_claim(integer, boolean);
drop function private.company_notice_destination(uuid);

-- Funções de 20261123130000, literais.
create or replace function private.enqueue_notification()
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

create or replace function private.enqueue_response_returned()
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

create or replace function public.notification_mark(p_id uuid, p_result text, p_error_code text default null, p_messages integer default 0)
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

revoke all on function public.notification_claim(integer) from public, anon, authenticated;
grant execute on function public.notification_claim(integer) to service_role;

-- Função de 20261118130000, literal.
create or replace function public.ops_mark_notice_sent(p_notice uuid, p_outcome text default 'sent')
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if not public.is_platform_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select status into v_status from public.company_notices where id = p_notice for update;
  if v_status is null then raise exception 'Aviso não encontrado.' using errcode = 'P0001'; end if;
  if p_outcome = 'sent' and v_status = 'approved' then
    update public.company_notices set status = 'sent', sent_by = auth.uid(), sent_at = now() where id = p_notice;
  elsif p_outcome = 'bounced' and v_status in ('approved', 'sent') then
    update public.company_notices set status = 'bounced' where id = p_notice;
  else
    raise exception 'Mudança não permitida a partir do estado atual.' using errcode = 'P0001';
  end if;
end;
$$;

drop index private.notification_outbox_notice_idx;
alter table private.notification_outbox drop constraint notification_outbox_reason_check;
alter table private.notification_outbox drop constraint notification_outbox_check;
alter table private.notification_outbox drop constraint notification_outbox_kind_check;
alter table private.notification_outbox drop column notice_id, drop column reason;
alter table private.notification_outbox
  add constraint notification_outbox_kind_check check (kind in ('worker_update', 'company_update')),
  add constraint notification_outbox_check check ((kind = 'worker_update' and worker_id is not null and company_id is null)
         or (kind = 'company_update' and company_id is not null and worker_id is null));

delete from supabase_migrations.schema_migrations where version = '20261126130000';

commit;
