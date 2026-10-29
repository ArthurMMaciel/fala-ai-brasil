import { maskCnpj, maskCpf } from "../domain/account-rules";

// Máscara de CPF/CNPJ por delegação: cobre os formulários renderizados por main.js a qualquer momento.
function maskFor(input: HTMLInputElement): ((value: string) => string) | undefined {
  if (input.name === "cpf") return maskCpf;
  if (input.name === "cnpj") return maskCnpj;
  if (input.name === "document") {
    const type = input.form?.querySelector<HTMLSelectElement>('select[name="documentType"]')?.value;
    return type === "cnpj" ? maskCnpj : maskCpf;
  }
  return undefined;
}

function apply(input: HTMLInputElement) {
  const mask = maskFor(input);
  if (!mask) return;
  const atEnd = input.selectionStart === input.value.length;
  const masked = mask(input.value);
  if (masked !== input.value) input.value = masked;
  if (atEnd) input.setSelectionRange(masked.length, masked.length);
}

document.addEventListener("input", event => {
  if (event.target instanceof HTMLInputElement) apply(event.target);
});

document.addEventListener("change", event => {
  const select = event.target;
  if (!(select instanceof HTMLSelectElement) || select.name !== "documentType") return;
  const input = select.form?.querySelector<HTMLInputElement>('input[name="document"]');
  if (!input) return;
  input.placeholder = select.value === "cnpj" ? "00.000.000/0000-00" : "000.000.000-00";
  apply(input);
});
