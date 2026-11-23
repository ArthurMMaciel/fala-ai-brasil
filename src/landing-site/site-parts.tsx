// Partes compartilhadas da landing oficial em React: cabeçalho, rodapé, caminhos, patrocinadores, contato,
// faixa de profissões e alternância mensal/anual. Classes e textos iguais aos das antigas páginas estáticas.
import { Children, cloneElement, createContext, isValidElement, useContext, useEffect, useState, type CSSProperties, type FormEvent, type ReactElement, type ReactNode } from 'react';
import { maskPhone } from '../domain/account-rules';
import { landingContactInput } from '../domain/landing-contact';
import { contactProfiles, isVisibleSitePage, siteMenu, sitePages, type SitePage, type SitePageId } from '../domain/site-pages';
import { submitContactSolicitation, validateContactSolicitation } from '../services/contact-solicitations';
import { FooterLogo, HeaderLogo } from './site-logos';

export function SiteHeader({ page }: { page: SitePage }) {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 10);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);
  return (
    <header id="topo" className={scrolled ? 'scrolled' : undefined}>
      <div className="wrap nav">
        <a className="logo" href="/" aria-label="escuta.aí Brasil, início"><HeaderLogo /></a>
        <ul className={open ? 'menu open' : 'menu'} id="menu">
          {siteMenu.map(item => <li key={item.id}><a className={item.id === page.id ? 'on' : undefined} href={sitePages[item.id].path ?? '/'}>{item.label}</a></li>)}
          <li className="m-only"><a href={page.entrar}>Entrar</a></li>
        </ul>
        <div className="nav-cta">
          <a className="entrar" href={page.entrar}>Entrar</a>
          <a className="btn btn-pri" href={page.cta.href}>{page.cta.label}</a>
          <button className="burger" type="button" aria-label="Abrir menu" aria-expanded={open} aria-controls="menu" onClick={() => setOpen(value => !value)}><span></span><span></span><span></span></button>
        </div>
      </div>
    </header>
  );
}

export function SiteFooter({ page }: { page: SitePage }) {
  return (
    <footer>
      <div className="wrap">
        <div className="f-top">
          <div><a className="logo" href="/"><FooterLogo /></a><p>A escuta precisa ter continuidade. Plataforma em desenvolvimento pra escuta psicossocial no trabalho.</p></div>
          <div><h4>Plataforma</h4><ul><li><a href="/">Início</a></li><li><a href="/#cadastrar">Relatar uma situação</a></li><li><a href="/#entrar">Acompanhamento</a></li></ul></div>
          <div><h4>Pra quem</h4><ul>{siteMenu.map(item => <li key={item.id}><a href={sitePages[item.id].path ?? '/'}>{item.label}</a></li>)}</ul></div>
          <div><h4>Conta</h4><ul><li><a href={page.entrar}>Entrar</a></li><li><a href={page.cadastrar}>Cadastrar</a></li><li><a href={page.contato}>Fale com a gente</a></li></ul></div>
        </div>
        <div className="sos"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" /><path d="M12 9v4M12 17h.01" /></svg>Não é um serviço de urgência. Em risco imediato, procure os serviços públicos de emergência.</div>
        <div className="f-bot"><span>© 2026 Escuta Aí Brasil</span><span>Protótipo · Dados fictícios · Evite inserir dados pessoais reais.</span></div>
      </div>
    </footer>
  );
}

export function Flag() {
  return <div className="flag" aria-hidden="true"><span style={{ background: '#0AA245' }}></span><span style={{ background: '#F5AB17' }}></span><span style={{ background: '#3155A6' }}></span></div>;
}

