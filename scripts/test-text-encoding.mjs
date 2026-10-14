import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';

test('textos versionados usam UTF-8 sem caracteres corrompidos', () => {
  const files = execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' }).split('\0');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  // Common signatures of UTF-8 decoded as Windows-1252, plus replacement characters.
  const corrupted = /[\u00c2\u00c3][\u0080-\u00bf\u0152\u0153\u0160\u0161\u0178\u017d\u017e\u0192\u02c6\u02dc\u2013-\u2022\u2026\u2030\u2039\u203a\u20ac\u2122]|\u00e2[\u0080-\u009f\u20ac]|\u00f0\u0178|\ufffd/;
  for (const file of files.filter(f => /\.(?:md|html|css|tsx?|js|mjs|json|ya?ml)$/.test(f))) {
    const content = decoder.decode(readFileSync(file));
    assert.equal(corrupted.test(content), false, `Caracteres corrompidos em ${file}`);
  }
});

test('mensagem da empresa preserva os acentos e o travessão em PT-BR', () => {
  const content = readFileSync('src/main.js', 'utf8');
  assert.ok(content.includes('Transforme sinais sensíveis em resposta institucional — com dono, prazo e prova.'));
  assert.ok(content.includes('A Escuta Aí Empresas organiza uma versão protegida, atribui responsáveis, acompanha prazos e converte o histórico em indicadores próprios de responsividade.'));
});
