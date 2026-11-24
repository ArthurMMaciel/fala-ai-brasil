-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar avisos_checks.sql e as migrations.
-- Migrations: 20261123130000_fila_de_avisos_da_plataforma.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'ffffffff-0000-0000-0000-000000000002'; u_c uuid := 'ffffffff-0000-0000-0000-000000000003'; u_op uuid := 'ffffffff-0000-0000-0000-000000000004'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765007987610'; v_co uuid; v_worker uuid; v_cp uuid; n int;
begin
  begin  -- trava: nada pode commitar daqui para dentro
    -- Sem lock em 3 s, falha limpa em vez de enfileirar o site atrás do DDL. (statement_timeout não se aplica: o
    -- cronômetro começa no DO, que é a instrução de topo; um SET aqui dentro não o rearma.)
    execute 'set local lock_timeout = ''3s''';

    -- 20261123130000_fila_de_avisos_da_plataforma.sql (8 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261123130000') then
      res := res || jsonb_build_object('20261123130000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- ADR-0020, revisão de 2026-11-23 (responsável, "Aprovo"): avisos só para contas da plataforma — o trabalhador dono do
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

set local lock_timeout = '5s'$s0$;
      execute $s0$create table private.notification_outbox (
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
)$s0$;
      execute $s0$create index notification_outbox_due_idx on private.notification_outbox (next_attempt_at) where status = 'pending'$s0$;
      execute $s0$alter table private.notification_outbox enable row level security$s0$;
      execute $s0$revoke all on private.notification_outbox from public, anon, authenticated, service_role$s0$;
      execute $s0$-- Alimenta a fila a partir da linha do tempo. Não lê nem copia conteúdo do evento.
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
$$$s0$;
      execute $s0$revoke all on function private.enqueue_notification() from public, anon, authenticated, service_role$s0$;
      execute $s0$create trigger complaint_events_notify after insert on public.complaint_events
  for each row execute function private.enqueue_notification()$s0$;
      res := res || jsonb_build_object('20261123130000', 'aplicada na transação de teste');
    end if;

    -- Verificações (avisos_checks.sql)
    -- declare: u_w uuid := 'ffffffff-0000-0000-0000-000000000002'; u_c uuid := 'ffffffff-0000-0000-0000-000000000003'; u_op uuid := 'ffffffff-0000-0000-0000-000000000004'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765007987610'; v_co uuid; v_worker uuid; v_cp uuid; n int;
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
    -- Empresa responde: aviso ao trabalhador (há atualização), sem conteúdo.
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    perform public.respond_complaint(v_cp, 'Tx resposta institucional da empresa.');
    execute 'reset role';
    
    select count(*) into n from private.notification_outbox where kind = 'worker_update' and worker_id = v_worker;
    if n <> 3 then falhas := falhas || jsonb_build_object('worker_update esperados 3 (ajuste, liberação, resposta)', n); end if;
    select count(*) into n from private.notification_outbox where kind = 'company_new_case' and company_id = v_co;
    if n <> 1 then falhas := falhas || jsonb_build_object('company_new_case esperado 1', n); end if;
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
    res := res || jsonb_build_object('verificações da fila de avisos', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
