// Modal de confirmação da plataforma (ClickUp 17tu7rpgnev, 2026-11-24): substitui o window.confirm do navegador.
// Mostra o título, o efeito da ação, o botão principal (vermelho quando destrutivo) e Cancelar. Acessível: role
// alertdialog, aria-modal, foco preso dentro do modal, Esc e clique fora cancelam, e o foco volta para onde estava.
// O resultado da ação continua indo para o toast (showToast), quem chama decide a mensagem.

export interface ConfirmOptions {
  title: string;
  text: string;
  confirmLabel: string;
  cancelLabel?: string;
  /** Ação que apaga, bloqueia, recusa ou não tem volta: botão principal em vermelho. */
  danger?: boolean;
}

let open: Promise<boolean> | null = null;

export function confirmAction(options: ConfirmOptions): Promise<boolean> {
  if (typeof document === "undefined") return Promise.resolve(false);
  if (open) return open; // um modal por vez: um segundo clique não empilha outro
  const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  const id = `confirm-${Date.now().toString(36)}`;

  const overlay = document.createElement("div");
  overlay.className = "confirm-overlay";
  const dialog = document.createElement("div");
  dialog.className = "confirm-dialog";
  dialog.setAttribute("role", "alertdialog");
  dialog.setAttribute("aria-modal", "true");
  dialog.setAttribute("aria-labelledby", `${id}-title`);
  dialog.setAttribute("aria-describedby", `${id}-text`);

  const title = document.createElement("h2");
  title.id = `${id}-title`;
  title.className = "confirm-title";
  title.textContent = options.title;
  const text = document.createElement("p");
  text.id = `${id}-text`;
  text.className = "confirm-text";
  text.textContent = options.text;

  const actions = document.createElement("div");
  actions.className = "confirm-actions";
  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "btn";
  cancel.textContent = options.cancelLabel ?? "Cancelar";
  const accept = document.createElement("button");
  accept.type = "button";
  accept.className = options.danger ? "btn primary danger" : "btn primary";
  accept.textContent = options.confirmLabel;
  actions.append(cancel, accept);
  dialog.append(title, text, actions);
  overlay.append(dialog);

  // A raiz do app (#app) fica escondida do leitor de tela enquanto o modal está aberto.
  const app = document.getElementById("app");
  const appHidden = app?.getAttribute("aria-hidden");
  app?.setAttribute("aria-hidden", "true");
  document.body.classList.add("confirm-open");
  document.body.append(overlay);
  // Ação destrutiva abre com o foco em Cancelar; as outras, no botão principal.
  (options.danger ? cancel : accept).focus();

  open = new Promise<boolean>(resolve => {
    const close = (result: boolean) => {
      document.removeEventListener("keydown", onKey, true);
      overlay.remove();
      document.body.classList.remove("confirm-open");
      if (appHidden === null || appHidden === undefined) app?.removeAttribute("aria-hidden"); else app?.setAttribute("aria-hidden", appHidden);
      open = null;
      if (previous && previous.isConnected) previous.focus();
      resolve(result);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); close(false); return; }
      if (event.key !== "Tab") return;
      const focusable = [cancel, accept];
      const index = focusable.indexOf(document.activeElement as HTMLButtonElement);
      event.preventDefault();
      const next = event.shiftKey ? (index <= 0 ? focusable.length - 1 : index - 1) : (index + 1) % focusable.length;
      focusable[next].focus();
    };
    document.addEventListener("keydown", onKey, true);
    cancel.addEventListener("click", () => close(false));
    accept.addEventListener("click", () => close(true));
    overlay.addEventListener("mousedown", event => { if (event.target === overlay) close(false); });
  });
  return open;
}
