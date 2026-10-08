import { StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";

type Audience = "worker" | "company" | "partner" | "intelligence" | "sponsor";

type LandingStory = {
  headline: string;
  promise: string;
  problem: string;
  outcomes: Array<{ title: string; copy: string }>;
};

type LandingProps = {
  audience: Audience;
  selected: { short: string; title: string; subtitle: string } | null;
  story: LandingStory | null;
  onAudienceChange: (audience: Audience) => void;
  onOpenAuth: (mode: "login" | "register", audience: Audience) => void;
  onRoute: (route: "solutions" | "landing") => void;
};

const personas: Array<[Audience, string, string]> = [
  ["worker", "Funcionário", "Quero ser ouvido"],
  ["company", "Empresa", "Quero responder"],
  ["partner", "Parceiro", "Quero crescer"],
  ["intelligence", "Intelligence", "Quero decidir melhor"],
  ["sponsor", "Patrocinador", "Quero apoiar"],
];

function Landing({ audience, selected, story, onAudienceChange, onOpenAuth, onRoute }: LandingProps) {
  const worker = audience === "worker";
  const headline = worker ? "Sua voz pode ser ouvida sem expor quem você é." : story?.headline;
  const lead = worker
    ? "Relate situações do ambiente de trabalho, acompanhe o retorno da empresa e ajude a construir relações profissionais mais responsáveis."
    : story?.promise;

  return (
    <div className="app-shell brand-app">
      <a className="skip-link" href="#main-content">Ir para o conteúdo principal</a>
      <header className="topbar react-topbar">
        <button className="brand" onClick={() => onRoute("landing")} aria-label="Ir para início">
          <span className="brand-mark">EA</span>
          <span>Escuta Aí Brasil</span>
        </button>

        <nav className="persona-selector" aria-label="Escolha uma persona">
          {personas.map(([key, label, note]) => (
            <button
              key={key}
              className={`persona-choice ${audience === key ? "selected" : ""}`}
              aria-pressed={audience === key}
              onClick={() => onAudienceChange(key)}
            >
              <strong>{label}</strong>
              <span>{note}</span>
            </button>
          ))}
        </nav>

        <nav className="nav-actions" aria-label="Navegação principal">
          <button className="btn ghost" onClick={() => onRoute("solutions")}>Soluções e planos</button>
          <button className="btn ghost" onClick={() => onOpenAuth("login", audience)}>Entrar</button>
          <button className="btn primary" onClick={() => onOpenAuth("register", audience)}>Cadastrar</button>
        </nav>
      </header>

      <main id="main-content" className="brand-home">
        <section className="home-hero">
          <div className="home-hero-copy">
            <span className="brand-eyebrow"><span className="eyebrow-dot" /> Escuta Aí Brasil</span>
            <h1>{headline}</h1>
            <p className="lead">{lead}</p>
            <div className="nav-actions hero-actions">
              <button className="btn primary" onClick={() => onOpenAuth("register", audience)}>
                {worker ? "Quero fazer uma manifestação" : `Conhecer ${selected?.short ?? "a plataforma"}`}
              </button>
              <button className="btn home-secondary" onClick={() => onOpenAuth("login", audience)}>Já tenho uma conta</button>
            </div>
          </div>
          <div className="home-hero-art" aria-label="Identidade visual Escuta Aí Brasil">
            <div className="brand-orbit orbit-one" />
            <div className="brand-orbit orbit-two" />
            <div className="logo-mark-large"><span /><span /></div>
            <div className="art-label">
              <strong>{worker ? "Proteção primeiro" : selected?.title}</strong>
              <small>{worker ? "Identidade preservada em toda a jornada" : selected?.subtitle}</small>
            </div>
          </div>
        </section>

        {worker ? (
          <section className="home-value-grid" aria-label="Benefícios para funcionários">
            <article><span className="value-number">01</span><h3>Conte do seu jeito</h3><p>Uma jornada simples para registrar o que aconteceu sem precisar traduzir sua experiência.</p></article>
            <article><span className="value-number">02</span><h3>Identidade protegida</h3><p>A plataforma prepara uma versão compartilhável sem expor quem você é para a empresa.</p></article>
            <article><span className="value-number">03</span><h3>Acompanhe o retorno</h3><p>Você consegue acompanhar o status e a resposta ao longo de toda a jornada.</p></article>
          </section>
        ) : (
          <section className="persona-highlight" aria-live="polite">
            <div><span className="brand-eyebrow">O que você ganha</span><h2>{selected?.title} em ação</h2><p>{story?.problem}</p></div>
            <div className="highlight-list">{story?.outcomes.map((item, index) => <article key={item.title}><span>0{index + 1}</span><div><strong>{item.title}</strong><p>{item.copy}</p></div></article>)}</div>
          </section>
        )}
      </main>
    </div>
  );
}

let root: Root | undefined;

export function mountLanding(element: HTMLElement, props: LandingProps) {
  root ??= createRoot(element);
  root.render(<StrictMode><Landing {...props} /></StrictMode>);
}

