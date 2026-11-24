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
-- Contagens para a Operação: só a equipe; refletem a falha definitiva e a parada por senha nas últimas 24 h.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
begin
  perform public.ops_notification_stats();
  falhas := falhas || jsonb_build_object('trabalhador lê contagens da fila', true);
exception when others then null; end;
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
select * into r from public.ops_notification_stats();
if coalesce(r.failed, 0) < 1 or coalesce(r.stopped_auth_24h, 0) < 1 or coalesce(r.sent_24h, 0) < 1 then
  falhas := falhas || jsonb_build_object('contagens da fila incompletas', jsonb_build_object('failed', r.failed, 'auth', r.stopped_auth_24h, 'sent', r.sent_24h));
end if;
execute 'reset role';
res := res || jsonb_build_object('verificações da fila de avisos', 'executadas');
