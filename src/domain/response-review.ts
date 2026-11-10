// Resposta da empresa revisada pela equipe (ADR-0013, TASK-0035): validações com as mesmas faixas e mensagens do banco.

export function validateWorkerSummary(value: string): string | null {
  const length = value.trim().length;
  return length < 30 || length > 1000 ? "Escreva a descrição para o trabalhador com 30 a 1.000 caracteres." : null;
}

export function validateReturnReason(value: string): string | null {
  const length = value.trim().length;
  return length < 10 || length > 500 ? "Explique à empresa o motivo da devolução com 10 a 500 caracteres." : null;
}

export function validateCorrectionReason(value: string): string | null {
  const length = value.trim().length;
  return length < 10 || length > 500 ? "Informe o motivo da correção com 10 a 500 caracteres." : null;
}

export function validateRatingComment(value: string): string | null {
  return value.trim().length > 300 ? "O comentário pode ter até 300 caracteres." : null;
}

/** "Descrição corrigida em DD/MM" quando a equipe corrigiu o texto depois da liberação. */
export function correctedLabel(summaryCorrectedAt: string | null | undefined): string | null {
  if (!summaryCorrectedAt) return null;
  const date = new Date(summaryCorrectedAt);
  if (Number.isNaN(date.getTime())) return null;
  return `Descrição corrigida em ${new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit" }).format(date)}`;
}

/** Tempo de espera em relação ao prazo de 2 dias úteis (aproximado em 48 h corridas para o destaque visual). */
export function reviewOverdue(waitingHours: number | null | undefined): boolean {
  return typeof waitingHours === "number" && waitingHours > 48;
}
