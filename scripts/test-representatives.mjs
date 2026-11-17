import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Representante verificado (ADR-0012): fila da Operação e portal da empresa sem casos nem números até a verificação.
const output = ts.transpileModule(readFileSync('src/domain/representatives.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const rep = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const plain = value => JSON.parse(JSON.stringify(value));

test('transições iguais às do banco', () => {
  assert.deepEqual(plain(rep.allowedDecisions('pending')), ['verified', 'rejected']);
  assert.deepEqual(plain(rep.allowedDecisions('rejected')), ['verified', 'rejected']);
  assert.deepEqual(plain(rep.allowedDecisions('verified')), ['revoked']);
  assert.deepEqual(plain(rep.allowedDecisions('revoked')), ['verified']);
});

test('verificar exige método e referência sem número de documento; recusar e revogar exigem motivo', () => {
  assert.equal(rep.validateVerification('verified', '', 'ligação ao RH', ''), 'Informe o método: ligação ou documento conferido.');
  assert.equal(rep.validateVerification('verified', 'callback', 'ab', ''), 'Informe a referência da conferência (3 a 200 caracteres, sem número de documento).');
  assert.equal(rep.validateVerification('verified', 'callback', 'a'.repeat(201), ''), 'Informe a referência da conferência (3 a 200 caracteres, sem número de documento).');
  assert.match(rep.validateVerification('verified', 'document_review', 'contrato social CNPJ 12.345.678/0001-95', ''), /Tire o número de documento/);
  assert.match(rep.validateVerification('verified', 'document_review', 'CPF 123.456.789-09', ''), /Tire o número de documento/);
  assert.equal(rep.validateVerification('verified', 'callback', 'ligação em 18/11 ao telefone do site', ''), null);
  assert.equal(rep.validateVerification('rejected', '', '', 'curto'), 'Informe o motivo (10 a 500 caracteres).');
  assert.equal(rep.validateVerification('revoked', '', '', 'a'.repeat(501)), 'Informe o motivo (10 a 500 caracteres).');
  assert.equal(rep.validateVerification('revoked', '', '', 'A pessoa deixou a empresa.'), null);
});

test('portal da empresa: só esconde quando o banco informa um estado diferente de verificado', () => {
  assert.equal(rep.companyAccessPending(null), false);
  assert.equal(rep.companyAccessPending(undefined), false);
  assert.equal(rep.companyAccessPending('verified'), false);
  for (const status of ['pending', 'rejected', 'revoked']) assert.equal(rep.companyAccessPending(status), true);
  const portal = readFileSync('src/portals/portal-live.tsx', 'utf8');
  assert.match(portal, /companyAccessPending\(verification\) && view !== 'partners' && view !== 'profile' \? <VerificationPending/);
});

test('telas toleram a ausência da migration 20261117120000', () => {
  const ops = readFileSync('src/services/ops.ts', 'utf8');
  assert.match(ops, /PGRST202/);
  assert.match(readFileSync('src/portals/representatives.tsx', 'utf8'), /ainda não está ativa no banco/);
  assert.match(readFileSync('src/services/data.ts', 'utf8'), /if \(error \|\| !data\) return null;/);
});
