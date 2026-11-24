import { escapeHtml } from "../domain/html-safety";

// Menu da conta (pedido do responsável, 2026-11-23): avatar com as iniciais no topo, à direita. Ao abrir, "Meu perfil"
// (trabalhador, empresa e parceiro) e "Sair" em vermelho. Substitui o "Meu perfil" da barra lateral e os botões
// "Minha área" e "Sair" do topo. As ações seguem pelos data-action do main.js (open-profile, logout).

export function userInitials(name: string): string {
  const parts = String(name ?? "").trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "?";
  const letters = parts.length === 1 ? parts[0].slice(0, 2) : parts[0][0] + parts[parts.length - 1][0];
  return letters.toLocaleUpperCase("pt-BR");
}

export function userMenuMarkup(user: { name: string; roleLabel: string; hasProfile: boolean }): string {
  const name = escapeHtml(user.name || "Sua conta");
  const profile = user.hasProfile ? '<button class="user-menu-item" type="button" role="menuitem" data-action="open-profile">Meu perfil</button>' : "";
  return `<div class="user-menu"><button class="user-avatar" type="button" data-user-menu aria-haspopup="menu" aria-expanded="false" aria-controls="user-menu-list" aria-label="Conta de ${name}: abrir menu">${escapeHtml(userInitials(user.name))}</button>`
    + `<div class="user-menu-list" id="user-menu-list" role="menu" aria-label="Conta" hidden><p class="user-menu-who"><strong>${name}</strong><span>${escapeHtml(user.roleLabel)}</span></p>`
    + `${profile}<button class="user-menu-item danger" type="button" role="menuitem" data-action="logout">Sair</button></div></div>`;
}

// Comportamento: clique no avatar abre e fecha; Esc fecha e devolve o foco ao avatar; clique fora fecha;
// setas e Home/End andam entre as opções. O main.js redesenha o topo a cada tela, então o menu sempre começa fechado.
function parts(from: Element | null) {
  const menu = from?.closest<HTMLElement>(".user-menu");
  const button = menu?.querySelector<HTMLButtonElement>("[data-user-menu]") ?? null;
  const list = menu?.querySelector<HTMLElement>(".user-menu-list") ?? null;
  return { menu, button, list, items: list ? Array.from(list.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')) : [] };
}
function setOpen(button: HTMLButtonElement, list: HTMLElement, open: boolean, focusFirst = false) {
  list.hidden = !open;
  button.setAttribute("aria-expanded", String(open));
  if (open && focusFirst) list.querySelector<HTMLElement>('[role="menuitem"]')?.focus();
}
function closeAll(except?: Element | null) {
  document.querySelectorAll<HTMLElement>(".user-menu").forEach(menu => {
    if (menu === except) return;
    const { button, list } = parts(menu);
    if (button && list && !list.hidden) setOpen(button, list, false);
  });
}

if (typeof document !== "undefined") {
  document.addEventListener("click", event => {
    const target = event.target as Element | null;
    const toggle = target?.closest?.("[data-user-menu]");
    if (toggle) {
      const { button, list } = parts(toggle);
      if (button && list) setOpen(button, list, list.hidden, event.detail === 0);
      closeAll(toggle.closest(".user-menu"));
      return;
    }
    const item = target?.closest?.(".user-menu-item");
    closeAll(item ? null : target?.closest?.(".user-menu"));
  });
  document.addEventListener("keydown", event => {
    const target = event.target as Element | null;
    const { button, list, items } = parts(target);
    if (!button || !list) return;
    if (event.key === "Escape" && !list.hidden) { event.preventDefault(); setOpen(button, list, false); button.focus(); return; }
    if (target === button && (event.key === "ArrowDown" || event.key === "ArrowUp")) { event.preventDefault(); setOpen(button, list, true); (event.key === "ArrowUp" ? items[items.length - 1] : items[0])?.focus(); return; }
    const index = items.indexOf(target as HTMLButtonElement);
    if (index < 0) return;
    const go = (next: number) => { event.preventDefault(); items[(next + items.length) % items.length]?.focus(); };
    if (event.key === "ArrowDown") go(index + 1);
    else if (event.key === "ArrowUp") go(index - 1);
    else if (event.key === "Home") go(0);
    else if (event.key === "End") go(items.length - 1);
    else if (event.key === "Tab") setOpen(button, list, false);
  });
}
