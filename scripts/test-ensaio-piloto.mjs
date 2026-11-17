import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

// Gerador do ensaio ponta a ponta (TASK-0033): o SQL roda em produção só com liberação; aqui se confere o que ele promete.
const generate = () => execFileSync(process.execPath, ['scripts/ensaio-piloto.mjs'], { encoding: 'utf8' });

test('ensaio é uma única instrução DO que termina sempre em exceção e não cria objetos', () => {
  const sql = generate();
  assert.equal((sql.match(/^do \$ensaio\$$/gm) ?? []).length, 1);
  assert.match(sql, /\$ensaio\$;\s*$/);
  assert.match(sql, /raise exception 'ensaio-desfeito'/);
  assert.match(sql, /raise exception 'RESULTADOS aprovado=/);
  assert.doesNotMatch(sql, /\bcommit\b/i);
  assert.doesNotMatch(sql, /\bcreate\s+(or\s+replace\s+)?(function|table|temp)/i);
});

test('sem senha, chave nem dado real: e-mails @example.com e nomes marcados TESTE', () => {
  const sql = generate();
  assert.doesNotMatch(sql, /crypt\(|service_role|eyJ[A-Za-z0-9_-]{10,}/);
  const emails = [...sql.matchAll(/'([^'\s]+@[^'\s]+)'/g)].map(match => match[1]);
  assert.equal(emails.length, 4);
  assert.ok(emails.every(email => email.endsWith('@example.com')));
  assert.match(sql, /TESTE Empresa Ensaio A/);
  assert.match(sql, /TESTE Empresa Ensaio B/);
});

test('cada execução usa contas novas e cobre fluxo, erros, isolamento e retirada', () => {
  const first = generate();
  assert.notEqual(first.match(/ensaio-w-([a-z0-9]+)@/)[1], generate().match(/ensaio-w-([a-z0-9]+)@/)[1]);
  for (const step of ['1b.', '3b.', '4a.', '4b.', '4c.', '4d.', '4e.', '5a.', '5c.', '6b.', '7a.', '7b.', '7c.', '7e.', '8b.', '9a.', '9c.', '9d. LACUNA CONHECIDA (decisão do responsável em 17/11)']) assert.ok(first.includes(`'${step}`), step);
});
