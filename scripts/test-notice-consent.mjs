import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Aceite do aviso pelo trabalhador (revisão do DevOps, 2026-11-19); chave provisória até o contrato do Back.
test('empresa não cadastrada: pergunta de aceite sempre, obrigatória, enviada só com a versão compartilhável', () => {
  const domain = readFileSync('src/domain/company-notice.ts', 'utf8');
  assert.match(domain, /export const noticeConsentKey = 'notice_consent';/);
  assert.match(domain, /Autorizo a equipe a avisar a empresa, se ela ainda não estiver na plataforma, de que existe um relato, sem o conteúdo, sem o meu nome e sem a data\./);
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, /if \(!registered && !noticeConsent\) return setError\(noticeConsentMissing\);/);
  assert.match(wizard, /\{!registered && <fieldset className="response-rating"><legend>\{noticeConsentQuestion\}<\/legend>/);
  assert.match(wizard, /noticeConsent: registered \? null : noticeConsent === 'yes'/);
  const data = readFileSync('src/services/data.ts', 'utf8');
  assert.match(data, /share && typeof input\.noticeConsent === "boolean" \? \{ \[noticeConsentKey\]: input\.noticeConsent \}/);
});

test('Operação: mostra o aceite e, sem ele, só permite recusar; sem o campo (contrato antigo), segue como antes', () => {
  const service = readFileSync('src/services/notices.ts', 'utf8');
  assert.match(service, /workerConsent: typeof row\.notice_consented === 'boolean' \? row\.notice_consented/);
  const screen = readFileSync('src/portals/company-notices.tsx', 'utf8');
  assert.match(screen, /const noConsent = item\.workerConsent === false;/);
  assert.match(screen, /\{!noConsent && <label className="check-row"><input type="radio" name="notice-decision" checked=\{decision === 'approved'\}/);
  assert.match(screen, /Trabalhador não autorizou o aviso\. Só é possível recusar\./);
});
