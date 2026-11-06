import { createRoot, type Root } from 'react-dom/client';
import { OpsPortalLive } from '../portals/ops-portal-live';

// Monta a área da equipe quando main.js renderiza a rota "ops" (só para contas em private.platform_admins).
const app = document.querySelector<HTMLElement>('#app');
let root: Root | undefined;
let container: HTMLElement | null = null;

function sync() {
  const next = app?.querySelector<HTMLElement>('#ops-root') ?? null;
  if (container === next) return;
  root?.unmount();
  root = undefined;
  container = next;
  if (container) { root = createRoot(container); root.render(<OpsPortalLive />); }
}

if (app) {
  new MutationObserver(sync).observe(app, { childList: true, subtree: true });
  sync();
}
