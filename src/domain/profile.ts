import { isValidPhone, onlyDigits, validateAddress, type AddressInput } from "./account-rules";

// "Meu perfil" do trabalhador e da empresa (ADR-0014). Regras puras: validação com as mensagens do cadastro
// e montagem do payload parcial das RPCs update_worker_profile / update_company_profile.

/** Troca do e-mail de login. Desligada até o responsável confirmar a dupla confirmação no projeto remoto (ADR-0014, C5). */
export const emailChangeEnabled = false;

/** Texto exibido junto de CPF, CNPJ e razão social, que só a equipe altera (ADR-0014, C1 e C4). */
export const lockedDocumentNote = "Para alterar, fale com a equipe.";

export interface AddressRow {
  zip_code: string; street_type: string; street_name: string; number: string;
  complement: string | null; neighborhood: string | null; city: string; state: string;
}

export function addressFromRow(row: AddressRow | null | undefined): AddressInput {
  return {
    zipCode: maskZip(row?.zip_code ?? ""), streetType: row?.street_type ?? "", streetName: row?.street_name ?? "", number: row?.number ?? "",
    complement: row?.complement ?? "", neighborhood: row?.neighborhood ?? "", city: row?.city ?? "", state: row?.state ?? "",
  };
}

export function maskZip(value: string): string {
  const digits = onlyDigits(value).slice(0, 8);
  return digits.length > 5 ? `${digits.slice(0, 5)}-${digits.slice(5)}` : digits;
}

/** Endereço no formato da RPC; a RPC exige o objeto completo. */
export function addressPayload(address: AddressInput): AddressRow {
  return {
    zip_code: onlyDigits(address.zipCode), street_type: address.streetType.trim(), street_name: address.streetName.trim(), number: address.number.trim(),
    complement: address.complement?.trim() || null, neighborhood: address.neighborhood?.trim() || null, city: address.city.trim(), state: address.state.trim().toUpperCase(),
  };
}

function sameAddress(a: AddressInput, b: AddressInput): boolean {
  return JSON.stringify(addressPayload(a)) === JSON.stringify(addressPayload(b));
}

export interface WorkerProfileForm { fullName: string; phone: string; address: AddressInput }
export interface CompanyProfileForm { tradeName: string; contactEmail: string; contactPhone: string; address: AddressInput }

export function validateWorkerProfile(form: WorkerProfileForm): string | null {
  const name = form.fullName.trim();
  if (name.length < 2 || name.length > 160) return "Informe o nome completo.";
  if (!isValidPhone(form.phone)) return "Informe um telefone válido com DDD: celular com 9 dígitos ou fixo com 8.";
  return validateAddress(form.address);
}

export function validateCompanyProfile(form: CompanyProfileForm): string | null {
  if (form.tradeName.trim().length > 160) return "O nome fantasia pode ter até 160 caracteres.";
  const email = form.contactEmail.trim();
  if (email && (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254)) return "Informe um e-mail de contato válido.";
  if (form.contactPhone.trim() && !isValidPhone(form.contactPhone)) return "Informe um telefone válido com DDD: celular com 9 dígitos ou fixo com 8.";
  return validateAddress(form.address);
}

/** Só as chaves alteradas; objeto vazio quando nada mudou. CPF nunca entra. */
export function workerProfileChanges(initial: WorkerProfileForm, form: WorkerProfileForm): Record<string, unknown> {
  const changes: Record<string, unknown> = {};
  if (form.fullName.trim() !== initial.fullName.trim()) changes.full_name = form.fullName.trim();
  if (onlyDigits(form.phone) !== onlyDigits(initial.phone)) changes.phone = onlyDigits(form.phone);
  if (!sameAddress(form.address, initial.address)) changes.address = addressPayload(form.address);
  return changes;
}

/** Só as chaves alteradas; CNPJ e razão social nunca entram. */
export function companyProfileChanges(initial: CompanyProfileForm, form: CompanyProfileForm): Record<string, unknown> {
  const changes: Record<string, unknown> = {};
  if (form.tradeName.trim() !== initial.tradeName.trim()) changes.trade_name = form.tradeName.trim();
  if (form.contactEmail.trim().toLowerCase() !== initial.contactEmail.trim().toLowerCase()) changes.contact_email = form.contactEmail.trim().toLowerCase();
  if (onlyDigits(form.contactPhone) !== onlyDigits(initial.contactPhone)) changes.contact_phone = onlyDigits(form.contactPhone);
  if (!sameAddress(form.address, initial.address)) changes.address = addressPayload(form.address);
  return changes;
}

export function validateLoginEmail(value: string, current: string): string | null {
  const email = value.trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254) return "Informe um e-mail válido.";
  if (email === current.trim().toLowerCase()) return "Informe um e-mail diferente do atual.";
  return null;
}
