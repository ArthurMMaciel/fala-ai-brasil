import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
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

test('nenhum sink HTML novo sem passar pelo inventário da TASK-0002', () => {
  const files = ['src/app/main.js', 'src/app/auth-steps.ts'];
  const sinks = files.flatMap(file => [...readFileSync(file, 'utf8').matchAll(/innerHTML|insertAdjacentHTML|outerHTML|dangerouslySetInnerHTML|document\.write/g)].map(() => file));
  // main.js: renderer y() e ícone do botão de senha (SVG constante); auth-steps.ts: barra de etapas sem dados do usuário.
  assert.deepEqual(sinks, ['src/app/main.js', 'src/app/main.js', 'src/app/auth-steps.ts']);
});
