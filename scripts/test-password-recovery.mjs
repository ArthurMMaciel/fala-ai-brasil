import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Esqueci minha senha e troca de e-mail (ADR-0024).
const compile = file => ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022, jsx: ts.JsxEmit.ReactJSX } }).outputText;
const asUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const rulesUrl = asUrl(compile('src/domain/account-rules.ts'));
const recovery = await import(asUrl(compile('src/domain/password-recovery.ts').replace(/from ['"]\.\/account-rules['"]/, `from '${rulesUrl}'`)));

test('pedido de link: resposta sempre neutra; só o limite de envio tem mensagem própria', () => {
  assert.equal(recovery.recoverySentMessage, 'Se houver uma conta com esse e-mail, enviamos um link para criar uma nova senha. Confira também a caixa de spam.');
  for (const code of [null, undefined, 'user_not_found', 'email_address_invalid', 'unexpected_failure', 'email_send_failed']) assert.equal(recovery.recoveryRequestOutcome(code), 'sent', String(code));
  assert.equal(recovery.recoveryRequestOutcome('over_email_send_rate_limit'), 'rate_limited');
  assert.equal(recovery.recoveryRequestOutcome('over_request_rate_limit'), 'rate_limited');
  assert.equal(recovery.recoveryRequestOutcome(null, 429), 'rate_limited');
  assert.equal(recovery.validateRecoveryEmail('teste@example.com'), null);
  assert.ok(recovery.validateRecoveryEmail('teste@'));
});

test('nova senha segue a regra do cadastro e erros do Auth viram mensagens claras', () => {
  assert.equal(recovery.validateNewPassword('Senha@123', 'Senha@123'), null);
  assert.match(recovery.validateNewPassword('curta', 'curta'), /pelo menos 8/);
  assert.match(recovery.validateNewPassword('senhasemregra', 'senhasemregra'), /precisa ter/);
  assert.match(recovery.validateNewPassword('Senha@123', 'Senha@124'), /confirmação/);
  assert.match(recovery.passwordUpdateError('same_password'), /diferente/);
  assert.equal(recovery.passwordUpdateError('no_session'), recovery.recoveryExpiredMessage);
});

test('tipo do link no hash separa recuperação de confirmação de cadastro', () => {
  assert.equal(recovery.authLinkType('#access_token=x&refresh_token=y&type=recovery'), 'recovery');
  assert.equal(recovery.authLinkType('#access_token=x&type=signup'), 'signup');
  assert.equal(recovery.authLinkType('#message=ok&type=email_change'), 'email_change');
  assert.equal(recovery.authLinkType('#termos'), null);
  assert.equal(recovery.authLinkType(''), null);
});

test('serviço: resetPasswordForEmail com redirectTo do site, retorno de recuperação mantém a sessão e a confirmação de cadastro não pega o link', () => {
  const account = readFileSync('src/services/account.ts', 'utf8');
  assert.match(account, /resetPasswordForEmail\(email\.trim\(\)\.toLowerCase\(\), \{ redirectTo: redirectUrl\(\) \}\)/);
  assert.match(account, /auth\.updateUser\(\{ password \}\)/);
  assert.match(account, /\/\[#&\]type=signup\(&\|\$\)\//);
  const restore = readFileSync('src/app/main.js', 'utf8').match(/async function acctRestoreInner\(\)\{[^\n]*/)[0];
  assert.ok(restore.indexOf('consumeRecoveryArrival') < restore.indexOf('loadAccount'), 'o retorno de recuperação vem antes de entrar na conta');
  const pages = readFileSync('src/domain/site-pages.ts', 'utf8');
  assert.match(pages, /if \(location\.search\) return false;\n  if \(\/\[=&\]\/\.test\(location\.hash\)\) return false;/, 'retorno de recuperação não cai na landing antes do app tratá-lo');
});

test('troca do e-mail de acesso liberada, com texto neutro sobre a confirmação; CPF continua travado', () => {
  const profile = readFileSync('src/domain/profile.ts', 'utf8');
  assert.match(profile, /export const emailChangeEnabled = true;/);
  const screen = readFileSync('src/portals/profile-live.tsx', 'utf8');
  assert.match(screen, /Enviamos um link de confirmação\. A troca só vale depois de confirmar\./);
  assert.match(screen, /LockedFacts facts=\{\[\['CPF'/);
});
