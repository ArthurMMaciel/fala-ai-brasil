import { readFileSync, writeFileSync } from 'node:fs';

// Gera SQL idempotente com contas e dados fictícios para a demonstração (TASK-0022).
// Uso: node scripts/seed-demo-data.mjs > <arquivo-temporario>.sql e depois
//      npx supabase db query --linked < <arquivo-temporario>.sql
// A senha vem de supabase/test-users.local.md (fora do Git) e nunca é impressa no terminal.
const local = 'supabase/test-users.local.md';
const password = readFileSync(local, 'utf8').match(/Senha de todas as contas: `([^`]+)`/)?.[1];
if (!password) throw new Error('Senha das contas de teste não encontrada em ' + local);

function cpf(base) {
  const d = String(base).padStart(9, '0').split('').map(Number);
  for (const len of [9, 10]) { const sum = d.slice(0, len).reduce((t, n, i) => t + n * (len + 1 - i), 0); const r = (sum * 10) % 11; d.push(r === 10 ? 0 : r); }
  return d.join('');
}
function cnpj(base) {
  const d = (String(base).padStart(8, '0') + '0001').split('').map(Number);
  for (const w of [[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]]) { const r = w.reduce((t, n, i) => t + n * d[i], 0) % 11; d.push(r < 2 ? 0 : 11 - r); }
  return d.join('');
}
const q = value => value === null || value === undefined ? 'null' : `'${String(value).replace(/'/g, "''")}'`;
const addr = (zip, type, name, number, neighborhood, city, state) => ({ zip_code: zip, street_type: type, street_name: name, number, neighborhood, city, state });

const companies = [
  ['aurora', 'Aurora Tecnologia Ltda.', 'Aurora Tecnologia', 31245678, addr('87013000', 'avenue', 'Brasil', '1200', 'Centro', 'Maringá', 'PR'), 'company-management'],
  ['nova', 'Nova Essencial Serviços S.A.', 'Nova Essencial', 22118441, addr('80020000', 'street', 'Marechal Deodoro', '450', 'Centro', 'Curitiba', 'PR'), 'company-essential'],
  ['lumina', 'Lumina Alimentos Ltda.', 'Lumina Alimentos', 31909103, addr('13015000', 'avenue', 'Francisco Glicério', '980', 'Centro', 'Campinas', 'SP'), 'company-essential'],
  ['viaserena', 'Via Serena Logística S.A.', 'Via Serena', 44100200, addr('32010000', 'avenue', 'João César de Oliveira', '2100', 'Eldorado', 'Contagem', 'MG'), 'company-management'],
  ['arconorte', 'Arco Norte Varejo Ltda.', 'Arco Norte', 19334789, addr('50030000', 'street', 'da Aurora', '300', 'Boa Vista', 'Recife', 'PE'), 'company-essential'],
  ['portoclaro', 'Porto Claro Energia S.A.', 'Porto Claro', 58221006, addr('24020000', 'street', 'da Conceição', '75', 'Centro', 'Niterói', 'RJ'), 'company-essential'],
];
const workers = [
  ['ana.souza', 'Ana Souza', 123456701, addr('01310100', 'avenue', 'Paulista', '900', 'Bela Vista', 'São Paulo', 'SP')],
  ['bruno.lima', 'Bruno Lima', 223456702, addr('80010000', 'street', 'XV de Novembro', '210', 'Centro', 'Curitiba', 'PR')],
  ['carla.mendes', 'Carla Mendes', 323456703, addr('13010000', 'street', 'Barão de Jaguara', '55', 'Centro', 'Campinas', 'SP')],
  ['diego.alves', 'Diego Alves', 423456704, addr('30130000', 'avenue', 'Amazonas', '1500', 'Centro', 'Belo Horizonte', 'MG')],
  ['elisa.rocha', 'Elisa Rocha', 523456705, addr('50010000', 'street', 'do Bom Jesus', '120', 'Recife', 'Recife', 'PE')],
];
const partners = [
  ['marina.costa', 'Marina Costa', 'Psicologia organizacional', 'Apoio a lideranças e equipes em saúde mental no trabalho, com foco em prevenção e escuta.', addr('01311000', 'avenue', 'Paulista', '1578', 'Bela Vista', 'São Paulo', 'SP'), 'partner-professional'],
  ['rafael.nunes', 'Rafael Nunes', 'Direito trabalhista', 'Orientação preventiva sobre jornada, assédio e políticas internas.', addr('80020010', 'street', 'Cândido Lopes', '102', 'Centro', 'Curitiba', 'PR'), 'partner-presence'],
  ['camila.torres', 'Camila Torres', 'Recursos humanos', 'Desenho de rituais de feedback, carga de trabalho e onboarding.', addr('30140000', 'street', 'da Bahia', '880', 'Lourdes', 'Belo Horizonte', 'MG'), 'partner-national'],
  ['juliana.prado', 'Juliana Prado', 'Mediação de conflitos', 'Mediação entre equipes e lideranças, com protocolos de confidencialidade.', addr('88010000', 'street', 'Felipe Schmidt', '330', 'Centro', 'Florianópolis', 'SC'), 'partner-presence'],
];
const sponsors = [
  ['mirante', 'Fundação Mirante', 'sponsor-study', ['study', 'Estudo aberto: rotina e descanso no trabalho', 'Pesquisa pública com resultados agregados sobre pausas e jornada.']],
  ['lumen', 'Lumen Saúde Ocupacional', 'sponsor-content', ['content', 'Guia prático de ergonomia no home office', 'Conteúdo educativo gratuito com orientações de postura e pausas.']],
  ['vilaserena', 'Instituto Vila Serena', 'sponsor-event', ['event', 'Semana do cuidado no trabalho', 'Encontros online abertos sobre bem-estar e convivência.']],
  ['pontal', 'Rede Pontal', 'sponsor-content', ['content', 'Série: como pedir ajuda no trabalho', 'Episódios curtos sobre canais de apoio e escuta.']],
  ['aurorabeneficios', 'Aurora Benefícios', 'sponsor-event', ['event', 'Roda de conversa sobre benefícios e saúde', 'Evento aberto sobre benefícios corporativos e cuidado.']],
];

