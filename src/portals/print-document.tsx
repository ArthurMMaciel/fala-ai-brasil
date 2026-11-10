import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { PrintDocument } from '../domain/print-document';

// Versão para impressão/PDF (TASK-0043, fase 1): texto real, montado só no clique, impresso pelo navegador.

export function PrintDocumentView({ doc }: { doc: PrintDocument }) {
 return <article className="print-document" aria-label={`${doc.eyebrow}: ${doc.title}`}>
  <header className="print-header"><img src="/brand/escuta-ai-brasil.svg" alt="Escuta Aí Brasil" width="180" height="36" /><span>{doc.eyebrow}</span></header>
  <h1>{doc.title}</h1>
  <dl className="print-meta">{doc.meta.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>
  {doc.sections.map(section => <section key={section.heading} className="print-section"><h2>{section.heading}</h2>
   {section.note && <p className="print-note">{section.note}</p>}
   {section.text && <p className="print-text">{section.text}</p>}
   {section.items && <ul>{section.items.map(item => <li key={item}>{item}</li>)}</ul>}
   {section.timeline && (section.timeline.length ? <ol className="print-timeline">{section.timeline.map((item, index) => <li key={index}><strong>{item.title}</strong> <span>{item.date}</span>{item.text && <p>{item.text}</p>}</li>)}</ol> : <p className="print-note">Sem registros.</p>)}
  </section>)}
  <footer className="print-footer">{doc.footer.map(line => <p key={line}>{line}</p>)}</footer>
 </article>;
}

/** Monta o documento fora do #app e abre o diálogo de impressão do navegador ("Salvar como PDF"). */
export function usePrintDocument() {
 const [doc, setDoc] = useState<PrintDocument | null>(null);
 const previousTitle = useRef('');
 useEffect(() => {
  if (!doc) return;
  previousTitle.current = document.title;
  document.title = doc.fileName; // nome sugerido do arquivo ao salvar como PDF
  const done = () => { document.title = previousTitle.current; setDoc(null); };
  window.addEventListener('afterprint', done, { once: true });
  // O efeito roda depois da renderização; setTimeout não depende de quadro de animação (aba em segundo plano).
  const timer = window.setTimeout(() => window.print(), 0);
  return () => { window.clearTimeout(timer); window.removeEventListener('afterprint', done); document.title = previousTitle.current; };
 }, [doc]);
 const host = doc ? createPortal(<div className="print-host"><PrintDocumentView doc={doc} /></div>, document.body) : null;
 return { print: setDoc, host };
}
