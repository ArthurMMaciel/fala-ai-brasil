// Edge Function send-notifications (ADR-0020; runbook docs/runbooks/EMAIL_NOTIFICATIONS.md).
// Chamada só pelo Cron (pg_cron + pg_net), a cada 5 minutos, com o cabeçalho x-cron-secret. Publicada com
// --no-verify-jwt: a proteção é o segredo do agendador, comparado em tempo constante com NOTIFY_CRON_SECRET.
// Secrets (definidos pelo responsável): GMAIL_USER, GMAIL_APP_PASSWORD, NOTIFY_CRON_SECRET. Banco: só as RPCs
// notification_claim e notification_mark, com a chave de serviço injetada pelo Supabase (nova ou, na falta, a legada).
// Logs: só id da linha, tipo, resultado e tempo. Resposta: só contagens.
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { runBatch, type ClaimRow, type MarkResult } from './send.ts';
import { buildMessage, SmtpAuthError, SmtpClient, SmtpError, type SmtpConn } from './smtp.ts';

const SMTP_HOST = 'smtp.gmail.com';
const SMTP_PORT = 465;
const SMTP_TIMEOUT_MS = 15000;
const FROM_NAME = 'Escuta Aí Brasil';

function pickKey(dictVar: string, legacyVar: string): string {
  try {
    const dict = JSON.parse(Deno.env.get(dictVar) ?? '{}') as Record<string, unknown>;
    const value = typeof dict.default === 'string' ? dict.default : Object.values(dict).find((v) => typeof v === 'string');
    if (typeof value === 'string' && value) return value;
  } catch {
    // dicionário ausente ou inválido: usa a chave legada
  }
  return Deno.env.get(legacyVar) ?? '';
}

const service = createClient(Deno.env.get('SUPABASE_URL') ?? '', pickKey('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY'),
  { auth: { persistSession: false, autoRefreshToken: false } });
const gmailUser = Deno.env.get('GMAIL_USER') ?? '';
const gmailPassword = Deno.env.get('GMAIL_APP_PASSWORD') ?? '';
const cronSecret = Deno.env.get('NOTIFY_CRON_SECRET') ?? '';

function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

// Conexão TLS direta (465) com leitura por linha e prazo por operação.
async function connect(): Promise<SmtpConn> {
  const conn = await Deno.connectTls({ hostname: SMTP_HOST, port: SMTP_PORT });
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = '';
  const withTimeout = <T>(p: Promise<T>): Promise<T> => Promise.race([
    p, new Promise<T>((_, reject) => setTimeout(() => reject(new SmtpError('timeout')), SMTP_TIMEOUT_MS)),
  ]);
  return {
    async readLine() {
      for (;;) {
        const i = buffer.indexOf('\r\n');
        if (i >= 0) { const line = buffer.slice(0, i); buffer = buffer.slice(i + 2); return line; }
        const chunk = new Uint8Array(4096);
        const n = await withTimeout(conn.read(chunk));
        if (n === null) return null;
        buffer += decoder.decode(chunk.subarray(0, n), { stream: true });
      }
    },
    async write(text: string) {
      const data = encoder.encode(text);
      let off = 0;
      while (off < data.length) off += await withTimeout(conn.write(data.subarray(off)));
    },
    close() { try { conn.close(); } catch { /* já fechada */ } },
  };
}

const deps = {
  async claim(limit: number): Promise<ClaimRow[]> {
    const { data, error } = await service.rpc('notification_claim', { p_limit: limit });
    if (error) throw new Error('claim');
    return (data ?? []) as ClaimRow[];
  },
  async mark(id: string, result: MarkResult, errorCode: string | null, messages: number) {
    const { error } = await service.rpc('notification_mark', { p_id: id, p_result: result, p_error_code: errorCode, p_messages: messages });
    if (error) throw new Error('mark');
  },
  async openMailer() {
    const client = await SmtpClient.open(await connect(), gmailUser, gmailPassword);
    return {
      send: (to: string, subject: string, body: string) =>
        client.send(to, buildMessage(gmailUser, FROM_NAME, to, subject, body, new Date(), crypto.randomUUID())),
      quit: () => client.quit(),
    };
  },
  isAuthError: (e: unknown) => e instanceof SmtpAuthError,
  errorCode: (e: unknown) => (e instanceof SmtpError ? `smtp_${e.code}`.toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 40) : 'send_error'),
  log(event: { id: string; kind: string; result: string; ms: number }) {
    console.log(JSON.stringify(event));  // sem e-mail, nome, protocolo, texto do servidor ou senha
  },
  now: () => performance.now(),
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response(null, { status: 405 });
  if (!cronSecret || !sameSecret(req.headers.get('x-cron-secret') ?? '', cronSecret)) return new Response(null, { status: 401 });
  if (!gmailUser || !gmailPassword) return Response.json({ status: 'not_configured' }, { status: 500 });
  try {
    const summary = await runBatch(deps);
    if (summary.authError) console.log(JSON.stringify({ result: 'smtp_auth_error' }));  // incidente: ver PILOT_SUSPENSION
    return Response.json(summary);
  } catch {
    console.log(JSON.stringify({ result: 'batch_error' }));
    return Response.json({ status: 'error' }, { status: 500 });
  }
});
