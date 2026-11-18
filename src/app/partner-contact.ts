import { maskPhone } from "../domain/account-rules";

// Cadastro de parceiro: o e-mail de contato acompanha o de login até a pessoa editá-lo; o telefone recebe a máscara do cadastro.
document.addEventListener("input", event => {
  const input = event.target;
  if (!(input instanceof HTMLInputElement) || !input.form) return;
  if (input.name === "contactPhone") { input.value = maskPhone(input.value); return; }
  const follow = input.form.querySelector<HTMLInputElement>("input[data-follow-login]");
  if (!follow) return;
  if (input === follow) { follow.dataset.edited = follow.value.trim() ? "1" : ""; return; }
  if (input.name === "email" && follow.dataset.edited !== "1") follow.value = input.value;
});
