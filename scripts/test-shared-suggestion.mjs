import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Revisor simulado da versão para a empresa (pedido do responsável, 2026-11-23): regras no navegador, sem IA nem serviço externo.
const output = ts.transpileModule(readFileSync('src/domain/shared-version-suggestion.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const s = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

test('troca contatos, documentos e datas', () => {
  const r = s.suggestSharedVersion('Meu e-mail é ana.teste@example.com e o telefone (11) 98765-4321. CPF 123.456.789-09, CNPJ 11.222.333/0001-81. Foi em 05/03/2026, no dia 12 e em 3 de março de 2026.');
  assert.equal(r.text, 'Meu e-mail é [e-mail] e o telefone [telefone]. CPF [documento], CNPJ [documento]. Foi em [data], no [data] e em [data].');
  assert.deepEqual({ ...r.counts }, { people: 0, emails: 1, phones: 1, documents: 2, dates: 3, offensive: 0 });
});

test('possíveis nomes no meio da frase viram [pessoa]; siglas e palavras de trabalho ficam', () => {
  const r = s.suggestSharedVersion('Falei com a Marina e com o João Pedro. A supervisora Ana Paula dos Santos ignorou. O RH e a CIPA da TESTE Ltda não responderam. Carlos Silva gritou.');
  assert.equal(r.text, 'Falei com a [pessoa] e com o [pessoa]. A supervisora [pessoa] ignorou. O RH e a CIPA da TESTE Ltda não responderam. [pessoa] gritou.');
  assert.equal(r.counts.people, 4);
});

test('limite conhecido: nome sozinho no começo da frase não é trocado (por isso o aviso pede conferência)', () => {
  assert.equal(s.suggestSharedVersion('Carlos me humilhou.').text, 'Carlos me humilhou.');
});

test('suaviza termos ofensivos da lista curta, sem pegar parte de outra palavra', () => {
  const r = s.suggestSharedVersion('Ele me chamou de IDIOTA e de burra. Que porra. O cronograma é burocrático.');
  assert.equal(r.text, 'Ele me chamou de [expressão ofensiva retirada] e de [expressão ofensiva retirada]. Que [expressão ofensiva retirada]. O cronograma é burocrático.');
  assert.equal(r.counts.offensive, 3);
});

test('resumo, rótulo e tela: sem promessa de anonimato; nada sai do navegador', () => {
  assert.equal(s.suggestionSummary({ people: 2, emails: 0, phones: 1, documents: 0, dates: 0, offensive: 0 }), 'Trocamos 2 possíveis nomes, 1 telefone.');
  assert.match(s.suggestionSummary({ people: 0, emails: 0, phones: 0, documents: 0, dates: 0, offensive: 0 }), /^Não encontramos/);
  assert.equal(s.suggestionLabel, 'Sugestão automática simples. Confira antes de enviar; a equipe também revisa.');
  const domain = readFileSync('src/domain/shared-version-suggestion.ts', 'utf8');
  assert.doesNotMatch(domain, /fetch\(|import .* from ['"]\.\.\/services|supabase/);
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, />Sugerir versão revisada<\/button>/);
  assert.match(wizard, /const result = suggestSharedVersion\(draft\.original\);/);
  assert.doesNotMatch(`${domain}\n${wizard}`, /anônim|anonim/i);
  assert.equal(s.suggestSharedVersion('').text, '');
});
