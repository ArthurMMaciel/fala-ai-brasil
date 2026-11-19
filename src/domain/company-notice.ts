import { brazilianStates } from './account-rules';

// ADR-0023: relato contra empresa não cadastrada e aviso à empresa, sem conteúdo, aprovado e enviado à mão pela equipe.
// Textos marcados "em revisão jurídica" até o advogado (prazo 24/11). Mudar aqui muda todas as telas.
export const noticeTextsInReview = true;
// Endereço do site no e-mail de aviso, como TEXTO (sem https:// nem link). Decisão do responsável em 2026-11-19;
// trocar aqui quando houver domínio próprio. Alguns leitores de e-mail transformam texto em link por conta própria.
export const platformAddress = 'fala-ai-brasil.vercel.app';
export const noticeTexts = {
  field: 'E-mail da empresa para o aviso (opcional)',
  help: 'Prefira um canal institucional, como RH, ouvidoria ou o contato do site. Não indique o e-mail pessoal de alguém.',
  question: 'A pessoa desse contato pode estar envolvida no que você relata?',
  // Consentimento único para qualquer empresa (contrato do Back e0f43bd, em revisão jurídica).
  consent: 'A equipe da Escuta Aí Brasil pode usar este contato como segundo canal com a empresa. Se a empresa ainda não estiver na plataforma, ela receberá por ele um aviso de que existe um relato, sem o conteúdo, sem o seu nome e sem a data.',
  involvedWarning: 'Com essa resposta, o aviso não será enviado a esse e-mail.',
  notSharedWarning: 'O e-mail para o aviso só é guardado quando você solicita a revisão. Ao guardar sem compartilhar, ele não é enviado.',
  // Texto que a equipe copia e envia da conta da plataforma. Sem link clicável (ADR-0023, mitigação do Gmail).
  emailSubject: 'Escuta Aí Brasil: existe um relato sobre a sua empresa',
  emailBody: [
    'Olá,',
    'A Escuta Aí Brasil é uma plataforma de escuta psicossocial no trabalho. Informamos que existe um relato na plataforma relacionado à sua empresa.',
    'Este aviso não traz o conteúdo do relato, a identidade de quem relatou nem a data.',
    `Para saber mais, digite no navegador o endereço ${platformAddress} e cadastre a empresa com o CNPJ. Não enviamos links por e-mail.`,
    'Se não quiser receber novos avisos, responda a este e-mail pedindo a exclusão.',
    'Equipe Escuta Aí Brasil',
  ].join('\n\n'),
};

// Aceite do aviso (revisão do DevOps, 2026-11-19): para empresa NÃO cadastrada a pergunta aparece sempre, com ou sem
// contato. Sem "Sim", nenhum aviso sai, nem pelo e-mail da Receita. Chave provisória até o contrato do Back; o
// create_complaint atual ignora chaves que não conhece.
export const noticeConsentKey = 'notice_consent';
export const noticeConsentQuestion = 'Aceito que a empresa receba um aviso de que existe um relato, sem o conteúdo, sem o meu nome e sem a data.';
export const noticeConsentMissing = 'Responda se aceita que a empresa receba o aviso.';
export type NoticeConsent = 'yes' | 'no' | '';

export type Involvement = 'yes' | 'no' | 'unknown' | '';
export const involvementLabels: Record<Exclude<Involvement, ''>, string> = { yes: 'Sim', no: 'Não', unknown: 'Não sei' };

// Contato na empresa em TODA manifestação (decisão do responsável, 2026-11-19; contrato do Back e0f43bd):
// p.notice_contact = { email?, phone?, possibly_involved, consent: true }, pelo menos um entre e-mail e telefone, só com p_share.
export const companyContactPhoneEnabled = true;

// Empresa cadastrada: o contato fica só com a equipe, como segundo canal; a empresa não vê.
export const registeredContactTexts = {
  intro: 'Se quiser, indique um contato da empresa, como o RH. Esse contato fica só com a equipe da Escuta Aí Brasil, como segundo canal desta manifestação. A empresa não vê o contato que você indicar. É opcional.',
  email: 'E-mail de contato na empresa (opcional)',
  phone: 'Telefone de contato na empresa (opcional)',
  consent: noticeTexts.consent,
  missingConsent: 'Para indicar um contato, confirme o uso dele pela equipe.',
};

export interface NoticeContactInput { email: string; phone?: string; involvement: Involvement; consent: boolean }
export interface NoticeContactPayload { email?: string; phone?: string; possibly_involved: boolean; consent: true }

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const phoneDigits = (value: string) => value.replace(/\D/g, '');
const hasPhone = (input: NoticeContactInput) => companyContactPhoneEnabled && Boolean(phoneDigits(input.phone ?? ''));

