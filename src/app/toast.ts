// Notificações visíveis e acessíveis para sucesso e erro (substituem mensagens inline e alert()).
export type ToastKind = "success" | "error" | "info";

const durations: Record<ToastKind, number> = { success: 5000, info: 6000, error: 9000 };
const icons: Record<ToastKind, string> = { success: "✓", info: "i", error: "!" };
const titles: Record<ToastKind, string> = { success: "Tudo certo", info: "Aviso", error: "Algo deu errado" };

function region(): HTMLElement {
  let element = document.getElementById("toast-region");
  if (!element) {
    element = document.createElement("div");
    element.id = "toast-region";
    element.className = "toast-region";
    document.body.appendChild(element);
  }
  return element;
}

export function showToast(kind: ToastKind, message: string): void {
  const toast = document.createElement("div");
  toast.className = `toast toast-${kind}`;
  // Erros interrompem o leitor de tela; sucesso e aviso são anunciados sem interromper.
  toast.setAttribute("role", kind === "error" ? "alert" : "status");
  toast.setAttribute("aria-live", kind === "error" ? "assertive" : "polite");

  const icon = document.createElement("span");
  icon.className = "toast-icon";
  icon.setAttribute("aria-hidden", "true");
  icon.textContent = icons[kind];

  const body = document.createElement("div");
  body.className = "toast-body";
  const title = document.createElement("strong");
  title.textContent = titles[kind];
  const text = document.createElement("p");
  text.textContent = message;
  body.append(title, text);

  const close = document.createElement("button");
  close.type = "button";
  close.className = "toast-close";
  close.setAttribute("aria-label", "Fechar notificação");
  close.textContent = "×";

  const progress = document.createElement("span");
  progress.className = "toast-progress";
  progress.style.animationDuration = `${durations[kind]}ms`;

  toast.append(icon, body, close, progress);
  const container = region();
  // Evita pilha de mensagens repetidas quando o usuário clica várias vezes.
  for (const existing of Array.from(container.children)) if (existing.querySelector("p")?.textContent === message) existing.remove();
  container.appendChild(toast);

  let timer = window.setTimeout(dismiss, durations[kind]);
  function dismiss() {
    window.clearTimeout(timer);
    toast.classList.add("toast-leaving");
    window.setTimeout(() => toast.remove(), 200);
  }
  close.addEventListener("click", dismiss);
  toast.addEventListener("mouseenter", () => { window.clearTimeout(timer); toast.classList.add("toast-paused"); });
  toast.addEventListener("mouseleave", () => { toast.classList.remove("toast-paused"); timer = window.setTimeout(dismiss, 2500); });
}
