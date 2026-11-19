import { supabase, type AuthResult } from './account';
import { rpcError } from './data';
import { lookupOutcome, type LookupOutcome, type NoticeStatus } from '../domain/company-notice';
import { normalizeCnpj } from '../domain/account-rules';
import type { ComplaintStatusDb } from './data';

// ADR-0023 e ADR-0017. Migrations 20261118120000/130000 ainda em supabase/pending: sem elas as RPCs não existem (missing).
const missingFunction = (error: { code?: string }) => error.code === 'PGRST202' || error.code === '42883';
const opsFailure = (error: { code?: string; message: string }, fallback: string) => error.code === '42501' ? 'Seu usuário não tem acesso à área da equipe.' : rpcError(error, fallback);

export interface FoundCompany { id: string; name: string; city: string; state: string }

export async function findCompanyByCnpj(cnpj: string): Promise<{ missing: true } | { missing: false; ok: true; company: FoundCompany | null } | { missing: false; ok: false; message: string }> {
  const { data, error } = await supabase().rpc('find_company_by_cnpj', { p_cnpj: normalizeCnpj(cnpj) });
  if (error) return missingFunction(error) ? { missing: true } : { missing: false, ok: false, message: rpcError(error, 'Não foi possível buscar a empresa agora.') };
  const row = (data ?? [])[0] as Record<string, unknown> | undefined;
  return { missing: false, ok: true, company: row ? { id: String(row.id), name: String(row.name ?? ''), city: String(row.city ?? ''), state: String(row.state ?? '') } : null };
}

// A função pode não existir (DevOps publica depois da migration 1): qualquer resposta diferente de 200 vira preenchimento manual.
export async function lookupCnpj(cnpj: string): Promise<LookupOutcome> {
  try {
    const { data, error } = await supabase().functions.invoke('cnpj-lookup', { body: { cnpj: normalizeCnpj(cnpj) } });
    return error ? { kind: 'manual' } : lookupOutcome(200, data);
  } catch {
    return { kind: 'manual' };
  }
}

// Contrato final (ADR-0023, "Contrato para o Front"): a tela não chama preregister_*. A empresa fora da base vai no
// create_complaint (company_cnpj e, sem resposta found da função, company_manual), que a cria na mesma transação.

// Operação: empresas fora do cadastro
export interface PendingCompany {
  companyId: string; name: string; cnpj: string; city: string; state: string; registrationStatus: string; dataSource: string;
  naturalPerson: boolean | null; cadastralSituation: string | null; reviewDecision: string | null; reviewReason: string | null;
  createdAt: string; complaints: number; lastNoticeAt: string | null;
}

export async function listPendingCompanies(): Promise<{ missing: true } | { missing: false; rows: PendingCompany[] }> {
  const { data, error } = await supabase().rpc('ops_list_pending_companies');
  if (error) { if (missingFunction(error)) return { missing: true }; throw new Error(opsFailure(error, 'Não foi possível carregar as empresas.')); }
  return { missing: false, rows: (data ?? []).map((row: Record<string, unknown>) => ({
    companyId: String(row.company_id), name: String(row.name ?? ''), cnpj: String(row.cnpj ?? ''), city: String(row.city ?? ''), state: String(row.state ?? ''),
    registrationStatus: String(row.registration_status ?? ''), dataSource: String(row.data_source ?? ''), naturalPerson: (row.natural_person as boolean | null) ?? null,
    cadastralSituation: (row.cadastral_situation as string | null) ?? null, reviewDecision: (row.review_decision as string | null) ?? null, reviewReason: (row.review_reason as string | null) ?? null,
    createdAt: String(row.created_at), complaints: Number(row.complaints ?? 0), lastNoticeAt: (row.last_notice_at as string | null) ?? null,
  })) };
}

export async function reviewPendingCompany(companyId: string, decision: 'confirmed' | 'blocked', reason: string, naturalPerson: boolean): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc('ops_review_company', { p_company: companyId, p_decision: decision, p_reason: reason.trim() || null, p_natural_person: naturalPerson });
  return error ? { ok: false, message: opsFailure(error, 'Não foi possível registrar a conferência.') } : { ok: true, value: null };
}

