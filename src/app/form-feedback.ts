import { showToast } from "./toast";

// Substitui os balões nativos de validação do navegador por um toast vermelho e destaca o campo.
// Vale para todos os formulários (main.js e portais React): o navegador continua bloqueando o envio.
let pending: HTMLElement[] = [];
let scheduled = false;

function labelFor(field: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement): string {
  const explicit = field.id ? document.querySelector<HTMLLabelElement>(`label[for="${CSS.escape(field.id)}"]`) : null;
  const wrapping = field.closest("label");
  const text = (explicit ?? wrapping)?.textContent ?? field.getAttribute("aria-label") ?? field.name;
  return text.replace(/\s+/g, " ").replace(/\(opcional\)/i, "").trim();
}

function messageFor(field: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement): string {
  const label = labelFor(field);
  const state = field.validity;
  if (state.customError) return field.validationMessage;
  if (state.valueMissing) {
    if (field instanceof HTMLInputElement && field.type === "checkbox") return `Para continuar, marque: "${label}"`;
    if (field instanceof HTMLSelectElement) return `Selecione uma opção em "${label}".`;
    return `Preencha o campo "${label}".`;
  }
  if (state.typeMismatch && field instanceof HTMLInputElement && field.type === "email") return "Informe um e-mail válido, como nome@empresa.com.br.";
  if (state.tooShort && "minLength" in field) return `"${label}" precisa ter pelo menos ${field.minLength} caracteres.`;
  if (state.tooLong && "maxLength" in field) return `"${label}" pode ter até ${field.maxLength} caracteres.`;
  if (state.patternMismatch) return `Confira o formato de "${label}".`;
  return `Confira o campo "${label}".`;
}

function flush() {
  scheduled = false;
  const fields = pending.filter(field => field.isConnected);
  pending = [];
  const first = fields[0] as HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | undefined;
  if (!first) return;
  showToast("error", messageFor(first), "Confira os dados");
  first.focus({ preventScroll: true });
  first.scrollIntoView({ block: "center", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
}

document.addEventListener("invalid", event => {
  const field = event.target;
  if (!(field instanceof HTMLInputElement || field instanceof HTMLSelectElement || field instanceof HTMLTextAreaElement)) return;
  event.preventDefault();
  field.setAttribute("aria-invalid", "true");
  field.closest(".field, label")?.classList.add("is-invalid");
  pending.push(field);
  if (!scheduled) { scheduled = true; queueMicrotask(flush); }
}, true);

function clear(event: Event) {
  const field = event.target;
  if (!(field instanceof HTMLElement) || field.getAttribute("aria-invalid") !== "true") return;
  field.removeAttribute("aria-invalid");
  field.closest(".field, label")?.classList.remove("is-invalid");
}
document.addEventListener("input", clear, true);
document.addEventListener("change", clear, true);