const users = [];
for (const [slug, legal, trade, base, address, plan] of companies) users.push([`rh.${slug}@example.com`, trade, 'company', { legal_name: legal, trade_name: trade, cnpj: cnpj(base), plan_id: plan, subscription_mode: 'trial', address }]);
for (const [slug, name, base, address] of workers) users.push([`${slug}@example.com`, name, 'worker', { full_name: name, cpf: cpf(base), address }]);
partners.forEach(([slug, name, specialty, description, address, plan], i) => users.push([`${slug}@example.com`, name, 'partner', { display_name: name, document_type: 'cpf', document: cpf(612345670 + i), specialty, description, plan_id: plan, subscription_mode: 'trial', address }]));
sponsors.forEach(([slug, name, plan], i) => users.push([`${slug}@example.com`, name, 'sponsor', { name, cnpj: cnpj(70100200 + i * 7), plan_id: plan, subscription_mode: 'trial', address: addr('01310200', 'avenue', 'Paulista', String(2000 + i), 'Bela Vista', 'São Paulo', 'SP') }]));

let sql = `do $$\ndeclare uid uuid;\nbegin\n`;
for (const [email, name, type, signup] of users) {
  sql += `if not exists (select 1 from auth.users where email = ${q(email)}) then
  uid := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current, reauthentication_token, phone_change, phone_change_token)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', ${q(email)}, extensions.crypt(${q(password)}, extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', ${q(JSON.stringify({ full_name: name, signup_type: type, signup }))}::jsonb, now(), now(), '', '', '', '', '', '', '', '');
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', ${q(email)}, 'email_verified', true), 'email', now(), now(), now());
end if;\n`;
}
sql += `end $$;\n\n`;

