import { Experience } from '../editorial/editorial-experience';
import { StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";

// A landing React antiga saiu (TASK 17tu7rpfxh3): a landing oficial é a estática (/inicio.html). Aqui fica só a raiz
// React das telas editoriais que o app ainda monta (termos, privacidade e protótipos de acompanhamento).
let root: Root | undefined;
export function mountExperience(element: HTMLElement, props: { route: string; onRoute: (route: string) => void }) { root ??= createRoot(element); root.render(<StrictMode><Experience {...props} /></StrictMode>); }
export function unmountLanding() { root?.unmount(); root = undefined; }
