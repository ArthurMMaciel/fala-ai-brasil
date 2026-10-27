import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { appRoleFor, authErrorMessage, buildProfilePayload, type CampaignInput, type CampaignKind, type CampaignStatus, type ProfileType, type RegistrationInput } from "./account-rules";

// ADR-0009: somente a chave pública no navegador; o acesso real é controlado por RLS.
const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const partnerMediaBucket = "partner-media";
const maxAvatarBytes = 5 * 1024 * 1024;
let client: SupabaseClient | null = null;

export function isAccountServiceConfigured(): boolean {
  return Boolean(url && key);
}

function supabase(): SupabaseClient {
  if (!url || !key) throw new Error("Cadastro real indisponível: configure VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY.");
  client ??= createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } });
  return client;
}

function redirectUrl(): string {
  return import.meta.env.VITE_SITE_URL || window.location.origin;
}

export interface AccountProfile {
  type: ProfileType;
  id: string;
  name: string;
}

export interface AppUser {
  id: string;
  name: string;
  email: string;
  role: "worker" | "admin" | "commercial";
  profile: AccountProfile;
  createdAt: string;
}

export interface AppSubscription {
  userId: string;
  audience: Exclude<ProfileType, "worker">;
  planId: string;
  mode: "trial" | "monthly" | "annual";
  status: "trialing" | "pending" | "active" | "expired";
  nextBillingAt: string | null;
  paidCents: number;
}

export interface Account {
  user: AppUser;
  subscription: AppSubscription | null;
  profiles: AccountProfile[];
}

export type AuthResult<T> = { ok: true; value: T } | { ok: false; message: string; code?: string };

export async function registerAccount(input: RegistrationInput): Promise<AuthResult<{ email: string }>> {
  const email = input.email.trim().toLowerCase();
  const { data, error } = await supabase().auth.signUp({
    email,
    password: input.password,
    options: {
      emailRedirectTo: redirectUrl(),
      // O trigger handle_new_user cria o perfil e remove signup/documentos deste metadado.
      data: { full_name: input.name.trim(), signup_type: input.type, signup: buildProfilePayload(input) },
    },
  });
  if (error) {
    // O Auth devolve 500 sem código específico quando o SMTP recusa o envio.
    const code = /sending confirmation email/i.test(error.message) ? "email_send_failed" : error.code;
    return { ok: false, code, message: authErrorMessage(code) };
  }
  // Com confirmação ativa, e-mail já cadastrado retorna usuário sem identidades e nenhum e-mail novo.
  if (data.user && data.user.identities?.length === 0) return { ok: false, code: "user_already_exists", message: authErrorMessage("user_already_exists") };
  return { ok: true, value: { email } };
}

// Conta já autenticada ganha outro tipo de perfil (função add_profile no banco).
export async function addProfile(input: RegistrationInput): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("add_profile", { p_type: input.type, p: buildProfilePayload(input) });
  return error ? { ok: false, code: error.code, message: error.code === "23505" ? "Sua conta já tem este tipo de perfil ou a empresa já está cadastrada." : authErrorMessage("unexpected_failure") } : { ok: true, value: null };
}

export async function resendConfirmation(email: string): Promise<AuthResult<null>> {
  const { error } = await supabase().auth.resend({ type: "signup", email: email.trim().toLowerCase(), options: { emailRedirectTo: redirectUrl() } });
  if (!error) return { ok: true, value: null };
  const code = /sending confirmation email/i.test(error.message) ? "email_send_failed" : error.code;
  return { ok: false, code, message: authErrorMessage(code) };
}

export async function signIn(email: string, password: string): Promise<AuthResult<Account>> {
  const { error } = await supabase().auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
  if (error) return { ok: false, code: error.code, message: authErrorMessage(error.code) };
  const account = await loadAccount();
  return account ? { ok: true, value: account } : { ok: false, message: "Conta autenticada, mas nenhum perfil foi encontrado. Fale com o suporte." };
}

export async function signOut(): Promise<void> {
  if (isAccountServiceConfigured()) await supabase().auth.signOut();
}

