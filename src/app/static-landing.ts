// Landing oficial estática. Quem sai da conta, ou clica na marca sem estar logado, vai para ela (TASK 17tu7rpfxh3).
export const staticLandingPath = "/inicio.html";

export function openStaticLanding(): void {
  window.location.assign(staticLandingPath);
}