// Manifestações fictícias: [trabalhador, empresa, categoria, título, original, compartilhável, status, dias atrás, resposta, avaliação]
const W = email => `(select w.id from public.workers w join auth.users u on u.id = w.user_id where u.email = ${q(email)})`;
const C = email => `(select cu.company_id from public.company_users cu join auth.users u on u.id = cu.user_id where u.email = ${q(email)} and cu.role = 'owner' limit 1)`;
const complaints = [
  ['trabalhador.teste', 'empresa.teste', 'Organização e carga de trabalho', 'Prioridades mudam toda semana', 'Desde a troca de coordenação, as prioridades mudam toda semana e recebo pedidos por mensagem depois das 22h.', 'O relato descreve mudanças frequentes de prioridade e pedidos fora do horário combinado. Solicita-se clareza sobre prioridades e canais.', 'answered', 18, 'Agradecemos o relato. Vamos revisar os combinados de prioridade e reforçar que demandas fora do horário não são esperadas.', null],
  ['trabalhador.teste', 'empresa.teste', 'Respeito e tratamento no trabalho', 'Cobranças em público', 'Em reuniões semanais, erros são apontados na frente de todos, com tom de deboche.', 'O relato aponta cobranças feitas em público, com exposição de quem errou. Pede-se revisão da forma de dar feedback.', 'shared', 6, null, null],
  ['trabalhador.teste', 'aurora', 'Condições para trabalhar', 'Equipamento sem manutenção', 'O notebook da equipe de suporte trava várias vezes ao dia e o chamado está aberto há dois meses.', 'O relato descreve equipamentos sem manutenção há meses, prejudicando o trabalho diário.', 'closed', 40, 'Os equipamentos foram substituídos e criamos um prazo máximo de 10 dias para chamados de hardware.', 'yes'],
  ['trabalhador.teste', 'nova', 'Relações e convivência', 'Clima tenso após reestruturação', 'Depois da reestruturação, colegas pararam de conversar e há boatos sobre demissões.', 'O relato menciona clima de tensão e insegurança após uma reestruturação, com pouca comunicação oficial.', 'received', 2, null, null],
  ['ana.souza', 'aurora', 'Organização e carga de trabalho', 'Metas aumentadas sem conversa', 'As metas do time subiram 40% sem explicação e quem questiona é visto como pouco comprometido.', 'O relato descreve aumento de metas sem diálogo e receio de questionar.', 'answered', 25, 'Vamos apresentar a base de cálculo das metas e abrir uma conversa com o time na próxima semana.', null],
  ['bruno.lima', 'aurora', 'Respeito e tratamento no trabalho', 'Comentários sobre aparência', 'Um colega faz comentários sobre aparência em reuniões e ninguém interrompe.', 'O relato aponta comentários inadequados sobre aparência em reuniões, sem intervenção.', 'answered', 31, 'O caso foi encaminhado ao comitê de conduta e haverá treinamento obrigatório sobre respeito.', null],
  ['carla.mendes', 'aurora', 'Condições para trabalhar', 'Calor excessivo no galpão', 'No galpão faz mais de 35 graus à tarde e não há pausa para água.', 'O relato descreve calor excessivo no ambiente de trabalho e ausência de pausas para hidratação.', 'shared', 9, null, null],
  ['diego.alves', 'aurora', 'Organização e carga de trabalho', 'Plantões sem escala', 'Os plantões de fim de semana são definidos na sexta à noite, sem escala prévia.', 'O relato aponta definição de plantões em cima da hora, sem escala previsível.', 'closed', 55, 'Publicamos escala mensal de plantões com antecedência de 15 dias.', 'partial'],
  ['elisa.rocha', 'nova', 'Organização e carga de trabalho', 'Acúmulo de funções', 'Assumi as tarefas de duas pessoas que saíram e não houve reposição.', 'O relato descreve acúmulo de funções após saídas da equipe, sem reposição.', 'answered', 20, 'Abrimos duas vagas e redistribuímos temporariamente as demandas.', null],
  ['ana.souza', 'nova', 'Respeito e tratamento no trabalho', 'Gritos em chamadas', 'A gestora grita em chamadas quando os números não batem.', 'O relato aponta tom agressivo em chamadas de acompanhamento de resultados.', 'shared', 4, null, null],
  ['bruno.lima', 'nova', 'Condições para trabalhar', 'Ferramenta de ponto instável', 'O sistema de ponto falha e as horas extras não são registradas.', 'O relato descreve falhas no registro de ponto que afetam o registro de horas extras.', 'answered', 14, 'O fornecedor do sistema foi acionado e as horas serão conferidas manualmente até a correção.', null],
  ['carla.mendes', 'lumina', 'Relações e convivência', 'Exclusão em decisões do turno', 'O turno da noite nunca é consultado sobre mudanças de processo.', 'O relato menciona que um turno não é consultado sobre mudanças de processo.', 'shared', 11, null, null],
  ['diego.alves', 'lumina', 'Organização e carga de trabalho', 'Horas extras frequentes', 'Fazemos horas extras quase todo dia no fechamento do mês.', 'O relato descreve horas extras recorrentes no fechamento mensal.', 'answered', 28, 'Vamos reforçar a equipe no fechamento e revisar o cronograma de entregas.', null],
  ['elisa.rocha', 'lumina', 'Condições para trabalhar', 'Falta de EPI', 'Faltam luvas e máscaras na linha de produção há duas semanas.', 'O relato aponta falta de equipamentos de proteção na produção.', 'closed', 35, 'O estoque de EPI foi regularizado e criamos alerta de reposição.', 'yes'],
  ['ana.souza', 'viaserena', 'Organização e carga de trabalho', 'Rotas longas demais', 'As rotas de entrega passam de 12 horas com frequência.', 'O relato descreve jornadas de entrega acima do previsto com frequência.', 'shared', 7, null, null],
  ['bruno.lima', 'viaserena', 'Respeito e tratamento no trabalho', 'Ameaças de desligamento', 'Supervisores dizem que quem reclamar da rota será desligado.', 'O relato aponta falas de supervisão associando reclamações a desligamento.', 'answered', 16, 'O tema foi levado à diretoria e reforçamos que manifestações não geram retaliação.', null],
  ['carla.mendes', 'viaserena', 'Condições para trabalhar', 'Veículos sem revisão', 'Dois caminhões estão sem revisão e com freio ruim.', 'O relato descreve veículos sem manutenção preventiva.', 'answered', 22, 'Os veículos foram retirados de circulação até a revisão.', null],
  ['diego.alves', 'arconorte', 'Relações e convivência', 'Disputa entre equipes', 'Loja e estoque vivem em conflito e a gerência não media.', 'O relato menciona conflitos recorrentes entre equipes sem mediação.', 'shared', 5, null, null],
  ['elisa.rocha', 'portoclaro', 'Organização e carga de trabalho', 'Sobreaviso sem pagamento', 'Ficamos de sobreaviso no celular sem registro.', 'O relato descreve períodos de sobreaviso sem registro formal.', 'shared', 3, null, null],
];
const companyRef = slug => slug === 'empresa.teste' ? C('empresa.teste@example.com') : C(`rh.${slug}@example.com`);
const workerRef = slug => W(`${slug}@example.com`);
sql += `do $$\ndeclare cid uuid;\nbegin\nif exists (select 1 from public.complaints) then return; end if;\n`;
for (const [worker, company, category, title, original, shared, status, days, response, feedback] of complaints) {
  const created = `now() - interval '${days} days'`;
  sql += `insert into public.complaints (worker_id, company_id, category, title, status, worker_feedback, created_at, updated_at, closed_at, expected_outcomes)
  values (${workerRef(worker)}, ${companyRef(company)}, ${q(category)}, ${q(title)}, '${status}', ${feedback ? `'${feedback}'` : 'null'}, ${created}, ${created}, ${status === 'closed' ? `now() - interval '${Math.max(1, days - 10)} days'` : 'null'}, '{"Receber uma resposta"}') returning id into cid;
insert into public.complaint_originals values (cid, ${q(original)});
insert into public.complaint_events (complaint_id, status, actor, note, created_at) values (cid, 'received', 'worker', 'Manifestação registrada.', ${created});\n`;
  if (status !== 'received') sql += `insert into public.complaint_shared_versions values (cid, ${q(shared)}, ${created} + interval '10 minutes');
insert into public.complaint_events (complaint_id, status, actor, note, created_at) values (cid, 'shared', 'worker', 'Versão compartilhável confirmada e enviada à empresa.', ${created} + interval '10 minutes');\n`;
  if (response) sql += `insert into public.company_responses (complaint_id, company_id, content, created_at) values (cid, ${companyRef(company)}, ${q(response)}, ${created} + interval '${1 + (days % 3)} days');
insert into public.complaint_events (complaint_id, status, actor, note, created_at) values (cid, 'answered', 'company', 'Empresa enviou uma resposta institucional.', ${created} + interval '${1 + (days % 3)} days');\n`;
  if (status === 'closed') sql += `insert into public.complaint_events (complaint_id, status, actor, note, created_at) values (cid, 'closed', 'worker', 'Trabalhador encerrou o acompanhamento.', now() - interval '${Math.max(1, days - 10)} days');\n`;
}
sql += `end $$;\n\n`;

