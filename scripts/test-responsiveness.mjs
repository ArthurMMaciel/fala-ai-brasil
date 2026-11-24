import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// TASK-0036: responsividade em faixas, ordem por nome, sem posição, contagem nem percentual na lista pública.
const require = createRequire(import.meta.url);
function compile(file, customRequire = require) {
  const module = { exports: {} };
  const code = ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2021 } }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: customRequire });
  return module.exports;
}
const domain = compile('src/domain/responsiveness.ts');
const ui = compile('src/portals/responsiveness.tsx', name => name === '../domain/responsiveness' ? domain : require(name));
const render = (component, props) => renderToStaticMarkup(React.createElement(component, props));
const row = (name, extra = {}) => ({ companyId: name, name, city: 'Curitiba', state: 'PR', responseBand: 'high', responseTimeBand: 'fast', satisfactionBand: null, isMine: false, ...extra });

test('rótulos das faixas e fallback "Sem dado"', () => {
  assert.equal(domain.bandLabel(domain.responseBandLabels, 'high'), 'Alta (80% ou mais)');
  assert.equal(domain.bandLabel(domain.responseBandLabels, 'medium'), 'Média (50% a 79%)');
  assert.equal(domain.bandLabel(domain.responseTimeBandLabels, 'none'), 'Sem resposta');
  assert.equal(domain.bandLabel(domain.satisfactionBandLabels, null), 'Sem dado');
  assert.equal(domain.bandLabel(domain.responseBandLabels, 'toString'), 'Sem dado');
  assert.equal(domain.bandTone('low'), 'retida');
  assert.equal(domain.bandTone(undefined), 'em-aberto');
  assert.equal(domain.formatHours(20), '20 h');
  assert.equal(domain.formatHours(72), '3,0 dias');
});

test('lista pública: ordem recebida (nome), sem posição, contagem ou percentual', () => {
  const html = render(ui.ResponsivenessTable, { rows: [row('Aurora'), row('Lumina', { responseBand: 'low', responseTimeBand: 'none' }), row('Nova', { isMine: true })], highlightMine: true });
  assert.doesNotMatch(html, /Posição|º<|Manifestações/);
  assert.doesNotMatch(html, /<td>\d+%?<\/td>/, 'nenhuma célula só com número ou percentual');
  assert.ok(html.indexOf('Aurora') < html.indexOf('Lumina') && html.indexOf('Lumina') < html.indexOf('Nova'), 'mantém a ordem por nome do banco');
  assert.match(html, /Baixa \(menos de 50%\)/);
  assert.match(html, /Sem resposta/);
  assert.match(html, /class="ranking-mine"[\s\S]*sua empresa/);
  assert.doesNotMatch(html, /Satisfação/, 'coluna de satisfação some enquanto não há dado');
  assert.match(render(ui.ResponsivenessTable, { rows: [row('A', { satisfactionBand: 'medium' }), row('B')] }), /Satisfação[\s\S]*Média[\s\S]*Sem dado/);
  assert.doesNotMatch(render(ui.ResponsivenessTable, { rows: [row('A', { isMine: true })] }), /sua empresa/, 'trabalhador não vê destaque');
});

test('números exatos só no painel da própria empresa', () => {
  const listed = render(ui.MyResponsivenessPanel, { mine: { companyId: 'c', name: 'Aurora', released: 5, answered: 4, responseRate: 80, avgFirstResponseHours: 30, responseBand: 'high', responseTimeBand: 'fast', listed: true } });
  assert.match(listed, /Manifestações liberadas<\/dt><dd>5/);
  assert.match(listed, /80%/);
  assert.match(listed, /30 h/);
  assert.match(listed, /aparece na lista pública/);
  const notListed = render(ui.MyResponsivenessPanel, { mine: { companyId: 'c', name: 'Aurora', released: 2, answered: 0, responseRate: 0, avgFirstResponseHours: null, responseBand: 'low', responseTimeBand: 'none', listed: false } });
  assert.match(notListed, /a partir de 3 manifestações liberadas/);
  assert.equal(render(ui.MyResponsivenessPanel, { mine: undefined }), '');
});

