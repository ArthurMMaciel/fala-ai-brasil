import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// "Meu perfil" (ADR-0014): validação com as mensagens do cadastro, payload parcial e dados travados.
const require = createRequire(import.meta.url);
function compile(file, customRequire = require) {
  const module = { exports: {} };
  const code = ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2021 } }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: customRequire });
  return module.exports;
}
const rules = compile('src/domain/account-rules.ts');
const profile = compile('src/domain/profile.ts', name => name === './account-rules' ? rules : require(name));
const ui = compile('src/portals/profile-live.tsx', name => ({ '../domain/account-rules': rules, '../domain/profile': profile, '../services/profile': {}, '../app/toast': { showToast() {} } }[name] ?? require(name)));

const plain = value => JSON.parse(JSON.stringify(value));
const address = { zipCode: '01310-100', streetType: 'avenue', streetName: 'Paulista', number: '900', complement: '', neighborhood: 'Bela Vista', city: 'São Paulo', state: 'SP' };
const worker = { fullName: 'Pessoa Teste', phone: '(41) 98765-4321', address };
const company = { tradeName: 'Aurora', contactEmail: 'contato@example.com', contactPhone: '(41) 3333-4444', address };

test('validação do trabalhador usa as mensagens do cadastro e do banco', () => {
  assert.equal(profile.validateWorkerProfile(worker), null);
  assert.equal(profile.validateWorkerProfile({ ...worker, fullName: ' A ' }), 'Informe o nome completo.');
  assert.equal(profile.validateWorkerProfile({ ...worker, phone: '(41) 8765-432' }), 'Informe um telefone válido com DDD: celular com 9 dígitos ou fixo com 8.');
  assert.equal(profile.validateWorkerProfile({ ...worker, address: { ...address, zipCode: '0131' } }), 'Informe um CEP com 8 dígitos.');
  assert.equal(profile.validateWorkerProfile({ ...worker, address: { ...address, state: 'XX' } }), 'Selecione a UF.');
});

test('validação da empresa aceita contato vazio e recusa formato inválido', () => {
  assert.equal(profile.validateCompanyProfile(company), null);
  assert.equal(profile.validateCompanyProfile({ ...company, contactEmail: '', contactPhone: '' }), null);
  assert.equal(profile.validateCompanyProfile({ ...company, contactEmail: 'sem-arroba' }), 'Informe um e-mail de contato válido.');
  assert.equal(profile.validateCompanyProfile({ ...company, tradeName: 'x'.repeat(161) }), 'O nome fantasia pode ter até 160 caracteres.');
});

test('payload parcial leva só o que mudou e nunca documento ou razão social', () => {
  assert.deepEqual(plain(profile.workerProfileChanges(worker, { ...worker })), {});
  assert.deepEqual(plain(profile.workerProfileChanges(worker, { ...worker, fullName: '  Pessoa Nova ' })), { full_name: 'Pessoa Nova' });
  assert.deepEqual(plain(profile.workerProfileChanges(worker, { ...worker, phone: '(41) 3333-4444' })), { phone: '4133334444' });
  const moved = profile.workerProfileChanges(worker, { ...worker, address: { ...address, number: '1000', state: 'sp' } });
  assert.deepEqual(plain(Object.keys(moved)), ['address']);
  assert.deepEqual(plain(moved.address), { zip_code: '01310100', street_type: 'avenue', street_name: 'Paulista', number: '1000', complement: null, neighborhood: 'Bela Vista', city: 'São Paulo', state: 'SP' });
  const changed = profile.companyProfileChanges(company, { ...company, tradeName: 'Aurora Nova', contactEmail: 'NOVO@Example.com', contactPhone: '' });
  assert.deepEqual(plain(changed), { trade_name: 'Aurora Nova', contact_email: 'novo@example.com', contact_phone: '' });
  for (const payload of [moved, changed]) for (const key of ['cpf', 'cnpj', 'legal_name']) assert.equal(key in payload, false);
});

test('máscara de CEP e validação do novo e-mail de acesso', () => {
  assert.equal(profile.maskZip('01310100'), '01310-100');
  assert.equal(profile.maskZip('0131'), '0131');
  assert.equal(profile.validateLoginEmail('nova@example.com', 'atual@example.com'), null);
  assert.equal(profile.validateLoginEmail('ATUAL@example.com', 'atual@example.com'), 'Informe um e-mail diferente do atual.');
  assert.equal(profile.validateLoginEmail('invalido', 'atual@example.com'), 'Informe um e-mail válido.');
});

test('CPF/CNPJ/razão social aparecem só para leitura, com o caminho para a equipe', () => {
  const html = renderToStaticMarkup(React.createElement(ui.LockedFacts, { facts: [['Razão social', 'Aurora Tecnologia Ltda.'], ['CNPJ', '31.245.678/0001-90']] }));
  assert.match(html, /Aurora Tecnologia Ltda\./);
  assert.match(html, /Para alterar, fale com a equipe\./);
  assert.doesNotMatch(html, /<input|<select|<textarea/, 'nenhum campo editável para dados travados');
  assert.match(html, /aria-describedby="([^"]+)"[\s\S]*id="\1"/, 'aviso ligado ao bloco por aria-describedby');
});

test('troca do e-mail de acesso fica desligada até a confirmação do responsável', () => {
  assert.equal(profile.emailChangeEnabled, false);
  const html = renderToStaticMarkup(React.createElement(ui.LoginEmail, { current: 'pessoa@example.com' }));
  assert.match(html, /pessoa@example\.com/);
  assert.match(html, /ainda não está disponível/);
  assert.doesNotMatch(html, /<form|type="email"/);
});

test('endereço tem rótulo em todos os campos e opcionais marcados', () => {
  const html = renderToStaticMarkup(React.createElement(ui.AddressFields, { value: address, onChange() {} }));
  assert.equal((html.match(/<label/g) || []).length, 8);
  assert.match(html, /<legend>Endereço<\/legend>/);
  assert.match(html, /Complemento \(opcional\)/);
  assert.equal((html.match(/required=""/g) || []).length, 6);
});
