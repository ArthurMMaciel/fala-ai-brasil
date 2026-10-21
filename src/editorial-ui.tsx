import { type ReactNode } from 'react';

export function PrototypeBar({ label = 'Escuta psicossocial no trabalho' }: { label?: string }) {
 return <div className="prototype-bar"><span>Protótipo · Dados fictícios</span><span>{label} · Sem envio externo</span></div>;
}
export function Journey({ active = 0 }: { active?: number }) {
 return <ol className="journey-line" aria-label="Percurso da escuta">{['Relato', 'Revisão', 'Encaminhamento', 'Retorno'].map((label, index) => <li key={label} aria-current={index === active ? 'step' : undefined}><div className="journey-track"><span>{String(index + 1).padStart(2, '0')}</span></div><strong>{label}</strong></li>)}</ol>;
}
export function Note({ title, children, tone = 'blue' }: { title: string; children: ReactNode; tone?: 'blue' | 'green' | 'error' }) {
 return <aside className={`editorial-note ${tone}`}><strong>{title}</strong><div>{children}</div></aside>;
}
export function EditorialSection({ number, title, children, tinted = false }: { number: string; title: string; children: ReactNode; tinted?: boolean }) {
 return <section className={`editorial-section${tinted ? ' tinted' : ''}`}><div className="editorial-section-heading"><span className="editorial-eyebrow">{number} / Escuta em continuidade</span><h2>{title}</h2></div><div className="editorial-section-body">{children}</div></section>;
}
export function EditorialFooter({ onRoute, children }: { onRoute: (route: string) => void; children?: ReactNode }) {
 return <footer className="editorial-footer"><div><h2>Escuta Aí Brasil</h2><p>A escuta precisa ter continuidade. Plataforma em desenvolvimento para escuta psicossocial no trabalho.</p></div><div><nav aria-label="Navegação do rodapé"><button onClick={() => onRoute('landing')}>Início</button><button onClick={() => onRoute('tracking')}>Acompanhamento</button>{children}</nav><p>Não é um serviço de urgência. Em risco imediato, procure os serviços públicos de emergência.</p></div><small>Protótipo · Dados fictícios · Dados apenas nesta sessão. Evite inserir dados pessoais reais.</small></footer>;
}
