// Lógica de uma rodada da send-notifications (ADR-0020, runbook EMAIL_NOTIFICATIONS). Sem APIs do Deno: o index.ts
// injeta banco, SMTP, log e relógio; scripts/test-send-notifications.mjs testa com SMTP simulado.
//
// Regras:
// - um e-mail por destinatário por rodada, com todas as pendências dele (agrupamento por endereço);
// - teto do dia: no máximo `remaining_today` e-mails; o que não couber volta a 'pending' sem gastar tentativa;
// - texto fixo e genérico, com link em texto, sem protocolo, empresa, situação nem conteúdo;
// - erro de autenticação SMTP: o lote para, nada gasta tentativa;
// - outro erro num destinatário: as linhas dele vão para nova tentativa (5 min, 30 min, 2 h, 6 h, 24 h; depois 'failed');
// - log só com id da linha, tipo, resultado e tempo.

export type Kind = 'worker_update' | 'company_update';
export interface ClaimRow { outbox_id: string; kind: Kind; email: string; remaining_today: number }
export type MarkResult = 'sent' | 'retry' | 'release';

export interface Mailer {
  send(to: string, subject: string, body: string): Promise<void>;
  quit(): Promise<void>;
}

export interface Deps {
  claim(limit: number): Promise<ClaimRow[]>;
  mark(id: string, result: MarkResult, errorCode: string | null, messages: number): Promise<void>;
  openMailer(): Promise<Mailer>;  // pode lançar erro de autenticação
  isAuthError(e: unknown): boolean;
  errorCode(e: unknown): string;
  log(event: { id: string; kind: Kind; result: string; ms: number }): void;
  now(): number;
}

export const SITE_URL = 'https://fala-ai-brasil.vercel.app';
export const SUBJECT = 'Há uma atualização na sua conta Escuta Aí Brasil';

// Texto fixo. Trabalhador: com o caminho do opt-out (ADR-0020 D8). Empresa: sem opt-out (aviso de serviço da conta).
export function messageBody(kinds: Set<Kind>): string {
  const lines = [
    'Olá.',
    '',
    'Há uma atualização na sua conta Escuta Aí Brasil.',
    `Para ver, entre na plataforma: ${SITE_URL}`,
    '',
    'Por segurança, este e-mail não traz detalhes. Nenhuma informação foi enviada a terceiros.',
  ];
  if (kinds.has('worker_update')) {
    lines.push('', 'Você recebe este aviso porque tem uma conta na Escuta Aí Brasil. Para não receber mais, desligue os avisos em Meu perfil.');
  } else {
    lines.push('', 'Você recebe este aviso porque representa uma empresa verificada na Escuta Aí Brasil.');
  }
  return lines.join('\n');
}

export interface Summary { claimed: number; emails: number; sent: number; failed: number; deferred: number; authError: boolean }

export async function runBatch(deps: Deps, limit = 50): Promise<Summary> {
  const rows = await deps.claim(limit);
  const summary: Summary = { claimed: 0, emails: 0, sent: 0, failed: 0, deferred: 0, authError: false };
  if (rows.length === 0) return summary;

  // Estado por linha da fila e agrupamento por destinatário.
  const outbox = new Map<string, { kind: Kind; started: number; delivered: number; failed: string | null; deferred: boolean }>();
  const byEmail = new Map<string, { ids: Set<string>; kinds: Set<Kind> }>();
  for (const r of rows) {
    if (!outbox.has(r.outbox_id)) outbox.set(r.outbox_id, { kind: r.kind, started: deps.now(), delivered: 0, failed: null, deferred: false });
    const email = r.email.trim().toLowerCase();
    const g = byEmail.get(email) ?? { ids: new Set<string>(), kinds: new Set<Kind>() };
    g.ids.add(r.outbox_id);
    g.kinds.add(r.kind);
    byEmail.set(email, g);
  }
  summary.claimed = outbox.size;
  const remaining = Math.max(0, Math.min(...rows.map((r) => r.remaining_today)));
  const emails = [...byEmail.keys()];

  let mailer: Mailer | null = null;
  let stop = false;
  try {
    mailer = await deps.openMailer();
  } catch (e) {
    stop = true;
    summary.authError = deps.isAuthError(e);
    if (!summary.authError) for (const s of outbox.values()) s.failed = deps.errorCode(e);  // falha de conexão: nova tentativa
  }

  for (const [i, email] of emails.entries()) {
    const g = byEmail.get(email)!;
    if (stop || i >= remaining) {
      for (const id of g.ids) outbox.get(id)!.deferred = true;
      continue;
    }
    try {
      await mailer!.send(email, SUBJECT, messageBody(g.kinds));
      summary.emails += 1;
      for (const id of g.ids) outbox.get(id)!.delivered += 1;
    } catch (e) {
      if (deps.isAuthError(e)) {
        stop = true;
        summary.authError = true;
        for (const id of g.ids) outbox.get(id)!.deferred = true;
      } else {
        const code = deps.errorCode(e);
        for (const id of g.ids) outbox.get(id)!.failed = code;
      }
    }
  }
  if (mailer) await mailer.quit();

  // Falha em qualquer destinatário da linha: nova tentativa da linha (os já entregues podem receber de novo: texto genérico).
  for (const [id, s] of outbox) {
    let result: MarkResult;
    let code: string | null = null;
    if (s.failed) { result = 'retry'; code = s.failed; summary.failed += 1; }
    else if (s.deferred || (stop && summary.authError)) { result = 'release'; code = summary.authError ? 'smtp_auth' : 'daily_cap'; summary.deferred += 1; }
    else { result = 'sent'; summary.sent += 1; }
    await deps.mark(id, result, code, result === 'sent' ? s.delivered : 0);
    deps.log({ id, kind: s.kind, result, ms: Math.max(0, Math.round(deps.now() - s.started)) });
  }
  return summary;
}
