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

// Nome do produto (decisão do responsável em 2026-11-27): "RH Escuta.Aí", vindo de src/domain/brand.ts. O nome antigo só
// fica nos textos em revisão jurídica (aviso à empresa e consentimentos).
test('nome antigo do produto não volta às telas', () => {
  // empresa.tsx: arquivo da sessão comercial; o nome muda junto com os preços, quando o Gestor liberar o arquivo.
  const allowed = ['src/domain/company-notice.ts', 'src/landing-site/pages/empresa.tsx'];
  const found = [];
  for (const file of [...sourceFiles('src'), 'index.html']) {
    if (allowed.includes(file)) continue;
    readFileSync(file, 'utf8').split(/\r?\n/).forEach((line, index) => {
      if (/escuta a[íi] brasil|escuta\.a[íi]/i.test(line.replaceAll('RH Escuta.Aí', ''))) found.push(`${file}:${index + 1}`);
    });
  }
  assert.deepEqual(found, []);
});

// P0 do piloto (2026-11-27): página pública do parceiro sem preço, teste grátis ou desconto; serviços "sob consulta".
test('parceiros: serviços por nome, sob consulta, sem preço, teste grátis nem desconto', () => {
  const page = readFileSync('src/landing-site/pages/parceiros.tsx', 'utf8');
  assert.doesNotMatch(page, /R\$|<Price|grátis|desconto|-5%|BillButton/);
  assert.equal((page.match(/<div className="val sob">Sob consulta<\/div>/g) ?? []).length, 3);
  for (const name of ['Presença', 'Profissional', 'Nacional']) assert.match(page, new RegExp(`<h3>${name}</h3>`));
});

test('assistente de manifestação mostra os canais de emergência e diz que não é canal de emergência', () => {
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.ok(wizard.includes('Em caso de risco imediato, procure ajuda: CVV 188, SAMU 192 ou Polícia Militar 190. A {brandName} não é um canal de emergência.'), 'frase fixa (B4)');
  assert.ok(wizard.includes('procure agora ajuda: CVV 188 (apoio emocional, 24 horas), SAMU 192 ou Polícia Militar 190. A {brandName} não é canal de emergência e não acompanha casos em tempo real.'), 'aviso da pergunta de risco (B1)');
  assert.match(readFileSync('src/domain/brand.ts', 'utf8'), /export const brandName = 'RH Escuta\.Aí';/);
  const fixed = wizard.match(/Etapa \{step \+ 1\} de \{total\}[\s\S]{0,200}?Em caso de risco imediato/);
  assert.ok(fixed, 'a frase fixa fica no cabeçalho, visível em todas as etapas');
});

// Design P3.10 (2026-11-24): glossário. "Manifestação" é o caso; "relato" é o texto do trabalhador. Sem sobretítulo repetido.
test('glossário: manifestação para o caso, relato para o texto; sobretítulos que só repetem a área saem', () => {
  const main = readFileSync('src/app/main.js', 'utf8');
  for (const old of ['acompanhar seus relatos', 'Acompanhe seus relatos', 'Seus últimos relatos']) assert.ok(!main.includes(old), old);
  assert.match(readFileSync('src/portals/ops-portal-live.tsx', 'utf8'), /label: 'Manifestações para revisar'/);
  assert.match(readFileSync('src/portals/worker-portal-live.tsx', 'utf8'), /Quantas manifestações você registrou no período\./);
  const notices = readFileSync('src/portals/company-notices.tsx', 'utf8');
  assert.match(notices, /<th>Manifestações<\/th><\/tr>/);
  for (const file of ['company-notices', 'response-review', 'representatives', 'profile-live', 'worker-portal-live', 'portal-live', 'ops-portal-live']) {
    assert.doesNotMatch(readFileSync(`src/portals/${file}.tsx`, 'utf8'), /<span className="editorial-eyebrow">(Operação|Hub de parceiros|Área do trabalhador|Área da empresa)<\/span>/, file);
  }
  // Textos em revisão jurídica (aviso à empresa e consentimento) não mudam.
  const legal = readFileSync('src/domain/company-notice.ts', 'utf8');
  assert.match(legal, /existe um relato sobre a sua empresa/);
  assert.match(readFileSync('src/domain/site-pages.ts', 'utf8'), /description: 'Receba manifestações liberadas pelos trabalhadores, organize a atuação e dê retorno\.'/);
});