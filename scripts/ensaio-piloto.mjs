// Ensaio ponta a ponta do piloto (TASK-0033), reproduzível e sem deixar dados.
// Gera um SQL que cria contas fictícias, percorre o fluxo pelas mesmas RPCs e políticas que o front usa
// (assumindo o papel de cada pessoa via request.jwt.claims) e desfaz tudo no fim: o resultado volta como tabela.
//
// Uso (banco de dev, nunca produção):
//   node scripts/ensaio-piloto.mjs > <pasta-temporaria>/ensaio.sql
//   node scripts/dev-db.mjs query <pasta-temporaria>/ensaio.sql
// Local com Docker: npx supabase db query --local < <pasta-temporaria>/ensaio.sql
//
// Não usa senha, chave de serviço nem dado real. E-mails em example.invalid; CPF e CNPJ gerados a cada execução.
import { randomInt } from 'node:crypto';

const cpf = base => { const d = String(base).padStart(9, '0').split('').map(Number); for (const len of [9, 10]) { const sum = d.slice(0, len).reduce((t, n, i) => t + n * (len + 1 - i), 0); const r = (sum * 10) % 11; d.push(r === 10 ? 0 : r); } return d.join(''); };
const cnpj = base => { const d = (String(base).padStart(8, '0') + '0001').split('').map(Number); for (const w of [[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]]) { const r = w.reduce((t, n, i) => t + n * d[i], 0) % 11; d.push(r < 2 ? 0 : 11 - r); } return d.join(''); };
const q = value => `'${String(value).replace(/'/g, "''")}'`;
const run = `${Date.now().toString(36)}${randomInt(1000, 9999)}`;
const address = { zip_code: '01310100', street_type: 'avenue', street_name: 'Paulista', number: '1000', neighborhood: 'Bela Vista', city: 'São Paulo', state: 'SP' };
const meta = (name, type, signup) => q(JSON.stringify({ full_name: name, signup_type: type, signup }));
const people = {
  w: ['Pessoa Ensaio Trabalhadora', 'worker', { full_name: 'Pessoa Ensaio Trabalhadora', cpf: cpf(randomInt(100000000, 899999999)), address }],
  a: ['Empresa Ensaio A', 'company', { legal_name: 'Empresa Ensaio A Ltda.', trade_name: 'Empresa Ensaio A', cnpj: cnpj(randomInt(10000000, 89999999)), plan_id: 'company-essential', subscription_mode: 'trial', address }],
  b: ['Empresa Ensaio B', 'company', { legal_name: 'Empresa Ensaio B Ltda.', trade_name: 'Empresa Ensaio B', cnpj: cnpj(randomInt(10000000, 89999999)), plan_id: 'company-essential', subscription_mode: 'trial', address }],
  ops: ['Equipe Ensaio', null, null],
};

const ORIGINAL = `Relato original fictício ${run}: só a equipe pode ler este texto.`;
const SHARED = `Versão compartilhável fictícia ${run}: a equipe do setor relata excesso de horas.`;
const RESPONSE_1 = `Resposta fictícia ${run} citando a supervisora Maria.`;
const RESPONSE_2 = `Resposta fictícia ${run}: vamos revisar a escala do setor nas próximas duas semanas.`;
const SUMMARY = `Descrição da equipe ${run}: a empresa informou que vai revisar a escala do setor em duas semanas.`;

// Troca de papel: mesmas claims que o PostgREST entrega ao banco para uma sessão autenticada.
const as = who => `perform set_config('request.jwt.claims', json_build_object('sub', u_${who}, 'role', 'authenticated')::text, true); perform set_config('role', 'authenticated', true);`;
const asSystem = `perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);`;
const record = (step, expected, got, ok) => `res := res || jsonb_build_object('passo', ${q(step)}, 'esperado', ${q(expected)}, 'obtido', (${got})::text, 'ok', coalesce((${ok})::boolean, false));`;
const expectError = (step, statement, message) => { const expected = message ? `erro "${message}"` : 'erro (recusado)'; return `begin
    ${statement};
    ${record(step, expected, `'sem erro'`, 'false')}
  exception when others then
    ${record(step, expected, 'sqlerrm', `sqlerrm ilike ${q(`%${message}%`)}`)}
  end;`; };
const companySees = (complaint, text) => `exists (select 1 from public.list_company_complaints() c where c.id = ${complaint}${text ? ` and row_to_json(c)::text like ${q(`%${text}%`)}` : ''})`;
const companyTimelineHas = text => `exists (select 1 from public.get_company_complaint_timeline(v_main) t where row_to_json(t)::text like ${q(`%${text}%`)})`;

