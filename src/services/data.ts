import { isAccountServiceConfigured, supabase, type AuthResult } from "./account";
import type { CampaignKind } from "../domain/account-rules";

// Acesso aos dados do modelo v3 (manifestações, Hub, landing). Regras e privacidade ficam no banco (RLS e funções).
export type ComplaintStatusDb = "received" | "shared" | "answered" | "closed" | "canceled";
export type ComplaintFeedback = "yes" | "partial" | "no";

function rpcError(error: { code?: string; message: string }, fallback: string): string {
  return error.code === "P0001" ? error.message : fallback;
}

export interface DirectoryCompany { id: string; name: string; city: string; state: string }

export async function listCompanyDirectory(): Promise<DirectoryCompany[]> {
  const { data } = await supabase().rpc("list_company_directory");
  return (data ?? []) as DirectoryCompany[];
}

export interface WorkerComplaint {
  id: string; protocol: string; companyId: string; category: string; title: string; status: ComplaintStatusDb;
  feedback: ComplaintFeedback | null; createdAt: string; incidentPeriod: string | null; recurrence: string | null; expectedOutcomes: string[];
}

export async function listWorkerComplaints(): Promise<WorkerComplaint[]> {
  const { data } = await supabase()
    .from("complaints")
    .select("id, protocol, company_id, category, title, status, worker_feedback, created_at, incident_period, recurrence, expected_outcomes")
    .order("created_at", { ascending: false });
  return (data ?? []).map(row => ({ id: row.id, protocol: row.protocol, companyId: row.company_id, category: row.category, title: row.title, status: row.status, feedback: row.worker_feedback, createdAt: row.created_at, incidentPeriod: row.incident_period, recurrence: row.recurrence, expectedOutcomes: row.expected_outcomes ?? [] }));
}

export interface TimelineItem { kind: "event" | "response"; status: ComplaintStatusDb | null; actor: "worker" | "company" | "platform"; content: string; createdAt: string }
export interface WorkerComplaintDetail { original: string; shared: string | null; timeline: TimelineItem[] }

export async function loadWorkerComplaintDetail(id: string): Promise<WorkerComplaintDetail> {
  const db = supabase();
  const [original, shared, events, responses] = await Promise.all([
    db.from("complaint_originals").select("original_content").eq("complaint_id", id).maybeSingle(),
    db.from("complaint_shared_versions").select("shared_content").eq("complaint_id", id).maybeSingle(),
    db.from("complaint_events").select("status, actor, note, created_at").eq("complaint_id", id),
    db.from("company_responses").select("content, created_at").eq("complaint_id", id),
  ]);
  const timeline: TimelineItem[] = [
    ...(events.data ?? []).map(row => ({ kind: "event" as const, status: row.status, actor: row.actor, content: row.note, createdAt: row.created_at })),
    ...(responses.data ?? []).map(row => ({ kind: "response" as const, status: null, actor: "company" as const, content: row.content, createdAt: row.created_at })),
  ].sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  return { original: original.data?.original_content ?? "", shared: shared.data?.shared_content ?? null, timeline };
}

export interface NewComplaintInput {
  companyId: string; category: string; title: string; original: string; shared: string;
  incidentPeriod?: string; recurrence?: string; expectedOutcomes: string[];
}

export async function createWorkerComplaint(input: NewComplaintInput, share: boolean): Promise<AuthResult<string>> {
  const { data, error } = await supabase().rpc("create_complaint", {
    p: { company_id: input.companyId, category: input.category, title: input.title.trim(), original_content: input.original.trim(), shared_content: share ? input.shared.trim() : null, incident_period: input.incidentPeriod, recurrence: input.recurrence, expected_outcomes: input.expectedOutcomes },
    p_share: share,
  });
  return error ? { ok: false, message: rpcError(error, "Não foi possível registrar a manifestação. Tente novamente.") } : { ok: true, value: data as string };
}

export async function shareWorkerComplaint(id: string, shared: string): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("share_complaint", { p_id: id, p_shared: shared.trim() });
  return error ? { ok: false, message: rpcError(error, "Não foi possível compartilhar agora.") } : { ok: true, value: null };
}

export async function closeWorkerComplaint(id: string, feedback: ComplaintFeedback | null): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("close_complaint", { p_id: id, p_feedback: feedback });
  return error ? { ok: false, message: rpcError(error, "Não foi possível encerrar agora.") } : { ok: true, value: null };
}

export interface CompanyComplaint {
  id: string; protocol: string; category: string; title: string; status: ComplaintStatusDb; shared: string;
  createdAt: string; responses: number; lastResponseAt: string | null; feedback: ComplaintFeedback | null;
}

