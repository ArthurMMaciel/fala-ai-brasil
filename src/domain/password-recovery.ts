import { minPasswordLength, passwordChecks, passwordRules } from './account-rules';

// Esqueci minha senha (ADR-0024). A resposta ao pedido é sempre a mesma, exista a conta ou não (aprovado pelo responsável).
export const recoverySentMessage = 'Se houver uma conta com esse e-mail, enviamos um link para criar uma nova senha. Confira também a caixa de spam.';
export const recoveryRateLimitMessage = 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente de novo.';
export const recoveryExpiredMessage = 'O link para criar uma nova senha expirou ou já foi usado. Peça um novo em "Esqueci minha senha".';
export const recoverySavedMessage = 'Senha alterada. Você já está na sua conta.';

const rateLimitCodes = new Set(['over_email_send_rate_limit', 'over_request_rate_limit']);

// Só o limite de envio vira mensagem própria; qualquer outro erro volta à resposta neutra, para não revelar se a conta existe.
export function recoveryRequestOutcome(errorCode: string | null | undefined, status?: number): 'sent' | 'rate_limited' {
  return errorCode && rateLimitCodes.has(errorCode) || status === 429 ? 'rate_limited' : 'sent';
}

export function validateRecoveryEmail(email: string): string | null {
  const value = email.trim();
  return value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value) ? null : 'Informe um e-mail válido.';
}

// Mesma regra de senha do cadastro.
export function validateNewPassword(password: string, confirm: string): string | null {
  const checks = passwordChecks(password, confirm);
  if (password.length < minPasswordLength) return `A senha precisa ter pelo menos ${minPasswordLength} caracteres.`;
  const missing = passwordRules.filter(rule => rule.id !== 'match' && !checks[rule.id]).map(rule => rule.label.toLowerCase());
  if (missing.length) return `A senha precisa ter: ${missing.join(', ')}.`;
  if (!checks.match) return 'A confirmação de senha precisa ser igual à senha informada.';
  return null;
}

export function passwordUpdateError(code: string | null | undefined): string {
  if (code === 'same_password') return 'A nova senha precisa ser diferente da anterior.';
  if (code === 'weak_password') return 'Escolha uma senha mais forte: maiúscula, minúscula, número e caractere especial.';
  if (code === 'session_not_found' || code === 'session_expired' || code === 'bad_jwt' || code === 'no_session') return recoveryExpiredMessage;
  if (code && rateLimitCodes.has(code)) return recoveryRateLimitMessage;
  return 'Não foi possível salvar a nova senha. Tente novamente.';
}

// Tipo do retorno de um link do Auth no hash (#...&type=recovery). Lido antes de o cliente limpar o hash.
export function authLinkType(hash: string): 'recovery' | 'signup' | 'email_change' | null {
  const type = new URLSearchParams(String(hash ?? '').replace(/^#/, '')).get('type');
  return type === 'recovery' || type === 'signup' || type === 'email_change' ? type : null;
}
