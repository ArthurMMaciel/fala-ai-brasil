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
