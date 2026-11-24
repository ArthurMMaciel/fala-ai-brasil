// Fila de revisão da Operação (TASK-0044, item 8): quem espera há mais tempo aparece primeiro.

/** Tempo de espera em texto curto: "há menos de 1 h", "há 5 h", "há 2 dias". */
export function waitingLabel(since: string, now: Date = new Date()): string {
  const hours = Math.floor((now.getTime() - Date.parse(since)) / 3_600_000);
  if (!Number.isFinite(hours) || hours < 1) return "há menos de 1 h";
  if (hours < 48) return `há ${hours} h`;
  return `há ${Math.floor(hours / 24)} dias`;
}

/** Mais antigos primeiro, pela última atualização (quando a revisão foi pedida ou retida). */
export function oldestFirst<T extends { updatedAt: string }>(rows: readonly T[]): T[] {
  return [...rows].sort((a, b) => Date.parse(a.updatedAt) - Date.parse(b.updatedAt));
}

// O banco grava o motivo na trilha com o prefixo "Ajuste solicitado pela equipe: " (31 caracteres) e a nota tem até 500.
// Acima de 469 caracteres a RPC ops_decide_complaint falha; o limite fica aqui e no campo.
export const opsReasonMax = 469;

/** Mensagem de erro do motivo da decisão da Operação, ou null quando está válido. */
export function validateOpsReason(decision: "released" | "adjustment_requested" | "held", reason: string): string | null {
  const length = reason.trim().length;
  if (length > opsReasonMax) return `O motivo pode ter até ${opsReasonMax} caracteres (agora tem ${length}).`;
  if (decision !== "released" && length < 10) return "Explique o motivo com pelo menos 10 caracteres.";
  return null;
}

// Próximo passo depois de "Liberar para a empresa" (pedido do responsável, 2026-11-23), com os dados que a Operação
// já carrega: empresas a conferir (sem conta) e representantes verificados. Sem a função no banco, o caso fica "unknown".
export type ReleaseDelivery = "verified" | "unverified" | "unregistered" | "unknown";
export type ReleaseView = "responses" | "representatives" | "pending-companies" | "notices" | "companies";

export function releaseDelivery(companyId: string, verifiedCompanyIds: ReadonlySet<string> | null, pendingCompanyIds: ReadonlySet<string> | null): ReleaseDelivery {
  if (pendingCompanyIds?.has(companyId)) return "unregistered";
  if (!verifiedCompanyIds) return "unknown";
  return verifiedCompanyIds.has(companyId) ? "verified" : "unverified";
}

// before: texto mostrado antes da liberação ("Depois de liberar"); sem before, o que já aconteceu ("Próximo passo").
export function releaseNextStep(delivery: ReleaseDelivery, before = false): { text: string; links: { view: ReleaseView; label: string }[] } {
  if (delivery === "verified") return { text: `${before ? "Vai chegar" : "Chegou"} à empresa; a resposta volta em Manifestações → Respostas da empresa.`, links: [{ view: "responses", label: "Abrir Respostas da empresa" }] };
  if (delivery === "unverified") return { text: "A empresa ainda não tem representante verificado: veja Empresas → Representantes.", links: [{ view: "representatives", label: "Abrir Representantes" }] };
  if (delivery === "unregistered") return { text: "Empresa sem conta: confira em Empresas → A conferir e decida o aviso em Empresas → Avisos.", links: [{ view: "pending-companies", label: "Abrir A conferir" }, { view: "notices", label: "Abrir Avisos" }] };
  return { text: "Confira a situação da empresa em Empresas.", links: [{ view: "companies", label: "Abrir Empresas" }] };
}
// Cartão "E-mails da plataforma" (ADR-0020): fica vermelho com falha, parada por senha ou por cota (pedido do Gestor,
// 2026-11-24). O texto separa a senha recusada (incidente, pausa do piloto) de cota ou falha.
export type NotificationAlert = "incident" | "attention" | "ok";
export function notificationAlert(stats: { failed: number; stoppedAuth24h: number; stoppedQuota24h: number }): NotificationAlert {
  if (stats.stoppedAuth24h > 0) return "incident";
  return stats.stoppedQuota24h > 0 || stats.failed > 0 ? "attention" : "ok";
}
export const notificationAlertText: Record<NotificationAlert, string> = {
  incident: "Envio parado: o Gmail recusou a senha. Confira o Gmail e siga o runbook EMAIL_NOTIFICATIONS.",
  attention: "Há falhas ou limite do Gmail. Confira o Gmail; veja o runbook EMAIL_NOTIFICATIONS.",
  ok: "Fila funcionando.",
};