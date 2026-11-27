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
  await c.send('pessoa@empresa.invalid', smtp.buildMessage('conta@gmail.invalid', 'RH Escuta.Aí', 'pessoa@empresa.invalid', 'Assunto', 'Corpo', new Date(0), 'id1'));
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
  const { subject, body } = send.message('worker_update', new Set(['update']));
  const m = smtp.buildMessage('conta@gmail.invalid', 'RH Escuta.Aí', 'p@x.invalid', subject, body, new Date(0), 'id1');
  assert.match(m, /^From: =\?UTF-8\?B\?.+\?= <conta@gmail\.invalid>/);
  assert.match(m, /Subject: =\?UTF-8\?B\?/);
  assert.match(m, /Content-Transfer-Encoding: base64/);
  assert.match(m, /\r\nAuto-Submitted: auto-generated\r\n/);
  const encoded = m.split('\r\n\r\n')[1].replace(/\r\n/g, '');
  assert.equal(Buffer.from(encoded, 'base64').toString('utf8'), body);
});

// Textos por evento (pedido do Gestor de 2026-11-26). Nenhum traz protocolo, categoria, situação ou promessa de proteção.
const allTexts = () => [
  send.message('worker_update', new Set(['update'])),
  ...['released', 'response_returned', 'closed', 'update'].map((r) => send.message('company_update', new Set([r]))),
  send.message('company_update', new Set(['released', 'closed'])),
  send.message('company_update', new Set()),
  send.message('company_notice', new Set(['notice'])),
];

