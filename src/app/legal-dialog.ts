import termsSource from "../content/legal/termos-de-uso.md?raw";
import privacySource from "../content/legal/aviso-de-privacidade.md?raw";
import { parseLegalDoc, type LegalBlock, type LegalRoute } from "../domain/legal-docs";

// Termos de uso e aviso de privacidade em modal (pedido do responsável, 2026-11-26): "abra um modal com os termos
// abertos que ele tem que 'ler' para fechar". Mesmo texto de src/content/legal, com a marca de revisão jurídica.
// "Li e fechar" só fica ativo depois de rolar até o fim; antes disso, Esc e clique fora não fecham. As rotas
// /#termos e /#privacidade continuam para links diretos (rodapé, e-mails).
const sources: Record<LegalRoute, string> = { terms: termsSource, privacy: privacySource };
export const legalDialogTexts = {
  hint: "Role até o fim para continuar.",
  done: "Você chegou ao fim. Já pode fechar.",
  close: "Li e fechar",
  review: "Texto em revisão jurídica. Este conteúdo ainda não é a versão final.",
};

/** Fim do texto: margem de 8 px para arredondamento de zoom e de rolagem. */
export function reachedEnd(box: { scrollTop: number; clientHeight: number; scrollHeight: number }): boolean {
  return box.scrollTop + box.clientHeight >= box.scrollHeight - 8;
}

function blockElement(block: LegalBlock): HTMLElement {
  if (block.kind === "heading") { const h = document.createElement(block.level === 2 ? "h3" : "h4"); h.textContent = block.text; return h; }
  if (block.kind === "list") {
    const list = document.createElement("ul");
    for (const item of block.items) { const li = document.createElement("li"); li.textContent = item; list.append(li); }
    return list;
  }
  const p = document.createElement("p");
  if (block.kind === "note") p.className = "legal-note";
  p.textContent = block.text;
  return p;
}

let open: Promise<boolean> | null = null;

/** Abre o texto completo. Resolve true quando a pessoa leu até o fim e fechou. */
export function openLegalDialog(route: LegalRoute): Promise<boolean> {
  if (typeof document === "undefined") return Promise.resolve(false);
  if (open) return open;
  const doc = parseLegalDoc(sources[route]);
  const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  const id = `legal-${route}`;

  const overlay = document.createElement("div");
  overlay.className = "legal-overlay";
  const dialog = document.createElement("div");
  dialog.className = "legal-dialog";
  dialog.setAttribute("role", "dialog");
  dialog.setAttribute("aria-modal", "true");
  dialog.setAttribute("aria-labelledby", `${id}-title`);

  const header = document.createElement("div");
  header.className = "legal-dialog-head";
  const title = document.createElement("h2");
  title.id = `${id}-title`;
  title.textContent = doc.title;
  header.append(title);
  if (doc.inReview) { const banner = document.createElement("p"); banner.className = "legal-review-banner"; banner.textContent = legalDialogTexts.review; header.append(banner); }

  const body = document.createElement("div");
  body.className = "legal-dialog-body";
  body.tabIndex = 0; // setas, PageDown e espaço rolam o texto com o teclado
  body.setAttribute("role", "region");
  body.setAttribute("aria-label", `Texto completo: ${doc.title}`);
  for (const block of doc.blocks) body.append(blockElement(block));
  const version = document.createElement("p");
  version.className = "muted small";
  version.textContent = `Versão ${doc.version || "sem versão"}${doc.inReview ? " · em revisão" : ""}`;
  body.append(version);

  const footer = document.createElement("div");
  footer.className = "legal-dialog-foot";
  const hint = document.createElement("p");
  hint.className = "legal-dialog-hint";
  hint.setAttribute("aria-live", "polite");
  hint.textContent = legalDialogTexts.hint;
  const close = document.createElement("button");
  close.type = "button";
  close.className = "btn primary";
  close.textContent = legalDialogTexts.close;
  close.disabled = true;
  footer.append(hint, close);

  dialog.append(header, body, footer);
  overlay.append(dialog);
  const app = document.getElementById("app");
  const appHidden = app?.getAttribute("aria-hidden");
  app?.setAttribute("aria-hidden", "true");
  document.body.classList.add("confirm-open");
  document.body.append(overlay);
  body.focus();

  open = new Promise<boolean>(resolve => {
    let unlocked = false;
    const unlock = () => {
      if (unlocked || !reachedEnd(body)) return;
      unlocked = true;
      close.disabled = false;
      hint.textContent = legalDialogTexts.done;
      dialog.classList.add("is-read");
    };
    const finish = (read: boolean) => {
      document.removeEventListener("keydown", onKey, true);
      window.removeEventListener("resize", unlock);
      overlay.remove();
      document.body.classList.remove("confirm-open");
      if (appHidden === null || appHidden === undefined) app?.removeAttribute("aria-hidden"); else app?.setAttribute("aria-hidden", appHidden);
      open = null;
      if (previous && previous.isConnected) previous.focus();
      resolve(read);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); if (unlocked) finish(true); return; }
      if (event.key !== "Tab") return;
      const focusable: HTMLElement[] = unlocked ? [body, close] : [body];
      const index = focusable.indexOf(document.activeElement as HTMLElement);
      event.preventDefault();
      focusable[event.shiftKey ? (index <= 0 ? focusable.length - 1 : index - 1) : (index + 1) % focusable.length].focus();
    };
    document.addEventListener("keydown", onKey, true);
    body.addEventListener("scroll", unlock, { passive: true });
    // Girar o celular ou aumentar a janela pode fazer o texto caber inteiro, sem rolagem: reavalia o fim.
    window.addEventListener("resize", unlock);
    close.addEventListener("click", () => { if (unlocked) finish(true); });
    overlay.addEventListener("mousedown", event => { if (event.target === overlay && unlocked) finish(true); });
    unlock(); // texto curto que cabe inteiro na tela já libera o botão
  });
  return open;
}

// Links com data-legal="terms|privacy" abrem o modal no lugar de outra aba. Depois de ler e fechar, a caixa de aceite
// do mesmo rótulo é marcada (a pessoa ainda pode desmarcar).
if (typeof document !== "undefined") {
  document.addEventListener("click", event => {
    const link = (event.target as Element | null)?.closest?.<HTMLAnchorElement>("a[data-legal]");
    const route = link?.dataset.legal;
    if (!link || (route !== "terms" && route !== "privacy")) return;
    event.preventDefault();
    const checkbox = link.closest("label")?.querySelector<HTMLInputElement>('input[type="checkbox"]');
    openLegalDialog(route).then(read => {
      if (!read || !checkbox || checkbox.checked) return;
      checkbox.checked = true;
      checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    });
  });
}
