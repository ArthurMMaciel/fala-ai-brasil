import { escapeHtml } from "../domain/html-safety";
import { recoveryRateLimitMessage, recoverySentMessage, validateNewPassword, validateRecoveryEmail } from "../domain/password-recovery";
import { requestPasswordReset, updatePassword } from "../services/account";
import { passwordRulesMarkup } from "./password-rules";
import { showToast } from "./toast";

// Telas "Esqueci minha senha" e "Criar nova senha" (ADR-0024). Login e cadastro continuam no main.js; aqui só o fluxo novo.
export interface RecoveryNotice { email?: string; recoverySent?: boolean }

const eye = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>';
const passwordField = (id: string, name: string, label: string, extra = "") => `<div class="field"><label for="${id}">${label}</label><div class="password-field"><input id="${id}" name="${name}" type="password" autocomplete="new-password" required /><button class="password-toggle" type="button" data-action="toggle-password" data-target="${id}" aria-label="Mostrar ${label.toLowerCase()}" aria-pressed="false">${eye}</button></div>${extra}</div>`;

export function forgotPasswordMarkup(notice: RecoveryNotice | null | undefined, audience = "worker"): string {
  const email = escapeHtml(notice?.email ?? "");
  const back = `<p class="auth-switch"><button type="button" class="text-action" data-action="open-auth" data-mode="login" data-audience="${escapeHtml(audience)}">Voltar para entrar</button></p>`;
  if (notice?.recoverySent) return `<main class="form-shell"><section class="auth-box check-email"><span class="eyebrow">Esqueci minha senha</span><h2>Confira seu e-mail.</h2>
    <p role="status">${recoverySentMessage} Ainda não tem conta? <button type="button" class="text-action" data-action="open-auth" data-mode="register" data-audience="worker">Cadastre-se</button></p>
    ${back}</section></main>`;
  return `<main class="form-shell"><section class="auth-box"><span class="eyebrow">Esqueci minha senha</span><h2>Crie uma nova senha.</h2>
    <p class="muted">Digite o e-mail da sua conta. Se ele estiver cadastrado, você recebe um link para criar uma nova senha.</p>
    <form data-form="forgot-password" novalidate><div class="field"><label for="forgot-email">E-mail</label><input id="forgot-email" name="email" type="email" autocomplete="email" maxlength="254" value="${email}" required /></div>
    <p class="field-error" data-recovery-error role="alert" hidden></p>
    <div class="auth-actions"><button class="btn primary" type="submit">Enviar link</button></div></form>
    ${back}</section></main>`;
}

export function resetPasswordMarkup(): string {
  return `<main class="form-shell"><section class="auth-box"><span class="eyebrow">Nova senha</span><h2>Criar nova senha</h2>
    <p class="muted">Escolha uma senha nova para a sua conta. A regra é a mesma do cadastro.</p>
    <form data-form="reset-password" novalidate>${passwordField("reset-password", "password", "Nova senha")}${passwordField("reset-confirm", "confirm", "Confirmação da nova senha", passwordRulesMarkup())}
    <p class="field-error" data-recovery-error role="alert" hidden></p>
    <div class="auth-actions"><button class="btn primary" type="submit">Salvar nova senha</button></div></form></section></main>`;
}

export function bindPasswordRecovery(root: ParentNode, handlers: { sent: (email: string) => void; saved: () => void }): void {
  const showError = (form: HTMLFormElement, message: string) => { const line = form.querySelector<HTMLElement>("[data-recovery-error]"); if (line) { line.textContent = message; line.hidden = !message; } };
  const forgot = root.querySelector<HTMLFormElement>('[data-form="forgot-password"]');
  forgot?.addEventListener("submit", async event => {
    event.preventDefault();
    const email = String(new FormData(forgot).get("email") ?? "");
    const problem = validateRecoveryEmail(email);
    if (problem) return showError(forgot, problem);
    const button = forgot.querySelector<HTMLButtonElement>('[type="submit"]');
    if (button) { button.disabled = true; button.textContent = "Enviando…"; }
    const outcome = await requestPasswordReset(email);
    if (outcome === "rate_limited") {
      if (button) { button.disabled = false; button.textContent = "Enviar link"; }
      return showToast("error", recoveryRateLimitMessage);
    }
    handlers.sent(email.trim().toLowerCase());
  });
  const reset = root.querySelector<HTMLFormElement>('[data-form="reset-password"]');
  reset?.addEventListener("submit", async event => {
    event.preventDefault();
    const data = new FormData(reset);
    const password = String(data.get("password") ?? ""), confirm = String(data.get("confirm") ?? "");
    const problem = validateNewPassword(password, confirm);
    if (problem) return showError(reset, problem);
    const button = reset.querySelector<HTMLButtonElement>('[type="submit"]');
    if (button) { button.disabled = true; button.textContent = "Salvando…"; }
    const result = await updatePassword(password);
    if (!result.ok) {
      if (button) { button.disabled = false; button.textContent = "Salvar nova senha"; }
      return showToast("error", result.message);
    }
    handlers.saved();
  });
}
