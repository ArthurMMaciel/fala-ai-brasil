// Situações da manifestação, na ordem do enum public.complaint_status (migrations). O teste
// scripts/test-complaint-status.mjs compara esta lista e os mapas de rótulo dos portais com as migrations.
export const complaintStatusOrder = ["received", "in_review", "adjustment_requested", "held", "shared", "answer_in_review", "answered", "closed", "canceled"] as const;

/** Texto exibido quando o banco devolve uma situação que o front ainda não conhece (evita selo vazio). */
export const unknownStatusLabel = "Situação em atualização";

/** Rótulo (ou classe) de uma situação, com fallback para valor ausente ou desconhecido. */
export function statusLabel(map: Readonly<Record<string, string>>, status: string | null | undefined, fallback = unknownStatusLabel): string {
  return status && Object.prototype.hasOwnProperty.call(map, status) ? map[status] : fallback;
}

// Desempate das linhas do tempo, igual ao do banco (migration 20261109120000): created_at; tipo do item
// (a causa antes do evento que ela gera: review 1, response 2, access 3, event 4); ordem do enum; id.
const kindRank: Record<string, number> = { review: 1, response_review: 1, response: 2, access: 3, event: 4 };
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

/**
 * Título que a empresa vê, sem repetir o protocolo. Com o lote 3 do Back (2026-11-23) a empresa recebe
 * "Manifestação EAB-…" no título; quando ele só repete o protocolo, a tela mostra o protocolo uma vez. O contrato não muda.
 */
export function companyFacingTitle(title: string | null | undefined, protocol: string | null | undefined): string | null {
  const text = String(title ?? "").trim();
  if (!text) return null;
  const norm = (value: string) => value.toLocaleLowerCase("pt-BR").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/\s+/g, " ").trim();
  const code = norm(String(protocol ?? ""));
  const value = norm(text);
  return code && (value === code || value === `manifestacao ${code}`) ? null : text;
}