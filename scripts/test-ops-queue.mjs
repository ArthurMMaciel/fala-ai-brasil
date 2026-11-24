import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Fila de revisão da Operação (TASK-0044, item 8).
const output = ts.transpileModule(readFileSync('src/domain/ops-queue.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const queue = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const now = new Date('2026-11-10T12:00:00Z');

test('tempo de espera em texto curto', () => {
  assert.equal(queue.waitingLabel('2026-11-10T11:30:00Z', now), 'há menos de 1 h');
  assert.equal(queue.waitingLabel('2026-11-10T07:00:00Z', now), 'há 5 h');
  assert.equal(queue.waitingLabel('2026-11-08T13:00:00Z', now), 'há 47 h');
  assert.equal(queue.waitingLabel('2026-11-08T12:00:00Z', now), 'há 2 dias');
  assert.equal(queue.waitingLabel('data inválida', now), 'há menos de 1 h');
});

test('fila em ordem dos mais antigos, sem alterar a lista original', () => {
  const rows = [{ id: 'b', updatedAt: '2026-11-10T10:00:00Z' }, { id: 'a', updatedAt: '2026-11-08T10:00:00Z' }, { id: 'c', updatedAt: '2026-11-09T10:00:00+00:00' }];
  assert.deepEqual(JSON.parse(JSON.stringify(queue.oldestFirst(rows).map(row => row.id))), ['a', 'c', 'b']);
  assert.equal(rows[0].id, 'b');
});

test('motivo da decisão: até 469 caracteres, mínimo de 10 fora da liberação', () => {
  assert.equal(queue.opsReasonMax, 469);
  assert.equal(queue.validateOpsReason('released', ''), null);
  assert.equal(queue.validateOpsReason('held', 'curto'), 'Explique o motivo com pelo menos 10 caracteres.');
  assert.equal(queue.validateOpsReason('adjustment_requested', 'a'.repeat(469)), null);
  assert.equal(queue.validateOpsReason('adjustment_requested', 'a'.repeat(470)), 'O motivo pode ter até 469 caracteres (agora tem 470).');
  assert.equal('Ajuste solicitado pela equipe: '.length + queue.opsReasonMax, 500);
  assert.ok(readFileSync('src/portals/ops-portal-live.tsx', 'utf8').includes('<textarea rows={3} maxLength={opsReasonMax}'));
});

// Próximo passo depois de liberar (pedido do responsável, 2026-11-23).
test('próximo passo da liberação: empresa verificada, sem verificado, sem conta e sem dados', () => {
  const verified = new Set(['c1']), pending = new Set(['c2']);
  assert.equal(queue.releaseDelivery('c1', verified, pending), 'verified');
  assert.equal(queue.releaseDelivery('c2', verified, pending), 'unregistered');
  assert.equal(queue.releaseDelivery('c3', verified, pending), 'unverified');
  assert.equal(queue.releaseDelivery('c2', null, pending), 'unregistered');
  assert.equal(queue.releaseDelivery('c3', null, null), 'unknown');
  assert.equal(queue.releaseNextStep('verified').text, 'Chegou à empresa; a resposta volta em Manifestações → Respostas da empresa.');
  assert.equal(queue.releaseNextStep('verified', true).text, 'Vai chegar à empresa; a resposta volta em Manifestações → Respostas da empresa.');
  assert.deepEqual(queue.releaseNextStep('verified').links.map(link => link.view), ['responses']);
  assert.equal(queue.releaseNextStep('unverified').text, 'A empresa ainda não tem representante verificado: veja Empresas → Representantes.');
  assert.deepEqual(queue.releaseNextStep('unverified').links.map(link => link.view), ['representatives']);
  assert.equal(queue.releaseNextStep('unregistered').text, 'Empresa sem conta: confira em Empresas → A conferir e decida o aviso em Empresas → Avisos.');
  assert.deepEqual(queue.releaseNextStep('unregistered').links.map(link => link.view), ['pending-companies', 'notices']);
  assert.deepEqual(queue.releaseNextStep('unknown').links.map(link => link.view), ['companies']);
  const portal = readFileSync('src/portals/ops-portal-live.tsx', 'utf8');
  assert.match(portal, /showToast\('success', decision === 'released' \? `Manifestação liberada\. \$\{releaseNextStep\(delivery\)\.text\}`/);
  assert.match(portal, /listOpsRepresentatives\('verified'\)/);
});