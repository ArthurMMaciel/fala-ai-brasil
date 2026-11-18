import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Contato público do parceiro (decisão do responsável, 2026-11-18). Tela pronta; ligada só quando o Back mandar o contrato.
const source = readFileSync('src/domain/account-rules.ts', 'utf8');
const load = async enabled => {
  const code = ts.transpileModule(source.replace('export const partnerContactEnabled = false;', `export const partnerContactEnabled = ${enabled};`), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}#${enabled}`);
};
const base = { type: 'partner', email: 'parceiro@example.com', password: 'Senha@123', confirm: 'Senha@123', name: 'TESTE Parceiro', documentType: 'cpf', document: '529.982.247-25', specialty: 'Psicologia', planId: 'partner-presence', subscriptionMode: 'trial', address: { zipCode: '01001-000', streetType: 'street', streetName: 'Rua Teste', number: '1', city: 'São Paulo', state: 'SP' } };

test('desligado (padrão até o contrato): cadastro de parceiro igual ao de hoje, sem campos nem payload novos', async () => {
  const rules = await load(false);
  assert.equal(rules.partnerContactEnabled, false);
  assert.equal(rules.validateRegistration(base), null);
  const payload = rules.buildProfilePayload(base);
  assert.equal('contact_email' in payload, false);
  assert.equal('contact_phone' in payload, false);
});

test('ligado: e-mail e telefone de contato obrigatórios no cadastro de parceiro e no payload', async () => {
  const rules = await load(true);
  assert.match(rules.validateRegistration(base), /e-mail de contato/);
  assert.match(rules.validateRegistration({ ...base, contactEmail: 'contato@example.com', contactPhone: '(11) 1234' }), /telefone de contato/);
  const full = { ...base, contactEmail: ' Contato@Example.com ', contactPhone: '(11) 91234-5678' };
  assert.equal(rules.validateRegistration(full), null);
  const payload = rules.buildProfilePayload(full);
  assert.equal(payload.contact_email, 'contato@example.com');
  assert.equal(payload.contact_phone, '11912345678');
  // Os outros cadastros não mudam.
  assert.equal('contact_email' in rules.buildProfilePayload({ ...base, type: 'sponsor', cnpj: '11.222.333/0001-81' }), false);
});

test('telas: campos só no formulário de parceiro, e-mail acompanha o login até ser editado, contato no Meu perfil e em Contratados', () => {
  const main = readFileSync('src/app/main.js', 'utf8');
  assert.match(main, /o\.authAudience==="partner"&&partnerContactEnabled\?acctPartnerContactFields\(\):""/);
  assert.match(main, /contactEmail:i\("contactEmail"\),contactPhone:i\("contactPhone"\)/);
  const follow = readFileSync('src/app/partner-contact.ts', 'utf8');
  assert.match(follow, /input\.name === "email" && follow\.dataset\.edited !== "1"/);
  assert.match(follow, /maskPhone/);
  const portal = readFileSync('src/portals/portal-live.tsx', 'utf8');
  assert.match(portal, /\{partnerContactEnabled && <div className="grid two"><label className="field">E-mail de contato/);
  assert.match(portal, /row\.contactEmail \|\| row\.contactPhone/);
});