// Conexões do Hub e campanhas aprovadas dos patrocinadores.
const P = email => `(select p.id from public.partners p join auth.users u on u.id = p.user_id where u.email = ${q(email)})`;
const S = email => `(select s.id from public.sponsors s join auth.users u on u.id = s.user_id where u.email = ${q(email)})`;
const connections = [
  ['parceiro.teste', 'aurora', 'company_interest'], ['parceiro.teste', 'nova', 'client'], ['parceiro.teste', 'lumina', 'client'], ['parceiro.teste', 'viaserena', 'partner_contacted'], ['parceiro.teste', 'empresa.teste', 'company_interest'],
  ['marina.costa', 'aurora', 'client'], ['marina.costa', 'empresa.teste', 'company_interest'], ['rafael.nunes', 'viaserena', 'company_interest'], ['camila.torres', 'nova', 'partner_contacted'],
];
sql += `insert into public.partner_connections (partner_id, company_id, stage) values\n${connections.map(([p, c, stage]) => `(${P(`${p}@example.com`)}, ${companyRef(c)}, '${stage}')`).join(',\n')}\non conflict do nothing;\n\n`;
sql += `do $$\nbegin\nif exists (select 1 from public.campaigns) then return; end if;\n`;
for (const [slug, , , [kind, title, description]] of sponsors) {
  sql += `insert into public.campaigns (sponsor_id, subscription_id, kind, title, description, starts_at, ends_at, status, submitted_at, reviewed_at)
  select s.id, sub.id, '${kind}', ${q(title)}, ${q(description)}, current_date - 5, current_date + 45, 'approved', now() - interval '6 days', now() - interval '5 days'
  from public.sponsors s join public.subscriptions sub on sub.sponsor_id = s.id where s.id = ${S(`${slug}@example.com`)};\n`;
}
sql += `insert into public.campaigns (sponsor_id, subscription_id, kind, title, description, starts_at, ends_at, status, submitted_at, reviewed_at)
  select s.id, sub.id, 'content', 'Cartilha sobre pausas no trabalho', 'Material educativo publicado no mês passado.', current_date - 60, current_date - 20, 'approved', now() - interval '62 days', now() - interval '61 days'
  from public.sponsors s join public.subscriptions sub on sub.sponsor_id = s.id where s.id = ${S('patrocinador.teste@example.com')};\n`;
