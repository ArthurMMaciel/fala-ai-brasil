// Regras puras do cadastro real (ADR-0009 v2); sem dependência de rede para permitir testes.
export type ProfileType = "worker" | "company" | "partner" | "sponsor";
export const registrableProfiles: ProfileType[] = ["worker", "company", "partner", "sponsor"];
export const minPasswordLength = 8;

export type StreetType = "street" | "avenue" | "alley" | "boulevard" | "square" | "road" | "highway" | "other";
export const streetTypeLabels: Record<StreetType, string> = {
  street: "Rua",
  avenue: "Avenida",
  alley: "Travessa",
  boulevard: "Alameda",
  square: "Praça",
  road: "Estrada",
  highway: "Rodovia",
  other: "Outro",
};

export const brazilianStates = ["AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO"];

export function onlyDigits(value: string): string {
  return value.replace(/\D/g, "");
}

// Máscara progressiva para digitação: aceita colagem com ou sem pontuação.
export function maskCpf(value: string): string {
  const d = onlyDigits(value).slice(0, 11);
  return d.replace(/^(\d{3})(\d)/, "$1.$2").replace(/^(\d{3})\.(\d{3})(\d)/, "$1.$2.$3").replace(/\.(\d{3})(\d{1,2})$/, ".$1-$2");
}

export function maskCnpj(value: string): string {
  const d = onlyDigits(value).slice(0, 14);
  return d.replace(/^(\d{2})(\d)/, "$1.$2").replace(/^(\d{2})\.(\d{3})(\d)/, "$1.$2.$3").replace(/\.(\d{3})(\d)/, ".$1/$2").replace(/(\d{4})(\d{1,2})$/, "$1-$2");
}

function allSameDigit(digits: string): boolean {
  return /^(\d)\1+$/.test(digits);
}

export function isValidCpf(value: string): boolean {
  const cpf = onlyDigits(value);
  if (cpf.length !== 11 || allSameDigit(cpf)) return false;
  const check = (length: number) => {
    let sum = 0;
    for (let i = 0; i < length; i++) sum += Number(cpf[i]) * (length + 1 - i);
    const rest = (sum * 10) % 11;
    return rest === 10 ? 0 : rest;
  };
  return check(9) === Number(cpf[9]) && check(10) === Number(cpf[10]);
}

export function isValidCnpj(value: string): boolean {
  const cnpj = onlyDigits(value);
  if (cnpj.length !== 14 || allSameDigit(cnpj)) return false;
  const check = (length: number) => {
    const weights = length === 12 ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2] : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const sum = weights.reduce((total, weight, i) => total + Number(cnpj[i]) * weight, 0);
    const rest = sum % 11;
    return rest < 2 ? 0 : 11 - rest;
  };
  return check(12) === Number(cnpj[12]) && check(13) === Number(cnpj[13]);
}

// ViaCEP devolve "Avenida Paulista"; o banco guarda tipo e nome separados.
const streetPrefixes: [RegExp, StreetType][] = [
  [/^(rua|r\.)\s+/i, "street"],
  [/^(avenida|av\.?)\s+/i, "avenue"],
  [/^(travessa|tv\.?)\s+/i, "alley"],
  [/^(alameda|al\.?)\s+/i, "boulevard"],
  [/^(praça|praca|pç\.?)\s+/i, "square"],
  [/^(estrada|est\.?)\s+/i, "road"],
  [/^(rodovia|rod\.?)\s+/i, "highway"],
];

export function splitStreet(value: string): { streetType: StreetType; streetName: string } | null {
  const text = value.trim();
  for (const [pattern, streetType] of streetPrefixes) {
    if (pattern.test(text)) return { streetType, streetName: text.replace(pattern, "").trim() };
  }
  return null;
}

export interface AddressInput {
  zipCode: string;
  streetType: string;
  streetName: string;
  number: string;
  complement?: string;
  neighborhood?: string;
  city: string;
  state: string;
}

