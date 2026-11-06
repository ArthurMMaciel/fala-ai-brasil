import { supabase, type AuthResult } from "./account";
import type { ComplaintStatusDb } from "./data";

// Área da equipe (ADR-0010): só funções do banco que exigem is_platform_admin; nada de identidade do trabalhador.
export type ReviewDecision = "released" | "adjustment_requested" | "held";

export interface OpsComplaint {
  id: string; protocol: string; companyId: string; companyName: string; category: string; title: string; status: ComplaintStatusDb;
  shared: string | null; incidentPeriod: string | null; recurrence: string | null; expectedOutcomes: string[];
  createdAt: string; updatedAt: string; responses: number; lastDecision: ReviewDecision | null; lastDecisionAt: string | null;
}
export interface OpsTimelineItem { kind: "event" | "response" | "review" | "access"; status: ComplaintStatusDb | null; actor: "worker" | "company" | "platform"; content: string; createdAt: string }
export interface OpsCompany { id: string; name: string; legalName: string; city: string; state: string; createdAt: string; users: number; complaints: number; released: number; answered: number; hasContact: boolean }
export interface OpsMetrics {
  byStatus: Partial<Record<ComplaintStatusDb, number>>; workers: number; companies: number; partners: number; sponsors: number;
  complaints30d: number; contactsWaiting: number; avgHoursToReview: number | null; avgHoursToCompanyResponse: number | null;
  weekly: { week: string; total: number }[];
}

function failure(error: { code?: string; message: string }, fallback: string) {
  return error.code === "P0001" ? error.message : error.code === "42501" ? "Seu usuário não tem acesso à área da equipe." : fallback;
}

export async function listOpsComplaints(status?: ComplaintStatusDb): Promise<OpsComplaint[]> {
  const { data, error } = await supabase().rpc("ops_list_complaints", { p_status: status ?? null });
  if (error) throw new Error(failure(error, "Não foi possível carregar as manifestações."));
  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.id), protocol: String(row.protocol), companyId: String(row.company_id), companyName: String(row.company_name), category: String(row.category),
    title: String(row.title), status: row.status as ComplaintStatusDb, shared: (row.shared_content as string | null) ?? null,
    incidentPeriod: (row.incident_period as string | null) ?? null, recurrence: (row.recurrence as string | null) ?? null,
    expectedOutcomes: (row.expected_outcomes as string[] | null) ?? [], createdAt: String(row.created_at), updatedAt: String(row.updated_at),
    responses: Number(row.responses ?? 0), lastDecision: (row.last_decision as ReviewDecision | null) ?? null, lastDecisionAt: (row.last_decision_at as string | null) ?? null,
  }));
}

export async function decideOpsComplaint(id: string, decision: ReviewDecision, reason: string): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("ops_decide_complaint", { p_id: id, p_decision: decision, p_reason: reason.trim() || null });
  return error ? { ok: false, message: failure(error, "Não foi possível registrar a decisão.") } : { ok: true, value: null };
}

export async function readOpsOriginal(id: string, justification: string): Promise<AuthResult<string>> {
  const { data, error } = await supabase().rpc("ops_read_original", { p_id: id, p_justification: justification.trim() });
  return error ? { ok: false, message: failure(error, "Não foi possível abrir o relato original.") } : { ok: true, value: String(data ?? "") };
}

export async function loadOpsTimeline(id: string): Promise<OpsTimelineItem[]> {
  const { data } = await supabase().rpc("ops_complaint_timeline", { p_id: id });
  return (data ?? []).map((row: { kind: OpsTimelineItem["kind"]; status: ComplaintStatusDb | null; actor: OpsTimelineItem["actor"]; content: string; created_at: string }) =>
    ({ kind: row.kind, status: row.status, actor: row.actor, content: row.content, createdAt: row.created_at }));
}

export async function listOpsCompanies(): Promise<OpsCompany[]> {
  const { data, error } = await supabase().rpc("ops_list_companies");
  if (error) throw new Error(failure(error, "Não foi possível carregar as empresas."));
  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.id), name: String(row.name), legalName: String(row.legal_name), city: String(row.city), state: String(row.state), createdAt: String(row.created_at),
    users: Number(row.users ?? 0), complaints: Number(row.complaints ?? 0), released: Number(row.released ?? 0), answered: Number(row.answered ?? 0), hasContact: Boolean(row.has_contact),
  }));
}

export async function loadOpsMetrics(): Promise<OpsMetrics> {
  const { data, error } = await supabase().rpc("ops_metrics");
  if (error) throw new Error(failure(error, "Não foi possível carregar os números."));
  const row = (data ?? {}) as Record<string, unknown>;
  const num = (value: unknown) => (value === null || value === undefined ? null : Number(value));
  return {
    byStatus: (row.by_status ?? {}) as OpsMetrics["byStatus"], workers: Number(row.workers ?? 0), companies: Number(row.companies ?? 0),
    partners: Number(row.partners ?? 0), sponsors: Number(row.sponsors ?? 0), complaints30d: Number(row.complaints_30d ?? 0),
    contactsWaiting: Number(row.contacts_waiting ?? 0), avgHoursToReview: num(row.avg_hours_to_review), avgHoursToCompanyResponse: num(row.avg_hours_to_company_response),
    weekly: (row.weekly ?? []) as OpsMetrics["weekly"],
  };
}
