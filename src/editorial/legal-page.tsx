import { useEffect } from 'react';
import termsSource from '../content/legal/termos-de-uso.md?raw';
import privacySource from '../content/legal/aviso-de-privacidade.md?raw';
import { legalRoutes, parseLegalDoc, type LegalBlock, type LegalRoute } from '../domain/legal-docs';
import { EditorialFooter } from './editorial-ui';
import { brandName } from '../domain/brand';

const docs: Record<LegalRoute, string> = { terms: termsSource, privacy: privacySource };

function Block({ block }: { block: LegalBlock }) {
 if (block.kind === 'heading') return block.level === 2 ? <h2>{block.text}</h2> : <h3>{block.text}</h3>;
 if (block.kind === 'list') return <ul>{block.items.map((item, index) => <li key={index}>{item}</li>)}</ul>;
 if (block.kind === 'note') return <p className="legal-note">{block.text}</p>;
 return <p>{block.text}</p>;
}

// Página pública de termos e privacidade (TASK-0033). O texto vem do arquivo de conteúdo; enquanto não for aprovado, o aviso de revisão fica visível.
export function LegalPage({ route, onRoute }: { route: LegalRoute; onRoute: (route: string) => void }) {
 const doc = parseLegalDoc(docs[route]);
 useEffect(() => {
  document.querySelector<HTMLElement>('#main-content')?.focus({ preventScroll: true });
  history.replaceState(null, '', `${location.pathname}${location.search}#${legalRoutes[route]}`);
  return () => { if (location.hash === `#${legalRoutes[route]}`) history.replaceState(null, '', location.pathname + location.search); };
 }, [route]);
 return <div className="app-shell editorial-app"><a className="skip-link" href="#main-content">Ir para o conteúdo principal</a>
  <header className="editorial-header"><button className="editorial-wordmark" onClick={() => onRoute('landing')} aria-label={`${brandName} — página inicial`}>{brandName}</button><button className="text-action" onClick={() => onRoute('landing')}>← Voltar à inicial</button></header>
  <main className="legal-page" id="main-content" tabIndex={-1}>
   {doc.inReview && <p className="legal-review-banner" role="note"><strong>Texto em revisão jurídica.</strong> Este conteúdo ainda não é a versão final.</p>}
   <h1>{doc.title}</h1>
   {doc.blocks.map((block, index) => <Block key={index} block={block} />)}
   <p className="muted small">Versão {doc.version || 'sem versão'}{doc.inReview ? ' · em revisão' : ''}</p>
   <nav className="legal-links" aria-label="Documentos"><button className="text-action" aria-current={route === 'terms' ? 'page' : undefined} onClick={() => onRoute('terms')}>Termos de uso</button><button className="text-action" aria-current={route === 'privacy' ? 'page' : undefined} onClick={() => onRoute('privacy')}>Aviso de privacidade</button></nav>
  </main>
  <EditorialFooter onRoute={onRoute} />
 </div>;
}
