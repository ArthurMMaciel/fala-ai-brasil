import { maskPhone } from '../domain/account-rules';
import { landingContactInput } from '../domain/landing-contact';
import { submitContactSolicitation, validateContactSolicitation } from '../services/contact-solicitations';

// Liga o formulário de contato das páginas estáticas (inicio, empresa, parceiros, patrocinio, intelligence) à RPC submit_contact_solicitation.
const value = (form: HTMLFormElement, name: string) => {
  const field = form.elements.namedItem(name);
  return field instanceof HTMLInputElement ? field.value : '';
};

document.querySelectorAll<HTMLFormElement>('form[data-contato]').forEach(form => {
  const button = form.querySelector<HTMLButtonElement>('button[type=submit]');
  const error = form.querySelector<HTMLElement>('[data-contato-erro]');
  const phone = form.elements.namedItem('telefone');
  if (phone instanceof HTMLInputElement) phone.addEventListener('input', () => { phone.value = maskPhone(phone.value); });
  const showError = (message: string) => { if (error) { error.textContent = message; error.hidden = !message; } };
  form.addEventListener('input', () => showError(''));
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const perfil = form.querySelector<HTMLInputElement>('input[name=perfil]:checked')?.value ?? '';
    const input = landingContactInput({ perfil, pagina: form.dataset.pagina ?? '', nome: value(form, 'nome'), email: value(form, 'email'), telefone: value(form, 'telefone'), organizacao: value(form, 'organizacao'), botField: value(form, 'bot-field') });
    if (!input) return showError('Escolha o seu perfil.');
    const problem = validateContactSolicitation(input);
    if (problem) return showError(problem);
    if (!button) return;
    const label = button.textContent;
    button.disabled = true; button.textContent = 'Enviando…';
    const result = await submitContactSolicitation(input);
    if (!result.ok) { button.disabled = false; button.textContent = label; return showError(result.message); }
    const done = document.createElement('div');
    done.className = 'form-ok'; done.setAttribute('role', 'status');
    const title = document.createElement('strong'); title.textContent = 'Solicitação recebida.';
    const text = document.createElement('p'); text.textContent = 'Retornaremos assim que possível pelo contato informado.';
    done.append(title, text);
    form.replaceChildren(done);
  });
});
