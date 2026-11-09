import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import ts from 'typescript';

// O React zera event.currentTarget quando o handler termina de rodar de forma síncrona. Lido depois de um
// await, ele vale null (bug de "Meus conteúdos": reset() falhava, a lista não atualizava e a pessoa publicava
// de novo). Regra: em função assíncrona, nenhum acesso a .currentTarget depois do primeiro await.
function sourceFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = `${dir}/${entry.name}`;
    return entry.isDirectory() ? sourceFiles(path) : /\.(ts|tsx|js|jsx)$/.test(entry.name) ? [path] : [];
  });
}

export function currentTargetAfterAwait(file, text) {
  const kind = file.endsWith('.tsx') ? ts.ScriptKind.TSX : file.endsWith('.js') || file.endsWith('.jsx') ? ts.ScriptKind.JSX : ts.ScriptKind.TS;
  const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, kind);
  const problems = [];
  const isFunction = node => ts.isFunctionDeclaration(node) || ts.isFunctionExpression(node) || ts.isArrowFunction(node) || ts.isMethodDeclaration(node);
  const isAsync = node => Boolean(ts.getCombinedModifierFlags(node) & ts.ModifierFlags.Async);
  function scan(fn) {
    let firstAwait = Infinity;
    const walk = node => {
      if (node !== fn && isFunction(node)) { if (isAsync(node)) scan(node); else ts.forEachChild(node, inner => visitNested(inner)); return; }
      if (ts.isAwaitExpression(node)) firstAwait = Math.min(firstAwait, node.getEnd());
      if (ts.isPropertyAccessExpression(node) && node.name.text === 'currentTarget' && node.getStart() > firstAwait) {
        const { line } = source.getLineAndCharacterOfPosition(node.getStart());
        problems.push(`${file}:${line + 1}`);
      }
      ts.forEachChild(node, walk);
    };
    ts.forEachChild(fn, walk);
  }
  const visitNested = node => { if (isFunction(node) && isAsync(node)) scan(node); else ts.forEachChild(node, visitNested); };
  visitNested(source);
  return problems;
}

test('nenhum handler assíncrono lê event.currentTarget depois de await', () => {
  const problems = sourceFiles('src').flatMap(file => currentTargetAfterAwait(file, readFileSync(file, 'utf8')));
  assert.deepEqual(problems, []);
});

test('o detector pega o padrão do bug e aceita guardar o elemento antes do await', () => {
  const bug = 'async function publish(event) { event.preventDefault(); await save(); event.currentTarget.reset(); }';
  const fixed = 'async function publish(event) { const formElement = event.currentTarget; await save(); formElement.reset(); }';
  const arrow = 'const f = async e => { await x(); if (e.currentTarget) y(); };';
  const sync = 'function onClick(e) { e.currentTarget.blur(); }';
  assert.deepEqual(currentTargetAfterAwait('x.tsx', bug), ['x.tsx:1']);
  assert.deepEqual(currentTargetAfterAwait('x.tsx', fixed), []);
  assert.deepEqual(currentTargetAfterAwait('x.ts', arrow), ['x.ts:1']);
  assert.deepEqual(currentTargetAfterAwait('x.js', sync), []);
});
