-- declare: u_w uuid := 'f0000000-0000-0000-0000-000000000021'; u_c uuid := 'f0000000-0000-0000-0000-000000000022'; u_op uuid := 'f0000000-0000-0000-0000-000000000023'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765007987610'; cnpj_a text := '98765001987643'; cnpj_b text := '98765004987687'; cnpj_d text := '98765005987621'; cnpj_e text := '98765009987600'; v_co uuid; v_worker uuid; v_cp uuid; v_resp uuid; cp_a uuid; cp_b uuid; cp_d uuid; cp_e uuid; cp_r uuid; co_a uuid; co_b uuid; co_d uuid; co_e uuid; n_a uuid; n_b uuid; n_d uuid; n_e uuid; v_id uuid; mine uuid[]; n int; i int; r record; base jsonb;
-- Verificações de 20261126130000 (motivo do aviso e aviso automático à empresa não cadastrada). Roda depois de
-- 20261126120000. CNPJs de teste conferidos como inexistentes (404 em 2026-11-18); CPF de teste só na transação.
-- Em produção a reserva pode pegar linhas reais: tudo é desfeito e as contagens filtram pelos ids do teste.
if exists (select 1 from public.companies where cnpj in (cnpj_c, cnpj_a, cnpj_b, cnpj_d, cnpj_e))
   or exists (select 1 from public.workers where cpf = '31415926590') then
  raise exception 'Valor de teste já existe; troque os CNPJs/CPF do teste.';
end if;
base := jsonb_build_object('category', 'Carga de trabalho', 'title', 'Tx caso', 'original_content', 'Tx relato original.',
                           'shared_content', 'Tx versao compartilhavel.', 'notice_consent', true);
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-ew@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Evento Trabalhador', 'cpf', '31415926590', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-ec@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Evento Empresa Ltda', 'cnpj', cnpj_c, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-eop@teste.invalid', '{}', now(), now());
insert into private.platform_admins (user_id) values (u_op);
select company_id into v_co from public.company_users where user_id = u_c;
select id into v_worker from public.workers where user_id = u_w;
perform public.cnpj_cache_put(cnpj_a, false, 'Tx Empresa A Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', 'receita@tx-a.invalid');
perform public.cnpj_cache_put(cnpj_b, false, 'Tx Empresa B Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', 'receita@tx-b.invalid');
perform public.cnpj_cache_put(cnpj_d, false, 'Tx Empresa D Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', null);
perform public.cnpj_cache_put(cnpj_e, false, 'Tx Empresa E Ltda', null, 'ATIVA', 'Santos', 'SP', '6201501', '2062', 'minhareceita', null);

-- 1) Motivo por evento na empresa cadastrada: liberação, devolução da resposta e encerramento.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
v_cp := public.create_complaint(base || jsonb_build_object('company_id', v_co), true);
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação ao telefone do site', null);
perform public.ops_decide_complaint(v_cp, 'released', null);
perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
perform public.respond_complaint(v_cp, 'Tx resposta institucional da empresa.');
execute 'reset role';
select id into v_resp from public.company_responses where complaint_id = v_cp;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_decide_response(v_resp, 'returned', null, 'Tx devolução da resposta para ajuste no teste.');
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
if (select string_agg(reason, ',' order by reason) from private.notification_outbox where kind = 'company_update' and company_id = v_co)
   is distinct from 'closed,released,response_returned' then
  falhas := falhas || jsonb_build_object('motivos da empresa (esperado closed, released, response_returned)',
    (select string_agg(reason, ',' order by reason) from private.notification_outbox where kind = 'company_update' and company_id = v_co));
end if;
if exists (select 1 from private.notification_outbox where kind = 'worker_update' and worker_id = v_worker and reason <> 'update')
   or not exists (select 1 from private.notification_outbox where kind = 'worker_update' and worker_id = v_worker) then
  falhas := falhas || jsonb_build_object('motivo do trabalhador diferente de update', true);
end if;
-- Combinações inválidas recusadas pelo banco.
begin
  insert into private.notification_outbox (kind, worker_id, dedupe_key, reason) values ('worker_update', v_worker, 'tx:motivo', 'released');
  falhas := falhas || jsonb_build_object('worker_update com motivo de empresa aceito', true);
exception when check_violation then null; end;
begin
  insert into private.notification_outbox (kind, company_id, dedupe_key, reason) values ('company_notice', v_co, 'tx:sem-aviso', 'notice');
  falhas := falhas || jsonb_build_object('company_notice sem notice_id aceito', true);
