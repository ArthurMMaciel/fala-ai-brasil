import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// ADR-0023: busca por CNPJ, empresa fora da base e aviso à empresa sem conteúdo.
const compile = file => ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const asUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const rulesUrl = asUrl(compile('src/domain/account-rules.ts'));
const notice = await import(asUrl(compile('src/domain/company-notice.ts').replace(/from ['"]\.\/account-rules['"]/, `from '${rulesUrl}'`)));
const plain = value => JSON.parse(JSON.stringify(value));

test('cnpj-lookup: só 200 com status found e dados completos preenchem a empresa; o resto vira manual', () => {
  assert.deepEqual(plain(notice.lookupOutcome(200, { status: 'found', company: { legal_name: 'TESTE Ltda', trade_name: 'TESTE', city: 'Recife', state: 'pe' }, source: 'cache' })), { kind: 'found', company: { name: 'TESTE', city: 'Recife', state: 'PE' } });
  assert.deepEqual(plain(notice.lookupOutcome(200, { status: 'found', company: { razao_social: 'TESTE Ltda', municipio: 'Recife', uf: 'PE' } })).company.name, 'TESTE Ltda');
  for (const [status, body] of [[200, { status: 'manual', reason: 'natural_person' }], [200, { status: 'found', company: { name: 'X', city: 'Recife' } }], [400, {}], [401, null], [404, { status: 'found' }], [500, 'erro'], [200, null]]) assert.equal(notice.lookupOutcome(status, body).kind, 'manual', `${status} ${JSON.stringify(body)}`);
});

test('contato do aviso: opcional; com e-mail, pergunta e consentimento são obrigatórios; "Não sei" conta como envolvido', () => {
  assert.equal(notice.validateNoticeContact({ email: '', involvement: '', consent: false }), null);
  assert.equal(notice.noticeContactPayload({ email: '  ', involvement: 'no', consent: true }), null);
  assert.match(notice.validateNoticeContact({ email: 'rh@', involvement: 'no', consent: true }), /e-mail válido/);
  assert.match(notice.validateNoticeContact({ email: 'rh@empresa.com.br', involvement: '', consent: true }), /envolvida/);
  assert.match(notice.validateNoticeContact({ email: 'rh@empresa.com.br', involvement: 'no', consent: false }), /confirme/);
  assert.deepEqual(plain(notice.noticeContactPayload({ email: ' RH@Empresa.com.br ', involvement: 'no', consent: true })), { email: 'rh@empresa.com.br', possibly_involved: false, consent: true });
  assert.equal(notice.noticeContactPayload({ email: 'rh@empresa.com.br', involvement: 'unknown', consent: true }).possibly_involved, true);
  assert.equal(notice.noticeContactPayload({ email: 'rh@empresa.com.br', involvement: 'yes', consent: true }).possibly_involved, true);
  assert.equal(notice.noticeContactPayload({ email: 'rh@empresa.com.br', involvement: 'no', consent: false }), null);
});

test('pré-cadastro manual e motivos da Operação seguem os limites do banco', () => {
  assert.equal(notice.validateManualCompany('TESTE Comércio', 'Recife', 'pe'), null);
  assert.match(notice.validateManualCompany('T', 'Recife', 'PE'), /nome/);
  assert.match(notice.validateManualCompany('TESTE', '', 'PE'), /município/);
  assert.match(notice.validateManualCompany('TESTE', 'Recife', 'XX'), /UF/);
  assert.equal(notice.validateOpsReason('e-mail pessoal de uma pessoa'), null);
  assert.ok(notice.validateOpsReason('curto'));
  assert.ok(notice.validateOpsReason('x'.repeat(301)));
});

test('abas da fila de avisos', () => {
  assert.equal(notice.noticeTab({ contactStatus: 'candidate', noticeStatus: null }), 'decide');
  assert.equal(notice.noticeTab({ contactStatus: 'verified', noticeStatus: 'approved' }), 'approved');
  assert.equal(notice.noticeTab({ contactStatus: 'verified', noticeStatus: 'sent' }), 'sent');
  assert.equal(notice.noticeTab({ contactStatus: 'verified', noticeStatus: 'bounced' }), 'sent');
  assert.equal(notice.noticeTab({ contactStatus: 'rejected', noticeStatus: 'rejected' }), 'rejected');
});

test('textos do aviso: em revisão jurídica, com a frase da ADR-0023 e sem link no e-mail', () => {
  assert.equal(notice.noticeTextsInReview, true);
  assert.ok(notice.noticeTexts.consent.includes('a empresa receberá um aviso de que existe um relato na plataforma, sem o conteúdo, sem o meu nome e sem a data'));
  assert.doesNotMatch(notice.noticeTexts.emailBody, /https?:\/\/|www\.|\.com\b|\.br\b/i);
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, /noticeTextsInReview && <p className="legal-review-banner">Texto em revisão jurídica\.<\/p>/);
  assert.doesNotMatch(wizard, /Demonstração: contatos/);
  const ops = readFileSync('src/portals/company-notices.tsx', 'utf8');
  assert.match(ops, /noticeTextsInReview && <p className="legal-review-banner">Texto em revisão jurídica\.<\/p>/);
});

test('serviço: busca e pré-cadastro tolerantes a RPC e função ausentes; contato só vai com a versão compartilhável', () => {
  const service = readFileSync('src/services/notices.ts', 'utf8');
  assert.match(service, /PGRST202/);
  assert.match(service, /functions\.invoke\('cnpj-lookup'/);
  assert.match(service, /catch \{\s*return \{ kind: 'manual' \};/);
  const data = readFileSync('src/services/data.ts', 'utf8');
  assert.match(data, /share && input\.noticeContact \? \{ notice_contact: input\.noticeContact \}/);
});
