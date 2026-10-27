import { createRoot, type Root } from 'react-dom/client';
import { WorkerPortalLive } from '../portals/worker-portal-live';

const app = document.querySelector<HTMLDivElement>('#app');
let root: Root | undefined;
let mounted = false;
let mountedContainer: HTMLElement | null = null;
let activeView: 'dashboard' | 'list' | null = null;
let pendingRelatedId: string | null = null;

function workerShell() { return app?.querySelector<HTMLElement>('.legacy-editorial'); }
function workerSidebar() { return workerShell()?.querySelector<HTMLElement>('.sidebar'); }
function normalizeSidebar() {
 const sidebar = workerSidebar();
 if (!sidebar || !sidebar.querySelector('[data-route="worker"]')) return;
 sidebar.querySelectorAll<HTMLElement>('[data-route="new-complaint"], [data-route="case"], [data-route="companies"]').forEach(element => { element.hidden = true; });
 let manifestations = sidebar.querySelector<HTMLButtonElement>('[data-worker-view="manifestations"]');
 if (!manifestations) { manifestations = document.createElement('button'); manifestations.className = 'side-link'; manifestations.type = 'button'; manifestations.dataset.workerView = 'manifestations'; manifestations.textContent = 'Manifestações'; sidebar.append(manifestations); }
 manifestations.classList.toggle('active', activeView === 'list');
 sidebar.querySelector<HTMLElement>('[data-route="worker"]')?.classList.toggle('active', activeView === 'dashboard');
}
function workerContent() { return workerShell()?.querySelector<HTMLElement>('.content'); }
function clickCompanies(complaint?: { id: string }) {
 pendingRelatedId = complaint?.id ?? null;
 activeView = null;
 root?.unmount();
 root = undefined;
 mounted = false;
 app?.querySelector<HTMLElement>('.sidebar [data-route="companies"]')?.click();
}
function addRelatedNote() {
 const content = workerContent();
 if (!content || !pendingRelatedId || content.querySelector('[data-related-note]')) return;
 const note = document.createElement('aside');
 note.className = 'worker-related-note';
 note.dataset.relatedNote = 'true';
 const title = document.createElement('strong');
 title.textContent = 'Continuidade da manifestação';
 const text = document.createElement('span');
 text.textContent = `Esta nova manifestação foi aberta a partir de ${pendingRelatedId}.`;
 note.append(title, text);
 content.prepend(note);
 content.dataset.relatedManifestationId = pendingRelatedId;
}
function isWorkerDashboard() { return Boolean(workerContent()?.querySelector('.page-head h2')?.textContent?.includes('Como podemos ajudar')); }
function mount(view: 'dashboard' | 'list') {
 const content = workerContent();
 if (!content) return;
 activeView = view;
 normalizeSidebar();
 addRelatedNote();
 if (mounted && mountedContainer !== content) { root?.unmount(); root = undefined; mounted = false; }
 if (mounted) { root?.render(<WorkerPortalLive initialView={view} />); return; }
 root = createRoot(content);
 mounted = true;
 mountedContainer = content;
 root.render(<WorkerPortalLive initialView={view} />);
}

if (app) {
 app.addEventListener('click', event => {
  const target = event.target as HTMLElement;
  const manifestations = target.closest<HTMLElement>('[data-worker-view="manifestations"]');
  if (manifestations) { event.preventDefault(); event.stopImmediatePropagation(); mount('list'); }
 }, true);
 const observer = new MutationObserver(() => {
  normalizeSidebar();
  addRelatedNote();
  const dashboard = isWorkerDashboard();
  const hasPortal = Boolean(workerContent()?.querySelector('.worker-portal-content'));
  if (dashboard && !hasPortal) { root?.unmount(); root = undefined; mounted = false; mount('dashboard'); }
  // Só desmonta quando outra tela ocupa a área (container trocado ou com outro conteúdo); vazio = render do React pendente.
  const content = workerContent();
  const replaced = mounted && (content !== mountedContainer || Boolean(content?.childElementCount && !hasPortal));
  if (replaced && !dashboard) { root?.unmount(); root = undefined; mounted = false; mountedContainer = null; activeView = null; }
 });
 observer.observe(app, { childList: true, subtree: true });
 requestAnimationFrame(() => { normalizeSidebar(); if (isWorkerDashboard()) mount('dashboard'); });
}
