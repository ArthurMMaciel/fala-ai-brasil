// Representante verificado (ADR-0012): a equipe confere quem representa cada empresa antes de liberar casos e números.
export type VerificationStatus = "pending" | "verified" | "rejected" | "revoked";
export type VerificationDecision = "verified" | "rejected" | "revoked";
export type VerificationMethod = "callback" | "document_review";

export const verificationStatusLabels: Record<VerificationStatus, string> = {
  pending: "Aguardando verificação",
  verified: "Verificado",
  rejected: "Recusado",
  revoked: "Revogado",
};
export const verificationDecisionLabels: Record<VerificationDecision, string> = { verified: "Verificar", rejected: "Recusar", revoked: "Revogar" };
export const verificationMethodLabels: Record<VerificationMethod, string> = {
  callback: "Ligação ao telefone público da empresa",
  document_review: "Documento conferido fora da plataforma",
};

/** Transições aceitas pelo banco (ops_verify_representative). */
export function allowedDecisions(status: VerificationStatus): VerificationDecision[] {
  if (status === "pending" || status === "rejected") return ["verified", "rejected"];
  if (status === "verified") return ["revoked"];
  return ["verified"];
}

/** Mesmas faixas do banco; a referência não pode carregar CPF, CNPJ ou outro número de documento. */
export function validateVerification(decision: VerificationDecision, method: VerificationMethod | "", evidenceRef: string, reason: string): string | null {
  if (decision === "verified") {
    if (!method) return "Informe o método: ligação ou documento conferido.";
    const ref = evidenceRef.trim();
    if (ref.length < 3 || ref.length > 200) return "Informe a referência da conferência (3 a 200 caracteres, sem número de documento).";
    if (/\d{11,}/.test(ref.replace(/[\s.\-/]/g, ""))) return "Tire o número de documento da referência. Descreva a conferência (ex.: \"ligação em 18/11, falou com o RH\").";
    return null;
  }
  const length = reason.trim().length;
  return length < 10 || length > 500 ? "Informe o motivo (10 a 500 caracteres)." : null;
}

/** O portal da empresa só mostra casos e números a representante verificado. Sem a coluna (migration ausente), segue como hoje. */
export function companyAccessPending(status: VerificationStatus | null | undefined): boolean {
  return status !== undefined && status !== null && status !== "verified";
}
