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
