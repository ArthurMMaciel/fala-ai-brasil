import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// TASK-0035 (ADR-0013): resposta da empresa revisada pela equipe antes de chegar ao trabalhador.
const require = createRequire(import.meta.url);
function compile(file, customRequire = require) {
  const module = { exports: {} };
  const code = ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2021 } }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: customRequire, Intl, Date, Number });
  return module.exports;
}
const domain = compile('src/domain/response-review.ts');
const stubs = { '../domain/response-review': domain, '../app/toast': { showToast() {} }, '../services/data': {}, '../services/ops': {} };
const ui = compile('src/portals/response-review.tsx', name => stubs[name] ?? require(name));
const render = (component, props) => renderToStaticMarkup(React.createElement(component, props));
const repeat = n => 'a'.repeat(n);

test('validações com as mesmas faixas do banco', () => {
  assert.equal(domain.validateWorkerSummary(repeat(29)), 'Escreva a descrição para o trabalhador com 30 a 1.000 caracteres.');
  assert.equal(domain.validateWorkerSummary(`  ${repeat(30)}  `), null);
  assert.equal(domain.validateWorkerSummary(repeat(1001)), 'Escreva a descrição para o trabalhador com 30 a 1.000 caracteres.');
  assert.equal(domain.validateReturnReason(repeat(9)), 'Explique à empresa o motivo da devolução com 10 a 500 caracteres.');
  assert.equal(domain.validateReturnReason(repeat(500)), null);
  assert.equal(domain.validateCorrectionReason(repeat(501)), 'Informe o motivo da correção com 10 a 500 caracteres.');
  assert.equal(domain.validateRatingComment(''), null);
  assert.equal(domain.validateRatingComment(repeat(301)), 'O comentário pode ter até 300 caracteres.');
});

test('data de correção e atraso da revisão', () => {
  assert.equal(domain.correctedLabel(null), null);
  assert.equal(domain.correctedLabel('data inválida'), null);
  assert.match(domain.correctedLabel('2026-11-09T15:00:00Z'), /^Descrição corrigida em \d{2}\/11$/);
  assert.equal(domain.reviewOverdue(48), false);
  assert.equal(domain.reviewOverdue(48.5), true);
  assert.equal(domain.reviewOverdue(null), false);
});

const response = (extra = {}) => ({ id: 'r1', kind: 'response', status: null, actor: 'company', content: 'Texto original da empresa.', createdAt: '2026-11-09T12:00:00Z', ...extra });

test('trabalhador vê a descrição da equipe em destaque e o texto original abaixo', () => {
  const html = render(ui.WorkerResponses, { responses: [response({ workerSummary: 'A empresa informou que vai revisar a escala do setor.', releasedAt: '2026-11-10T12:00:00Z', summaryCorrectedAt: '2026-11-10T15:00:00Z' })], ratings: [], onRated() {} });
  assert.ok(html.indexOf('Descrição da equipe Escuta Aí Brasil') < html.indexOf('Resposta original da empresa'));
  assert.match(html, /Descrição corrigida em/);
  assert.match(html, /Esta resposta ajudou\?/);
  assert.match(html, /A empresa não vê o comentário/);
});

test('resposta anterior à revisão aparece sem descrição; avaliada mostra a nota e não o formulário', () => {
  const html = render(ui.WorkerResponses, { responses: [response()], ratings: [{ responseId: 'r1', rating: 'partial', createdAt: '2026-11-10T12:00:00Z' }], onRated() {} });
  assert.doesNotMatch(html, /Descrição da equipe/);
  assert.match(html, /Resposta da empresa/);
  assert.match(html, /Sua avaliação: <strong>Em parte<\/strong>/);
  assert.doesNotMatch(html, /<form/);
  assert.equal(render(ui.WorkerResponses, { responses: [], ratings: [], onRated() {} }), '');
});

test('empresa nunca recebe a descrição da equipe; Operação rotula a revisão', () => {
  const company = readFileSync('src/portals/portal-live.tsx', 'utf8');
  assert.doesNotMatch(company, /workerSummary|worker_summary/);
  assert.match(company, /'response_review' \? 'Revisão da equipe'/);
  assert.match(readFileSync('src/portals/ops-portal-live.tsx', 'utf8'), /'response_review' \? 'Revisão da resposta'/);
});
