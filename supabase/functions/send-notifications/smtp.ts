// Cliente SMTP mínimo para o Gmail na porta 465 (TLS direto), sem dependência externa (ADR-0020).
// A conexão é injetada: o index.ts usa Deno.connectTls; scripts/test-send-notifications.mjs usa um servidor simulado.
// Nada daqui registra log: e-mail, senha e texto do servidor nunca saem da função.

export interface SmtpConn {
  readLine(): Promise<string | null>;  // uma linha sem o \r\n; null no fim da conexão
  write(text: string): Promise<void>;
  close(): void;
}

export class SmtpAuthError extends Error {
  constructor() { super('smtp_auth'); }
}
export class SmtpError extends Error {
  code: string;
  constructor(code: string) { super('smtp_' + code); this.code = code; }
}

interface Reply { code: number; lines: string[] }

async function readReply(conn: SmtpConn): Promise<Reply> {
  const lines: string[] = [];
  for (;;) {
    const line = await conn.readLine();
    if (line === null) throw new SmtpError('closed');
    lines.push(line);
    if (!/^\d{3}-/.test(line)) break;  // "250-..." continua; "250 ..." termina
  }
  const code = Number(lines[lines.length - 1].slice(0, 3));
  if (!Number.isFinite(code)) throw new SmtpError('bad_reply');
  return { code, lines };
}

async function command(conn: SmtpConn, line: string | null, expect: number[]): Promise<Reply> {
  if (line !== null) await conn.write(line + '\r\n');
  const reply = await readReply(conn);
  if (!expect.includes(reply.code)) throw new SmtpError(String(reply.code));
  return reply;
}

function b64(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

// Cabeçalho com acento (RFC 2047) e corpo em base64 (sem 8bit e sem "." no início de linha).
export function buildMessage(from: string, fromName: string, to: string, subject: string, body: string, now: Date, id: string): string {
  const wrapped = (b64(body).match(/.{1,76}/g) ?? []).join('\r\n');
  return [
    `From: =?UTF-8?B?${b64(fromName)}?= <${from}>`,
    `To: <${to}>`,
    `Subject: =?UTF-8?B?${b64(subject)}?=`,
    `Date: ${now.toUTCString()}`,
    `Message-ID: <${id}@escutaai.invalid>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    wrapped,
  ].join('\r\n');
}

const SAFE_ADDRESS = /^[^\s<>@,;:"]+@[^\s<>@,;:"]+\.[^\s<>@,;:"]+$/;

export class SmtpClient {
  private constructor(private conn: SmtpConn, private user: string) {}

  // Saudação, EHLO e AUTH LOGIN. Falha de autenticação vira SmtpAuthError (o lote para sem gastar tentativa).
  static async open(conn: SmtpConn, user: string, password: string, heloName = 'escutaai.invalid'): Promise<SmtpClient> {
    try {
      await command(conn, null, [220]);
      await command(conn, `EHLO ${heloName}`, [250]);
      await command(conn, 'AUTH LOGIN', [334]);
      await command(conn, b64(user), [334]);
      await conn.write(b64(password) + '\r\n');
      const reply = await readReply(conn);
      if (reply.code !== 235) {
        if ([530, 534, 535].includes(reply.code)) throw new SmtpAuthError();
        throw new SmtpError(String(reply.code));
      }
      return new SmtpClient(conn, user);
    } catch (e) {
      conn.close();
      throw e;
    }
  }

  async send(to: string, message: string): Promise<void> {
    if (!SAFE_ADDRESS.test(to)) throw new SmtpError('bad_address');
    await command(this.conn, `MAIL FROM:<${this.user}>`, [250]);
    try {
      await command(this.conn, `RCPT TO:<${to}>`, [250, 251]);
      await command(this.conn, 'DATA', [354]);
      await command(this.conn, message + '\r\n.', [250]);
    } catch (e) {
      // Volta a sessão ao estado inicial para o próximo destinatário.
      try { await command(this.conn, 'RSET', [250]); } catch { /* conexão perdida: o próximo envio acusa */ }
      throw e;
    }
  }

  async quit(): Promise<void> {
    try { await command(this.conn, 'QUIT', [221]); } catch { /* fecha mesmo assim */ }
    this.conn.close();
  }
}
