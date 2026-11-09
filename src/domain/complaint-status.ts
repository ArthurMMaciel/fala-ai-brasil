// Situações da manifestação, na ordem do enum public.complaint_status (migrations). O teste
// scripts/test-complaint-status.mjs compara esta lista e os mapas de rótulo dos portais com as migrations.
export const complaintStatusOrder = ["received", "in_review", "adjustment_requested", "held", "shared", "answered", "closed", "canceled"] as const;

/** Texto exibido quando o banco devolve uma situação que o front ainda não conhece (evita selo vazio). */
export const unknownStatusLabel = "Situação em atualização";

/** Rótulo (ou classe) de uma situação, com fallback para valor ausente ou desconhecido. */
export function statusLabel(map: Readonly<Record<string, string>>, status: string | null | undefined, fallback = unknownStatusLabel): string {
  return status && Object.prototype.hasOwnProperty.call(map, status) ? map[status] : fallback;
}
