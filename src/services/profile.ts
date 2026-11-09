import { redirectUrl, supabase, type AuthResult } from "./account";
import { rpcError } from "./data";
import { addressFromRow, type AddressRow } from "../domain/profile";
import type { AddressInput } from "../domain/account-rules";

// "Meu perfil" (ADR-0014): leitura direta pelas tabelas (RLS) e escrita só pelas RPCs com trilha.
const addressColumns = "zip_code, street_type, street_name, number, complement, neighborhood, city, state";
const one = <T>(value: T | T[] | null | undefined): T | null => (Array.isArray(value) ? value[0] ?? null : value ?? null);

export interface WorkerProfileData { fullName: string; cpf: string; phone: string; email: string; address: AddressInput }

export async function loadWorkerProfile(): Promise<WorkerProfileData | null> {
  const db = supabase();
  const { data: auth } = await db.auth.getUser();
  if (!auth.user) return null;
  const { data } = await db.from("workers").select(`full_name, cpf, phone, address:address_id (${addressColumns})`).eq("user_id", auth.user.id).maybeSingle();
  if (!data) return null;
  return { fullName: data.full_name, cpf: data.cpf, phone: data.phone ?? "", email: auth.user.email ?? "", address: addressFromRow(one(data.address) as AddressRow | null) };
}

export async function updateWorkerProfile(changes: Record<string, unknown>): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("update_worker_profile", { p: changes });
  return error ? { ok: false, message: rpcError(error, "Não foi possível salvar o perfil. Tente novamente.") } : { ok: true, value: null };
}

export interface CompanyProfileData {
  legalName: string; tradeName: string; cnpj: string; contactEmail: string; contactPhone: string;
  address: AddressInput; isOwner: boolean; loginEmail: string;
}

export async function loadCompanyProfile(companyId: string): Promise<CompanyProfileData | null> {
  const db = supabase();
  const { data: auth } = await db.auth.getUser();
  if (!auth.user) return null;
  const [{ data }, { data: membership }] = await Promise.all([
    db.from("companies").select(`legal_name, trade_name, cnpj, contact_email, contact_phone, address:address_id (${addressColumns})`).eq("id", companyId).maybeSingle(),
    db.from("company_users").select("role").eq("company_id", companyId).eq("user_id", auth.user.id).maybeSingle(),
  ]);
  if (!data) return null;
  return {
    legalName: data.legal_name, tradeName: data.trade_name ?? "", cnpj: data.cnpj, contactEmail: data.contact_email ?? "", contactPhone: data.contact_phone ?? "",
    address: addressFromRow(one(data.address) as AddressRow | null), isOwner: membership?.role === "owner", loginEmail: auth.user.email ?? "",
  };
}

export async function updateCompanyProfile(companyId: string, changes: Record<string, unknown>): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("update_company_profile", { p_company: companyId, p: changes });
  return error ? { ok: false, message: rpcError(error, "Não foi possível salvar os dados da empresa. Tente novamente.") } : { ok: true, value: null };
}

/** E-mail de login pelo fluxo do Supabase Auth (dupla confirmação). Só é chamado com a flag emailChangeEnabled ligada. */
export async function requestLoginEmailChange(email: string): Promise<AuthResult<null>> {
  const { error } = await supabase().auth.updateUser({ email: email.trim().toLowerCase() }, { emailRedirectTo: redirectUrl() });
  if (!error) return { ok: true, value: null };
  const message = error.code === "email_exists" ? "Este e-mail já está em uso em outra conta." : error.code === "over_email_send_rate_limit" ? "Aguarde alguns minutos antes de pedir outra troca de e-mail." : "Não foi possível pedir a troca de e-mail agora. Tente novamente.";
  return { ok: false, message, code: error.code };
}