export interface RegistrationInput {
  type: ProfileType;
  email: string;
  password: string;
  confirm: string;
  name: string;
  tradeName?: string;
  cpf?: string;
  cnpj?: string;
  documentType?: string;
  document?: string;
  specialty?: string;
  description?: string;
  planId?: string;
  subscriptionMode?: string;
  address: AddressInput;
}

export function validateAddress(address: AddressInput): string | null {
  if (onlyDigits(address.zipCode).length !== 8) return "Informe um CEP com 8 dígitos.";
  if (!Object.prototype.hasOwnProperty.call(streetTypeLabels, address.streetType)) return "Selecione o tipo de logradouro.";
  if (!address.streetName.trim() || !address.number.trim()) return "Preencha o nome do logradouro e o número. Somente complemento e bairro são opcionais.";
  if (!address.city.trim()) return "Informe a cidade.";
  if (!brazilianStates.includes(address.state.trim().toUpperCase())) return "Selecione a UF.";
  return null;
}

// Retorna a primeira mensagem de erro para exibir ao usuário, ou null se válido.
export function validateRegistration(input: RegistrationInput): string | null {
  if (!registrableProfiles.includes(input.type)) return "Este tipo de conta ainda não está disponível para cadastro.";
  if (!input.name.trim()) return input.type === "company" ? "Informe a razão social." : "Informe o nome.";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email.trim())) return "Informe um e-mail válido.";
  if (input.type === "worker" && !isValidCpf(input.cpf ?? "")) return "Informe um CPF válido.";
  if ((input.type === "company" || input.type === "sponsor") && !isValidCnpj(input.cnpj ?? "")) return "Informe um CNPJ válido.";
  if (input.type === "partner") {
    if (input.documentType === "cpf" ? !isValidCpf(input.document ?? "") : input.documentType === "cnpj" ? !isValidCnpj(input.document ?? "") : true) {
      return "Informe um CPF ou CNPJ válido.";
    }
    if (!input.specialty?.trim()) return "Informe sua especialidade.";
    if ((input.description ?? "").length > 2000) return "A descrição pode ter até 2.000 caracteres.";
  }
  const addressError = validateAddress(input.address);
  if (addressError) return addressError;
  if (input.type !== "worker" && (!input.planId || !input.subscriptionMode)) return "Selecione um plano e uma modalidade.";
  if (input.password.length < minPasswordLength) return `A senha precisa ter pelo menos ${minPasswordLength} caracteres.`;
  if (input.password !== input.confirm) return "A confirmação de senha precisa ser igual à senha informada.";
  return null;
}

// Monta o payload esperado por private.create_profile (nomes de banco em inglês).
export function buildProfilePayload(input: RegistrationInput): Record<string, unknown> {
  const address = {
    zip_code: onlyDigits(input.address.zipCode),
    street_type: input.address.streetType,
    street_name: input.address.streetName.trim(),
    number: input.address.number.trim(),
    complement: input.address.complement?.trim() || undefined,
    neighborhood: input.address.neighborhood?.trim() || undefined,
    city: input.address.city.trim(),
    state: input.address.state.trim().toUpperCase(),
  };
  const plan = input.type === "worker" ? {} : { plan_id: input.planId, subscription_mode: input.subscriptionMode };
  switch (input.type) {
    case "worker":
      return { full_name: input.name.trim(), cpf: onlyDigits(input.cpf ?? ""), address };
    case "company":
      return { legal_name: input.name.trim(), trade_name: input.tradeName?.trim() || undefined, cnpj: onlyDigits(input.cnpj ?? ""), address, ...plan };
    case "partner":
      return {
        display_name: input.name.trim(),
        document_type: input.documentType,
        document: onlyDigits(input.document ?? ""),
        specialty: input.specialty?.trim(),
        description: input.description?.trim() || undefined,
        address,
        ...plan,
      };
    case "sponsor":
      return { name: input.name.trim(), cnpj: onlyDigits(input.cnpj ?? ""), address, ...plan };
  }
}