async function loadSubscription(profile: AccountProfile, userId: string): Promise<AppSubscription | null> {
  if (profile.type === "worker") return null;
  const column = `${profile.type}_id`;
  const { data } = await supabase()
    .from("subscriptions")
    .select("plan_id, mode, status, next_billing_at, paid_cents, created_at")
    .eq(column, profile.id)
    .order("created_at", { ascending: false })
    .limit(1);
  const row = data?.[0];
  return row
    ? { userId, audience: profile.type, planId: row.plan_id, mode: row.mode, status: row.status, nextBillingAt: row.next_billing_at, paidCents: row.paid_cents }
    : null;
}

// Lê a sessão atual (inclusive a criada pelo link de confirmação) e abre o perfil escolhido ou o mais antigo.
export async function loadAccount(preferred?: { type: ProfileType; id: string }): Promise<Account | null> {
  if (!isAccountServiceConfigured()) return null;
  const db = supabase();
  const { data: sessionData } = await db.auth.getSession();
  const authUser = sessionData.session?.user;
  if (!authUser) return null;

  const { data: rows, error } = await db.rpc("current_profiles");
  if (error || !rows?.length) return null;
  const profiles: AccountProfile[] = rows.map((row: { profile_type: ProfileType; profile_id: string; display_name: string }) => ({ type: row.profile_type, id: row.profile_id, name: row.display_name }));
  const profile = profiles.find(item => item.type === preferred?.type && item.id === preferred?.id) ?? profiles[0];
  const user: AppUser = {
    id: authUser.id,
    name: profile.name,
    email: authUser.email ?? "",
    role: appRoleFor(profile.type),
    profile,
    createdAt: authUser.created_at,
  };
  return { user, subscription: await loadSubscription(profile, user.id), profiles };
}

export interface PartnerPhoto {
  url: string | null;
}

export async function loadPartnerPhoto(partnerId: string): Promise<PartnerPhoto> {
  const db = supabase();
  const { data } = await db.from("partners").select("avatar_media_id, media:avatar_media_id (storage_path)").eq("id", partnerId).maybeSingle();
  const media = data?.media as { storage_path?: string } | { storage_path?: string }[] | null | undefined;
  const path = Array.isArray(media) ? media[0]?.storage_path : media?.storage_path;
  return { url: path ? db.storage.from(partnerMediaBucket).getPublicUrl(path).data.publicUrl : null };
}

// Foto pública de perfil: arquivo na pasta do parceiro, registro em media e vínculo no avatar.
export async function uploadPartnerPhoto(partnerId: string, file: File): Promise<AuthResult<PartnerPhoto>> {
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) return { ok: false, message: "Use uma imagem JPG, PNG ou WebP." };
  if (file.size > maxAvatarBytes) return { ok: false, message: "A imagem pode ter até 5 MB." };
  const db = supabase();
  const extension = file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg";
  const path = `${partnerId}/avatar-${Date.now()}.${extension}`;
  const upload = await db.storage.from(partnerMediaBucket).upload(path, file, { contentType: file.type, upsert: false });
  if (upload.error) return { ok: false, message: "Não foi possível enviar a imagem. Tente novamente." };
  const { data: media, error } = await db
    .from("media")
    .insert({ partner_id: partnerId, kind: "image", storage_path: path, mime_type: file.type, size_bytes: file.size })
    .select("id")
    .single();
  if (error || !media) return { ok: false, message: "A imagem foi enviada, mas não pôde ser registrada." };
  const link = await db.from("partners").update({ avatar_media_id: media.id }).eq("id", partnerId);
  if (link.error) return { ok: false, message: "A imagem foi enviada, mas não pôde ser definida como foto de perfil." };
  return { ok: true, value: { url: db.storage.from(partnerMediaBucket).getPublicUrl(path).data.publicUrl } };
}