// Sem contato, nada a validar (é opcional). Com e-mail ou telefone, pergunta e consentimento são obrigatórios.
export function validateNoticeContact(input: NoticeContactInput, registered = false): string | null {
  const email = input.email.trim();
  if (!email && !hasPhone(input)) return null;
  // Mesmas mensagens do create_complaint (contrato e0f43bd).
  if (email && (email.length > 254 || !emailPattern.test(email))) return 'Informe um e-mail de contato válido.';
  if (hasPhone(input) && !/^\d{10,11}$/.test(phoneDigits(input.phone ?? ''))) return 'Informe um telefone de contato com DDD (10 ou 11 dígitos).';
  if (!input.involvement) return 'Responda se a pessoa desse contato pode estar envolvida no que você relata.';
  if (!input.consent) return registeredContactTexts.missingConsent;
  return null;
}

// "Não sei" conta como possivelmente envolvido (decisão do Gestor em 18/11, coerente com a ADR-0012 D4).
export function noticeContactPayload(input: NoticeContactInput, registered = false): NoticeContactPayload | null {
  const email = input.email.trim();
  if ((!email && !hasPhone(input)) || validateNoticeContact(input, registered)) return null;
  return { ...(email ? { email: email.toLowerCase() } : {}), ...(hasPhone(input) ? { phone: phoneDigits(input.phone ?? '') } : {}), possibly_involved: input.involvement !== 'no', consent: true };
}

export function validateManualCompany(name: string, city: string, state: string): string | null {
  if (name.trim().length < 2 || name.trim().length > 160) return 'Informe o nome da empresa (2 a 160 caracteres).';
  if (city.trim().length < 2 || city.trim().length > 80) return 'Informe o município da empresa.';
  if (!brazilianStates.includes(state.trim().toUpperCase())) return 'Informe a UF da empresa.';
  return null;
}

export interface LookupCompany { name: string; city: string; state: string }
export type LookupOutcome = { kind: 'found'; company: LookupCompany } | { kind: 'manual' };

const text = (value: unknown) => typeof value === 'string' ? value.trim() : '';
const pick = (row: Record<string, unknown>, keys: string[]) => keys.map(key => text(row[key])).find(Boolean) ?? '';

// Contrato da cnpj-lookup (ADR-0017): 200 com status "found" e a lista branca, ou "manual". Qualquer outra coisa vira preenchimento manual.
export function lookupOutcome(status: number, body: unknown): LookupOutcome {
  if (status !== 200 || !body || typeof body !== 'object') return { kind: 'manual' };
  const data = body as Record<string, unknown>;
  if (data.status !== 'found' || !data.company || typeof data.company !== 'object') return { kind: 'manual' };
  const row = data.company as Record<string, unknown>;
  const name = pick(row, ['trade_name', 'nome_fantasia', 'legal_name', 'razao_social', 'name']);
  const city = pick(row, ['city', 'municipio']);
  const state = pick(row, ['state', 'uf']).toUpperCase();
  return name && city && brazilianStates.includes(state) ? { kind: 'found', company: { name, city, state } } : { kind: 'manual' };
}

// Operação
export const opsNoticeReasonLimits = { min: 10, max: 300 };
export function validateOpsReason(reason: string): string | null {
  const length = reason.trim().length;
  return length < opsNoticeReasonLimits.min || length > opsNoticeReasonLimits.max ? 'Informe o motivo (10 a 300 caracteres, sem conteúdo de relato).' : null;
}

export type NoticeStatus = 'approved' | 'sent' | 'rejected' | 'bounced';
export const noticeStatusLabels: Record<NoticeStatus, string> = { approved: 'Aprovado, a enviar', sent: 'Enviado', rejected: 'Recusado', bounced: 'E-mail voltou' };
export type NoticeTab = 'decide' | 'approved' | 'sent' | 'rejected';
export interface NoticeCandidateState { contactStatus: string; noticeStatus: NoticeStatus | null }

export function noticeTab(row: NoticeCandidateState): NoticeTab {
  if (row.noticeStatus === 'approved') return 'approved';
  if (row.noticeStatus === 'sent' || row.noticeStatus === 'bounced') return 'sent';
  if (row.noticeStatus === 'rejected' || row.contactStatus === 'rejected') return 'rejected';
  return 'decide';
}

export const registrationLabels: Record<string, string> = { pending_check: 'A conferir', pre_registered: 'Pré-cadastrada', registered: 'Cadastrada' };
export const dataSourceLabels: Record<string, string> = { manual: 'Preenchida pelo trabalhador', cnpj_api: 'Consulta de CNPJ', signup: 'Cadastro da empresa' };
