import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

// Auditoria de textos pedida pelo parecer jurídico (2026-11-09): sem promessa de anonimato absoluto nem de
// atendimento a risco imediato. Se alguma frase voltar ao src/, o teste falha.
const forbidden = ['recebem atenção humana', 'sem revelar quem você é', 'sem saber quem você é', 'Identidade protegida', 'anonimizada'];

function sourceFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = `${dir}/${entry.name}`;
    return entry.isDirectory() ? sourceFiles(path) : /\.(ts|tsx|js|jsx|html|css)$/.test(entry.name) ? [path] : [];
  });
}

test('nenhuma frase proibida pelo parecer volta ao src/', () => {
  const found = [];
  for (const file of [...sourceFiles('src'), 'index.html']) {
    readFileSync(file, 'utf8').split(/\r?\n/).forEach((line, index) => {
      for (const phrase of forbidden) if (line.toLowerCase().includes(phrase.toLowerCase())) found.push(`${file}:${index + 1} "${phrase}"`);
    });
  }
  assert.deepEqual(found, []);
});

test('assistente de manifestação mostra os canais de emergência e diz que não é canal de emergência', () => {
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.ok(wizard.includes('Em caso de risco imediato, procure ajuda: CVV 188, SAMU 192 ou Polícia Militar 190. A Escuta Aí Brasil não é um canal de emergência.'), 'frase fixa (B4)');
  assert.ok(wizard.includes('procure agora ajuda: CVV 188 (apoio emocional, 24 horas), SAMU 192 ou Polícia Militar 190. A Escuta Aí Brasil não é canal de emergência e não acompanha casos em tempo real.'), 'aviso da pergunta de risco (B1)');
  const fixed = wizard.match(/Etapa \{step \+ 1\} de 9[\s\S]{0,200}?Em caso de risco imediato/);
  assert.ok(fixed, 'a frase fixa fica no cabeçalho, visível em todas as etapas');
});
