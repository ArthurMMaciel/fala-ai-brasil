import { passwordChecks, passwordRules } from "../domain/account-rules";

// Checklist de senha do cadastro: começa em vermelho e cada regra fica verde quando atendida.
export function passwordRulesMarkup(): string {
  return `<ul class="password-rules" id="password-rules" aria-label="Regras da senha">${passwordRules
    .map(rule => `<li data-rule="${rule.id}"><span class="password-rule-icon" aria-hidden="true">✕</span> ${rule.label}<span class="visually-hidden"> (pendente)</span></li>`)
    .join("")}</ul>`;
}

function update(form: HTMLFormElement) {
  const list = form.querySelector<HTMLUListElement>("#password-rules");
  if (!list) return;
  const password = form.querySelector<HTMLInputElement>('input[name="password"]')?.value ?? "";
  const confirm = form.querySelector<HTMLInputElement>('input[name="confirm"]')?.value ?? "";
  const checks = passwordChecks(password, confirm);
  list.querySelectorAll<HTMLLIElement>("li[data-rule]").forEach(item => {
    const ok = checks[item.dataset.rule as keyof typeof checks];
    item.classList.toggle("ok", ok);
    item.querySelector(".password-rule-icon")!.textContent = ok ? "✓" : "✕";
    item.querySelector(".visually-hidden")!.textContent = ok ? " (atendida)" : " (pendente)";
  });
}

document.addEventListener("input", event => {
  const input = event.target;
  if (input instanceof HTMLInputElement && (input.name === "password" || input.name === "confirm") && input.form) update(input.form);
});