test('textos: frases e links por evento', () => {
  const w = send.message('worker_update', new Set(['update']));
  assert.equal(w.subject, 'Há uma novidade na sua manifestação na RH Escuta.Aí');
  assert.match(w.body, /Há uma novidade na sua manifestação na RH Escuta.Aí\.\nPara ver, entre na plataforma: https:\/\/fala-ai-brasil\.vercel\.app\/#entrar\n/);
  assert.match(w.body, /Meu perfil/);

  const rel = send.message('company_update', new Set(['released']));
  assert.equal(rel.subject, 'Nova manifestação para a sua empresa na RH Escuta.Aí');
  assert.match(rel.body, /Sua empresa acabou de receber uma nova manifestação na RH Escuta.Aí\.\nPara ver e responder, entre na plataforma: https:\/\/fala-ai-brasil\.vercel\.app\/#entrar-empresa\n/);
  assert.match(send.message('company_update', new Set(['response_returned'])).body, /A equipe da RH Escuta.Aí pediu um ajuste em uma resposta da sua empresa\.\nPara ver, entre/);
  assert.match(send.message('company_update', new Set(['closed'])).body, /Uma manifestação da sua empresa foi encerrada\.\nPara ver, entre/);

  const mixed = send.message('company_update', new Set(['closed', 'released']));
  assert.equal(mixed.subject, 'Há novidades para a sua empresa na RH Escuta.Aí');
  assert.match(mixed.body, /nova manifestação na RH Escuta.Aí\.\nUma manifestação da sua empresa foi encerrada\.\nPara ver e responder/);
  assert.match(send.message('company_update', new Set()).body, /Há uma atualização para a sua empresa/);  // linha antiga, sem motivo

  const n = send.message('company_notice', new Set(['notice']));
  assert.equal(n.subject, 'Existe uma manifestação sobre a sua empresa na RH Escuta.Aí');
  assert.match(n.body, /https:\/\/fala-ai-brasil\.vercel\.app\/empresa\n/);
  assert.match(n.body, /responda a este e-mail pedindo a exclusão/);
  assert.doesNotMatch(n.body, /Meu perfil|empresa verificada/);
  for (const { body } of allTexts().slice(1)) assert.doesNotMatch(body, /Meu perfil/);
});

test('textos: todos com o aviso de segurança e sem detalhe nem promessa', () => {
  for (const { subject, body } of allTexts()) {
    assert.ok((subject + body).includes('RH Escuta.Aí'), 'nome do produto');
    assert.doesNotMatch(subject + body, /Escuta A[ií] Brasil/);
    assert.match(body, /Por segurança, este e-mail não traz detalhes\./);
    assert.doesNotMatch(subject + body, /EAB-|protocolo|retid|assédio|categoria|anônim|sigil|garant|terceiros/i);
  }
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
      stopCode: (e) => (e && e.stop) || (e && e.auth ? 'smtp_auth' : null),
      errorCode: (e) => (e && e.code) || 'send_error',
      log(event) { calls.logs.push(event); },
      now: () => 0,
    },
  };
}

test('SMTP: 421 e códigos estendidos de cota param o lote; outros erros não', () => {
  assert.equal(smtp.stopCode(new smtp.SmtpAuthError()), 'smtp_auth');
  assert.equal(smtp.stopCode(new smtp.SmtpError('421', '4.7.0')), 'smtp_quota');
  assert.equal(smtp.stopCode(new smtp.SmtpError('550', '5.4.5')), 'smtp_quota');
  assert.equal(smtp.stopCode(new smtp.SmtpError('421', null)), 'smtp_421');
  assert.equal(smtp.stopCode(new smtp.SmtpError('550', '5.1.1')), null);
  assert.equal(smtp.stopCode(new Error('x')), null);
});

test('SMTP: o código estendido vem da resposta do servidor', async () => {
  const s = fakeServer({ rcptCode: 550 });
  const c = await smtp.SmtpClient.open(s.conn, 'a@gmail.invalid', 'x');
  // o servidor simulado responde "550 rcpt" (sem código estendido)
  await assert.rejects(c.send('x@y.invalid', 'm'), (e) => e instanceof smtp.SmtpError && e.enhanced === null);
});
const row = (id, kind, email, remaining = 300, reason = null) => ({ outbox_id: id, kind, reason, email, remaining_today: remaining });
const markOf = (calls, id) => calls.marks.find((m) => m.id === id);

test('rodada: um e-mail por destinatário e tipo, agrupando as pendências; empresa com dois verificados recebe dois', async () => {
  const t = makeDeps({ rows: [row('a', 'worker_update', 'W@x.invalid'), row('b', 'worker_update', 'w@x.invalid'),
    row('c', 'company_update', 'r1@e.invalid'), row('c', 'company_update', 'r2@e.invalid')] });
  const s = await send.runBatch(t.deps);
  assert.deepEqual(t.calls.sent.map((e) => e.to).sort(), ['r1@e.invalid', 'r2@e.invalid', 'w@x.invalid']);
  assert.deepEqual(markOf(t.calls, 'a'), { id: 'a', result: 'sent', code: null, messages: 1 });
  assert.deepEqual(markOf(t.calls, 'c'), { id: 'c', result: 'sent', code: null, messages: 2 });
  assert.equal(s.emails, 3);
  assert.equal(t.calls.quit, 1);
});

test('rodada: motivos da mesma empresa no mesmo e-mail; tipos diferentes no mesmo endereço não se misturam', async () => {
  const t = makeDeps({ rows: [row('a', 'company_update', 'r@e.invalid', 300, 'released'), row('b', 'company_update', 'r@e.invalid', 300, 'closed'),
    row('c', 'worker_update', 'r@e.invalid', 300, 'update')] });
  const s = await send.runBatch(t.deps);
  assert.equal(s.emails, 2);
  const company = t.calls.sent.find((e) => e.body.includes('#entrar-empresa'));
  assert.match(company.body, /nova manifestação[\s\S]*foi encerrada/);
  assert.ok(t.calls.sent.some((e) => e.subject === send.WORKER_SUBJECT));
  assert.ok(['a', 'b', 'c'].every((id) => markOf(t.calls, id).result === 'sent'));
});

test('rodada: aviso à empresa não cadastrada sai sozinho, um por linha, e conta no teto', async () => {
  const t = makeDeps({ rows: [row('n1', 'company_notice', 'c@e.invalid', 2, 'notice'), row('n2', 'company_notice', 'c@e.invalid', 2, 'notice'),
    row('u', 'company_update', 'c@e.invalid', 2, 'released')] });
  const s = await send.runBatch(t.deps);
  assert.equal(s.emails, 2);
  assert.equal(t.calls.sent.filter((e) => e.subject === send.NOTICE_SUBJECT).length, 2);
  assert.deepEqual(markOf(t.calls, 'n1'), { id: 'n1', result: 'sent', code: null, messages: 1 });
  assert.deepEqual(markOf(t.calls, 'u'), { id: 'u', result: 'release', code: 'daily_cap', messages: 0 });
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
  assert.equal(s.stopped, 'smtp_auth');
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

test('rodada: 421 ao abrir e cota no meio param o lote sem gastar tentativa', async () => {
  const busy = new Error('421'); busy.stop = 'smtp_421';
  let t = makeDeps({ rows: [row('a', 'worker_update', 'a@x.invalid')], openError: busy });
  let s = await send.runBatch(t.deps);
  assert.equal(s.stopped, 'smtp_421');
  assert.deepEqual(markOf(t.calls, 'a'), { id: 'a', result: 'release', code: 'smtp_421', messages: 0 });
  const quota = new Error('5.4.5'); quota.stop = 'smtp_quota';
  t = makeDeps({ rows: [row('a', 'worker_update', 'a@x.invalid'), row('b', 'worker_update', 'b@x.invalid')] });
  t.deps.openMailer = async () => ({ async send(to) { if (to === 'a@x.invalid') throw quota; }, async quit() {} });
  s = await send.runBatch(t.deps);
  assert.equal(s.stopped, 'smtp_quota');
  assert.deepEqual(markOf(t.calls, 'a'), { id: 'a', result: 'release', code: 'smtp_quota', messages: 0 });
  assert.deepEqual(markOf(t.calls, 'b'), { id: 'b', result: 'release', code: 'smtp_quota', messages: 0 });
});

test('rodada: orçamento de tempo para de enviar e devolve o restante', async () => {
  let clock = 0;
  const t = makeDeps({ rows: [row('a', 'worker_update', 'a@x.invalid'), row('b', 'worker_update', 'b@x.invalid')] });
  t.deps.now = () => clock;
  t.deps.openMailer = async () => ({ async send() { clock += 25000; }, async quit() {} });
  await send.runBatch(t.deps);
  assert.equal(markOf(t.calls, 'a').result, 'sent');
  assert.deepEqual(markOf(t.calls, 'b'), { id: 'b', result: 'release', code: 'time_budget', messages: 0 });
  assert.equal(send.DEFAULT_LIMIT, 20);
  assert.equal(send.TIME_BUDGET_MS, 20000);
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
  assert.deepEqual([...new Set([...src.matchAll(/rpc\('([a-z_]+)'/g)].map((m) => m[1]))].sort(), ['notification_claim', 'notification_mark']);
  assert.match(src, /p_include_notices: true/);
  assert.match(src, /PGRST202/);
  assert.match(src, /FROM_NAME = 'RH Escuta\.Aí'/);
  assert.equal((src.match(/console\.log/g) ?? []).length, 3);
  assert.doesNotMatch(src, /console\.log\([^)]*\b(email|to|gmailUser|password)\b/i);
  assert.match(src, /clearTimeout\(timer\)/);
  assert.match(src, /runBatch\(deps, DEFAULT_LIMIT\)/);
  assert.match(src, /pickKey\('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY'\)/);
});
