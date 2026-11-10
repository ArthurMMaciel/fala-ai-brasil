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
