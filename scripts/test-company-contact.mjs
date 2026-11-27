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

test('contrato final (e0f43bd): telefone ligado, e-mail e telefone no payload e mensagens iguais às do banco', async () => {
  assert.match(source, /export const companyContactPhoneEnabled = true;/);
  const notice = await load(true);
  assert.deepEqual(JSON.parse(JSON.stringify(notice.noticeContactPayload({ email: 'RH@example.com', phone: '(11) 91234-5678', involvement: 'no', consent: true }, true))), { email: 'rh@example.com', phone: '11912345678', possibly_involved: false, consent: true });
  assert.equal(notice.validateNoticeContact({ email: 'rh@example.com', involvement: 'no', consent: false }, true), 'Para indicar um contato, confirme o uso dele pela equipe.');
  assert.equal(notice.validateNoticeContact({ email: '', phone: '(11) 1234', involvement: 'no', consent: true }), 'Informe um telefone de contato com DDD (10 ou 11 dígitos).');
});

test('Operação e trabalhador no contrato final: campos novos da fila, escolha do destino e contato por função', () => {
  const service = readFileSync('src/services/notices.ts', 'utf8');
  assert.match(service, /email: String\(row\.contact_email \?\? row\.email \?\? ''\)/);
  assert.match(service, /registryEmail: String\(row\.receita_email \?\? ''\)/);
  assert.match(service, /: destination \? \{ p_destination: destination \} : \{\};/, 'p_destination só quando a equipe escolhe');
  assert.match(service, /contactId \? \{ p_destination: null, p_contact_id: contactId \}/, 'contato escolhido vai em p_contact_id, com p_destination nulo');
  assert.match(service, /'ops_complaint_contact' : 'my_complaint_contact'/);
  const notices = readFileSync('src/portals/company-notices.tsx', 'utf8');
  assert.match(notices, /decision === 'approved' && !usingList && bothDestinations && <fieldset/, 'sem a lista de contatos, vale a escolha antiga');
  assert.match(readFileSync('src/portals/worker-portal-live.tsx', 'utf8'), /<MyComplaintContact complaintId=\{complaint\.id\} \/>/);
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
  assert.match(ops, /Só a equipe vê\. A empresa não recebe \{contacts\.length > 1 \? 'estes contatos' : 'este contato'\}\./);
});

// Até 3 contatos da empresa por manifestação (2026-11-26). A tela fica desligada até o contrato do Back.
test('vários contatos: até 3, validação por contato, "Não sei" conta como envolvido, consentimento único', async () => {
  const notice = await load(true);
  assert.equal(notice.maxNoticeContacts, 3);
  assert.equal(notice.multipleNoticeContactsEnabled, true, 'ligado depois do lote 5 (p.notice_contacts no banco)');
  const first = { email: 'rh@example.com', phone: '', involvement: 'no', consent: true };
  const extras = [{ email: 'ouvidoria@example.com', phone: '', involvement: 'unknown' }, { email: '', phone: '(11) 91234-5678', involvement: 'no' }];
  assert.equal(notice.validateNoticeContacts(first, extras), null);
  assert.deepEqual(notice.noticeContactsPayload(first, extras).map(c => [c.email ?? c.phone, c.possibly_involved]), [['rh@example.com', false], ['ouvidoria@example.com', true], ['11912345678', false]]);
  assert.match(notice.validateNoticeContacts(first, [{ email: 'ruim', phone: '', involvement: 'no' }]), /^Contato 2: Informe um e-mail de contato válido\./);
  assert.match(notice.validateNoticeContacts(first, [{ email: 'a@example.com', phone: '', involvement: '' }]), /^Contato 2: Responda se a pessoa/);
  assert.match(notice.validateNoticeContacts({ ...first, involvement: '' }, extras), /^Contato 1: /);
  assert.equal(notice.validateNoticeContacts({ ...first, consent: false }, extras), notice.registeredContactTexts.missingConsent, 'consentimento vale para todos, sem número');
  assert.equal(notice.validateNoticeContacts({ email: '', phone: '', involvement: '', consent: false }, [extras[0]]), notice.registeredContactTexts.missingConsent);
  assert.equal(notice.noticeContactsPayload(first, [...extras, { email: 'quarto@example.com', phone: '', involvement: 'no' }]).length, 3, 'nunca mais que 3');
  assert.deepEqual(notice.noticeContactsPayload(first, [{ email: '', phone: '', involvement: '' }]).length, 1, 'contato vazio é ignorado');
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, /noticeContact: noticeContactPayload\(notice, registered\)/, 'envio segue no contrato atual até ligar a lista');
  assert.match(wizard, /multipleNoticeContactsEnabled && extraContacts\.map/);
});
// Contrato dos até 3 contatos (Back 03847ae, migration 20261126120000): listas, envio e escolha do destino.
test('contrato dos 3 contatos: notice_contacts sem notice_contact, listas com retorno ao contato único, consentimento no plural', async () => {
  const data = readFileSync('src/services/data.ts', 'utf8');
  assert.match(data, /share && input\.noticeContacts\?\.length \? \{ notice_contacts: input\.noticeContacts \} : share && input\.noticeContact \? \{ notice_contact: input\.noticeContact \} : \{\}/, 'nunca os dois juntos');
  const service = readFileSync('src/services/notices.ts', 'utf8');
  assert.match(service, /'ops_complaint_contacts_list' : 'my_complaint_contacts_list'/);
  assert.match(service, /if \(!missingFunction\(error\)\) throw/);
  assert.match(service, /const single = await loadComplaintContact\(complaintId, as\);/, 'sem a lista, cai no contato único');
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, /multipleNoticeContactsEnabled \? \{ noticeContacts: noticeContactsPayload\(notice, extraContacts, registered\), noticeContact: null \} : \{ noticeContact: noticeContactPayload\(notice, registered\) \}/);
  const notice = await load(true);
  assert.equal(notice.contactsConsentText(1), notice.noticeTexts.consent);
  assert.equal(notice.contactsConsentText(2), 'Concordo que a equipe da Escuta Aí Brasil use estes contatos como segundo canal com a empresa nesta manifestação. A empresa não vê estes contatos.');
  const notices = readFileSync('src/portals/company-notices.tsx', 'utf8');
  assert.match(notices, /contact\.eligibleForNotice !== false && !contact\.possiblyInvolved && !contact\.optedOut/, 'só contatos elegíveis com e-mail');
});