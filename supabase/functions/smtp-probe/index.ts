// Função DESCARTÁVEL (ADR-0020 D2, teste de 2026-11-24). Publicar, chamar uma vez e APAGAR no mesmo dia.
// Só responde se a Edge Function consegue abrir TLS em smtp.gmail.com:465 e receber a saudação SMTP "220".
// Não autentica, não envia e-mail, não usa segredo. Responde só o código da saudação, sem o texto do servidor.
// Roteiro: docs/runbooks/EMAIL_NOTIFICATIONS.md, seção "Teste da porta 465".

const HOST = 'smtp.gmail.com';
const PORT = 465;
const TIMEOUT_MS = 5000;

async function probe(): Promise<{ tls: boolean; code: string | null; error: string | null; ms: number }> {
  const started = performance.now();
  let conn: Deno.TlsConn | null = null;
  const timer = setTimeout(() => { try { conn?.close(); } catch { /* já fechada */ } }, TIMEOUT_MS);
  try {
    conn = await Deno.connectTls({ hostname: HOST, port: PORT });
    const buf = new Uint8Array(512);
    const n = await conn.read(buf);
    const text = n ? new TextDecoder().decode(buf.subarray(0, n)) : '';
    const code = /^\d{3}/.exec(text)?.[0] ?? null;
    try { await conn.write(new TextEncoder().encode('QUIT\r\n')); } catch { /* ignora */ }
    return { tls: true, code, error: null, ms: Math.round(performance.now() - started) };
  } catch (e) {
    // Só o nome da classe do erro (ex.: PermissionDenied, ConnectionRefused, TimedOut), sem mensagem do servidor.
    const name = e instanceof Error ? e.name : 'Error';
    return { tls: false, code: null, error: name, ms: Math.round(performance.now() - started) };
  } finally {
    clearTimeout(timer);
    try { conn?.close(); } catch { /* já fechada */ }
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method_not_allowed', { status: 405 });
  const result = await probe();
  return new Response(JSON.stringify({ host: HOST, port: PORT, ...result, open: result.code === '220' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
