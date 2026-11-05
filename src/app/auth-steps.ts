import { isValidCnpj, isValidCpf } from "../domain/account-rules";

// Cadastro em etapas (dados, endereço, plano, senha e termos). O formulário é renderizado por main.js;
// este módulo só mostra uma etapa por vez e impede avançar com campo obrigatório pendente.
let form: HTMLFormElement | null = null;
let current = 0;

function steps(target: HTMLFormElement) {
  return [...target.querySelectorAll<HTMLFieldSetElement>(":scope > .auth-step")];
}

function render(target: HTMLFormElement) {
  const list = steps(target);
  if (!list.length) return;
  current = Math.min(Math.max(current, 0), list.length - 1);
  list.forEach((step, index) => { step.hidden = index !== current; });
  const last = current === list.length - 1;
  target.querySelector<HTMLElement>("[data-step-back]")!.hidden = current === 0;
  target.querySelector<HTMLElement>("[data-step-next]")!.hidden = last;
  target.querySelector<HTMLElement>("[data-step-submit]")!.hidden = !last;
  const bar = target.querySelector<HTMLElement>(".auth-stepper-bar");
  if (bar) bar.innerHTML = list.map((_, index) => `<i class="${index < current ? "done" : index === current ? "current" : ""}"></i>`).join("");
  const label = target.querySelector<HTMLElement>(".auth-stepper-label");
  if (label) label.textContent = `Etapa ${current + 1} de ${list.length} · ${list[current].dataset.title ?? ""}`;
  const box = target.closest<HTMLElement>(".auth-box");
  if (box) box.dataset.currentStep = String(current + 1);
}

function checkDocument(input: HTMLInputElement) {
  const value = input.value.trim();
  if (!value) return;
  const type = input.name === "document" ? input.form?.querySelector<HTMLSelectElement>('select[name="documentType"]')?.value : input.name;
  const valid = type === "cnpj" ? isValidCnpj(value) : isValidCpf(value);
  input.setCustomValidity(valid ? "" : type === "cnpj" ? "Confira o CNPJ informado." : "Confira o CPF informado.");
}

function stepIsValid(step: HTMLFieldSetElement) {
  step.querySelectorAll<HTMLInputElement>('input[name="cpf"], input[name="cnpj"], input[name="document"]').forEach(checkDocument);
  const fields = [...step.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>("input, select, textarea")].filter(field => !field.disabled);
  const invalid = fields.find(field => !field.checkValidity());
  if (!invalid) return true;
  invalid.reportValidity();
  invalid.focus();
  return false;
}

function move(delta: number) {
  if (!form) return;
  const list = steps(form);
  if (delta > 0 && !stepIsValid(list[current])) return;
  current += delta;
  render(form);
  const next = steps(form)[current];
  next?.querySelector<HTMLElement>("input, select, textarea")?.focus({ preventScroll: true });
  form.closest(".auth-box")?.scrollIntoView({ block: "start", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
}

document.addEventListener("click", event => {
  const target = event.target instanceof Element ? event.target : null;
  if (target?.closest("[data-step-next]")) move(1);
  else if (target?.closest("[data-step-back]")) move(-1);
});

// Enter antes da última etapa avança em vez de enviar (captura antes do handler de main.js).
document.addEventListener("submit", event => {
  const target = event.target;
  if (!(target instanceof HTMLFormElement) || target !== form) return;
  if (current < steps(target).length - 1) { event.preventDefault(); event.stopImmediatePropagation(); move(1); }
}, true);

document.addEventListener("input", event => {
  const input = event.target;
  if (input instanceof HTMLInputElement && ["cpf", "cnpj", "document"].includes(input.name)) input.setCustomValidity("");
});

// Cada novo formulário de cadastro (troca de persona, nova visita) começa na primeira etapa.
new MutationObserver(() => {
  const found = document.querySelector<HTMLFormElement>("form.auth-steps-form");
  if (found && found !== form) { form = found; current = 0; render(found); }
  else if (!found) form = null;
}).observe(document.documentElement, { childList: true, subtree: true });
