import { createRoot, type Root } from 'react-dom/client';
import { CommercialPortal } from './commercial-portal';

const app = document.querySelector<HTMLDivElement>('#app');
let root: Root | undefined;
let active: 'company' | 'partner' | null = null;
let activeCompanyId: string | undefined;

function shell() { return app?.querySelector<HTMLElement>('.legacy-editorial'); }
function content() { return shell()?.querySelector<HTMLElement>('.content'); }
function mount(persona: 'company' | 'partner', companyId = activeCompanyId) {
 const target = content();
 if (!target) return;
 active = persona;
 target.closest<HTMLElement>('.portal-layout')?.classList.add('commercial-legacy-layout');
 shell()?.querySelector<HTMLElement>('.sidebar')?.classList.add('commercial-legacy-sidebar-hidden');
 if (!root) root = createRoot(target);
 root.render(<CommercialPortal persona={persona} companyId={persona === 'company' ? companyId : undefined} />);
}
function unmount() {
 content()?.closest<HTMLElement>('.portal-layout')?.classList.remove('commercial-legacy-layout');
 root?.unmount();
 root = undefined;
 active = null;
 activeCompanyId = undefined;
 shell()?.querySelector<HTMLElement>('.sidebar')?.classList.remove('commercial-legacy-sidebar-hidden');
}
function addPartnerShortcut() {
 const nav = shell()?.querySelector<HTMLElement>('.topbar .nav-actions');
 if (!nav || nav.querySelector('[data-commercial-portal="partner"]')) return;
 const button = document.createElement('button');
 button.className = 'btn ghost';
 button.type = 'button';
 button.dataset.commercialPortal = 'partner';
 button.textContent = 'Hub parceiro';
 nav.insertBefore(button, nav.lastElementChild);
}

if (app) {
 app.addEventListener('click', event => {
  const target = event.target as HTMLElement;
  const company = target.closest<HTMLElement>('[data-route="company-portal"]');
  const partner = target.closest<HTMLElement>('[data-commercial-portal="partner"]');
  const operator = target.closest<HTMLElement>('[data-route="admin"]');
  if (company) { event.preventDefault(); event.stopImmediatePropagation(); mount('company'); return; }
  if (partner) { event.preventDefault(); event.stopImmediatePropagation(); mount('partner'); return; }
  if (operator && active) { unmount(); }
 }, true);
 // Conta real de empresa abre direto o portal da empresa (TASK-0022).
 app.addEventListener('escuta:open-portal', event => { const detail = (event as CustomEvent<{ persona: 'company' | 'partner'; companyId?: string }>).detail; activeCompanyId = detail.companyId; mount(detail.persona, detail.companyId); });
 app.addEventListener('escuta:reset-portal', () => { activeCompanyId = undefined; if (active) unmount(); });
 const observer = new MutationObserver(() => { if (!active) addPartnerShortcut(); });
 observer.observe(app, { childList: true, subtree: true });
 requestAnimationFrame(addPartnerShortcut);
}
