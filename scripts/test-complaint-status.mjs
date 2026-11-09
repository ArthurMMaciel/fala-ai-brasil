import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import ts from 'typescript';

// Rótulos de situação × enum public.complaint_status (regressão do selo vazio de 2026-11: o banco ganhou
// in_review/adjustment_requested/held antes do front). Lê as migrations na ordem dos arquivos.
const output = ts.transpileModule(readFileSync('src/domain/complaint-status.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const domain = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

function enumFromMigrations() {
  const values = [];
  for (const file of readdirSync('supabase/migrations').filter(name => name.endsWith('.sql')).sort()) {
    const sql = readFileSync(`supabase/migrations/${file}`, 'utf8');
    const created = sql.match(/create type public\.complaint_status as enum \(([^)]*)\)/i);
    if (created) values.splice(0, values.length, ...[...created[1].matchAll(/'([^']+)'/g)].map(m => m[1]));
    for (const [, value, position, anchor] of sql.matchAll(/alter type public\.complaint_status add value if not exists '([^']+)'(?:\s+(before|after)\s+'([^']+)')?/gi)) {
      if (values.includes(value)) continue;
      const at = anchor ? values.indexOf(anchor) + (position?.toLowerCase() === 'after' ? 1 : 0) : values.length;
      values.splice(at, 0, value);
    }
  }
  return values;
}
const statusEnum = enumFromMigrations();
const portals = ['src/portals/worker-portal-live.tsx', 'src/portals/portal-live.tsx', 'src/portals/ops-portal-live.tsx'];
const mapNames = /^(statusLabels|eventLabels|statusClass|statusTone|companyStatus)$/;

test('lista do domínio e tipo ComplaintStatusDb seguem o enum das migrations, na mesma ordem', () => {
  assert.ok(statusEnum.length >= 8, `enum lido das migrations: ${statusEnum.join(', ')}`);
  assert.deepEqual([...domain.complaintStatusOrder], statusEnum);
  const union = readFileSync('src/services/data.ts', 'utf8').match(/export type ComplaintStatusDb = ([^;]+);/)[1];
  assert.deepEqual([...union.matchAll(/"([^"]+)"/g)].map(m => m[1]).sort(), [...statusEnum].sort());
});

test('todo mapa de rótulo dos três portais tem todas as situações do banco', () => {
  let maps = 0;
  for (const file of portals) {
    const source = readFileSync(file, 'utf8');
    for (const [, name, body] of source.matchAll(/const (\w+): Record<ComplaintStatusDb, string> = \{([^}]*)\};/g)) {
      if (!mapNames.test(name)) continue;
      maps++;
      const keys = [...body.matchAll(/(\w+):\s*'/g)].map(m => m[1]);
      for (const status of statusEnum) assert.ok(keys.includes(status), `${file} → ${name} sem rótulo para "${status}"`);
      for (const value of [...body.matchAll(/\w+:\s*'([^']*)'/g)].map(m => m[1])) assert.ok(value.trim(), `${file} → ${name} com rótulo vazio`);
    }
  }
  assert.equal(maps, 7, 'mapas conferidos: trabalhador 3, empresa 1, Operação 3');
});

test('portais usam o rótulo com fallback, nunca o mapa indexado direto pelo status', () => {
  for (const file of portals) {
    const direct = readFileSync(file, 'utf8').match(/\b(statusLabels|eventLabels|statusClass|statusTone|companyStatus)\[(?!key\])[^\]]+\]/g);
    assert.equal(direct, null, `${file}: ${direct}`);
  }
});

test('situação desconhecida ou ausente mostra o fallback, não um selo vazio', () => {
  const labels = { received: 'Guardada' };
  assert.equal(domain.statusLabel(labels, 'received'), 'Guardada');
  assert.equal(domain.statusLabel(labels, 'em_auditoria'), 'Situação em atualização');
  assert.equal(domain.statusLabel(labels, null), 'Situação em atualização');
  assert.equal(domain.statusLabel(labels, 'toString'), 'Situação em atualização', 'não herda do Object.prototype');
  assert.equal(domain.statusLabel({ received: 'em-aberto' }, 'novo', 'em-aberto'), 'em-aberto');
});

test('Operação não repete "Resposta da empresa" na linha do tempo', () => {
  const ops = readFileSync('src/portals/ops-portal-live.tsx', 'utf8');
  assert.match(ops.match(/const eventLabels: Record<ComplaintStatusDb, string> = \{([^}]*)\}/)[1], /answered: 'Respondida'/);
});
