import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import ts from 'typescript';

const output = ts.transpileModule(readFileSync('src/domain/html-safety.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const { escapeHtml, safeHttpUrl } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

test('escapeHtml neutraliza tags, aspas e crase sem perder Unicode', () => {
  assert.equal(escapeHtml('<img src=x onerror=alert(1)>'), '&lt;img src=x onerror=alert(1)&gt;');
  assert.equal(escapeHtml('<script>alert("x")</script>'), '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;');
  assert.equal(escapeHtml(`"' \`&`), '&quot;&#39; &#96;&amp;');
  assert.equal(escapeHtml('Ação · São Paulo — ✓ 😀'), 'Ação · São Paulo — ✓ 😀');
  assert.equal(escapeHtml(null), '');
  assert.equal(escapeHtml(undefined), '');
  assert.equal(escapeHtml(42), '42');
  assert.equal(escapeHtml('&lt;'), '&amp;lt;', 'não decodifica entidades já existentes');
});

test('safeHttpUrl aceita só http/https absolutos', () => {
  assert.equal(safeHttpUrl('https://example.com/a?b=1'), 'https://example.com/a?b=1');
  assert.equal(safeHttpUrl('http://example.com'), 'http://example.com/');
  assert.equal(safeHttpUrl('  https://www.youtube.com/watch?v=x  '), 'https://www.youtube.com/watch?v=x');
  for (const value of [
    'javascript:alert(1)', 'JaVaScRiPt:alert(1)', ' javascript:alert(1)', 'java\tscript:alert(1)', 'java\nscript:alert(1)',
    'data:text/html,<script>alert(1)</script>', 'vbscript:msgbox(1)', '//evil.example.com', '/relativo', 'https://exa mple.com',
    'file:///etc/passwd', 'mailto:a@b.com', 'https://', '', null, undefined, 42, {},
  ]) assert.equal(safeHttpUrl(value), null, `rejeita ${JSON.stringify(value)}`);
});

// Inventário da TASK-0002: qualquer sink HTML novo em src/ precisa ser revisado e entrar nesta lista.
const allowedSinks = {
  'src/app/main.js': 2, // renderer y() e ícone SVG constante do botão de senha
  'src/app/auth-steps.ts': 1, // barra de etapas, sem dado do usuário
};
const sinkPattern = /\binnerHTML\b|\bouterHTML\b|insertAdjacentHTML|dangerouslySetInnerHTML|document\.write(ln)?\s*\(|\bsrcdoc\b|createContextualFragment|parseFromString/g;

function sourceFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory()) return sourceFiles(path);
    return /\.(ts|tsx|js|jsx|mjs)$/.test(entry.name) ? [path] : [];
  });
}

export function countSinks(files, read = file => readFileSync(file, 'utf8')) {
  const found = {};
  for (const file of files) {
    const count = (read(file).match(sinkPattern) || []).length;
    if (count) found[file] = count;
  }
  return found;
}

test('nenhum sink HTML novo em src/ fora do inventário da TASK-0002', () => {
  const files = sourceFiles('src');
  assert.ok(files.length > 20, 'varre a árvore src/ inteira');
  assert.deepEqual(countSinks(files), allowedSinks);
});

test('a trava detecta sink novo em arquivo qualquer', () => {
  const fake = { 'src/x.tsx': '<div dangerouslySetInnerHTML={{ __html: a }} />', 'src/y.ts': 'el.insertAdjacentHTML("beforeend", b); el.outerHTML = c;', 'src/z.ts': 'el.textContent = d; // innerText' };
  assert.deepEqual(countSinks(Object.keys(fake), file => fake[file]), { 'src/x.tsx': 1, 'src/y.ts': 2 });
});