const authMessages: Record<string, string> = {
  email_not_confirmed: "Confirme seu e-mail antes de entrar. Procure a mensagem da Escuta Aí Brasil na sua caixa de entrada.",
  invalid_credentials: "E-mail ou senha incorretos.",
  user_already_exists: "Já existe uma conta com este e-mail. Entre e adicione este perfil pela sua conta.",
  email_exists: "Já existe uma conta com este e-mail. Entre e adicione este perfil pela sua conta.",
  weak_password: `Escolha uma senha mais forte, com pelo menos ${minPasswordLength} caracteres.`,
  over_email_send_rate_limit: "Muitos e-mails enviados em pouco tempo. Aguarde alguns minutos e tente de novo.",
  over_request_rate_limit: "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente de novo.",
  email_send_failed: "Não conseguimos enviar o e-mail de confirmação agora. Nenhuma conta foi criada; tente novamente em alguns minutos.",
  signup_disabled: "O cadastro está temporariamente indisponível.",
  unexpected_failure: "Não foi possível concluir o cadastro. Se a empresa já estiver cadastrada, peça acesso a quem a cadastrou; caso contrário, confira os dados.",
};

export function authErrorMessage(code: string | undefined): string {
  return (code && authMessages[code]) || "Não foi possível concluir agora. Tente novamente em instantes.";
}

export function appRoleFor(type: ProfileType): "worker" | "admin" | "commercial" {
  if (type === "worker") return "worker";
  // No portal legado, a conta de empresa usa o papel "admin" do painel empresarial.
  return type === "company" ? "admin" : "commercial";
}

export const profileLabels: Record<ProfileType, string> = {
  worker: "Trabalhador",
  company: "Empresa",
  partner: "Parceiro",
  sponsor: "Patrocinador",
};

export function isDemoEmail(email: string): boolean {
  return email.trim().toLowerCase().endsWith("@escutaai.demo");
}

// Campanhas de patrocínio: o tipo vem do plano contratado (migration mvp_campanhas_patrocinador).
export type CampaignKind = "content" | "event" | "study";
export type CampaignStatus = "draft" | "submitted" | "approved" | "rejected";
export const campaignKindLabels: Record<CampaignKind, string> = { content: "Conteúdo patrocinado", event: "Evento", study: "Estudo público" };
export const campaignStatusLabels: Record<CampaignStatus, string> = { draft: "Rascunho", submitted: "Em revisão", approved: "Aprovada", rejected: "Recusada" };

export function campaignKindForPlan(planId: string | undefined): CampaignKind | null {
  return planId === "sponsor-content" ? "content" : planId === "sponsor-event" ? "event" : planId === "sponsor-study" ? "study" : null;
}

export interface CampaignInput {
  title: string;
  description: string;
  ctaUrl?: string;
  startsAt: string;
  endsAt: string;
}

export function isActiveCampaign(campaign: { status: CampaignStatus; endsAt: string }, today: string): boolean {
  return campaign.status !== "rejected" && campaign.endsAt >= today;
}

export function validateCampaign(input: CampaignInput, today: string): string | null {
  if (input.title.trim().length < 3) return "Dê um título com pelo menos 3 caracteres.";
  if (input.description.trim().length < 10) return "Descreva a campanha com pelo menos 10 caracteres.";
  if (input.description.length > 2000) return "A descrição pode ter até 2.000 caracteres.";
  if (input.ctaUrl?.trim() && !/^https:\/\/\S+$/.test(input.ctaUrl.trim())) return "O link precisa começar com https://.";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.startsAt) || !/^\d{4}-\d{2}-\d{2}$/.test(input.endsAt)) return "Informe início e fim da campanha.";
  if (input.startsAt < today) return "O início precisa ser hoje ou depois.";
  if (input.endsAt < input.startsAt) return "O fim precisa ser igual ou posterior ao início.";
  return null;
}