sql += `end $$;\n`;

// Contato fictício das empresas (domínio example.com) e Parceira Teste no plano Nacional (Destaques e Meus conteúdos).
companies.forEach(([slug], i) => { sql += `update public.companies set contact_email = ${q(`contato.${slug}@example.com`)}, contact_phone = ${q(`1199990000${i}`)} where id = ${companyRef(slug)} and contact_email is null;
`; });
sql += `update public.companies set contact_email = 'contato.empresateste@example.com', contact_phone = '41999990000' where id = ${companyRef('empresa.teste')} and contact_email is null;
`;
sql += `update public.subscriptions set plan_id = 'partner-national' where partner_id = ${P('parceiro.teste@example.com')};
`;

process.stdout.write(sql);

// Atualiza a lista de contas no arquivo local (sem senha no terminal).
const rows = users.map(([email, name, type]) => `| ${{ company: 'Empresa', worker: 'Trabalhador', partner: 'Parceiro', sponsor: 'Patrocinador' }[type]} | ${email} | ${name} |`).join('\n');
const text = readFileSync(local, 'utf8').replace(/\n## Contas adicionais[\s\S]*$/, '');
writeFileSync(local, `${text.trimEnd()}\n\n## Contas adicionais (seed de demonstração, mesma senha)\n\n| Tipo | E-mail | Nome |\n|---|---|---|\n${rows}\n`);
