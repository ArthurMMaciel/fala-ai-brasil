import { readFileSync, writeFileSync } from 'node:fs';

// Executar com node --env-file=.env. Nunca imprimir a credencial ou payloads pessoais.
const token = process.env.CLICKUP_API_TOKEN;
if (!token) throw new Error('CLICKUP_API_TOKEN ausente.');
async function api(path, method = 'GET', body) {
  const response = await fetch(`https://api.clickup.com/api/v2/${path}`, {
    method, headers: { Authorization: token, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw new Error(`ClickUp HTTP ${response.status}`);
  return response.json();
}
const listId = '901329218347';
let tasks = [];
for (let page = 0; ; page++) {
  const result = await api(`list/${listId}/task?include_closed=true&subtasks=true&page=${page}`);
  tasks.push(...result.tasks);
  if (result.last_page) break;
}
const file = 'docs/tasks/TASK-0019-cadastro-planos-e-endereco.md';
let text = readFileSync(file, 'utf8');
let task = tasks.find(item => item.name.startsWith('TASK-0019'));
if (!task) {
  task = await api(`list/${listId}/task`, 'POST', {
    name: 'TASK-0019 — Cadastro comercial, assinatura e endereço estruturado',
    markdown_description: `Documento local: ${file}\n\n${text}`,
    priority: 2,
  });
}
text = text.replace(/^- ClickUp:.*$/m, `- ClickUp: [TASK-0019](https://app.clickup.com/t/${task.id})`);
writeFileSync(file, text, 'utf8');
await api(`task/${task.id}`, 'PUT', { markdown_description: `Documento local: ${file}\n\n${text}` });
console.log(`TASK-0019: https://app.clickup.com/t/${task.id}`);
const stripeFile = 'docs/tasks/TASK-0018-integracao-stripe-pagamentos.md';
const stripeText = readFileSync(stripeFile, 'utf8');
await api('task/86aktngf0', 'PUT', { markdown_description: `Documento local: ${stripeFile}\n\n${stripeText}` });
console.log('TASK-0018 atualizada.');
for (const section of stripeText.split(/(?=^### ST-\d+)/m).slice(1)) {
  const id = section.match(/https:\/\/app\.clickup\.com\/t\/([a-z0-9]+)/)?.[1];
  if (!id || !tasks.some(item => item.id === id)) throw new Error('Subtarefa não encontrada na lista consultada.');
  await api(`task/${id}`, 'PUT', { markdown_description: `Documento local: ${stripeFile}\nRegras atualizadas: trial de um mês, mensal imediato, anual com 5%; funcionário gratuito; cadastro e gestão na própria conta; Boleto em estudo para BRL; transferência bancária genérica BRL não confirmada; cobrança real pendente.\n\n${section}` });
}
console.log('Sete subtarefas Stripe sincronizadas.');