const users = Object.entries(people).map(([key, [name, type, signup]]) => `  u_${key} := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current, reauthentication_token, phone_change, phone_change_token)
  values ('00000000-0000-0000-0000-000000000000', u_${key}, 'authenticated', 'authenticated', ${q(`ensaio-${key}-${run}@example.invalid`)}, '', now(), '{"provider":"email","providers":["email"]}', ${type ? meta(name, type, signup) : q(JSON.stringify({ full_name: name }))}::jsonb, now(), now(), '', '', '', '', '', '', '', '');`).join('\n');

const sql = `-- Ensaio ponta a ponta ${run} (TASK-0033). Gerado por scripts/ensaio-piloto.mjs; tudo é desfeito no fim.
-- A trava contra produção fica no executor (scripts/dev-db.mjs, assertDevTarget); este SQL não grava nada.
create or replace function pg_temp.ensaio_piloto() returns table (n bigint, passo text, esperado text, obtido text, ok boolean)
language plpgsql as $fn$
declare
  res jsonb := '[]'::jsonb;
  u_w uuid; u_a uuid; u_b uuid; u_ops uuid;
  v_company_a uuid; v_company_b uuid; v_main uuid; v_withdrawn uuid; v_resp1 uuid; v_resp2 uuid; v_text text; v_count int;
begin
  begin
  -- Preparação (papel do sistema): contas fictícias e equipe provisionada como em produção.
${users}
  insert into private.platform_admins (user_id) values (u_ops);
  select company_id into v_company_a from public.company_users where user_id = u_a;
  select company_id into v_company_b from public.company_users where user_id = u_b;
  ${record('0. Preparação: contas fictícias criadas pelo cadastro', 'trabalhador e duas empresas com perfil', `(select count(*) from public.workers where user_id = u_w) || ' trabalhador, ' || (case when v_company_a is not null and v_company_b is not null then 2 else 0 end) || ' empresas'`, `exists (select 1 from public.workers where user_id = u_w) and v_company_a is not null and v_company_b is not null`)}

  -- 1. Trabalhador manifesta.
  ${as('w')}
  ${expectError('1a. Erro: pedir revisão sem versão compartilhável', `perform public.create_complaint(jsonb_build_object('company_id', v_company_a, 'category', 'Sobrecarga / excesso de trabalho', 'title', 'Ensaio sem versão', 'original_content', ${q(ORIGINAL)}, 'incident_period', 'Últimas semanas', 'recurrence', 'Recorrente', 'expected_outcomes', jsonb_build_array('Receber uma resposta')), true)`, 'Escreva a versão que poderá ser compartilhada')}
  v_main := public.create_complaint(jsonb_build_object('company_id', v_company_a, 'category', 'Sobrecarga / excesso de trabalho', 'title', 'Ensaio principal', 'original_content', ${q(ORIGINAL)}, 'shared_content', ${q(SHARED)}, 'incident_period', 'Últimas semanas', 'recurrence', 'Recorrente', 'expected_outcomes', jsonb_build_array('Receber uma resposta')), true)::uuid;
  ${record('1b. Manifestação criada com pedido de revisão', 'status in_review', `(select status from public.complaints where id = v_main)`, `(select status from public.complaints where id = v_main) = 'in_review'`)}

  -- 2. Antes da liberação, a empresa não vê nada.
  ${as('a')}
  ${record('2a. Empresa A antes da liberação', 'não vê a manifestação', companySees('v_main'), `not ${companySees('v_main')}`)}
  ${expectError('2b. Erro: empresa responde antes da liberação', `perform public.respond_complaint(v_main, ${q(RESPONSE_2)})`, '')}
  ${expectError('2c. Erro: empresa tenta decidir como Operação', `perform public.ops_decide_complaint(v_main, 'released', null)`, 'acesso negado')}

  -- 3. Operação libera.
  ${as('ops')}
  ${expectError('3a. Erro: reter sem motivo', `perform public.ops_decide_complaint(v_main, 'held', 'curto')`, 'pelo menos 10 caracteres')}
  perform public.ops_decide_complaint(v_main, 'released', null);
  ${asSystem}
  ${record('3b. Operação libera a versão compartilhável', 'status shared', `(select status from public.complaints where id = v_main)`, `(select status from public.complaints where id = v_main) = 'shared'`)}

  -- 4. Empresa A vê só a versão autorizada; empresa B não vê nada.
  ${as('a')}
  ${record('4a. Empresa A vê a versão compartilhável', 'linha com a versão compartilhável', companySees('v_main', SHARED), companySees('v_main', SHARED))}
  ${record('4b. Empresa A não recebe o relato original (lista e histórico)', 'texto original ausente', `${companySees('v_main', ORIGINAL)} or ${companyTimelineHas(ORIGINAL)}`, `not (${companySees('v_main', ORIGINAL)} or ${companyTimelineHas(ORIGINAL)})`)}
  select count(*) into v_count from public.complaint_originals where complaint_id = v_main;
  ${record('4c. Empresa A lendo a tabela de originais direto', '0 linhas (RLS)', 'v_count', 'v_count = 0')}
  ${as('b')}
  ${record('4d. Empresa B não vê o caso da empresa A', 'ausente da lista', companySees('v_main'), `not ${companySees('v_main')}`)}
  ${expectError('4e. Erro: empresa B responde ao caso da empresa A', `perform public.respond_complaint(v_main, ${q(RESPONSE_2)})`, '')}
  begin
    select count(*) into v_count from public.get_company_complaint_timeline(v_main);
    ${record('4f. Empresa B lendo o histórico do caso da empresa A', '0 linhas ou erro', 'v_count', 'v_count = 0')}
  exception when others then
    ${record('4f. Empresa B lendo o histórico do caso da empresa A', '0 linhas ou erro', 'sqlerrm', 'true')}
  end;

  -- 5. Empresa responde; a resposta fica com a equipe.
  ${as('a')}
  perform public.respond_complaint(v_main, ${q(RESPONSE_1)});
  ${record('5a. Empresa A responde', 'status answer_in_review', `(select status from public.list_company_complaints() c where c.id = v_main)`, `(select status from public.list_company_complaints() c where c.id = v_main) = 'answer_in_review'`)}
  ${expectError('5b. Erro: segunda resposta com outra em revisão', `perform public.respond_complaint(v_main, ${q(RESPONSE_2)})`, '')}
  ${as('w')}
  select count(*) into v_count from public.company_responses where complaint_id = v_main;
  ${record('5c. Trabalhador antes da revisão da resposta', '0 respostas visíveis', 'v_count', 'v_count = 0')}

  -- 6. Operação revisa: devolve, a empresa reenvia, a Operação libera com descrição e corrige.
  ${asSystem}
  select id into v_resp1 from public.company_responses where complaint_id = v_main order by created_at desc limit 1;
  ${as('ops')}
  ${expectError('6a. Erro: devolver sem motivo suficiente', `perform public.ops_decide_response(v_resp1, 'returned', null, 'curto')`, '10 a 500 caracteres')}
  perform public.ops_decide_response(v_resp1, 'returned', null, 'A resposta cita uma pessoa pelo nome; retire o nome e reenvie.');
  ${as('a')}
  ${record('6b. Empresa A vê o motivo da devolução no histórico', 'item response_review com o motivo', companyTimelineHas('retire o nome'), companyTimelineHas('retire o nome'))}
  perform public.respond_complaint(v_main, ${q(RESPONSE_2)});
  ${asSystem}
  select id into v_resp2 from public.company_responses where complaint_id = v_main order by created_at desc limit 1;
  ${as('ops')}
  ${expectError('6c. Erro: liberar com descrição curta', `perform public.ops_decide_response(v_resp2, 'released', 'curta demais', null)`, '30 a 1.000 caracteres')}
  perform public.ops_decide_response(v_resp2, 'released', ${q(SUMMARY)}, null);
  ${expectError('6d. Erro: corrigir descrição sem motivo', `perform public.ops_correct_response_summary(v_resp2, ${q(SUMMARY + ' (corrigida)')}, 'curto')`, '10 a 500 caracteres')}
  perform public.ops_correct_response_summary(v_resp2, ${q(SUMMARY + ' (corrigida)')}, 'Ajuste de clareza na descrição.');

  -- 7. Trabalhador lê a resposta liberada e avalia.
  ${as('w')}
  select count(*) into v_count from public.company_responses where complaint_id = v_main;
  ${record('7a. Trabalhador vê só a resposta liberada', '1 resposta (a devolvida fica oculta)', 'v_count', 'v_count = 1')}
  select worker_summary into v_text from public.company_responses where id = v_resp2;
  ${record('7b. Trabalhador recebe a descrição corrigida da equipe', 'descrição com "(corrigida)"', 'v_text', `v_text like '%(corrigida)'`)}
  perform public.rate_response(v_resp2, 'partial', 'Comentário fictício só para a equipe.');
  ${expectError('7c. Erro: avaliar a mesma resposta duas vezes', `perform public.rate_response(v_resp2, 'yes', null)`, 'já avaliou')}
  ${expectError('7d. Erro: avaliar a resposta devolvida', `perform public.rate_response(v_resp1, 'yes', null)`, 'não disponível')}
  ${as('a')}
  ${record('7e. Empresa A nunca recebe a descrição da equipe', 'descrição ausente da lista e do histórico', `${companySees('v_main', 'Descrição da equipe')} or ${companyTimelineHas('Descrição da equipe')}`, `not (${companySees('v_main', 'Descrição da equipe')} or ${companyTimelineHas('Descrição da equipe')})`)}
  ${record('7f. Satisfação da empresa A com 1 avaliação', 'sem dado (menos de 3)', `(select coalesce(satisfaction_band, 'sem dado') from public.my_company_satisfaction() where company_id = v_company_a)`, `(select satisfaction_band is null from public.my_company_satisfaction() where company_id = v_company_a)`)}
  ${as('b')}
  ${expectError('7g. Erro: empresa B avalia resposta do trabalhador', `perform public.rate_response(v_resp2, 'no', null)`, '')}

  -- 8. Acesso excepcional ao original fica registrado.
  ${as('ops')}
  ${expectError('8a. Erro: ler original sem justificativa', `perform public.ops_read_original(v_main, 'curta')`, 'pelo menos 10 caracteres')}
  v_text := public.ops_read_original(v_main, 'Ensaio do acesso excepcional ao original.')::text;
  ${asSystem}
  ${record('8b. Leitura do original com justificativa fica na trilha', 'texto devolvido e 1 registro de acesso', `(v_text like ${q(`%${run}%`)})::text || ', ' || (select count(*) from public.original_access_log where complaint_id = v_main) || ' registro(s)'`, `v_text like ${q(`%${run}%`)} and (select count(*) from public.original_access_log where complaint_id = v_main) = 1`)}

  -- 9. Retirada antes da liberação e encerramento depois da liberação.
  ${as('w')}
  v_withdrawn := public.create_complaint(jsonb_build_object('company_id', v_company_a, 'category', 'Sobrecarga / excesso de trabalho', 'title', 'Ensaio retirada', 'original_content', ${q(ORIGINAL)}, 'shared_content', ${q(SHARED)}, 'incident_period', 'Últimas semanas', 'recurrence', 'Recorrente', 'expected_outcomes', jsonb_build_array('Receber uma resposta')), true)::uuid;
  perform public.close_complaint(v_withdrawn, null);
  ${record('9a. Trabalhador retira antes da liberação', 'status canceled', `(select status from public.complaints where id = v_withdrawn)`, `(select status from public.complaints where id = v_withdrawn) = 'canceled'`)}
  ${as('ops')}
  ${expectError('9b. Erro: Operação tenta liberar a retirada', `perform public.ops_decide_complaint(v_withdrawn, 'released', null)`, 'Só manifestações em revisão ou retidas')}
  ${as('a')}
  ${record('9c. Empresa A nunca vê a manifestação retirada', 'ausente da lista', companySees('v_withdrawn'), `not ${companySees('v_withdrawn')}`)}
  ${as('w')}
  perform public.close_complaint(v_main, 'partial');
  ${as('a')}
  ${record('9d. LACUNA: encerrar depois da liberação não revoga o acesso', 'empresa continua vendo (comportamento atual; não há revogação)', companySees('v_main', SHARED), companySees('v_main', SHARED))}

  ${asSystem}
  raise exception 'ensaio-desfeito';
  exception when others then
    perform set_config('role', 'none', true);
    if sqlerrm <> 'ensaio-desfeito' then
      res := res || jsonb_build_object('passo', 'FALHA INESPERADA (ensaio interrompido)', 'esperado', '-', 'obtido', sqlerrm, 'ok', false);
    end if;
  end;
  return query select e.i, e.v ->> 'passo', e.v ->> 'esperado', e.v ->> 'obtido', (e.v ->> 'ok')::boolean from jsonb_array_elements(res) with ordinality as e(v, i);
end
$fn$;

select * from pg_temp.ensaio_piloto();
`;
process.stdout.write(sql);