const iconProps = { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: '2', strokeLinecap: 'round', strokeLinejoin: 'round' } as const;
const caminhos: { id: Exclude<SitePageId, '404'>; color: string; title: string; small: string; icon: ReactNode }[] = [
  { id: 'inicio', color: 'var(--azul)', title: 'Trabalhador', small: 'Quero ser ouvido', icon: <svg {...iconProps}><path d="M4 5h16v11H9l-5 4z" /><path d="M8 9h8M8 12h5" /></svg> },
  { id: 'empresa', color: 'var(--verde)', title: 'Empresa', small: 'Quero responder', icon: <svg {...iconProps}><rect x="4" y="3" width="16" height="18" rx="1" /><path d="M9 8h1M14 8h1M9 12h1M14 12h1M10 21v-4h4v4" /></svg> },
  { id: 'parceiros', color: 'var(--amarelo)', title: 'Parceiros', small: 'Quero crescer', icon: <svg {...iconProps}><circle cx="12" cy="12" r="2.5" /><circle cx="4.5" cy="5" r="2" /><circle cx="19.5" cy="5" r="2" /><circle cx="4.5" cy="19" r="2" /><circle cx="19.5" cy="19" r="2" /><path d="M6 6.5l4.2 4M18 6.5l-4.2 4M6 17.5l4.2-4M18 17.5l-4.2-4" /></svg> },
  { id: 'intelligence', color: 'var(--profundo)', title: 'Intelligence', small: 'Quero decidir melhor', icon: <svg {...iconProps}><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" /></svg> },
  { id: 'patrocinio', color: 'var(--tinta)', title: 'Patrocínio', small: 'Quero apoiar', icon: <svg {...iconProps}><path d="M20.8 5.6a5 5 0 0 0-7.1 0L12 7.3l-1.7-1.7a5 5 0 1 0-7.1 7.1L12 21.5l8.8-8.8a5 5 0 0 0 0-7.1z" /></svg> },
];

export function Caminhos({ active }: { active: SitePageId }) {
  const visible = caminhos.filter(item => isVisibleSitePage(item.id));
  return (
    <section className="caminhos" aria-label="Escolha seu perfil"><div className="wrap"><nav className="cam-grid" style={{ '--cams': visible.length } as CSSProperties}>
      {visible.map(item => (
        <a key={item.id} className={item.id === active ? 'cam on' : 'cam'} href={sitePages[item.id].path ?? '/'} aria-current={item.id === active ? 'page' : undefined}>
          <i style={{ background: item.color }}>{item.icon}</i><span><b>{item.title}</b><small>{item.small}</small></span>
        </a>
      ))}
    </nav></div></section>
  );
}

export function SponsorStrip() {
  return (
    <section className="patro-strip" style={{ borderTop: '1px solid var(--linha)' }}>
      <div className="wrap rv">
        <div className="patro-head"><div><span className="eyebrow">Quem apoia a escuta</span><h2 style={{ fontSize: 'clamp(26px,2.8vw,36px)', marginBottom: '6px' }}>Nossos patrocinadores</h2></div>
          <div className="selo"><svg {...iconProps}><path d="M12 3l8 4v5c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V7z" /><path d="M9 12l2 2 4-4" /></svg>Nenhum patrocinador acessa relatos, identidades ou influencia o tratamento dos relatos.</div></div>
        <div className="ps-row"><div className="ps"><img src="/sponsors/lumen.svg" alt="" /><div><b>Lumen Saúde Ocupacional</b><small>Conteúdo · Guia prático de ergonomia no home office</small></div></div><div className="ps"><img src="/sponsors/vila-serena.svg" alt="" /><div><b>Instituto Vila Serena</b><small>Evento · Semana do cuidado no trabalho</small></div></div><div className="ps"><img src="/sponsors/aurora-beneficios.svg" alt="" /><div><b>Aurora Benefícios</b><small>Evento · Roda de conversa sobre benefícios e saúde</small></div></div><div className="ps"><img src="/sponsors/pontal.svg" alt="" /><div><b>Rede Pontal</b><small>Conteúdo · Série: como pedir ajuda no trabalho</small></div></div><div className="ps"><img src="/sponsors/mirante.svg" alt="" /><div><b>Fundação Mirante</b><small>Estudo público · Estudo aberto: rotina e descanso no trabalho</small></div></div></div>
        <p className="patro-nota">Patrocinadores com campanha aprovada pela escuta.aí.{isVisibleSitePage('patrocinio') ? <> <a href="/patrocinio" style={{ color: 'var(--azul)', fontWeight: 600 }}>Quero apoiar →</a></> : null}</p>
      </div>
    </section>
  );
}

// Faixa de profissões: a lista aparece duas vezes para o rolar contínuo; a cópia fica escondida do leitor de tela.
export function Marquee({ children }: { children: ReactNode }) {
  const items = Children.toArray(children);
  const copies = items.map((item, index) => isValidElement(item) ? cloneElement(item as ReactElement<Record<string, unknown>>, { key: `copia-${index}`, 'aria-hidden': 'true' }) : item);
  return <div className="marquee" id="marquee">{items}{copies}</div>;
}

// Alternância mensal/anual (anual com 5% de desconto), compartilhada pelos cartões de plano da página.
const BillingContext = createContext<{ annual: boolean; setAnnual: (annual: boolean) => void }>({ annual: false, setAnnual: () => undefined });

export function BillingProvider({ children }: { children: ReactNode }) {
  const [annual, setAnnual] = useState(false);
  return <BillingContext.Provider value={{ annual, setAnnual }}>{children}</BillingContext.Provider>;
}

export function BillButton({ bill, children }: { bill: 'm' | 'a'; children: ReactNode }) {
  const { annual, setAnnual } = useContext(BillingContext);
  const on = (bill === 'a') === annual;
  return <button type="button" className={on ? 'on' : undefined} aria-pressed={on} onClick={() => setAnnual(bill === 'a')}>{children}</button>;
}

export function Price({ monthly }: { monthly: number }) {
  const { annual } = useContext(BillingContext);
  return <span>{(annual ? Math.round(monthly * 0.95) : monthly).toLocaleString('pt-BR')}</span>;
}

export function Per() {
  const { annual } = useContext(BillingContext);
  return <>{annual ? 'por mês, no plano anual' : 'cobrança mensal'}</>;
}

// Formulário de contato: grava pela RPC submit_contact_solicitation, como o formulário do app.
// Perfis de público oculto ficam fora (contactProfiles).

export function ContactForm({ pagina, perfil, organizacao = false }: { pagina: string; perfil: string; organizacao?: boolean }) {
  const [error, setError] = useState('');
  const [sending, setSending] = useState(false);
  const [done, setDone] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (sending) return;
    const data = new FormData(event.currentTarget);
    const field = (name: string) => { const value = data.get(name); return typeof value === 'string' ? value : ''; };
    const input = landingContactInput({ perfil: field('perfil'), pagina, nome: field('nome'), email: field('email'), telefone: field('telefone'), organizacao: field('organizacao'), botField: field('bot-field') });
    if (!input) return setError('Escolha o seu perfil.');
    const problem = validateContactSolicitation(input);
    if (problem) return setError(problem);
    setSending(true);
    const result = await submitContactSolicitation(input);
    setSending(false);
    if (!result.ok) return setError(result.message);
    setDone(true);
  };
  if (done) return (
    <form className="form" data-pagina={pagina} noValidate>
      <div className="form-ok" role="status"><strong>Solicitação recebida.</strong><p>Retornaremos assim que possível pelo contato informado.</p></div>
    </form>
  );
  return (
    <form className="form" data-pagina={pagina} noValidate onSubmit={submit} onInput={() => { if (error) setError(''); }}>
      {organizacao ? null : <input type="hidden" name="organizacao" defaultValue="" />}
      <p className="hp" aria-hidden="true"><label>Não preencha: <input name="bot-field" tabIndex={-1} autoComplete="off" /></label></p>
      <span className="eyebrow">Saiba mais</span>
      <h2>Vamos conversar?</h2>
      <p style={{ color: 'var(--cinza)' }}>Deixe seus dados e nossa equipe retorna pra apresentar a escuta.aí pro seu perfil.</p>
      <div className="perfis" role="radiogroup" aria-label="Seu perfil">{contactProfiles.map(value => <label key={value}><input type="radio" name="perfil" value={value} defaultChecked={value === perfil} /><span>{value}</span></label>)}</div>
      <div className="campos">
        <div className="campo full"><label htmlFor="nome">Nome</label><input id="nome" name="nome" required maxLength={120} autoComplete="name" /></div>
        <div className="campo"><label htmlFor="email">E-mail</label><input id="email" name="email" required maxLength={254} type="email" autoComplete="email" /></div>
        <div className="campo"><label htmlFor="tel">Telefone com DDD</label><input id="tel" name="telefone" required type="tel" inputMode="tel" maxLength={15} placeholder="(00) 00000-0000" autoComplete="tel" onInput={event => { event.currentTarget.value = maskPhone(event.currentTarget.value); }} /></div>
        {organizacao ? <div className="campo full"><label htmlFor="org">Organização (opcional)</label><input id="org" name="organizacao" maxLength={120} autoComplete="organization" /></div> : null}
      </div>
      <div className="form-nota"><svg {...iconProps}><rect x="5" y="10" width="14" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg>Usaremos estes dados somente pra responder ao seu pedido. Não escreva relatos nem informações sensíveis aqui.</div>
      <p className="form-erro" role="alert" hidden={!error}>{error}</p>
      <button className="btn btn-pri" type="submit" disabled={sending}>{sending ? 'Enviando…' : 'Solicitar contato'}</button>
    </form>
  );
}