export async function listCompanyComplaints(): Promise<CompanyComplaint[]> {
  const { data } = await supabase().rpc("list_company_complaints");
  return (data ?? []).map((row: { id: string; protocol: string; category: string; title: string; status: ComplaintStatusDb; shared_content: string; created_at: string; responses: number; last_response_at: string | null; worker_feedback: ComplaintFeedback | null }) => ({ id: row.id, protocol: row.protocol, category: row.category, title: row.title, status: row.status, shared: row.shared_content, createdAt: row.created_at, responses: row.responses, lastResponseAt: row.last_response_at, feedback: row.worker_feedback }));
}

export async function loadCompanyTimeline(id: string): Promise<TimelineItem[]> {
  const { data } = await supabase().rpc("get_company_complaint_timeline", { p_id: id });
  return (data ?? []).map((row: { kind: "event" | "response"; status: ComplaintStatusDb | null; actor: TimelineItem["actor"]; content: string; created_at: string }) => ({ kind: row.kind, status: row.status, actor: row.actor, content: row.content, createdAt: row.created_at }));
}

export async function respondCompanyComplaint(id: string, content: string): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("respond_complaint", { p_id: id, p_content: content.trim() });
  return error ? { ok: false, message: rpcError(error, "Não foi possível enviar a resposta.") } : { ok: true, value: null };
}

export interface RankingRow { companyId: string; name: string; city: string; state: string; received: number; responseRate: number; avgFirstResponseHours: number | null; isMine: boolean }

export async function loadCompanyRanking(): Promise<RankingRow[]> {
  const { data } = await supabase().rpc("company_ranking");
  return (data ?? []).map((row: { company_id: string; name: string; city: string; state: string; received: number; response_rate: number; avg_first_response_hours: number | null; is_mine: boolean }) => ({ companyId: row.company_id, name: row.name, city: row.city, state: row.state, received: row.received, responseRate: row.response_rate, avgFirstResponseHours: row.avg_first_response_hours, isMine: row.is_mine }));
}

export async function requestPartner(partnerId: string): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("company_request_partner", { p_partner: partnerId });
  return error ? { ok: false, message: rpcError(error, "Não foi possível registrar o interesse.") } : { ok: true, value: null };
}

export type ConnectionStage = "company_interest" | "partner_contacted" | "client";
export interface PartnerCompany { id: string; name: string; legalName: string; city: string; state: string; stage: ConnectionStage | null }

export async function listPartnerCompanies(): Promise<PartnerCompany[]> {
  const { data } = await supabase().rpc("list_partner_companies");
  return (data ?? []).map((row: { id: string; name: string; legal_name: string; city: string; state: string; stage: ConnectionStage | null }) => ({ id: row.id, name: row.name, legalName: row.legal_name, city: row.city, state: row.state, stage: row.stage }));
}

export async function setPartnerConnection(companyId: string, stage: Exclude<ConnectionStage, "company_interest">): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("partner_set_connection", { p_company: companyId, p_stage: stage });
  return error ? { ok: false, message: rpcError(error, "Não foi possível atualizar agora.") } : { ok: true, value: null };
}

export interface PartnerProfileData { displayName: string; specialty: string; description: string | null; city: string; state: string }

export async function updatePartnerProfile(partnerId: string, input: { displayName: string; specialty: string; description: string }): Promise<AuthResult<null>> {
  const displayName = input.displayName.trim(), specialty = input.specialty.trim(), description = input.description.trim();
  if (!displayName || displayName.length > 160) return { ok: false, message: "Informe o nome profissional (até 160 caracteres)." };
  if (!specialty || specialty.length > 120) return { ok: false, message: "Informe a especialidade (até 120 caracteres)." };
  if (description.length > 2000) return { ok: false, message: "A descrição pode ter até 2.000 caracteres." };
  const { error } = await supabase().from("partners").update({ display_name: displayName, specialty, description: description || null }).eq("id", partnerId);
  return error ? { ok: false, message: "Não foi possível salvar o perfil. Tente novamente." } : { ok: true, value: null };
}

export async function loadPartnerProfile(partnerId: string): Promise<PartnerProfileData | null> {
  const { data } = await supabase().from("partners").select("display_name, specialty, description, address:address_id (city, state)").eq("id", partnerId).maybeSingle();
  if (!data) return null;
  const address = (Array.isArray(data.address) ? data.address[0] : data.address) as { city?: string; state?: string } | null;
  return { displayName: data.display_name, specialty: data.specialty, description: data.description, city: address?.city ?? "", state: address?.state ?? "" };
}

export interface PublicSponsor { id: string; name: string; campaignTitle: string; campaignKind: CampaignKind }

export async function listPublicSponsors(): Promise<PublicSponsor[]> {
  if (!isAccountServiceConfigured()) return [];
  const { data } = await supabase().rpc("list_public_sponsors");
  return (data ?? []).map((row: { id: string; name: string; campaign_title: string; campaign_kind: CampaignKind }) => ({ id: row.id, name: row.name, campaignTitle: row.campaign_title, campaignKind: row.campaign_kind }));
}
