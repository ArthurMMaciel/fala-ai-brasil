// Landing oficial em React. Substitui as páginas estáticas (inicio, empresa, parceiros, patrocinio, intelligence e 404).
import { useEffect, useRef, type ComponentType } from 'react';
import { sitePages, type SitePageId } from '../domain/site-pages';
import { BillingProvider, Flag, SiteFooter, SiteHeader } from './site-parts';
import { EmpresaPage } from './pages/empresa';
import { InicioPage } from './pages/inicio';
import { IntelligencePage } from './pages/intelligence';
import { NotFoundPage } from './pages/404';
import { ParceirosPage } from './pages/parceiros';
import { PatrocinioPage } from './pages/patrocinio';
import './landing.css';

const pageComponents: Record<SitePageId, ComponentType> = {
  inicio: InicioPage, empresa: EmpresaPage, parceiros: ParceirosPage, patrocinio: PatrocinioPage, intelligence: IntelligencePage, '404': NotFoundPage,
};

const setMeta = (name: string, content: string | null) => {
  const meta = document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`);
  if (!meta || content === null) return () => undefined;
  const previous = meta.content;
  meta.content = content;
  return () => { meta.content = previous; };
};

export function Site({ pageId }: { pageId: SitePageId }) {
  const page = sitePages[pageId];
  const Page = pageComponents[pageId];
  const root = useRef<HTMLDivElement>(null);

  // Título, descrição e cor do navegador por página; ao sair da landing (login, cadastro), voltam os do app.
  useEffect(() => {
    const previousTitle = document.title;
    document.title = page.title;
    const restoreDescription = setMeta('description', page.description);
    const restoreTheme = setMeta('theme-color', '#3155A6');
    return () => { document.title = previousTitle; restoreDescription(); restoreTheme(); };
  }, [page]);

  // Seções com .rv aparecem ao entrar na tela.
  useEffect(() => {
    const element = root.current;
    if (!element) return;
    const items = Array.from(element.querySelectorAll<HTMLElement>('.rv'));
    if (typeof IntersectionObserver === 'undefined') { items.forEach(item => item.classList.add('in')); return; }
    const observer = new IntersectionObserver(entries => entries.forEach(entry => {
      if (entry.isIntersecting) { entry.target.classList.add('in'); observer.unobserve(entry.target); }
    }), { threshold: 0.1 });
    items.forEach(item => observer.observe(item));
    return () => observer.disconnect();
  }, [pageId]);

  // Link com âncora (/#contato, /empresa#planos): a página é desenhada depois do carregamento, então rola até a seção aqui.
  useEffect(() => {
    const id = decodeURIComponent(window.location.hash.slice(1));
    if (/^[\w-]+$/.test(id)) document.getElementById(id)?.scrollIntoView();
  }, [pageId]);

  return (
    <div id="escuta-site" className={page.bodyClass} ref={root}>
      <a className="skip" href="#main">Ir para o conteúdo principal</a>
      <SiteHeader page={page} />
      <main id="main">
        <BillingProvider><Page /></BillingProvider>
      </main>
      <SiteFooter page={page} />
      <Flag />
    </div>
  );
}
