-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar avisos_checks.sql e as migrations.
-- Migrations: 20261123130000_fila_de_avisos_da_plataforma.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'ffffffff-0000-0000-0000-000000000002'; u_c uuid := 'ffffffff-0000-0000-0000-000000000003'; u_op uuid := 'ffffffff-0000-0000-0000-000000000004'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765007987610'; v_co uuid; v_worker uuid; v_cp uuid; v_resp uuid; n int; v_id uuid; i int; r record;
begin
  begin  -- trava: nada pode commitar daqui para dentro
    -- Sem lock em 3 s, falha limpa em vez de enfileirar o site atrás do DDL. (statement_timeout não se aplica: o
    -- cronômetro começa no DO, que é a instrução de topo; um SET aqui dentro não o rearma.)
    execute 'set local lock_timeout = ''3s''';

    -- 20261123130000_fila_de_avisos_da_plataforma.sql (21 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261123130000') then
      res := res || jsonb_build_object('20261123130000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0020, revisão de 2026-11-23 (responsável, "Aprovo"): avisos só para contas da plataforma — o trabalhador dono do
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
--   public.set_worker_email_updates(boolean), public.my_email_updates(); drop table private.notification_outbox;
--   alter table public.workers drop column email_updates.

set local lock_timeout = '5s'$s0$;
      execute $s0$-- Opt-out do trabalhador (D8): o mínimo, uma coluna. Padrão ligado (aviso de serviço, texto genérico); a base legal e o
-- padrão continuam como decisão do responsável com o advogado (ADR-0020, pendência 5).
alter table public.workers add column email_updates boolean not null default true$s0$;
      execute $s0$create table private.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('worker_update', 'company_update')),
  worker_id uuid references public.workers (id) on delete cascade,
  company_id uuid references public.companies (id) on delete cascade,
  dedupe_key text not null unique check (char_length(dedupe_key) <= 120),
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed', 'suppressed')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  messages_sent integer not null default 0 check (messages_sent >= 0),  -- e-mails entregues por esta linha (teto diário)
  last_error_code text check (last_error_code is null or last_error_code ~ '^[a-z0-9_]{1,40}$'),  -- código curto, nunca texto do servidor
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  check ((kind = 'worker_update' and worker_id is not null and company_id is null)
         or (kind = 'company_update' and company_id is not null and worker_id is null))
)$s0$;
      execute $s0$create index notification_outbox_due_idx on private.notification_outbox (next_attempt_at) where status = 'pending'$s0$;
      execute $s0$create index notification_outbox_sent_idx on private.notification_outbox (sent_at) where status = 'sent'$s0$;
      execute $s0$alter table private.notification_outbox enable row level security$s0$;
      execute $s0$revoke all on private.notification_outbox from public, anon, authenticated, service_role$s0$;
      execute $s0$-- Alimenta a fila a partir da linha do tempo. Não lê nem copia conteúdo do evento.
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
$$$s0$;
      execute $s0$revoke all on function private.enqueue_notification() from public, anon, authenticated, service_role$s0$;
      execute $s0$create trigger complaint_events_notify after insert on public.complaint_events
  for each row execute function private.enqueue_notification()$s0$;
      execute $s0$-- Devolução da resposta à empresa (ADR-0013 D2: sem evento na linha do tempo do trabalhador).
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
$$$s0$;
      execute $s0$revoke all on function private.enqueue_response_returned() from public, anon, authenticated, service_role$s0$;
      execute $s0$create trigger company_responses_notify after update of review_status on public.company_responses
  for each row execute function private.enqueue_response_returned()$s0$;
      execute $s0$-- Interface da Edge Function (service_role). Reserva um lote e devolve uma linha por destinatário, com o e-mail
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
$$$s0$;
      execute $s0$-- Resultado de uma linha: 'sent' (p_messages = e-mails entregues), 'retry' (falha; nova tentativa ou 'failed'),
