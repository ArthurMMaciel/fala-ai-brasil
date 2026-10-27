import { createRoot, type Root } from 'react-dom/client';
import { CompanyPortalLive, PartnerPortalLive } from '../portals/portal-live';

const app = document.querySelector<HTMLDivElement>('#app');
let root: Root | undefined;
let active: 'company' | 'partner' | null = null;
let activeCompanyId: string | undefined;
let activePartnerId: string | undefined;

function shell() { return app?.querySelector<HTMLElement>('.legacy-editorial'); }
function content() { return shell()?.querySelector<HTMLElement>('.content'); }
function mount(persona: 'company' | 'partner', companyId = activeCompanyId, partnerId = activePartnerId) {
 const target = content();
 if (!target) return;
 active = persona;
 target.closest<HTMLElement>('.portal-layout')?.classList.add('commercial-legacy-layout');
 shell()?.querySelector<HTMLElement>('.sidebar')?.classList.add('commercial-legacy-sidebar-hidden');
 if (!root) root = createRoot(target);
 if (persona === 'company' && companyId) root.render(<CompanyPortalLive companyId={companyId} />);
 else if (persona === 'partner' && partnerId) root.render(<PartnerPortalLive partnerId={partnerId} />);
}
function unmount() {
 content()?.closest<HTMLElement>('.portal-layout')?.classList.remove('commercial-legacy-layout');
 root?.unmount();
 root = undefined;
 active = null;
 activeCompanyId = undefined;
 shell()?.querySelector<HTMLElement>('.sidebar')?.classList.remove('commercial-legacy-sidebar-hidden');
}

if (app) {
 // Conta real de empresa abre direto o portal da empresa (TASK-0022).
 app.addEventListener('escuta:open-portal', event => { const detail = (event as CustomEvent<{ persona: 'company' | 'partner'; companyId?: string; partnerId?: string }>).detail; activeCompanyId = detail.companyId; activePartnerId = detail.partnerId; mount(detail.persona, detail.companyId, detail.partnerId); });
 app.addEventListener('escuta:reset-portal', () => { activeCompanyId = undefined; activePartnerId = undefined; if (active) unmount(); });

}
