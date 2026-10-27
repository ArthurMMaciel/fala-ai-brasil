import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import ts from 'typescript';

function model() {
 const module = { exports: {} };
 vm.runInNewContext(ts.transpileModule(readFileSync('src/editorial/editorial-model.ts', 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText, { module, exports: module.exports, Date });
 return module.exports;
}
test('manifestação exige assunto, descrição e decisão explícita; recusa continua válida', () => {
 const api = model();
 const draft = { topic: '', description: '', sharing: '', step: 0 };
 assert.match(api.validateReport(draft), /assunto/);
 draft.topic = api.topics[0];
 assert.equal(api.validateReport(draft), '');
 assert.match(api.validateReport({ ...draft, step: 1 }), /Descreva/);
 draft.description = 'Contexto fictício para revisão.';
 assert.match(api.validateReport({ ...draft, step: 2 }), /compartilhar/);
 assert.equal(api.validateReport({ ...draft, sharing: 'no', step: 2 }), '');
 assert.throws(() => api.submitReport(draft));
});
test('envio não encaminha original à empresa e consulta exige protocolo e chave correspondentes', () => {
 const api = model();
 const before = JSON.stringify(api.session.cases);
 for (const sharing of ['yes', 'no']) {
  const record = api.submitReport({ topic: api.topics[0], description: '<script>exemplo fictício</script>', sharing, step: 3 });
  assert.equal(record.sharing, sharing === 'yes');
  assert.equal(api.lookupReport(record.protocol, 'incorreta'), undefined);
  assert.equal(api.lookupReport('incorreto', record.key), undefined);
  assert.equal(api.lookupReport(' ' + record.protocol.toLowerCase() + ' ', record.key), record);
 }
 assert.equal(JSON.stringify(api.session.cases), before);
 assert.equal(api.session.draft.description, '');
});
test('rascunho e fila de revisão não alteram retorno público nem expõem texto privado', () => {
 const api = model();
 const item = api.session.cases[0];
 const published = item.published;
 const status = item.status;
 item.draft = '';
 assert.throws(() => api.queueCompanyUpdate(item), /Escreva/);
 item.draft = 'Ação prevista, ainda não realizada.';
 api.queueCompanyUpdate(item);
 assert.equal(item.queued, true);
 assert.equal(item.published, published);
 assert.equal(item.status, status);
 assert.equal('description' in item, false);
 assert.equal('key' in item, false);
});

test('pendências da empresa excluem espera por informação e saem da fila ao enviar para revisão', () => {
 const api = model();
 const filters = { status: '', topic: '', pending: 'action' };
 const protocols = () => Array.from(api.filterCompanyCases(api.session.cases, filters), item => item.protocol);
 assert.deepEqual(protocols(), ['EAB-2026-0042', 'EAB-2026-0047']);
 const item = api.session.cases[0];
 api.queueCompanyUpdate(item);
 assert.deepEqual(protocols(), ['EAB-2026-0047']);
 assert.equal(api.companyCaseStatus(item), 'Resposta em revisão');
 assert.equal(item.status, 'Retorno disponível');
 assert.equal(api.filterCompanyCases(api.session.cases, { ...filters, pending: 'review', status: 'Resposta em revisão' }).length, 2);
 assert.deepEqual(Array.from(api.filterCompanyCases(api.session.cases, { ...filters, pending: 'waiting' }), item => item.protocol), ['EAB-2026-0031']);
 assert.equal(api.filterCompanyCases(api.session.cases, { ...filters, topic: api.topics[1] }).length, 0);
});
