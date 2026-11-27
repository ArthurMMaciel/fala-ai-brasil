// Lógica de uma rodada da send-notifications (ADR-0020, runbook EMAIL_NOTIFICATIONS). Sem APIs do Deno: o index.ts
// injeta banco, SMTP, log e relógio; scripts/test-send-notifications.mjs testa com SMTP simulado.
//
// Regras:
// - um e-mail por destinatário e tipo por rodada, com as pendências dele (agrupamento por tipo e endereço); o aviso à
//   empresa não cadastrada (company_notice) sai sempre sozinho;
// - teto do dia: no máximo `remaining_today` e-mails; o que não couber volta a 'pending' sem gastar tentativa;
// - texto fixo por tipo e motivo (message), com link em texto, sem protocolo, empresa, situação nem conteúdo;
// - parada do lote sem gastar tentativa: erro de autenticação SMTP, 421 e códigos estendidos de cota (4.7.x, 5.4.5);
// - orçamento de tempo: perto de 20 s a rodada para de enviar e devolve o restante (o Cron chama a cada 5 min);
// - outro erro num destinatário: as linhas dele vão para nova tentativa (5 min, 30 min, 2 h, 6 h, 24 h; depois 'failed');
// - log só com id da linha, tipo, resultado e tempo.

export type Kind = 'worker_update' | 'company_update' | 'company_notice';
export type Reason = 'update' | 'released' | 'closed' | 'response_returned' | 'notice';
export interface ClaimRow { outbox_id: string; kind: Kind; reason?: Reason | null; email: string; remaining_today: number }
export type MarkResult = 'sent' | 'retry' | 'release';

export interface Mailer {
  send(to: string, subject: string, body: string): Promise<void>;
  quit(): Promise<void>;
}

export interface Deps {
  claim(limit: number): Promise<ClaimRow[]>;
  mark(id: string, result: MarkResult, errorCode: string | null, messages: number): Promise<void>;
  openMailer(): Promise<Mailer>;  // pode lançar erro de autenticação ou de cota
  stopCode(e: unknown): string | null;  // 'smtp_auth', 'smtp_421', 'smtp_quota' ou null
  errorCode(e: unknown): string;
  log(event: { id: string; kind: Kind; result: string; ms: number }): void;
  now(): number;
}

export const SITE_URL = 'https://fala-ai-brasil.vercel.app';
export const WORKER_LINK = `${SITE_URL}/#entrar`;
export const COMPANY_LINK = `${SITE_URL}/#entrar-empresa`;
export const NOTICE_LINK = `${SITE_URL}/empresa`;
const SAFETY = 'Por segurança, este e-mail não traz detalhes.';

// Uma frase fixa por motivo (empresa cadastrada). Linhas antigas, sem motivo, usam a genérica ('update').
const COMPANY_LINES: Record<string, string> = {
  released: 'Sua empresa acabou de receber uma nova manifestação na Escuta Aí Brasil.',
  response_returned: 'A equipe da Escuta Aí Brasil pediu um ajuste em uma resposta da sua empresa.',
  closed: 'Uma manifestação da sua empresa foi encerrada.',
  update: 'Há uma atualização para a sua empresa na Escuta Aí Brasil.',
};
const COMPANY_SUBJECTS: Record<string, string> = {
  released: 'Nova manifestação para a sua empresa na Escuta Aí Brasil',
  response_returned: 'Pedido de ajuste em uma resposta na Escuta Aí Brasil',
  closed: 'Uma manifestação da sua empresa foi encerrada na Escuta Aí Brasil',
  update: 'Há novidades para a sua empresa na Escuta Aí Brasil',
};
export const WORKER_SUBJECT = 'Há uma novidade na sua manifestação na Escuta Aí Brasil';
export const NOTICE_SUBJECT = 'Existe uma manifestação sobre a sua empresa na Escuta Aí Brasil';

