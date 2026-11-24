import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Edge Function send-notifications (ADR-0020): SMTP simulado e banco simulado. Nenhuma rede.
const load = async (path) => {
  const out = ts.transpileModule(readFileSync(path, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(out).toString('base64')}`);
};
const smtp = await load('supabase/functions/send-notifications/smtp.ts');
const send = await load('supabase/functions/send-notifications/send.ts');

// Servidor SMTP simulado: responde por regra a cada linha recebida e registra o que o cliente mandou.
function fakeServer({ authCode = 235, rcptCode = 250 } = {}) {
  const sent = [];
  const queue = ['220 smtp.test ESMTP'];
  let inData = false;
  let closed = false;
  const reply = (line) => {
    if (inData) { if (line.endsWith('\r\n.')) { inData = false; queue.push('250 2.0.0 OK queued'); } return; }
    if (line.startsWith('EHLO')) queue.push('250-smtp.test', '250-AUTH LOGIN PLAIN', '250 8BITMIME');
    else if (line === 'AUTH LOGIN') queue.push('334 VXNlcm5hbWU6');
    else if (sent.filter((l) => !l.startsWith('EHLO') && l !== 'AUTH LOGIN').length === 1 && !line.includes(':')) queue.push('334 UGFzc3dvcmQ6');
    else if (sent.length === 4) queue.push(`${authCode} auth`);
    else if (line.startsWith('MAIL FROM')) queue.push('250 OK');
    else if (line.startsWith('RCPT TO')) queue.push(`${rcptCode} rcpt`);
    else if (line === 'DATA') { queue.push('354 go'); inData = true; }
    else if (line === 'RSET') queue.push('250 reset');
    else if (line === 'QUIT') queue.push('221 bye');
  };
  return {
    sent,
    get closed() { return closed; },
    conn: {
      async readLine() { return queue.length ? queue.shift() : null; },
      async write(text) {
        const line = text.replace(/\r\n$/, '');
        sent.push(line);
        reply(line);
      },
      close() { closed = true; },
    },
  };
}

test('SMTP: saudação, EHLO, AUTH LOGIN, envio e QUIT, na ordem', async () => {
  const s = fakeServer();
  const c = await smtp.SmtpClient.open(s.conn, 'conta@gmail.invalid', 'senha-de-app');
  await c.send('pessoa@empresa.invalid', smtp.buildMessage('conta@gmail.invalid', 'Escuta Aí Brasil', 'pessoa@empresa.invalid', 'Assunto', 'Corpo', new Date(0), 'id1'));
  await c.quit();
  assert.equal(s.sent[0], 'EHLO escutaai.invalid');
  assert.equal(s.sent[1], 'AUTH LOGIN');
  assert.equal(Buffer.from(s.sent[2], 'base64').toString(), 'conta@gmail.invalid');
  assert.equal(Buffer.from(s.sent[3], 'base64').toString(), 'senha-de-app');
  assert.equal(s.sent[4], 'MAIL FROM:<conta@gmail.invalid>');
  assert.equal(s.sent[5], 'RCPT TO:<pessoa@empresa.invalid>');
  assert.equal(s.sent[6], 'DATA');
  assert.ok(s.sent[7].endsWith('\r\n.'));
  assert.equal(s.sent.at(-1), 'QUIT');
  assert.equal(s.closed, true);
});

test('SMTP: 535 no login vira erro de autenticação e fecha a conexão', async () => {
  const s = fakeServer({ authCode: 535 });
  await assert.rejects(smtp.SmtpClient.open(s.conn, 'a@gmail.invalid', 'x'), (e) => e instanceof smtp.SmtpAuthError);
  assert.equal(s.closed, true);
});

test('SMTP: destinatário recusado vira erro com código e a sessão é reiniciada (RSET)', async () => {
  const s = fakeServer({ rcptCode: 550 });
  const c = await smtp.SmtpClient.open(s.conn, 'a@gmail.invalid', 'x');
  await assert.rejects(c.send('x@y.invalid', 'm'), (e) => e instanceof smtp.SmtpError && e.code === '550');
  assert.equal(s.sent.at(-1), 'RSET');
  await assert.rejects(c.send('sem-arroba', 'm'), (e) => e instanceof smtp.SmtpError && e.code === 'bad_address');
});

test('mensagem: cabeçalhos codificados, corpo em base64 e só o texto fixo', () => {
  const body = send.messageBody(new Set(['worker_update']));
  const m = smtp.buildMessage('conta@gmail.invalid', 'Escuta Aí Brasil', 'p@x.invalid', send.SUBJECT, body, new Date(0), 'id1');
  assert.match(m, /^From: =\?UTF-8\?B\?.+\?= <conta@gmail\.invalid>/);
  assert.match(m, /Subject: =\?UTF-8\?B\?/);
  assert.match(m, /Content-Transfer-Encoding: base64/);
  const encoded = m.split('\r\n\r\n')[1].replace(/\r\n/g, '');
  assert.equal(Buffer.from(encoded, 'base64').toString('utf8'), body);
  assert.match(body, /https:\/\/fala-ai-brasil\.vercel\.app/);
  assert.match(body, /Meu perfil/);
  assert.doesNotMatch(body, /EAB-|protocolo|empresa .*respondeu|liberad|retid/i);
  assert.doesNotMatch(send.messageBody(new Set(['company_update'])), /Meu perfil/);
});

// Banco e SMTP simulados para a rodada.
function makeDeps({ rows, openError = null, sendErrors = {} }) {
  const calls = { sent: [], marks: [], logs: [], quit: 0 };
  const authErr = new Error('auth'); authErr.auth = true;
  return {
    calls, authErr,
    deps: {
      async claim() { return rows; },
      async mark(id, result, code, messages) { calls.marks.push({ id, result, code, messages }); },
      async openMailer() {
        if (openError) throw openError;
        return {
          async send(to, subject, body) {
            if (sendErrors[to]) throw sendErrors[to];
            calls.sent.push({ to, subject, body });
          },
          async quit() { calls.quit += 1; },
        };
      },
      isAuthError: (e) => Boolean(e && e.auth),
      errorCode: (e) => (e && e.code) || 'send_error',
      log(event) { calls.logs.push(event); },
      now: () => 0,
    },
  };
}
const row = (id, kind, email, remaining = 300) => ({ outbox_id: id, kind, email, remaining_today: remaining });
const markOf = (calls, id) => calls.marks.find((m) => m.id === id);

test('rodada: um e-mail por destinatário, agrupando as pendências; empresa com dois verificados recebe dois', async () => {
  const t = makeDeps({ rows: [row('a', 'worker_update', 'W@x.invalid'), row('b', 'worker_update', 'w@x.invalid'),
    row('c', 'company_update', 'r1@e.invalid'), row('c', 'company_update', 'r2@e.invalid')] });
  const s = await send.runBatch(t.deps);
  assert.deepEqual(t.calls.sent.map((e) => e.to).sort(), ['r1@e.invalid', 'r2@e.invalid', 'w@x.invalid']);
  assert.deepEqual(markOf(t.calls, 'a'), { id: 'a', result: 'sent', code: null, messages: 1 });
  assert.deepEqual(markOf(t.calls, 'c'), { id: 'c', result: 'sent', code: null, messages: 2 });
  assert.equal(s.emails, 3);
  assert.equal(t.calls.quit, 1);
});

test('rodada: teto do dia adia o excedente sem gastar tentativa', async () => {
  const t = makeDeps({ rows: [row('a', 'worker_update', 'a@x.invalid', 1), row('b', 'worker_update', 'b@x.invalid', 1)] });
  await send.runBatch(t.deps);
  assert.equal(t.calls.sent.length, 1);
  assert.equal(markOf(t.calls, 'a').result, 'sent');
  assert.deepEqual(markOf(t.calls, 'b'), { id: 'b', result: 'release', code: 'daily_cap', messages: 0 });
});

test('rodada: erro de autenticação ao abrir para o lote sem gastar tentativa', async () => {
  const t = makeDeps({ rows: [row('a', 'worker_update', 'a@x.invalid'), row('b', 'company_update', 'b@x.invalid')] });
  t.deps.openMailer = async () => { throw t.authErr; };
  const s = await send.runBatch(t.deps);
  assert.equal(s.authError, true);
  assert.equal(t.calls.sent.length, 0);
  assert.ok(t.calls.marks.every((m) => m.result === 'release' && m.code === 'smtp_auth'));
});

test('rodada: erro de autenticação no meio para o resto; outro erro vai para nova tentativa', async () => {
  const fail = new Error('550'); fail.code = 'smtp_550';
  const t = makeDeps({ rows: [row('a', 'worker_update', 'a@x.invalid'), row('b', 'worker_update', 'b@x.invalid'), row('c', 'worker_update', 'c@x.invalid')] });
  t.deps.openMailer = async () => ({
    async send(to) { if (to === 'a@x.invalid') throw fail; if (to === 'b@x.invalid') throw t.authErr; },
    async quit() {},
  });
  await send.runBatch(t.deps);
  assert.deepEqual(markOf(t.calls, 'a'), { id: 'a', result: 'retry', code: 'smtp_550', messages: 0 });
  assert.equal(markOf(t.calls, 'b').result, 'release');
  assert.equal(markOf(t.calls, 'c').result, 'release');
});

test('rodada: falha de conexão (não autenticação) vai para nova tentativa', async () => {
  const down = new Error('down'); down.code = 'smtp_timeout';
  const t = makeDeps({ rows: [row('a', 'worker_update', 'a@x.invalid')], openError: down });
  await send.runBatch(t.deps);
  assert.deepEqual(markOf(t.calls, 'a'), { id: 'a', result: 'retry', code: 'smtp_timeout', messages: 0 });
});

test('rodada: log só com id, tipo, resultado e tempo; nada de e-mail', async () => {
  const t = makeDeps({ rows: [row('a', 'worker_update', 'pessoa@x.invalid')] });
  await send.runBatch(t.deps);
  assert.deepEqual(Object.keys(t.calls.logs[0]).sort(), ['id', 'kind', 'ms', 'result']);
  assert.equal(JSON.stringify(t.calls.logs).includes('pessoa@'), false);
});

test('index.ts: segredo do agendador em tempo constante, sem JWT, só as duas RPCs e logs sem conteúdo', () => {
  const src = readFileSync('supabase/functions/send-notifications/index.ts', 'utf8');
  assert.match(src, /x-cron-secret/);
  assert.match(src, /sameSecret\(/);
  assert.match(src, /status: 401/);
  assert.match(src, /smtp\.gmail\.com/);
  assert.match(src, /SMTP_PORT = 465/);
  assert.deepEqual([...src.matchAll(/rpc\('([a-z_]+)'/g)].map((m) => m[1]).sort(), ['notification_claim', 'notification_mark']);
  assert.equal((src.match(/console\.log/g) ?? []).length, 3);
  assert.doesNotMatch(src, /console\.log\([^)]*(email|to|gmailUser|password)/i);
  assert.match(src, /pickKey\('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY'\)/);
});
