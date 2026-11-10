import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// PDF da manifestação, fase 1 (TASK-0043).
const require = createRequire(import.meta.url);
function compile(file, customRequire = require) {
  const module = { exports: {} };
  const code = ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2021 } }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: customRequire });
  return module.exports;
}
const domain = compile('src/domain/print-document.ts');
const view = compile('src/portals/print-document.tsx');
const ORIGINAL = 'Texto original sigiloso do trabalhador';
const worker = { protocol: 'EAB-2026-1007', title: 'Cobranças fora do horário', statusText: 'Aguardando empresa', createdAt: '08 de nov. de 2026', generatedAt: '10/11/2026 12:00', companyName: 'Aurora', category: 'Sobrecarga', incidentPeriod: 'Últimas semanas', recurrence: 'Recorrente', expectedOutcomes: ['Receber uma resposta'], shared: 'Versão compartilhável revisada.', sharedReleased: true, timeline: [{ title: 'Registrada', date: '08 de nov.', text: 'Manifestação registrada.' }], feedbackText: null, original: ORIGINAL, includeOriginal: false };
const text = doc => JSON.stringify(doc);

test('trabalhador: original fica fora por padrão e entra só quando marcado', () => {
  const without = domain.buildWorkerPrint(worker);
  assert.ok(!text(without).includes(ORIGINAL));
  assert.ok(!text(without).includes('Seu relato original'));
  assert.ok(text(without).includes('Versão que a empresa recebeu'));
  assert.ok(text(without).includes('Documento pessoal com informações do seu relato. Guarde com cuidado.'));
  assert.ok(text(without).includes('CVV 188'));
  const withOriginal = domain.buildWorkerPrint({ ...worker, includeOriginal: true });
  assert.equal(withOriginal.sections[0].heading, 'Seu relato original');
  assert.equal(withOriginal.sections[0].text, ORIGINAL);
  assert.equal(domain.buildWorkerPrint({ ...worker, sharedReleased: false }).sections[0].heading, 'Versão em revisão pela equipe');
});

test('empresa: só a versão compartilhável, com rodapé de não identificação', () => {
  const doc = domain.buildCompanyPrint({ protocol: 'EAB-2026-1007', title: 'Cobranças', statusText: 'Respondida', receivedAt: '08 de nov.', generatedAt: '10/11/2026 12:00', companyName: 'Aurora', category: 'Sobrecarga', shared: 'Versão compartilhável revisada.', timeline: [], feedbackText: 'A resposta ajudou' });
  assert.deepEqual(JSON.parse(JSON.stringify(doc.sections.map(section => section.heading))), ['Versão compartilhada', 'Histórico', 'Avaliação do retorno']);
  assert.match(doc.footer[0], /Não contém a identidade de quem relatou\. Não tente identificar a pessoa\. Gerado por Aurora em 10\/11\/2026 12:00\./);
  assert.ok(!text(doc).includes('original'));
});

test('empresa nunca recebe o original: a chamada no portal não passa original', () => {
  const source = readFileSync('src/portals/portal-live.tsx', 'utf8');
  const call = source.slice(source.indexOf('buildCompanyPrint({'), source.indexOf('}))', source.indexOf('buildCompanyPrint({')));
  assert.ok(call.length > 20);
  assert.doesNotMatch(call, /original/i);
});

test('nome do arquivo e versão impressa em texto real', () => {
  const doc = domain.buildWorkerPrint({ ...worker, protocol: 'EAB/2026 1007' });
  assert.equal(doc.fileName, 'manifestacao-EAB20261007');
  const html = renderToStaticMarkup(React.createElement(view.PrintDocumentView, { doc: domain.buildWorkerPrint(worker) }));
  assert.match(html, /<h1>Cobranças fora do horário<\/h1>/);
  assert.match(html, /Protocolo<\/dt><dd>EAB-2026-1007/);
  assert.doesNotMatch(html, /<input|<canvas/);
});
