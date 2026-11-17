-- Teste de isolamento entre organizações e pessoas (TASK-0006). Executa tudo e desfaz.
-- Execução: uma única instrução DO, que termina sempre em exceção; o Postgres desfaz tudo, inclusive auth.users.
-- Trava: o corpo roda dentro de um bloco com tratador de exceção (subtransação). Ali, COMMIT ou ROLLBACK explícitos
-- são proibidos pelo próprio Postgres ("cannot commit while a subtransaction is active"), e funções não podem commitar.
-- Efeito que o rollback não desfaz: a sequência complaint_protocol_seq avança (números de protocolo pulados).
-- Em produção, só com liberação escrita do responsável a cada execução: npx supabase db query --linked < supabase/tests/isolation_smoke.sql
--
-- Cenário: empresas A e B, trabalhadores A (manifesta contra A) e B (manifesta contra B), uma pessoa da equipe.
-- O teste descobre tabelas e funções pelo catálogo, então uma tabela ou RPC nova entra na varredura sozinha;
-- as listas esperadas de RPCs abertas a anon e a authenticated fazem o teste falhar quando surgir algo fora delas.
--
-- Provas:
--   1) catálogo: toda tabela de public com acesso de cliente tem RLS; RPCs de anon e authenticated batem com a lista;
--   2) anon: nenhuma tabela devolve linha; nenhuma RPC devolve marcador;
--   3) empresa A, trabalhador A e trabalhador B: em nenhuma tabela e em nenhuma RPC aparece marcador do outro lado
--      (relato original, identidade do trabalhador, dados privados da outra empresa ou do outro trabalhador);
--   4) escrita: update/delete por id do outro lado não afeta linha; inserts diretos são barrados; toda RPC chamada
--      com ids do outro lado erra ou não muda nada (impressão digital dos dados do outro lado antes e depois).
-- Cada chamada genérica roda em subtransação desfeita, para uma RPC não contaminar a seguinte.
do $$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  addr jsonb := '{"zip_code":"01310100","street_type":"avenue","street_name":"Paulista","number":"1","city":"São Paulo","state":"SP"}';
  u_wa uuid := 'd1111111-1111-1111-1111-111111111111';
  u_wb uuid := 'd2222222-2222-2222-2222-222222222222';
  u_ca uuid := 'd3333333-3333-3333-3333-333333333333';
  u_cb uuid := 'd4444444-4444-4444-4444-444444444444';
  u_op uuid := 'd5555555-5555-5555-5555-555555555555';
  co_a uuid; co_b uuid; wk_a uuid; wk_b uuid; cp_a uuid; cp_b uuid; rp_a uuid; rp_b uuid;
  -- Marcadores: textos e documentos únicos; se aparecerem para quem não deve, o teste aponta onde.
  mk_wa text[]; mk_wb text[]; mk_ca text[]; mk_cb text[];
  ator record; tbl record; fn record; col record;
  proibidos text[]; ids_outro uuid[]; v_id uuid; txt text; achou text; n int; antes text; depois text;
  args text; arg_t oid; i int; sql_fp text; esperado_anon text[]; esperado_auth text[]; atual text[];