test('nenhum código chama company_ranking nem mostra coluna de posição', () => {
  const files = ['src/services/data.ts', 'src/portals/portal-live.tsx', 'src/portals/worker-portal-live.tsx', 'src/portals/responsiveness.tsx'];
  for (const file of files) {
    const source = readFileSync(file, 'utf8');
    assert.doesNotMatch(source, /rpc\("company_ranking"\)|<th>Posição<\/th>/, file);
  }
  assert.match(readFileSync('src/services/data.ts', 'utf8'), /rpc\("company_responsiveness"\)/);
});

// Design P1.1 (2026-11-23): uma voz tipográfica. Títulos em Outfit, corpo em Inter; a Lora saiu do sistema.
test('tipografia: nenhuma regra usa Lora; Outfit declarada e usada nos títulos', () => {
  for (const file of ['src/styles/styles.css', 'src/styles/editorial.css', 'src/styles/system.css']) {
    const css = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    assert.doesNotMatch(css, /Lora/, file);
  }
  const editorial = readFileSync('src/styles/editorial.css', 'utf8');
  assert.match(editorial, /@font-face \{ font-family: Outfit; src: url\('\/fonts\/outfit\.ttf'\)/);
  assert.match(editorial, /\.legacy-editorial h2, \.legacy-editorial h3 \{ font-family: Outfit, Arial, sans-serif; font-weight: 600;/);
  assert.match(readFileSync('src/styles/system.css', 'utf8'), /\.commercial-page-head h1 \{ font-family: Outfit, Arial, sans-serif; font-weight: 600;/);
});
// Design P1.2 (2026-11-23): abas de seção sublinhadas; filtros de situação como controle segmentado.
test('abas: seção com sublinhado e filtro de situação segmentado', () => {
  const css = readFileSync('src/styles/system.css', 'utf8');
  assert.match(css, /\.ops-section-tabs \.account-tab\[aria-selected="true"\] \{ color: var\(--deep\); border-bottom-color: var\(--deep\); \}/);
  assert.match(css, /\.ops-response-tabs \{ display: inline-flex; flex-wrap: wrap;[^}]*border-radius: 12px; background: #eef1f6; \}/);
  assert.match(css, /\.ops-response-tabs \.account-tab\[aria-selected="true"\] \{ background: #fff;/);
});
// Design P1.3 (2026-11-23): tabelas com CNPJ mascarado, cabeçalho AA, linha clicável com seta e números à direita.
test('tabelas: CNPJ com máscara, cabeçalho legível, seta nas linhas clicáveis e números à direita', () => {
  const reps = readFileSync('src/portals/representatives.tsx', 'utf8');
  assert.doesNotMatch(reps, /CNPJ \{(item|row)\.cnpj\}/);
  assert.match(reps, /<small>CNPJ \{maskCnpj\(row\.cnpj\)\}<\/small>/);
  assert.match(readFileSync('src/portals/ops-portal-live.tsx', 'utf8'), /<td className="num">\{row\.users\}<\/td><td className="num">\{row\.complaints\}<\/td>/);
  const css = readFileSync('src/styles/system.css', 'utf8');
  assert.match(css, /\.legacy-editorial \.contact-admin-table th \{ color: #3f4759; \}/);
  assert.match(css, /tbody tr\[tabindex="0"\] > td:last-child::after \{ content: "";/);
  assert.match(css, /tbody tr\[tabindex="0"\]:focus-visible \{ outline: 3px solid var\(--deep\);/);
  assert.match(css, /:is\(th, td\)\.num \{ text-align: right; font-variant-numeric: tabular-nums; \}/);
});
// Design P1.4 (2026-11-23): estado vazio padrão nas listas da Operação.
test('estado vazio: componente com ícone, frase e dica; listas da Operação sem "Nada por aqui"', () => {
  const ui = readFileSync('src/portals/ui.tsx', 'utf8');
  assert.match(ui, /export function EmptyState\(\{ text, hint, icon = 'inbox', action \}/);
  for (const file of ['ops-portal-live.tsx', 'representatives.tsx', 'response-review.tsx', 'company-notices.tsx']) {
    const source = readFileSync(`src/portals/${file}`, 'utf8');
    assert.match(source, /<EmptyState /, file);
    assert.doesNotMatch(source, /Nada por aqui/, file);
  }
  assert.match(readFileSync('src/styles/system.css', 'utf8'), /\.legacy-editorial \.empty-state \{ display: flex;/);
});
// Design P1.5 (2026-11-23): assistente com um indicador de progresso, faixa de emergência e marcador na opção.
test('assistente: progresso só na barra, emergência em faixa e marcador na opção escolhida', () => {
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, /<p className="wizard-progress-label">Etapa \{step \+ 1\} de \{total\} · \{stepTitle\}<\/p>/);
  assert.equal((wizard.match(/Etapa \{step \+ 1\} de \{total\}/g) ?? []).length, 1, 'um indicador de etapa só');
  assert.match(wizard, /<p className="wizard-emergency" role="note">Em caso de risco imediato, procure ajuda: CVV 188, SAMU 192 ou Polícia Militar 190\./);
  const css = readFileSync('src/styles/system.css', 'utf8');
  assert.match(css, /\.legacy-editorial \.option\.selected::before \{ content: "";/);
  assert.match(css, /\.legacy-editorial \.wizard-emergency \{[^}]*border-left: 3px solid/);
});
// Design P2.6 (2026-11-23): botões com papéis claros e alturas 44/40.
test('botões: primário azul profundo, secundário com contorno, 44 px e 40 px nas tabelas', () => {
  const css = readFileSync('src/styles/system.css', 'utf8');
  assert.match(css, /\.legacy-editorial \.btn\.primary \{ border-color: var\(--deep\); background: var\(--deep\); color: #fff; \}/);
  assert.match(css, /\.legacy-editorial \.btn:not\(\.primary\):not\(\.ghost\):not\(\.danger\) \{ border: 1px solid rgba\(31, 58, 122, \.35\); background: #fff;/);
  assert.match(css, /\.legacy-editorial \.btn \{ min-height: 44px; \}/);
  assert.match(css, /:is\(\.commercial-table, \.worker-table, \.contact-admin-table\) \.btn \{ min-height: 40px;/);
});
// Design P2.7 (2026-11-23): selos de status curtos e cor por significado.
test('selos: rótulos curtos e uma cor por significado; cancelada não fica verde', () => {
  const ops = readFileSync('src/portals/ops-portal-live.tsx', 'utf8');
  assert.match(ops, /received: 'Guardada', in_review: 'Em revisão', adjustment_requested: 'Ajuste solicitado', held: 'Retida', shared: 'Liberada',/);
  assert.match(ops, /closed: 'finalizada', canceled: 'em-aberto' \};/);
  assert.match(readFileSync('src/portals/worker-portal-live.tsx', 'utf8'), /answer_in_review: 'Resposta em análise',/);
  assert.match(readFileSync('src/portals/portal-live.tsx', 'utf8'), /answer_in_review: 'Resposta em revisão',/);
  const css = readFileSync('src/styles/system.css', 'utf8');
  assert.match(css, /\.legacy-editorial \.worker-status \{ white-space: nowrap; \}/);
  assert.match(css, /\.legacy-editorial \.worker-status\.retida \{ background: #fde8e8; color: #9f1f1f; \}/);
});
// Design P2.8 (2026-11-23): atalhos em grade regular e contador legível.
test('atalhos: colunas pela quantidade (6 → 3×2, 4 → 4, 8 → 4×2) e contador ao lado do ícone', async () => {
  const source = readFileSync('src/portals/ui.tsx', 'utf8');
  const fn = source.match(/export function quickColumns[\s\S]*?\n\}/)[0].replace('export function quickColumns(count: number): { wide: number; narrow: number }', 'function quickColumns(count)');
  const quickColumns = new Function(`${fn}; return quickColumns;`)();
  assert.deepEqual(quickColumns(6), { wide: 3, narrow: 3 });
  assert.deepEqual(quickColumns(4), { wide: 4, narrow: 2 });
  assert.deepEqual(quickColumns(3), { wide: 3, narrow: 3 });
  assert.deepEqual(quickColumns(8), { wide: 4, narrow: 2 });
  assert.match(source, /<em className="sys-quick-count" aria-label=\{`\$\{item\.badge\} pendentes`\}>/);
  assert.match(readFileSync('src/styles/system.css', 'utf8'), /\.sys-quick \{ grid-template-columns: repeat\(var\(--quick-cols, 3\), minmax\(0, 1fr\)\); \}/);
});
// Design P2.9 (2026-11-23): foco visível em cartões e menus.
test('foco visível: cartões e itens clicáveis com contorno; menus laterais em amarelo', () => {
  const css = readFileSync('src/styles/system.css', 'utf8');
  assert.match(css, /\.legacy-editorial :is\(\.sys-quick-card, \.commercial-list-row, \.partner-card, \.worker-row-action, \.worker-company-row button\):focus-visible \{ outline: 3px solid var\(--deep\); outline-offset: 3px; \}/);
  assert.match(css, /\.legacy-editorial :is\(\.sys-nav button, \.sidebar \.side-link\):focus-visible \{ outline: 3px solid #f2aa1d;/);
});
// Design P3.12 (2026-11-24): um ícone próprio por item de menu, sem repetição, do conjunto da Operação.
test('menus: cada item com ícone próprio (Contratados e Manifestações do trabalhador deixam o ícone genérico)', () => {
  const portal = readFileSync('src/portals/portal-live.tsx', 'utf8');
  const icons = Object.fromEntries([...portal.match(/const sidebarIcons: Record<string, IconName> = \{([^}]*)\}/)[1].matchAll(/(\w+): '(\w+)'/g)].map(m => [m[1], m[2]]));
  const menus = {
    company: ['dashboard', 'complaints', 'ranking', 'partners', 'contracted'],
    partner: ['dashboard', 'content', 'companies', 'leads', 'clients'],
  };
  for (const [name, keys] of Object.entries(menus)) {
    const used = keys.map(key => icons[key]);
    assert.ok(used.every(Boolean), `${name}: todo item tem ícone mapeado`);
    assert.equal(new Set(used).size, used.length, `${name}: sem ícone repetido`);
    assert.ok(!used.includes('list'), `${name}: sem o ícone genérico`);
  }
  assert.match(readFileSync('src/portals/ui.tsx', 'utf8'), /contract: 'M14 3H6/);
  assert.match(readFileSync('src/styles/system.css', 'utf8'), /\.side-link\[data-worker-view="manifestations"\]::before \{ -webkit-mask-image: var\(--sys-i-inbox\);/);
  assert.match(readFileSync('src/portals/worker-portal-live.tsx', 'utf8'), /icon: 'inbox', label: 'Minhas manifestações'/);
});
// Correção do P2.8 (2026-11-24): em até 480 px, atalhos sempre em 2 colunas (3 colunas estouravam o rótulo).
test('atalhos no celular: até 480 px, duas colunas', () => {
  assert.match(readFileSync('src/styles/system.css', 'utf8'), /@media \(max-width: 480px\) \{ \.sys-quick \{ grid-template-columns: repeat\(2, minmax\(0, 1fr\)\); \} \}/);
});