// Operação: avisos
export interface NoticeCandidate {
  complaintId: string; protocol: string; complaintStatus: ComplaintStatusDb; companyId: string; companyName: string; registrationStatus: string;
  naturalPerson: boolean | null; reviewDecision: string | null; contactId: string | null; email: string; possiblyInvolved: boolean; contactStatus: string;
  optedOut: boolean; lastCompanyNoticeAt: string | null; noticeId: string | null; noticeStatus: NoticeStatus | null;
  // Contrato novo (decisão do responsável, 2026-11-19), nomes provisórios até o Back confirmar: telefone indicado pelo
  // trabalhador e e-mail da Receita (cnpj-lookup), usado como destino quando o trabalhador não indica contato.
  phone: string; registryEmail: string;
}

// Destino do aviso: o contato do trabalhador; sem ele, o e-mail da Receita, que a equipe precisa conferir.
export function noticeDestination(row: Pick<NoticeCandidate, 'email' | 'registryEmail'>): { email: string; fromRegistry: boolean } | null {
  if (row.email) return { email: row.email, fromRegistry: false };
  return row.registryEmail ? { email: row.registryEmail, fromRegistry: true } : null;
}

export async function listNoticeCandidates(): Promise<{ missing: true } | { missing: false; rows: NoticeCandidate[] }> {
  const { data, error } = await supabase().rpc('ops_list_notice_candidates');
  if (error) { if (missingFunction(error)) return { missing: true }; throw new Error(opsFailure(error, 'Não foi possível carregar os avisos.')); }
  return { missing: false, rows: (data ?? []).map((row: Record<string, unknown>) => ({
    complaintId: String(row.complaint_id), protocol: String(row.protocol ?? ''), complaintStatus: row.complaint_status as ComplaintStatusDb, companyId: String(row.company_id),
    companyName: String(row.company_name ?? ''), registrationStatus: String(row.registration_status ?? ''), naturalPerson: (row.natural_person as boolean | null) ?? null,
    reviewDecision: (row.review_decision as string | null) ?? null, contactId: (row.contact_id as string | null) ?? null, email: String(row.email ?? ''),
    phone: String(row.phone ?? ''), registryEmail: String(row.registry_email ?? ''),
    possiblyInvolved: Boolean(row.possibly_involved), contactStatus: String(row.contact_status ?? 'candidate'), optedOut: Boolean(row.opted_out),
    lastCompanyNoticeAt: (row.last_company_notice_at as string | null) ?? null, noticeId: (row.notice_id as string | null) ?? null, noticeStatus: (row.notice_status as NoticeStatus | null) ?? null,
  })) };
}

export async function decideNotice(complaintId: string, decision: 'approved' | 'rejected', reason: string): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc('ops_decide_notice', { p_complaint: complaintId, p_decision: decision, p_reason: reason.trim() || null });
  return error ? { ok: false, message: opsFailure(error, 'Não foi possível registrar a decisão do aviso.') } : { ok: true, value: null };
}

export async function markNoticeSent(noticeId: string, outcome: 'sent' | 'bounced'): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc('ops_mark_notice_sent', { p_notice: noticeId, p_outcome: outcome });
  return error ? { ok: false, message: opsFailure(error, 'Não foi possível registrar o envio.') } : { ok: true, value: null };
}

export async function addNoticeOptOut(email: string): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc('ops_add_opt_out', { p_email: email.trim().toLowerCase() });
  return error ? { ok: false, message: opsFailure(error, 'Não foi possível registrar o pedido.') } : { ok: true, value: null };
}

export async function purgeExpiredContacts(): Promise<AuthResult<number>> {
  const { data, error } = await supabase().rpc('ops_purge_expired_contacts');
  return error ? { ok: false, message: opsFailure(error, 'Não foi possível apagar os contatos vencidos.') } : { ok: true, value: Number(data ?? 0) };
}
