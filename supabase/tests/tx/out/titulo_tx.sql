-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar titulo_checks.sql e as migrations.
-- Migrations: 20261123120000_titulo_sem_conteudo_para_empresa.sql
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  u_w uuid := 'fddddddd-dddd-dddd-dddd-dddddddddddd'; u_c uuid := 'feeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'; u_op uuid := 'ffffffff-0000-0000-0000-000000000001'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765006987676'; v_co uuid; v_cp uuid; v_prot text; r record;
begin
  begin  -- trava: nada pode commitar daqui para dentro
    -- Sem lock em 3 s, falha limpa em vez de enfileirar o site atrás do DDL. (statement_timeout não se aplica: o
    -- cronômetro começa no DO, que é a instrução de topo; um SET aqui dentro não o rearma.)
    execute 'set local lock_timeout = ''3s''';

    -- 20261123120000_titulo_sem_conteudo_para_empresa.sql (1 instruções)
    if exists (select 1 from supabase_migrations.schema_migrations where version = '20261123120000') then
      res := res || jsonb_build_object('20261123120000', 'já aplicada em produção; pulada');
    else
      execute $s0$-- Achado de privacidade no teste em produção (EAB-2026-1067), opção (a) aprovada pelo responsável em 2026-11-23 ("Aprovo").
-- complaints.title é escrito na etapa do relato ORIGINAL e não passa pela revisão da versão compartilhável; a empresa o
-- recebia como título da manifestação (lista, detalhe, fila de atenção e PDF). Aplica a regra de que o original nunca sai
-- para a empresa (ADR-0010): list_company_complaints passa a devolver, na mesma coluna title, só 'Manifestação ' || protocolo.
-- Mesma assinatura e mesmos grants; o Front não precisa mudar. Trabalhador e equipe continuam vendo o título original.
-- Era a única função da empresa que devolvia complaints.title (conferido em 2026-11-23).
--
-- Rollback: reaplicar list_company_complaints de 20261117130000_representante_verificado_gate.sql.

create or replace function public.list_company_complaints()
returns table (id uuid, protocol text, category text, title text, status public.complaint_status, shared_content text,
               created_at timestamptz, updated_at timestamptz, responses integer, last_response_at timestamptz, worker_feedback public.complaint_feedback)
language sql stable security definer set search_path = '' as $$
  select c.id, c.protocol, c.category, 'Manifestação ' || c.protocol, c.status, s.shared_content, c.created_at, c.updated_at,
         (select count(*)::int from public.company_responses r where r.complaint_id = c.id),
         (select max(r.created_at) from public.company_responses r where r.complaint_id = c.id),
         c.worker_feedback
  from public.complaints c
  join public.complaint_shared_versions s on s.complaint_id = c.id
  where c.status in ('shared', 'answer_in_review', 'answered', 'closed') and public.is_verified_company_user(c.company_id)
  order by c.created_at desc;
$$$s0$;
      res := res || jsonb_build_object('20261123120000', 'aplicada na transação de teste');
    end if;

    -- Verificações (titulo_checks.sql)
    -- declare: u_w uuid := 'fddddddd-dddd-dddd-dddd-dddddddddddd'; u_c uuid := 'feeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'; u_op uuid := 'ffffffff-0000-0000-0000-000000000001'; addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}'; cnpj_c text := '98765006987676'; v_co uuid; v_cp uuid; v_prot text; r record;
    -- Verificações de 20261123120000: a empresa nunca recebe complaints.title (título do relato original).
    -- CNPJ de teste conferido como inexistente (404 na Minha Receita e na BrasilAPI em 2026-11-18); CPF de teste só na transação.
    if exists (select 1 from public.companies where cnpj = cnpj_c) or exists (select 1 from public.workers where cpf = '27182818205') then
      raise exception 'Valor de teste já existe em produção; troque o CNPJ/CPF do teste.';
    end if;
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000', u_w, 'authenticated', 'authenticated', 'tx-tw@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Tx Titulo Trabalhador', 'cpf', '27182818205', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_c, 'authenticated', 'authenticated', 'tx-tc@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Tx Titulo Empresa Ltda', 'cnpj', cnpj_c, 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
    ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'tx-top@teste.invalid', '{}', now(), now());
    insert into private.platform_admins (user_id) values (u_op);
    select company_id into v_co from public.company_users where user_id = u_c;
    
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'role', 'authenticated')::text, true);
    v_cp := public.create_complaint(jsonb_build_object('company_id', v_co, 'category', 'Carga de trabalho',
      'title', 'Tx Fulano Identificavel me pressiona', 'original_content', 'Tx relato original.', 'shared_content', 'Tx versao compartilhavel revisada.'), true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
    perform public.ops_verify_representative(v_co, u_c, 'verified', 'callback', 'Tx ligação ao telefone do site', null);
    perform public.ops_decide_complaint(v_cp, 'released', null);
    
    -- Empresa verificada: vê o caso, com título sem conteúdo do trabalhador.
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    select * into r from public.list_company_complaints() l where l.id = v_cp;
    if r.id is null then falhas := falhas || jsonb_build_object('empresa verificada não vê o caso liberado', true); end if;
    if r.title is distinct from 'Manifestação ' || r.protocol then falhas := falhas || jsonb_build_object('título da empresa não é o protocolo', true); end if;
    if exists (select 1 from public.list_company_complaints() l where l.title like '%Fulano%' or l.title like 'Tx %') then
      falhas := falhas || jsonb_build_object('empresa recebe o título do relato original', true);
    end if;
    if exists (select 1 from public.get_company_complaint_timeline(v_cp) t where t.content like '%Fulano%') then
      falhas := falhas || jsonb_build_object('linha do tempo da empresa com o título original', true);
    end if;
    
    -- Trabalhador e equipe continuam vendo o título original.
    execute 'reset role';
    if (select title from public.complaints where id = v_cp) is distinct from 'Tx Fulano Identificavel me pressiona' then
      falhas := falhas || jsonb_build_object('título original alterado', true);
    end if;
    res := res || jsonb_build_object('verificações do título', 'executadas');
    

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
