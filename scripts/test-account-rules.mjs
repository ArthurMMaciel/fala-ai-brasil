import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

const output = ts.transpileModule(readFileSync('src/account-rules.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const rules = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

const address = { zipCode: '01310-100', streetType: 'avenue', streetName: 'Paulista', number: '1000', city: 'São Paulo', state: 'sp' };
const worker = { type: 'worker', name: 'Pessoa Teste', email: 'pessoa@exemplo.com', password: 'senha-forte-1', confirm: 'senha-forte-1', cpf: '529.982.247-25', address };

test('CPF e CNPJ validam dígitos verificadores', () => {
  assert.equal(rules.isValidCpf('529.982.247-25'), true);
  assert.equal(rules.isValidCpf('529.982.247-24'), false);
  assert.equal(rules.isValidCpf('111.111.111-11'), false);
  assert.equal(rules.isValidCnpj('11.222.333/0001-81'), true);
  assert.equal(rules.isValidCnpj('12.345.678/0001-90'), false);
});

test('cadastro exige confirmação de senha igual e tamanho mínimo', () => {
  assert.equal(rules.validateRegistration(worker), null);
  assert.match(rules.validateRegistration({ ...worker, confirm: 'outra-senha' }), /confirmação de senha/);
  assert.match(rules.validateRegistration({ ...worker, password: '1234567', confirm: '1234567' }), /pelo menos 8/);
});

test('cada tipo exige seus próprios documentos', () => {
  assert.match(rules.validateRegistration({ ...worker, cpf: '' }), /CPF/);
  const company = { ...worker, type: 'company', cnpj: '11.222.333/0001-81', planId: 'company-essential', subscriptionMode: 'trial' };
  assert.equal(rules.validateRegistration(company), null);
  assert.match(rules.validateRegistration({ ...company, cnpj: '123' }), /CNPJ/);
  const partner = { ...worker, type: 'partner', documentType: 'cnpj', document: '11.222.333/0001-81', specialty: 'Mediação', planId: 'partner-presence', subscriptionMode: 'monthly' };
  assert.equal(rules.validateRegistration(partner), null);
  assert.match(rules.validateRegistration({ ...partner, documentType: 'cpf' }), /CPF ou CNPJ/);
  assert.match(rules.validateRegistration({ ...partner, specialty: ' ' }), /especialidade/);
  assert.match(rules.validateRegistration({ ...company, type: 'sponsor', cnpj: '' }), /CNPJ/);
  assert.match(rules.validateRegistration({ ...worker, type: 'intelligence' }), /não está disponível/);
});

test('endereço exige CEP, tipo, nome, número, cidade e UF', () => {
  assert.match(rules.validateAddress({ ...address, zipCode: '0131' }), /CEP/);
  assert.match(rules.validateAddress({ ...address, streetType: 'rua' }), /tipo de logradouro/);
  assert.match(rules.validateAddress({ ...address, number: ' ' }), /número/);
  assert.match(rules.validateAddress({ ...address, city: '' }), /cidade/);
  assert.match(rules.validateAddress({ ...address, state: 'XX' }), /UF/);
});

test('logradouro do ViaCEP é separado em tipo e nome', () => {
  assert.deepEqual(rules.splitStreet('Avenida Paulista'), { streetType: 'avenue', streetName: 'Paulista' });
  assert.deepEqual(rules.splitStreet('Rua XV de Novembro'), { streetType: 'street', streetName: 'XV de Novembro' });
  assert.deepEqual(rules.splitStreet('Praça da Sé'), { streetType: 'square', streetName: 'da Sé' });
  assert.equal(rules.splitStreet('Quadra 5'), null);
});

test('payload usa nomes de banco em inglês e só os campos do tipo', () => {
  const payload = rules.buildProfilePayload({ ...worker, type: 'partner', documentType: 'cpf', document: '529.982.247-25', specialty: ' Mediação ', planId: 'partner-presence', subscriptionMode: 'trial' });
  assert.deepEqual(Object.keys(payload).sort(), ['address', 'description', 'display_name', 'document', 'document_type', 'plan_id', 'specialty', 'subscription_mode'].sort());
  assert.equal(payload.document, '52998224725');
  assert.equal(payload.specialty, 'Mediação');
  assert.deepEqual(payload.address, { zip_code: '01310100', street_type: 'avenue', street_name: 'Paulista', number: '1000', complement: undefined, neighborhood: undefined, city: 'São Paulo', state: 'SP' });
  const workerPayload = rules.buildProfilePayload(worker);
  assert.equal('plan_id' in workerPayload, false);
  assert.equal(workerPayload.cpf, '52998224725');
});

test('papéis da aplicação e contas demo', () => {
  assert.equal(rules.appRoleFor('worker'), 'worker');
  assert.equal(rules.appRoleFor('company'), 'admin');
  assert.equal(rules.appRoleFor('sponsor'), 'commercial');
  assert.equal(rules.isDemoEmail('Usuario@EscutaAi.demo'), true);
  assert.equal(rules.authErrorMessage('email_not_confirmed').startsWith('Confirme seu e-mail'), true);
});