// Erros devolvidos pelo link de confirmação (ex.: link expirado) chegam no fragmento da URL.
export function readRedirectError(): string | null {
  const params = new URLSearchParams(window.location.hash.slice(1));
  const code = params.get("error_code");
  if (!code) return null;
  history.replaceState(null, "", window.location.pathname + window.location.search);
  return code === "otp_expired"
    ? "O link de confirmação expirou ou já foi usado. Entre com seu e-mail para receber um novo."
    : "Não foi possível confirmar sua conta por este link. Tente entrar novamente.";
}

export interface Campaign {
  id: string;
  kind: CampaignKind;
  title: string;
  description: string;
  ctaUrl: string | null;
  startsAt: string;
  endsAt: string;
  status: CampaignStatus;
  reviewNote: string | null;
}

export async function listCampaigns(): Promise<Campaign[]> {
  const { data, error } = await supabase()
    .from("campaigns")
    .select("id, kind, title, description, cta_url, starts_at, ends_at, status, review_note, created_at")
    .order("created_at", { ascending: false });
  if (error || !data) return [];
  return data.map(row => ({ id: row.id, kind: row.kind, title: row.title, description: row.description, ctaUrl: row.cta_url, startsAt: row.starts_at, endsAt: row.ends_at, status: row.status, reviewNote: row.review_note }));
}

// Regras (tipo pelo plano, assinatura vigente, uma ativa por vez) são aplicadas no banco; a mensagem vem de lá.
function campaignError(error: { code?: string; message: string }): string {
  return error.code === "P0001" ? error.message : "Não foi possível salvar a campanha agora. Tente novamente.";
}

export async function createCampaign(input: CampaignInput, submit: boolean): Promise<AuthResult<string>> {
  const { data, error } = await supabase().rpc("create_campaign", {
    p: { title: input.title.trim(), description: input.description.trim(), cta_url: input.ctaUrl?.trim() || null, starts_at: input.startsAt, ends_at: input.endsAt },
    p_submit: submit,
  });
  return error ? { ok: false, message: campaignError(error) } : { ok: true, value: data as string };
}

export async function submitCampaign(id: string): Promise<AuthResult<null>> {
  const { error } = await supabase().rpc("submit_campaign", { p_id: id });
  return error ? { ok: false, message: campaignError(error) } : { ok: true, value: null };
}

export async function deleteCampaignDraft(id: string): Promise<AuthResult<null>> {
  const { error } = await supabase().from("campaigns").delete().eq("id", id).eq("status", "draft");
  return error ? { ok: false, message: "Não foi possível descartar o rascunho." } : { ok: true, value: null };
}

export interface CompanyContext {
  id: string;
  name: string;
  legalName: string;
  cnpj: string;
  city: string;
  state: string;
}

// Empresa da conta logada (RLS: só empresas das quais o usuário é membro).
export async function loadCompanyContext(companyId: string): Promise<CompanyContext | null> {
  const { data } = await supabase()
    .from("companies")
    .select("id, legal_name, trade_name, cnpj, address:address_id (city, state)")
    .eq("id", companyId)
    .maybeSingle();
  if (!data) return null;
  const address = (Array.isArray(data.address) ? data.address[0] : data.address) as { city?: string; state?: string } | null;
  return { id: data.id, name: data.trade_name || data.legal_name, legalName: data.legal_name, cnpj: data.cnpj, city: address?.city ?? "", state: address?.state ?? "" };
}

export interface DirectoryPartner {
  id: string;
  name: string;
  specialty: string;
  description: string | null;
  avatarUrl: string | null;
  city: string;
  state: string;
}

// Diretório para empresas: sem documento nem endereço completo (list_partner_directory).
export async function listPartnerDirectory(): Promise<DirectoryPartner[]> {
  const db = supabase();
  const { data, error } = await db.rpc("list_partner_directory");
  if (error || !data) return [];
  return data.map((row: { id: string; display_name: string; specialty: string; description: string | null; avatar_path: string | null; city: string; state: string }) => ({
    id: row.id,
    name: row.display_name,
    specialty: row.specialty,
    description: row.description,
    avatarUrl: row.avatar_path ? db.storage.from(partnerMediaBucket).getPublicUrl(row.avatar_path).data.publicUrl : null,
    city: row.city,
    state: row.state,
  }));
}
