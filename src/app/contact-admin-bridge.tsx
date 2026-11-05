import { createRoot, type Root } from 'react-dom/client';
import { ContactSolicitationsAdmin } from '../portals/contact-solicitations-admin';

const app = document.querySelector<HTMLElement>('#app');
let root: Root | undefined;
let container: HTMLElement | null = null;

function sync() {
  const next = app?.querySelector<HTMLElement>('#contact-admin-root') ?? null;
  if (container === next) return;
  root?.unmount();
  root = undefined;
  container = next;
  if (container) { root = createRoot(container); root.render(<ContactSolicitationsAdmin />); }
}

if (app) {
  new MutationObserver(sync).observe(app, { childList: true, subtree: true });
  sync();
}