exception when check_violation then null; end;

-- 2) Avisos às empresas não cadastradas: só a aprovação entra na fila.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
cp_a := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_a, 'notice_contacts', jsonb_build_array(
  jsonb_build_object('email', 'rh@tx-a.invalid', 'possibly_involved', false, 'consent', true))), true);
cp_b := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_b, 'notice_contacts', jsonb_build_array(
  jsonb_build_object('email', 'chefe@tx-b.invalid', 'possibly_involved', true, 'consent', true))), true);
cp_d := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_d, 'notice_contacts', jsonb_build_array(
  jsonb_build_object('email', 'sai@tx-d.invalid', 'possibly_involved', false, 'consent', true))), true);
-- Limite de 3 pré-cadastros por dia por pessoa: zera o contador do usuário de teste (só nesta transação).
execute 'reset role';
select id into co_a from public.companies where cnpj = cnpj_a;
delete from private.cnpj_lookup_quota where user_id = u_w;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
cp_r := public.create_complaint(base || jsonb_build_object('company_id', co_a, 'notice_contacts', jsonb_build_array(
  jsonb_build_object('email', 'outro@tx-a.invalid', 'possibly_involved', false, 'consent', true))), true);
cp_e := public.create_complaint(base || jsonb_build_object('company_cnpj', cnpj_e, 'notice_contacts', jsonb_build_array(
  jsonb_build_object('email', 'manual@tx-e.invalid', 'possibly_involved', false, 'consent', true))), true);
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_decide_complaint(cp_a, 'released', null);
perform public.ops_decide_complaint(cp_r, 'released', null);
perform public.ops_decide_complaint(cp_b, 'released', null);
perform public.ops_decide_complaint(cp_d, 'released', null);
perform public.ops_decide_complaint(cp_e, 'released', null);
n_a := public.ops_decide_notice(cp_a, 'approved', null);                  -- contato do trabalhador
perform public.ops_decide_notice(cp_r, 'rejected', 'Tx recusa do aviso no teste da fila.');
n_b := public.ops_decide_notice(cp_b, 'approved', null);                  -- só envolvido: Receita
n_d := public.ops_decide_notice(cp_d, 'approved', null);
n_e := public.ops_decide_notice(cp_e, 'approved', null);
execute 'reset role';
if (select count(*) from private.notification_outbox where kind = 'company_notice' and notice_id in (n_a, n_b, n_d, n_e)
    and status = 'pending' and reason = 'notice') <> 4 then
  falhas := falhas || jsonb_build_object('aprovação não pôs os 4 avisos na fila', true);
end if;
if exists (select 1 from private.notification_outbox o join public.company_notices cn on cn.id = o.notice_id where cn.complaint_id = cp_r) then
  falhas := falhas || jsonb_build_object('recusa pôs aviso na fila', true);
end if;
if (select destination_source from public.company_notices where id = n_b) is distinct from 'receita' then
  falhas := falhas || jsonb_build_object('aviso B não foi para a Receita', true);
end if;

-- Opt-out depois da aprovação: conferido no envio.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_add_opt_out('Sai@tx-d.invalid');
-- Marcação manual: recusada com envio em curso; com envio pendente, tira da fila.
execute 'reset role';
update private.notification_outbox set status = 'sending', claimed_at = now() where notice_id = n_e;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
begin
  perform public.ops_mark_notice_sent(n_e, 'sent');
  falhas := falhas || jsonb_build_object('marcação manual com envio em curso aceita', true);
exception when others then
  if sqlerrm not like '%em curso%' then falhas := falhas || jsonb_build_object('mensagem envio em curso', sqlerrm); end if;
end;
execute 'reset role';
update private.notification_outbox set status = 'pending', claimed_at = null where notice_id = n_e;
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_mark_notice_sent(n_e, 'sent');
execute 'reset role';
if (select status from private.notification_outbox where notice_id = n_e) is distinct from 'suppressed'
   or (select status || '/' || (sent_by = u_op)::text from public.company_notices where id = n_e) is distinct from 'sent/true' then
  falhas := falhas || jsonb_build_object('marcação manual não tirou o envio da fila', true);
end if;

