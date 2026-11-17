import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Bug 17tu7rpc7ru: sessão encerrada ou trocada em outra aba precisa refletir na tela aberta.
const output = ts.transpileModule(readFileSync('src/domain/session-sync.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const sync = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

test('sem conta na tela, nenhum aviso muda a tela', () => {
  for (const event of ['INITIAL_SESSION', 'SIGNED_IN', 'SIGNED_OUT', 'TOKEN_REFRESHED']) assert.equal(sync.sessionChange(event, 'u1', null), null);
  assert.equal(sync.sessionChange('SIGNED_OUT', null, null), null);
});

test('saída em outra aba ou token sem renovação encerra a tela', () => {
  assert.equal(sync.sessionChange('SIGNED_OUT', null, 'u1'), 'ended');
  assert.equal(sync.sessionChange('TOKEN_REFRESHED', null, 'u1'), 'ended');
});

test('mesma conta segue; outra conta recarrega', () => {
  for (const event of ['INITIAL_SESSION', 'SIGNED_IN', 'TOKEN_REFRESHED', 'USER_UPDATED']) assert.equal(sync.sessionChange(event, 'u1', 'u1'), null);
  assert.equal(sync.sessionChange('SIGNED_IN', 'u2', 'u1'), 'changed');
});

test('main.js liga o aviso e o logout não chama signOut duas vezes no reset', () => {
  const main = readFileSync('src/app/main.js', 'utf8');
  assert.match(main, /watchSession\(\(e,a\)=>\{const t=sessionChange\(e,a,o\.user\?\.id\?\?null\)/);
  assert.match(main, /function acctLogout\(\)\{acctResetUi\(\);signOut\(\)/);
  assert.doesNotMatch(main.match(/function acctResetUi\(\)\{[^\n]*/)[0], /signOut/);
});