-- 'release' (volta a 'pending' sem gastar tentativa: erro de autenticação SMTP ou teto do dia).
create function public.notification_mark(p_id uuid, p_result text, p_error_code text default null, p_messages integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_attempts integer; v_code text := case when p_error_code ~ '^[a-z0-9_]{1,40}$' then p_error_code end;
begin
  if p_result = 'sent' then
    update private.notification_outbox
    set status = 'sent', sent_at = now(), messages_sent = greatest(coalesce(p_messages, 0), 0), claimed_at = null, last_error_code = null
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
        last_error_code = v_code, claimed_at = null
    where id = p_id;
  elsif p_result = 'release' then
    update private.notification_outbox set status = 'pending', claimed_at = null, last_error_code = v_code
    where id = p_id and status = 'sending';
  else
    raise exception 'Resultado inválido.' using errcode = 'P0001';
  end if;
end;
$$$s0$;
      execute $s0$revoke all on function public.notification_claim(integer), public.notification_mark(uuid, text, text, integer)
  from public, anon, authenticated$s0$;
      execute $s0$grant execute on function public.notification_claim(integer), public.notification_mark(uuid, text, text, integer) to service_role$s0$;
      execute $s0$-- Opt-out em Meu perfil (só o próprio trabalhador). Desligado: avisos novos nascem 'suppressed' e os pendentes não saem.
create function public.set_worker_email_updates(p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_enabled is null then raise exception 'Valor inválido.' using errcode = 'P0001'; end if;
  update public.workers set email_updates = p_enabled where user_id = auth.uid();
  if not found then raise exception 'Somente trabalhadores têm esta preferência.' using errcode = 'P0001'; end if;
end;
$$$s0$;
      execute $s0$create function public.my_email_updates()
returns boolean language sql stable security definer set search_path = '' as $$
  select email_updates from public.workers where user_id = auth.uid();
$$$s0$;
      execute $s0$revoke all on function public.set_worker_email_updates(boolean), public.my_email_updates() from public, anon, service_role$s0$;
      execute $s0$grant execute on function public.set_worker_email_updates(boolean), public.my_email_updates() to authenticated$s0$;
      res := res || jsonb_build_object('20261123130000', 'aplicada na transação de teste');
    end if;

    -- Verificações (avisos_checks.sql)
    -- declare: u_w uuid := 'ffffffff-0000-0000-0000-000000000002'; u_c uuid := 'ffffffff-0000-0000-0000-000000000003'; u_op uuid := 'ffffffff-0000-0000-0000-000000000004'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765007987610'; v_co uuid; v_worker uuid; v_cp uuid; v_resp uuid; n int; v_id uuid; i int; r record;
    -- Verificações de 20261123130000 (fila de avisos às contas da plataforma). Só contagens.
    -- CNPJ de teste conferido como inexistente (404 em 2026-11-18); CPF de teste só na transação.
    if exists (select 1 from public.companies where cnpj = cnpj_c) or exists (select 1 from public.workers where cpf = '31415926590') then
      raise exception 'Valor de teste já existe em produção; troque o CNPJ/CPF do teste.';
    end if;
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-nw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Aviso Trabalhador', 'cpf', '31415926590', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-nc@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Aviso Empresa Ltda', 'cnpj', cnpj_c, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-nop@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    select company_id into v_co from public.company_users where user_id = u_c;
    select id into v_worker from public.workers where user_id = u_w;
    
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    v_cp := public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho', 'title', 'Tx caso do aviso',
      'original_content', 'Tx relato original.', 'shared_content', 'Tx versao compartilhavel.'), true);
    execute 'reset role';
    -- Eventos do próprio trabalhador (received, in_review) não geram aviso.
    if exists (select 1 from private.notification_outbox where worker_id = v_worker or company_id = v_co) then
      falhas := falhas || jsonb_build_object('evento do próprio trabalhador gerou aviso', true);
    end if;
    
    -- Equipe pede ajuste: aviso ao trabalhador; empresa nada.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_complaint(v_cp, 'adjustment_requested', 'Tx ajuste pedido pela equipe no teste.');
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    perform public.share_complaint(v_cp, 'Tx versao compartilhavel ajustada.');
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação ao telefone do site', null);
    perform public.ops_decide_complaint(v_cp, 'released', null);
    -- Empresa responde: aviso ao trabalhador (há atualização), sem conteúdo; a empresa não é avisada da própria resposta.
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    perform public.respond_complaint(v_cp, 'Tx resposta institucional da empresa.');
    execute 'reset role';
    select id into v_resp from public.company_responses where complaint_id = v_cp;
    select count(*) into n from private.notification_outbox where kind = 'company_update' and company_id = v_co;
    if n <> 1 then falhas := falhas || jsonb_build_object('company_update após liberação e resposta (esperado 1, só a liberação)', n); end if;
    -- Equipe devolve a resposta: aviso à empresa (sem evento na linha do tempo).
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_response(v_resp, 'returned', null, 'Tx devolução da resposta para ajuste no teste.');
    -- Empresa responde de novo; equipe libera; trabalhador encerra: aviso à empresa no encerramento.
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    perform public.respond_complaint(v_cp, 'Tx resposta institucional revisada da empresa.');
    execute 'reset role';
    select id into v_resp from public.company_responses where complaint_id = v_cp and review_status = 'in_review';
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_decide_response(v_resp, 'released', 'Tx a empresa respondeu e explicou as medidas que vai tomar no caso relatado.', null);
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    perform public.close_complaint(v_cp, 'yes');
    execute 'reset role';
    
    -- Trabalhador: ajuste, liberação, 1ª resposta (answer_in_review), 2ª resposta, resposta liberada (answered) = 5.
    select count(*) into n from private.notification_outbox where kind = 'worker_update' and worker_id = v_worker;
    if n <> 5 then falhas := falhas || jsonb_build_object('worker_update esperados 5', n); end if;
    -- Empresa: liberação, devolução e encerramento = 3; nunca received, in_review, held ou answer_in_review.
    select count(*) into n from private.notification_outbox where kind = 'company_update' and company_id = v_co;
    if n <> 3 then falhas := falhas || jsonb_build_object('company_update esperados 3 (liberação, devolução, encerramento)', n); end if;
    if exists (select 1 from private.notification_outbox where (worker_id = v_worker or company_id = v_co) and status <> 'pending') then
      falhas := falhas || jsonb_build_object('linha nasceu fora de pending', true);
    end if;
    -- A fila não guarda conteúdo: só as colunas previstas.
    if exists (select 1 from information_schema.columns where table_schema = 'private' and table_name = 'notification_outbox'
               and column_name in ('email', 'body', 'content', 'subject', 'protocol', 'title', 'note')) then
      falhas := falhas || jsonb_build_object('fila com coluna de conteúdo', true);
    end if;
    -- Ninguém de fora lê a fila.
    execute 'set local role authenticated';
    begin
      select count(*) into n from private.notification_outbox;
      falhas := falhas || jsonb_build_object('authenticated lê a fila', n);
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    execute 'set local role service_role';
    begin
      select count(*) into n from private.notification_outbox;
      falhas := falhas || jsonb_build_object('service_role lê a fila direto', n);
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    -- Opt-out do trabalhador: desligado, aviso novo nasce 'suppressed'; religa.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    perform public.set_worker_email_updates(false);
    if public.my_email_updates() is distinct from false then falhas := falhas || jsonb_build_object('opt-out não gravado', true); end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    begin
      perform public.set_worker_email_updates(false);
      falhas := falhas || jsonb_build_object('empresa grava opt-out de trabalhador', true);
    exception when others then null; end;
    execute 'reset role';
    insert into public.complaint_events (complaint_id, status, actor, note) values (v_cp, 'answered', 'platform', 'Tx evento da equipe com avisos desligados.');
    if not exists (select 1 from private.notification_outbox where worker_id = v_worker and status = 'suppressed') then
      falhas := falhas || jsonb_build_object('aviso com opt-out não nasceu suppressed', true);
    end if;
    update public.workers set email_updates = true where id = v_worker;
    
    -- Interface da função de envio: só service_role.
    execute 'set local role authenticated';
    begin
      perform public.notification_claim(10);
      falhas := falhas || jsonb_build_object('authenticated reserva a fila', true);
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    execute 'set local role service_role';
    select count(*) as n_rows, count(distinct outbox_id) as n_ids, bool_and(email in ('tx-nw@teste.invalid', 'tx-nc@teste.invalid')) as ok_emails, min(remaining_today) as rem
      into r from public.notification_claim(500);
    if r.n_rows <> 8 or r.n_ids <> 8 then falhas := falhas || jsonb_build_object('reserva devolveu linhas inesperadas (esperado 8: 5 do trabalhador, 3 da empresa)', r.n_rows); end if;
    if r.ok_emails is distinct from true then falhas := falhas || jsonb_build_object('reserva com e-mail fora dos destinatários previstos', true); end if;
    if coalesce(r.rem, 0) <= 0 then falhas := falhas || jsonb_build_object('saldo do dia não informado', true); end if;
    execute 'reset role';
    if exists (select 1 from private.notification_outbox where (worker_id = v_worker or company_id = v_co) and status = 'pending') then
      falhas := falhas || jsonb_build_object('linha pendente não reservada', true);
    end if;
    -- Resultados: sent, release (sem gastar tentativa) e retry até 'failed' na 6ª falha.
    select id into v_id from private.notification_outbox where worker_id = v_worker and status = 'sending' order by created_at limit 1;
    execute 'set local role service_role';
    perform public.notification_mark(v_id, 'sent', null, 1);
    execute 'reset role';
    if (select status || '/' || messages_sent from private.notification_outbox where id = v_id) is distinct from 'sent/1' then
      falhas := falhas || jsonb_build_object('mark sent', true);
    end if;
    select id into v_id from private.notification_outbox where company_id = v_co and status = 'sending' order by created_at limit 1;
    execute 'set local role service_role';
    perform public.notification_mark(v_id, 'release', 'smtp_auth', 0);
    execute 'reset role';
    if (select status || '/' || attempts || '/' || last_error_code from private.notification_outbox where id = v_id) is distinct from 'pending/0/smtp_auth' then
      falhas := falhas || jsonb_build_object('mark release', true);
    end if;
    select id into v_id from private.notification_outbox where worker_id = v_worker and status = 'sending' order by created_at limit 1;
    for i in 1..6 loop
      update private.notification_outbox set status = 'sending' where id = v_id;
      execute 'set local role service_role';
      perform public.notification_mark(v_id, 'retry', 'smtp_550', 0);
      execute 'reset role';
      if i = 1 and (select next_attempt_at between now() + interval '4 minutes' and now() + interval '6 minutes' from private.notification_outbox where id = v_id) is distinct from true then
        falhas := falhas || jsonb_build_object('primeira nova tentativa fora de 5 min', true);
      end if;
    end loop;
    if (select status || '/' || attempts from private.notification_outbox where id = v_id) is distinct from 'failed/6' then
      falhas := falhas || jsonb_build_object('6ª falha não virou failed', (select status || '/' || attempts from private.notification_outbox where id = v_id));
    end if;
    -- Teto do dia: com 300 mensagens enviadas hoje, a reserva não devolve nada.
    update private.notification_outbox set messages_sent = 300 where id = (select id from private.notification_outbox where status = 'sent' and worker_id = v_worker limit 1);
    update private.notification_outbox set status = 'pending', next_attempt_at = now() where company_id = v_co and status = 'sending';
    execute 'set local role service_role';
    select count(*) into n from public.notification_claim(500);
    execute 'reset role';
    if n <> 0 then falhas := falhas || jsonb_build_object('teto diário não respeitado', n); end if;
    res := res || jsonb_build_object('verificações da fila de avisos', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