-- 3) Reserva: sem p_include_notices, nenhum aviso de empresa; com, o destino resolvido agora.
select array_agg(id) into mine from private.notification_outbox where worker_id = v_worker or company_id in (select id from public.companies where cnpj in (cnpj_c, cnpj_a, cnpj_b, cnpj_d, cnpj_e));
execute 'set local role authenticated';
begin
  perform public.notification_claim(10, true);
  falhas := falhas || jsonb_build_object('authenticated reserva a fila', true);
exception when insufficient_privilege then null; end;
execute 'reset role';
if to_regprocedure('public.notification_claim(integer)') is not null then falhas := falhas || jsonb_build_object('reserva antiga (integer) continua', true); end if;
execute 'set local role service_role';
select count(*) filter (where kind = 'company_notice') as notices, count(*) filter (where kind = 'company_update' and reason = 'released') as released
  into r from public.notification_claim(200) where outbox_id = any (mine);
execute 'reset role';
if r.notices <> 0 then falhas := falhas || jsonb_build_object('reserva padrão entregou aviso de empresa', r.notices); end if;
if r.released < 1 then falhas := falhas || jsonb_build_object('reserva sem o motivo released', true); end if;
if exists (select 1 from private.notification_outbox where notice_id in (n_a, n_b, n_d) and status <> 'pending') then
  falhas := falhas || jsonb_build_object('reserva padrão tocou nos avisos de empresa', true);
end if;
execute 'set local role service_role';
select string_agg(c.reason || ':' || c.email, ',' order by c.email) as got into r
  from public.notification_claim(200, true) c where c.outbox_id = any (mine);
execute 'reset role';
if r.got is distinct from 'notice:receita@tx-b.invalid,notice:rh@tx-a.invalid' then
  falhas := falhas || jsonb_build_object('reserva com avisos (esperado Receita B e contato A)', r.got);
end if;
if (select status from private.notification_outbox where notice_id = n_d) is distinct from 'suppressed'
   or (select status from public.company_notices where id = n_d) is distinct from 'approved' then
  falhas := falhas || jsonb_build_object('opt-out depois da aprovação não suprimiu o envio (aviso continua approved)', true);
end if;

-- 4) Resultado reflete em company_notices: enviado -> sent (automático, sent_by nulo); 6ª falha -> bounced.
select id into v_id from private.notification_outbox where notice_id = n_a;
execute 'set local role service_role';
perform public.notification_mark(v_id, 'sent', null, 1);
execute 'reset role';
if (select status || '/' || coalesce(sent_by::text, 'auto') || '/' || (sent_at is not null)::text from public.company_notices where id = n_a)
   is distinct from 'sent/auto/true' then
  falhas := falhas || jsonb_build_object('envio automático não marcou o aviso como sent', true);
end if;
select id into v_id from private.notification_outbox where notice_id = n_b;
for i in 1..6 loop
  update private.notification_outbox set status = 'sending' where id = v_id;
  execute 'set local role service_role';
  perform public.notification_mark(v_id, 'retry', 'smtp_550', 0);
  execute 'reset role';
  if i = 5 and (select status from public.company_notices where id = n_b) is distinct from 'approved' then
    falhas := falhas || jsonb_build_object('aviso devolvido antes da falha definitiva', true);
  end if;
end loop;
if (select status from public.company_notices where id = n_b) is distinct from 'bounced' then
  falhas := falhas || jsonb_build_object('falha definitiva não marcou o aviso como bounced', true);
end if;
-- O 30 dias por empresa continua: cp_r (empresa A) não aprova depois do envio... já recusado; nova manifestação na A.
execute 'set local role authenticated';
perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
cp_r := public.create_complaint(base || jsonb_build_object('company_id', co_a), true);
perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
perform public.ops_decide_complaint(cp_r, 'released', null);
begin
  perform public.ops_decide_notice(cp_r, 'approved', null, 'receita');
  falhas := falhas || jsonb_build_object('segundo aviso à empresa A em 30 dias', true);
exception when others then null; end;
execute 'reset role';
-- A fila continua sem e-mail nem conteúdo.
if exists (select 1 from information_schema.columns where table_schema = 'private' and table_name = 'notification_outbox'
           and column_name in ('email', 'body', 'content', 'subject', 'protocol', 'title', 'note', 'destination')) then
  falhas := falhas || jsonb_build_object('fila com coluna de conteúdo ou destino', true);
end if;
res := res || jsonb_build_object('verificações de avisos por evento e aviso automático', 'executadas');
