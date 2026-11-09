// Situações da manifestação, na ordem do enum public.complaint_status (migrations). O teste
// scripts/test-complaint-status.mjs compara esta lista e os mapas de rótulo dos portais com as migrations.
export const complaintStatusOrder = ["received", "in_review", "adjustment_requested", "held", "shared", "answered", "closed", "canceled"] as const;

/** Texto exibido quando o banco devolve uma situação que o front ainda não conhece (evita selo vazio). */
export const unknownStatusLabel = "Situação em atualização";

/** Rótulo (ou classe) de uma situação, com fallback para valor ausente ou desconhecido. */
export function statusLabel(map: Readonly<Record<string, string>>, status: string | null | undefined, fallback = unknownStatusLabel): string {
  return status && Object.prototype.hasOwnProperty.call(map, status) ? map[status] : fallback;
}

// Desempate das linhas do tempo, igual ao do banco (migration 20261109120000): created_at; tipo do item
// (a causa antes do evento que ela gera: review 1, response 2, access 3, event 4); ordem do enum; id.
const kindRank: Record<string, number> = { review: 1, response: 2, access: 3, event: 4 };
export interface TimelineSortable { kind: string; status: string | null; createdAt: string; id?: string }

export function compareTimeline(a: TimelineSortable, b: TimelineSortable): number {
  const time = Date.parse(a.createdAt) - Date.parse(b.createdAt);
  if (time) return time;
  if (a.createdAt !== b.createdAt) return a.createdAt < b.createdAt ? -1 : 1; // microssegundos além do milissegundo
  const kind = (kindRank[a.kind] ?? 9) - (kindRank[b.kind] ?? 9);
  if (kind) return kind;
  const rank = (status: string | null) => { const index = complaintStatusOrder.indexOf(status as (typeof complaintStatusOrder)[number]); return index < 0 ? complaintStatusOrder.length : index; };
  const status = rank(a.status) - rank(b.status);
  if (status) return status;
  const idA = a.id ?? "", idB = b.id ?? "";
  return idA === idB ? 0 : idA < idB ? -1 : 1; // mesma ordem do uuid no Postgres (hex minúsculo)
}
