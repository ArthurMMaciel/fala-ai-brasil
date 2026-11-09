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
