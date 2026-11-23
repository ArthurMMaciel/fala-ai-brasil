import { Experience } from '../editorial/editorial-experience';
import { StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";
import type { SitePageId } from "../domain/site-pages";
import { Site } from "../landing-site/site";

// Raiz React do app: landing oficial (src/landing-site) e telas editoriais (termos, privacidade e protótipos de acompanhamento).
let root: Root | undefined;
export function mountExperience(element: HTMLElement, props: { route: string; onRoute: (route: string) => void }) { root ??= createRoot(element); root.render(<StrictMode><Experience {...props} /></StrictMode>); }
export function mountSite(element: HTMLElement, pageId: SitePageId) { root ??= createRoot(element); root.render(<StrictMode><Site pageId={pageId} /></StrictMode>); }
export function unmountLanding() { root?.unmount(); root = undefined; }