begin
  begin  -- trava: todo o teste dentro de subtransação; nada pode commitar daqui para dentro
  ---------------------------------------------------------------------------------------------------------------
  -- Montagem (como postgres)
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', u_wa, 'authenticated', 'authenticated', 'iso-wa@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Isomarca Trabalhadora Alfa', 'cpf', '52998224725', 'phone', '41987650001', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', u_wb, 'authenticated', 'authenticated', 'iso-wb@teste.invalid', jsonb_build_object('signup_type', 'worker', 'signup', jsonb_build_object('full_name', 'Isomarca Trabalhador Beta', 'cpf', '39053344705', 'phone', '41987650002', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', u_ca, 'authenticated', 'authenticated', 'iso-ca@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Isomarca Empresa Alfa Ltda', 'cnpj', '11222333000181', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', u_cb, 'authenticated', 'authenticated', 'iso-cb@teste.invalid', jsonb_build_object('signup_type', 'company', 'signup', jsonb_build_object('legal_name', 'Isomarca Empresa Beta Ltda', 'cnpj', '45723174000110', 'plan_id', 'company-essential', 'subscription_mode', 'trial', 'address', addr)), now(), now()),
  ('00000000-0000-0000-0000-000000000000', u_op, 'authenticated', 'authenticated', 'iso-op@teste.invalid', '{}', now(), now());
  insert into private.platform_admins (user_id) values (u_op);
  select company_id into co_a from public.company_users where user_id = u_ca;
  select company_id into co_b from public.company_users where user_id = u_cb;
  select id into wk_a from public.workers where user_id = u_wa;
  select id into wk_b from public.workers where user_id = u_wb;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_wa, 'role', 'authenticated')::text, true);
  cp_a := public.create_complaint(jsonb_build_object('company_id', co_a, 'category', 'Carga de trabalho', 'title', 'Isomarca titulo caso Alfa',
    'original_content', 'Isomarca ORIGINAL Alfa: relato com nome de colega.', 'shared_content', 'Isomarca compartilhada Alfa: versao sem nomes.'), true);
  perform public.create_complaint(jsonb_build_object('company_id', co_a, 'category', 'Carga de trabalho', 'title', 'Isomarca titulo Alfa em revisao',
    'original_content', 'Isomarca ORIGINAL Alfa dois ainda em revisao.', 'shared_content', 'Isomarca compartilhada Alfa dois em revisao.'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_wb, 'role', 'authenticated')::text, true);
  cp_b := public.create_complaint(jsonb_build_object('company_id', co_b, 'category', 'Carga de trabalho', 'title', 'Isomarca titulo caso Beta',
    'original_content', 'Isomarca ORIGINAL Beta: relato com nome de colega.', 'shared_content', 'Isomarca compartilhada Beta: versao sem nomes.'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
  perform public.ops_decide_complaint(cp_a, 'released', null);
  perform public.ops_decide_complaint(cp_b, 'released', null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
  perform public.respond_complaint(cp_a, 'Isomarca resposta Alfa: a empresa revisou a escala.');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role', 'authenticated')::text, true);
  perform public.respond_complaint(cp_b, 'Isomarca resposta Beta: a empresa revisou a escala.');
  perform set_config('request.jwt.claims', json_build_object('sub', u_op, 'role', 'authenticated')::text, true);
  perform public.ops_decide_response(r.response_id, 'released', 'Isomarca resumo da equipe para o trabalhador ler com calma.', null)
  from public.ops_list_responses('in_review') r where r.complaint_id in (cp_a, cp_b);
  perform set_config('request.jwt.claims', json_build_object('sub', u_wb, 'role', 'authenticated')::text, true);
  select id into rp_b from public.company_responses where complaint_id = cp_b;
  perform public.rate_response(rp_b, 'yes', null);
  execute 'reset role';
  select id into rp_a from public.company_responses where complaint_id = cp_a;
  select id into rp_b from public.company_responses where complaint_id = cp_b;
  res := res || jsonb_build_object('montagem completa', cp_a is not null and cp_b is not null and rp_a is not null and rp_b is not null);

  -- Marcadores por lado. O nome e o id da empresa são públicos na lista de responsividade, então não entram.
  mk_wa := array['Isomarca Trabalhadora Alfa', '52998224725', '41987650001', 'iso-wa@teste.invalid', u_wa::text, wk_a::text, 'Isomarca ORIGINAL Alfa'];
  mk_wb := array['Isomarca Trabalhador Beta', '39053344705', '41987650002', 'iso-wb@teste.invalid', u_wb::text, wk_b::text, 'Isomarca ORIGINAL Beta'];
  mk_ca := array['iso-ca@teste.invalid', u_ca::text, 'Isomarca titulo Alfa em revisao'];
  mk_cb := array['iso-cb@teste.invalid', u_cb::text, 'Isomarca titulo caso Beta', 'Isomarca compartilhada Beta', 'Isomarca resposta Beta', cp_b::text, rp_b::text];

  -- Impressão digital (como postgres) de tudo que pertence ao lado B: mudou, alguém escreveu.
  select string_agg(format('(select coalesce(md5(string_agg(to_jsonb(t)::text, ''|'' order by to_jsonb(t)::text)), ''-'') from public.%I t where to_jsonb(t)::text ~ %L)',
           c.relname, array_to_string(array[co_b::text, u_cb::text, u_wb::text, wk_b::text, cp_b::text, rp_b::text], '|')), ' || ')
    into sql_fp
  from pg_class c join pg_namespace s on s.oid = c.relnamespace
  where s.nspname = 'public' and c.relkind = 'r';
  sql_fp := 'select ' || sql_fp;

  ---------------------------------------------------------------------------------------------------------------
  -- 1) Catálogo
  select coalesce(array_agg(c.relname order by c.relname), '{}') into atual
  from pg_class c join pg_namespace s on s.oid = c.relnamespace
  where s.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
    and (has_table_privilege('anon', c.oid, 'select,insert,update,delete') or has_table_privilege('authenticated', c.oid, 'select,insert,update,delete'));
  res := res || jsonb_build_object('tabelas com acesso de cliente sem RLS', to_jsonb(atual));
  if cardinality(atual) > 0 then falhas := falhas || jsonb_build_object('tabela sem RLS', to_jsonb(atual)); end if;

  select coalesce(array_agg(c.relname order by c.relname), '{}') into atual
  from pg_class c join pg_namespace s on s.oid = c.relnamespace
  where s.nspname = 'public' and c.relkind in ('v', 'm')
    and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select'));
  res := res || jsonb_build_object('views abertas a cliente', to_jsonb(atual));

  -- Listas esperadas: atualizar aqui, com revisão, ao abrir uma RPC nova.
  esperado_anon := array[]::text[];
  esperado_auth := array[]::text[];
  select coalesce(array_agg(p.oid::regprocedure::text order by 1), '{}') into atual
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
  res := res || jsonb_build_object('rpc anon', to_jsonb(atual));
  if atual is distinct from esperado_anon then falhas := falhas || jsonb_build_object('rpc anon fora da lista', to_jsonb(array(select unnest(atual) except select unnest(esperado_anon)))); end if;
  select coalesce(array_agg(p.oid::regprocedure::text order by 1), '{}') into atual
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype and has_function_privilege('authenticated', p.oid, 'execute');
  res := res || jsonb_build_object('rpc authenticated', to_jsonb(atual));
  if atual is distinct from esperado_auth then falhas := falhas || jsonb_build_object('rpc authenticated fora da lista', to_jsonb(array(select unnest(atual) except select unnest(esperado_auth)))); end if;
  select coalesce(array_agg(p.oid::regprocedure::text order by 1), '{}') into atual
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'private' and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
  res := res || jsonb_build_object('funções de private abertas a cliente', to_jsonb(atual));

  ---------------------------------------------------------------------------------------------------------------
  -- 2) a 4) Varredura por ator. Para cada ator: o que ele não pode ver e os ids do outro lado.
  for ator in
    select * from (values
      ('anon',            null::uuid, 'anon'),
      ('empresa A',       u_ca,       'authenticated'),
      ('trabalhador A',   u_wa,       'authenticated'),
      ('trabalhador B',   u_wb,       'authenticated')
    ) as t(nome, sub, papel)
  loop
    proibidos := case ator.nome
      when 'anon'          then mk_wa || mk_wb || mk_ca || mk_cb || array['Isomarca compartilhada Alfa', 'Isomarca resposta Alfa', 'Isomarca titulo caso Alfa']
      when 'empresa A'     then mk_wa || mk_wb || mk_cb || array['Isomarca titulo Alfa em revisao', 'Isomarca compartilhada Alfa dois']
      when 'trabalhador A' then mk_wb || mk_cb || mk_ca
      when 'trabalhador B' then mk_wa || mk_ca || array['Isomarca titulo caso Alfa', 'Isomarca compartilhada Alfa', 'Isomarca resposta Alfa', cp_a::text, rp_a::text]
    end;
    -- Ids que o ator não pode alterar. Para o trabalhador B, o lado protegido é o A.
    ids_outro := case ator.nome
      when 'trabalhador B' then array[co_a, u_ca, u_wa, wk_a, cp_a, rp_a]
      else array[co_b, u_cb, u_wb, wk_b, cp_b, rp_b]
    end;
    if ator.nome = 'trabalhador B' then
      select string_agg(format('(select coalesce(md5(string_agg(to_jsonb(t)::text, ''|'' order by to_jsonb(t)::text)), ''-'') from public.%I t where to_jsonb(t)::text ~ %L)',
               c.relname, array_to_string(array[co_a::text, u_ca::text, u_wa::text, wk_a::text, cp_a::text, rp_a::text], '|')), ' || ')
        into sql_fp
      from pg_class c join pg_namespace s on s.oid = c.relnamespace where s.nspname = 'public' and c.relkind = 'r';
      sql_fp := 'select ' || sql_fp;
    end if;

    execute 'reset role';
    if ator.sub is null then
      perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    else
      perform set_config('request.jwt.claims', json_build_object('sub', ator.sub, 'role', 'authenticated')::text, true);
    end if;
    execute format('set local role %I', ator.papel);

    -- 2/3) Leitura direta de toda tabela e view de public.
    for tbl in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
               where s.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') order by 1 loop
      begin
        execute format('select coalesce(string_agg(to_jsonb(t)::text, ''|''), ''''), count(*) from public.%I t', tbl.relname) into txt, n;
        select string_agg(m, ', ') into achou from unnest(proibidos) m where strpos(txt, m) > 0;
        if achou is not null then falhas := falhas || jsonb_build_object(ator.nome || ' lê ' || tbl.relname, achou); end if;
        if ator.nome = 'anon' and n > 0 then res := res || jsonb_build_object('anon lê linhas de ' || tbl.relname, n); end if;
      exception when insufficient_privilege then null;
      end;
    end loop;

    -- 4a) Update e delete por id do outro lado, em toda tabela com coluna de vínculo.
    for col in select c.table_name, c.column_name from information_schema.columns c
               join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
               where c.table_schema = 'public' and c.data_type = 'uuid'
                 and c.column_name in ('id', 'user_id', 'company_id', 'worker_id', 'complaint_id', 'response_id', 'created_by', 'author_user_id')
               order by 1, 2 loop
      begin
        execute format('update public.%I set %I = %I where %I = any($1)', col.table_name, col.column_name, col.column_name, col.column_name) using ids_outro;
        get diagnostics n = row_count;
        if n > 0 then falhas := falhas || jsonb_build_object(ator.nome || ' altera ' || col.table_name || '.' || col.column_name, n); end if;
      exception when others then null;
      end;
      begin
        execute format('delete from public.%I where %I = any($1)', col.table_name, col.column_name) using ids_outro;
        get diagnostics n = row_count;
        if n > 0 then falhas := falhas || jsonb_build_object(ator.nome || ' apaga ' || col.table_name || '.' || col.column_name, n); end if;
      exception when others then null;
      end;
    end loop;

    -- 4b) Inserts diretos que criariam vínculo com o outro lado.
    begin
      execute 'insert into public.company_responses (complaint_id, company_id, content) values ($1, $2, $3)'
        using ids_outro[5], ids_outro[1], 'Isomarca resposta intrusa com tamanho suficiente.';
      falhas := falhas || jsonb_build_object(ator.nome || ' insere resposta em caso alheio', true);
    exception when others then null; end;
    begin
      execute 'insert into public.complaint_events (complaint_id, status, actor, note) values ($1, ''closed'', ''platform'', ''Isomarca evento intruso.'')' using ids_outro[5];
      falhas := falhas || jsonb_build_object(ator.nome || ' insere evento em caso alheio', true);
    exception when others then null; end;
    begin
      execute 'insert into public.company_users (company_id, user_id, role) values ($1, $2, ''owner'')' using ids_outro[1], coalesce(ator.sub, u_wa);
      falhas := falhas || jsonb_build_object(ator.nome || ' entra em empresa alheia', true);
    exception when others then null; end;
    begin
      execute 'insert into public.complaint_shared_versions (complaint_id, shared_content) values ($1, $2)' using ids_outro[5], 'Isomarca versao intrusa com tamanho.';
      falhas := falhas || jsonb_build_object(ator.nome || ' insere versão em caso alheio', true);
    exception when others then null; end;

    -- 2/3/4c) Toda RPC aberta ao papel, chamada com cada id do outro lado nos parâmetros uuid.
    -- Saída aceita: erro, ou resultado sem marcador proibido e sem mudança nos dados do outro lado.
    for fn in select p.oid, p.proname, p.pronargs, p.proargtypes, p.oid::regprocedure::text as assinatura, p.provolatile = 'v' as pode_escrever
              from pg_proc p join pg_namespace s on s.oid = p.pronamespace
              where s.nspname = 'public' and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype
                and has_function_privilege(ator.papel, p.oid, 'execute')
              order by p.proname loop
      foreach v_id in array (case when 'uuid'::regtype = any(fn.proargtypes::oid[]) then ids_outro else array[null::uuid] end) loop
        args := '';
        for i in 0 .. fn.pronargs - 1 loop
          arg_t := fn.proargtypes[i];
          args := args || case when i > 0 then ', ' else '' end || case
            when arg_t = 'uuid'::regtype then quote_nullable(v_id::text) || '::uuid'
            when arg_t in ('text'::regtype, 'varchar'::regtype) then quote_literal('Isomarca texto de teste com tamanho suficiente para validar.')
            when arg_t in ('jsonb'::regtype, 'json'::regtype) then quote_literal(jsonb_build_object('company_id', ids_outro[1], 'id', v_id)::text) || '::' || format_type(arg_t, null)
            when arg_t in ('integer'::regtype, 'bigint'::regtype, 'numeric'::regtype, 'smallint'::regtype) then '1'
            when arg_t = 'boolean'::regtype then 'true'
            when exists (select 1 from pg_enum e where e.enumtypid = arg_t)
              then quote_literal((select e.enumlabel from pg_enum e where e.enumtypid = arg_t order by e.enumsortorder limit 1)) || '::' || format_type(arg_t, null)
            else 'null::' || format_type(arg_t, null)
          end;
        end loop;
        txt := null; antes := null; depois := null;
        begin
          execute 'reset role';
          if fn.pode_escrever then execute sql_fp into antes; end if;
          execute format('set local role %I', ator.papel);
          execute format('select coalesce(string_agg(x::text, ''|''), '''') from (select public.%I(%s) as x) s', fn.proname, args) into txt;
          execute 'reset role';
          if fn.pode_escrever then execute sql_fp into depois; end if;
          execute format('set local role %I', ator.papel);
          raise exception using errcode = 'P0001', message = 'ISO_DESFAZ';
        exception when others then
          if sqlerrm <> 'ISO_DESFAZ' then txt := null; depois := antes; end if;
        end;
        execute format('set local role %I', ator.papel);
        if txt is not null then
          select string_agg(m, ', ') into achou from unnest(proibidos) m where strpos(txt, m) > 0;
          if achou is not null then falhas := falhas || jsonb_build_object(ator.nome || ' recebe de ' || fn.assinatura, achou); end if;
        end if;
        -- Abrir manifestação contra outra empresa é permitido ao trabalhador por desenho.
        if antes is distinct from depois and not (fn.proname = 'create_complaint' and ator.nome like 'trabalhador%') then falhas := falhas || jsonb_build_object(ator.nome || ' muda dados alheios via ' || fn.assinatura, coalesce(v_id::text, 'sem uuid')); end if;
      end loop;
    end loop;
  end loop;

  ---------------------------------------------------------------------------------------------------------------
  -- Chamadas dirigidas, com argumentos válidos, nas RPCs de escrita mais sensíveis.
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
  begin
    perform public.respond_complaint(cp_b, 'Isomarca resposta da empresa A no caso da empresa B.');
    falhas := falhas || jsonb_build_object('empresa A responde caso de B', true);
  exception when others then null; end;
  res := res || jsonb_build_object('empresa A não abre linha do tempo de B', (select count(*) from public.get_company_complaint_timeline(cp_b)) = 0);
  res := res || jsonb_build_object('empresa A vê o próprio caso liberado', exists (select 1 from public.list_company_complaints() where id = cp_a));
  perform set_config('request.jwt.claims', json_build_object('sub', u_wa, 'role', 'authenticated')::text, true);
  begin
    perform public.rate_response(rp_b, 'yes', null);
    falhas := falhas || jsonb_build_object('trabalhador A avalia resposta de B', true);
  exception when others then null; end;
  begin
    perform public.close_complaint(cp_b, 'yes');
    falhas := falhas || jsonb_build_object('trabalhador A encerra caso de B', true);
  exception when others then null; end;
  begin
    perform public.share_complaint(cp_b, 'Isomarca versao trocada pelo trabalhador A.');
    falhas := falhas || jsonb_build_object('trabalhador A troca versão de B', true);
  exception when others then null; end;
  begin
    perform public.ops_read_original(cp_b, 'Isomarca justificativa de quem não é da equipe.');
    falhas := falhas || jsonb_build_object('trabalhador lê original pela RPC da equipe', true);
  exception when others then null; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
  begin
    perform public.ops_read_original(cp_a, 'Isomarca justificativa de quem não é da equipe.');
    falhas := falhas || jsonb_build_object('empresa lê original pela RPC da equipe', true);
  exception when others then null; end;

  execute 'reset role';
  res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
  raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): %', sqlerrm;
  end;
end $$;
