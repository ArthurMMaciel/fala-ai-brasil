import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Termos de uso e aviso de privacidade vindos de arquivo de conteúdo (TASK-0033).
const output = ts.transpileModule(readFileSync('src/domain/legal-docs.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const legal = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const plain = value => JSON.parse(JSON.stringify(value));

test('arquivos publicados estão marcados em revisão jurídica e sem texto jurídico inventado', () => {
  for (const [file, title] of [['termos-de-uso.md', 'Termos de uso'], ['aviso-de-privacidade.md', 'Aviso de privacidade']]) {
    const doc = legal.parseLegalDoc(readFileSync(`src/content/legal/${file}`, 'utf8'));
    assert.equal(doc.title, title);
    assert.equal(doc.inReview, true);
    assert.equal(doc.version, 'rascunho-2026-11');
    assert.deepEqual(plain(doc.blocks.map(block => block.kind)), ['note']);
  }
});

test('leitor de conteúdo: seções, listas, destaque e status aprovado', () => {
  const doc = legal.parseLegalDoc('<!-- versao: v1 -->\n<!-- status: aprovado -->\n# Título\n\n## Seção\nLinha um\nlinha dois\n\n- item a\n- item b\n> destaque\n### Sub\n<script>alert(1)</script>');
  assert.equal(doc.inReview, false);
  assert.deepEqual(plain(doc.blocks), [
    { kind: 'heading', level: 2, text: 'Seção' },
    { kind: 'paragraph', text: 'Linha um linha dois' },
    { kind: 'list', items: ['item a', 'item b'] },
    { kind: 'note', text: 'destaque' },
    { kind: 'heading', level: 3, text: 'Sub' },
    { kind: 'paragraph', text: '<script>alert(1)</script>' },
  ]);
  assert.equal(legal.parseLegalDoc('# Sem metadados').inReview, true);
});

test('endereços públicos por hash', () => {
  assert.equal(legal.legalRouteFromHash('#termos'), 'terms');
  assert.equal(legal.legalRouteFromHash('#/privacidade'), 'privacy');
  assert.equal(legal.legalRouteFromHash('#access_token=x&type=signup'), null);
  assert.equal(legal.legalRouteFromHash(''), null);
});

test('cadastro liga as caixas obrigatórias às páginas e a página não usa HTML cru', () => {
  const main = readFileSync('src/app/main.js', 'utf8');
  assert.match(main, /<input name="terms" type="checkbox" required \/> <span>Aceito os <a href="\/#termos"/);
  assert.match(main, /<input name="privacy" type="checkbox" required \/> <span>Li o <a href="\/#privacidade"/);
  assert.doesNotMatch(readFileSync('src/editorial/legal-page.tsx', 'utf8'), /dangerouslySetInnerHTML/);
});
