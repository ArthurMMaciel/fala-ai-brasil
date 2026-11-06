import { isAccountServiceConfigured, supabase } from './account';
import { isValidPhone, normalizePhone } from '../domain/account-rules';

export type ContactProfile = 'worker' | 'company' | 'partner' | 'sponsor';
export type LandingOrigin = ContactProfile | 'intelligence';
export type ContactStatus = 'waiting_contact' | 'contacted';

export interface ContactSolicitationInput {
  profile: ContactProfile;
  origin: LandingOrigin;
  name: string;
  email: string;
  phone: string;
  organization: string;
  website: string;
}

export interface ContactSolicitation {
  id: string;
  profile: ContactProfile;
  landingOrigin: LandingOrigin;
  name: string;
  email: string;
  phone: string;
  organization: string | null;
  status: ContactStatus;
  createdAt: string;
  contactedAt: string | null;
}

export function validateContactSolicitation(input: ContactSolicitationInput): string | null {
  if (input.name.trim().length < 2 || input.name.trim().length > 120) return 'Informe seu nome (de 2 a 120 caracteres).';
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(input.email.trim()) || input.email.trim().length > 254) return 'Informe um e-mail válido.';
  if (!isValidPhone(input.phone)) return 'Confira o telefone: DDD + celular com 9 dígitos (começando com 9) ou fixo com 8.';
  if (input.organization.trim() && (input.organization.trim().length < 2 || input.organization.trim().length > 120)) return 'Informe o nome da organização ou deixe o campo vazio.';
  return null;
}

export async function submitContactSolicitation(input: ContactSolicitationInput): Promise<{ ok: true } | { ok: false; message: string }> {
  const validation = validateContactSolicitation(input);
  if (validation) return { ok: false, message: validation };
  if (!isAccountServiceConfigured()) return { ok: false, message: 'Solicitações de contato indisponíveis neste ambiente.' };
  const { error } = await supabase().rpc('submit_contact_solicitation', {
    p_profile: input.profile,
    p_origin: input.origin,
    p_name: input.name.trim(),
    p_email: input.email.trim().toLowerCase(),
    p_phone: normalizePhone(input.phone),
    p_organization: input.organization.trim() || null,
    p_website: input.website,
  });
  return error ? { ok: false, message: 'Não foi possível enviar agora. Tente novamente em instantes.' } : { ok: true };
}

export async function listContactSolicitations(status: ContactStatus | '', profile: ContactProfile | ''): Promise<ContactSolicitation[]> {
  const { data, error } = await supabase().rpc('list_contact_solicitations', { p_status: status || null, p_profile: profile || null });
  if (error) throw new Error('Não foi possível carregar as solicitações.');
  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.id), profile: row.profile as ContactProfile, landingOrigin: row.landing_origin as LandingOrigin,
    name: String(row.full_name), email: String(row.email), phone: String(row.phone),
    organization: row.organization_name ? String(row.organization_name) : null,
    status: row.status as ContactStatus, createdAt: String(row.created_at),
    contactedAt: row.contacted_at ? String(row.contacted_at) : null,
  }));
}

export async function setContactSolicitationStatus(id: string, status: ContactStatus): Promise<void> {
  const { error } = await supabase().rpc('set_contact_solicitation_status', { p_id: id, p_status: status });
  if (error) throw new Error('Não foi possível atualizar o status. Tente novamente.');
}