// Texto fixo por tipo e motivos, sem protocolo, categoria, empresa, situação nem conteúdo.
// Trabalhador: com o caminho do opt-out (ADR-0020 D8). Empresa cadastrada: aviso de serviço da conta. Empresa não
// cadastrada (ADR-0023): quem é a plataforma, que existe uma manifestação, o link público e o pedido de exclusão por resposta.
export function message(kind: Kind, reasons: Set<string> = new Set()): { subject: string; body: string } {
  if (kind === 'worker_update') {
    return { subject: WORKER_SUBJECT, body: [
      'Olá.', '',
      'Há uma novidade na sua manifestação na Escuta Aí Brasil.',
      `Para ver, entre na plataforma: ${WORKER_LINK}`, '',
      SAFETY, '',
      'Você recebe este aviso porque tem uma conta na Escuta Aí Brasil. Para não receber mais, desligue os avisos em Meu perfil.',
    ].join('\n') };
  }
  if (kind === 'company_notice') {
    return { subject: NOTICE_SUBJECT, body: [
      'Olá.', '',
      'A Escuta Aí Brasil é uma plataforma em que trabalhadores registram manifestações sobre o ambiente de trabalho, e as empresas podem recebê-las e responder.',
      '',
      'Existe uma manifestação sobre a sua empresa na plataforma. Para saber como a empresa pode se cadastrar e acompanhar, acesse:',
      NOTICE_LINK, '',
      SAFETY, '',
      'Se não quiser receber novos avisos da Escuta Aí Brasil neste endereço, responda a este e-mail pedindo a exclusão.',
    ].join('\n') };
  }
  const order = ['released', 'response_returned', 'closed', 'update'];
  const known = order.filter((r) => reasons.has(r));
  const list = known.length ? known : ['update'];
  return {
    subject: list.length === 1 ? COMPANY_SUBJECTS[list[0]] : COMPANY_SUBJECTS.update,
    body: [
      'Olá.', '',
      ...list.map((r) => COMPANY_LINES[r]),
      `${list.includes('released') ? 'Para ver e responder' : 'Para ver'}, entre na plataforma: ${COMPANY_LINK}`, '',
      SAFETY, '',
      'Você recebe este aviso porque representa uma empresa verificada na Escuta Aí Brasil.',
    ].join('\n'),
  };
}

export interface Summary { claimed: number; emails: number; sent: number; failed: number; deferred: number; stopped: string | null }

export const DEFAULT_LIMIT = 20;
export const TIME_BUDGET_MS = 20000;

export async function runBatch(deps: Deps, limit = DEFAULT_LIMIT, budgetMs = TIME_BUDGET_MS): Promise<Summary> {
  const startedAt = deps.now();
  const rows = await deps.claim(limit);
  const summary: Summary = { claimed: 0, emails: 0, sent: 0, failed: 0, deferred: 0, stopped: null };
  if (rows.length === 0) return summary;

  // Estado por linha da fila e agrupamento por destinatário.
  const outbox = new Map<string, { kind: Kind; started: number; delivered: number; failed: string | null; deferred: boolean; deferCode: string }>();
  // Grupo = tipo + endereço; o aviso à empresa não cadastrada sai sempre sozinho (um e-mail por aviso).
  const byEmail = new Map<string, { email: string; kind: Kind; ids: Set<string>; reasons: Set<string> }>();
  for (const r of rows) {
    if (!outbox.has(r.outbox_id)) outbox.set(r.outbox_id, { kind: r.kind, started: deps.now(), delivered: 0, failed: null, deferred: false, deferCode: 'daily_cap' });
    const email = r.email.trim().toLowerCase();
    const key = r.kind === 'company_notice' ? `${r.kind}:${r.outbox_id}:${email}` : `${r.kind}:${email}`;
    const g = byEmail.get(key) ?? { email, kind: r.kind, ids: new Set<string>(), reasons: new Set<string>() };
    g.ids.add(r.outbox_id);
    if (r.reason) g.reasons.add(r.reason);
    byEmail.set(key, g);
  }
  summary.claimed = outbox.size;
  const remaining = Math.max(0, Math.min(...rows.map((r) => r.remaining_today)));
  const groups = [...byEmail.keys()];

  let mailer: Mailer | null = null;
  let stop = false;
  let deferCode = 'daily_cap';
  try {
    mailer = await deps.openMailer();
  } catch (e) {
    stop = true;
    summary.stopped = deps.stopCode(e);
    if (summary.stopped) deferCode = summary.stopped;
    else for (const s of outbox.values()) s.failed = deps.errorCode(e);  // falha de conexão: nova tentativa
  }

  for (const [i, key] of groups.entries()) {
    const g = byEmail.get(key)!;
    if (!stop && deps.now() - startedAt >= budgetMs) { stop = true; deferCode = 'time_budget'; }
    if (stop || i >= remaining) {
      for (const id of g.ids) { const s = outbox.get(id)!; s.deferred = true; s.deferCode = stop ? deferCode : 'daily_cap'; }
      continue;
    }
    try {
      const m = message(g.kind, g.reasons);
      await mailer!.send(g.email, m.subject, m.body);
      summary.emails += 1;
      for (const id of g.ids) outbox.get(id)!.delivered += 1;
    } catch (e) {
      const sc = deps.stopCode(e);
      if (sc) {
        stop = true;
        summary.stopped = sc;
        deferCode = sc;
        for (const id of g.ids) { const s = outbox.get(id)!; s.deferred = true; s.deferCode = sc; }
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
    else if (s.deferred) { result = 'release'; code = s.deferCode; summary.deferred += 1; }
    else { result = 'sent'; summary.sent += 1; }
    await deps.mark(id, result, code, result === 'sent' ? s.delivered : 0);
    deps.log({ id, kind: s.kind, result, ms: Math.max(0, Math.round(deps.now() - s.started)) });
  }
  return summary;
}
