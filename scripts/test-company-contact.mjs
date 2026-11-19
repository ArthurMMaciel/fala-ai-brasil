import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Contato na empresa em toda manifestação (decisão do responsável, 2026-11-19).
const compile = file => ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const asUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const rulesUrl = asUrl(compile('src/domain/account-rules.ts'));
const source = readFileSync('src/domain/company-notice.ts', 'utf8');
const load = async phone => import(asUrl(ts.transpileModule(source.replace(/export const companyContactPhoneEnabled = (true|false);/, `export const companyContactPhoneEnabled = ${phone};`), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText.replace(/from ['"]\.\/account-rules['"]/, `from '${rulesUrl}'`)) + `#${phone}`);

test('etapa de contato aparece em toda manifestação, com texto próprio para empresa cadastrada', () => {
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, /'theme', 'report', 'notice', 'expect', 'review'\]/);
  assert.match(wizard, /registered \? registeredContactTexts\.intro/);
  assert.match(wizard, /noticeContact: noticeContactPayload\(notice, registered\)/);
  assert.doesNotMatch(wizard, /Formas de comunicação|Demonstração: contatos/);
});

test('sem o contrato novo: telefone desligado e contato só vai com e-mail (o create_complaint atual exige e-mail)', async () => {
  const notice = await load(false);
  assert.equal(notice.companyContactPhoneEnabled, false);
  assert.equal(notice.noticeContactPayload({ email: '', phone: '(11) 91234-5678', involvement: 'no', consent: true }), null);
  assert.deepEqual(JSON.parse(JSON.stringify(notice.noticeContactPayload({ email: 'RH@example.com', phone: '(11) 91234-5678', involvement: 'no', consent: true }, true))), { email: 'rh@example.com', possibly_involved: false, consent: true });
  assert.match(notice.validateNoticeContact({ email: 'rh@example.com', involvement: 'no', consent: false }, true), /segundo canal/);
});

test('com o telefone ligado: e-mail ou telefone, pelo menos um; pergunta e consentimento quando houver contato', async () => {
  const notice = await load(true);
  assert.equal(notice.validateNoticeContact({ email: '', phone: '', involvement: '', consent: false }), null);
  assert.match(notice.validateNoticeContact({ email: '', phone: '(11) 1234', involvement: 'no', consent: true }), /telefone/);
  assert.match(notice.validateNoticeContact({ email: '', phone: '(11) 91234-5678', involvement: '', consent: true }), /envolvida/);
  assert.deepEqual(JSON.parse(JSON.stringify(notice.noticeContactPayload({ email: '', phone: '(11) 91234-5678', involvement: 'unknown', consent: true }, true))), { phone: '11912345678', possibly_involved: true, consent: true });
});

test('Operação: contato indicado no detalhe e e-mail da Receita como destino quando não há contato do trabalhador', () => {
  const service = readFileSync('src/services/notices.ts', 'utf8');
  assert.match(service, /if \(row\.email\) return \{ email: row\.email, fromRegistry: false \};/);
  assert.match(service, /return row\.registryEmail \? \{ email: row\.registryEmail, fromRegistry: true \} : null;/);
  const notices = readFileSync('src/portals/company-notices.tsx', 'utf8');
  assert.match(notices, /E-mail da Receita: confira antes \(pode ser do contador ou pessoal\)/);
  const ops = readFileSync('src/portals/ops-portal-live.tsx', 'utf8');
  assert.match(ops, /<ComplaintContact complaintId=\{complaint\.id\} \/>/);
  assert.match(ops, /Só a equipe vê\. A empresa não recebe este contato\./);
});
