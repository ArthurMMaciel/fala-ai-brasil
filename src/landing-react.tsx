import { StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { commercialCatalog, type CommercialPlan } from "./commercial";

type Audience = "worker" | "company" | "partner" | "intelligence" | "sponsor";
type LandingStory = { headline: string; promise: string; problem: string; outcomes: Array<{ title: string; copy: string }> };
type LandingProps = {
  audience: Audience; selected: { short: string; title: string; subtitle: string } | null; story: LandingStory | null;
  user: { name: string; role: string } | null;
  onAudienceChange: (audience: Audience) => void;
  onOpenAuth: (mode: "login" | "register", audience: Audience) => void;
  onChoosePlan: (planId: string, audience: Audience) => void;
  onRoute: (route: string) => void; onLogout: () => void;
};
const personas: Array<[Audience, string, string]> = [
  ["worker", "Trabalhador", "Quero ser ouvido"], ["company", "Empresa", "Quero responder"],
  ["partner", "Parceiro", "Quero crescer"], ["intelligence", "Intelligence", "Quero decidir melhor"], ["sponsor", "Patrocinador", "Quero apoiar"],
];
const planDetails: Record<string, [string, string[]]> = {
  "company-essential": ["Para organizar a escuta de uma unidade.", ["Fila e responsáveis", "Resposta e acompanhamento", "Indicadores da organização"]],
  "company-management": ["Para RH e Compliance trabalharem juntos.", ["Até cinco unidades", "Prazos e escalonamento", "Revisão executiva"]],
  "company-multi": ["Para grupos com operação em várias unidades.", ["Governança regional", "Comparação interna protegida", "Implantação sob proposta"]],
  "partner-presence": ["Para apresentar sua especialidade e região.", ["Perfil e credenciais", "Presença regional", "Métricas de descoberta"]],
  "partner-professional": ["Para ampliar presença e acompanhar oportunidades.", ["Até três regiões", "Conteúdo no perfil", "Contatos consentidos"]],
  "partner-national": ["Para consultorias e redes com cobertura ampla.", ["Abrangência nacional", "Múltiplos especialistas", "Leitura agregada de demanda"]],
  "intelligence-radar": ["Para acompanhar um contexto setorial.", ["Uma coorte elegível", "Atualização trimestral", "Método e limitações explícitos"]],
  "intelligence-benchmark": ["Para comparar contextos e priorizar decisões.", ["Até três coortes elegíveis", "Tendências e histórico", "Revisão analítica"]],
  "intelligence-institutional": ["Para associações e programas setoriais.", ["Escopo sob contrato", "Governança de uso", "Acompanhamento analítico"]],
  "intelligence-project": ["Para uma pergunta ou diagnóstico específico.", ["Pergunta e método definidos", "Entrega agregada", "Devolutiva com próximos passos"]],
  "sponsor-content": ["Para apoiar uma pauta educativa.", ["Marca identificada como apoiadora", "Distribuição contextual", "Relatório agregado"]],
  "sponsor-event": ["Para apoiar uma agenda de encontros.", ["Contrapartidas definidas", "Separação editorial", "Sem acesso a dados individuais"]],
  "sponsor-study": ["Para apoiar a publicação de um estudo.", ["Método independente", "Resultados públicos agregados", "Apoio claramente identificado"]],
};
const currency = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
function scrollToPlans() {
  const section = document.getElementById("solucoes-e-planos");
  section?.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "start" });
  section?.focus({ preventScroll: true });
}
function Plan({ plan, onChoose }: { plan: CommercialPlan; onChoose: () => void }) {
  const [fit, features] = planDetails[plan.id];
  return <article className="landing-plan"><h3>{plan.name}</h3><p className="landing-plan-fit">{fit}</p>
    <p className="landing-plan-price">{plan.monthlyCents === null ? "Sob proposta" : <>{currency.format(plan.monthlyCents / 100)}<span>/mês</span></>}</p>
    <ul>{features.map(feature => <li key={feature}>{feature}</li>)}</ul>
    <button className="btn primary" onClick={onChoose} aria-label={`Escolher plano ${plan.name}`}>Escolher {plan.name}</button></article>;
}
function Landing({ audience, selected, story, user, onAudienceChange, onOpenAuth, onChoosePlan, onRoute, onLogout }: LandingProps) {
  const worker = audience === "worker";
  const plans = commercialCatalog.filter(plan => plan.audience === audience);
  const userRoute = user?.role === "worker" ? "worker" : user?.role === "admin" ? "admin" : "commercial-account";
  return <div className="app-shell brand-app">
    <a className="skip-link" href="#main-content">Ir para o conteúdo principal</a>
    <header className="topbar react-topbar">
      <button className="brand" onClick={() => onRoute("landing")} aria-label="Escuta Aí Brasil — página inicial"><img className="brand-logo" src="/brand/escuta-ai-brasil.svg" alt="Escuta Aí Brasil" width="225" height="45" /></button>
      <nav className="persona-selector" aria-label="Escolha uma persona">{personas.map(([key, label, note]) => <button key={key} className={`persona-choice ${audience === key ? "selected" : ""}`} aria-pressed={audience === key} onClick={() => onAudienceChange(key)}><strong>{label}</strong><span>{note}</span></button>)}</nav>
      <nav className="nav-actions" aria-label="Navegação principal">{user ? <><button className="btn ghost" onClick={() => onRoute(userRoute)}>Minha área</button><button className="btn" onClick={onLogout}>Sair</button></> : <><button className="btn ghost" onClick={() => onOpenAuth("login", audience)}>Entrar</button><button className="btn primary" onClick={() => onOpenAuth("register", audience)}>Cadastrar</button></>}</nav>
    </header>
    <main id="main-content" className="brand-home" tabIndex={-1}>
      <section className="home-hero" key={audience}>
        <div className="home-hero-copy"><span className="brand-eyebrow">{worker ? "Escuta para quem trabalha" : selected?.title}</span>
          <h1>{worker ? "Sua voz pode ser ouvida sem expor quem você é." : story?.headline}</h1>
          <p className="lead">{worker ? "Relate situações do ambiente de trabalho e acompanhe o retorno da empresa em um só lugar." : story?.promise}</p>
          <div className="nav-actions hero-actions"><button className="btn primary" onClick={() => worker ? (user?.role === "worker" ? onRoute("companies") : onOpenAuth("register", audience)) : scrollToPlans()}>{worker ? "Quero fazer uma manifestação" : "Ver soluções e planos"}</button><button className="btn home-secondary" onClick={() => user ? onRoute(userRoute) : onOpenAuth("login", audience)}>{user ? "Ir para minha área" : "Já tenho uma conta"}</button></div>
          <p className="hero-context">{worker ? "Acesso gratuito · acompanhe no seu ritmo" : "Conheça a solução e escolha como começar"}</p>
        </div>
        <div className="home-hero-art" aria-hidden="true"><img className="hero-brand-symbol" src="/brand/escuta-ai-simbolo.svg" alt="" width="230" height="132" /><div className="art-label"><strong>{worker ? "Escuta. Resposta. Acompanhamento." : selected?.short}</strong><small>{worker ? "Uma jornada para ser ouvido" : selected?.subtitle}</small></div></div>
      </section>
      {worker ? <section className="home-value-grid" aria-label="Benefícios para trabalhadores"><article><span className="value-number">01</span><h3>Conte do seu jeito</h3><p>Registre o que aconteceu e o retorno que você espera.</p></article><article><span className="value-number">02</span><h3>Revise antes de enviar</h3><p>Confira a versão compartilhável destinada à empresa.</p></article><article><span className="value-number">03</span><h3>Acompanhe o retorno</h3><p>Consulte o andamento e a resposta institucional.</p></article></section> : <section className="persona-highlight" aria-labelledby="solution-title"><div><span className="brand-eyebrow">A solução para você</span><h2 id="solution-title">{selected?.title}</h2><p>{story?.problem}</p></div><div className="highlight-list">{story?.outcomes.map((item, index) => <article key={item.title}><span>0{index + 1}</span><div><strong>{item.title}</strong><p>{item.copy}</p></div></article>)}</div></section>}
      <section id="solucoes-e-planos" className="landing-pricing" aria-labelledby="landing-plans-title" tabIndex={-1}>
        <div className="landing-pricing-heading"><span className="brand-eyebrow">{worker ? "Seu acesso" : `Planos para ${selected?.short}`}</span><h2 id="landing-plans-title">{worker ? "Para você, o acesso é gratuito." : "Escolha como começar."}</h2><p>{worker ? "Você não precisa contratar um plano para relatar e acompanhar. O pagamento não define prioridade de atendimento." : "Um mês de calendário grátis e mensal a partir do segundo, mensal imediato ou anual com 5% de desconto."}</p></div>
        {worker ? <div className="worker-free-access"><strong>R$ 0 <span>para relatar e acompanhar</span></strong><button className="btn primary" onClick={() => user?.role === "worker" ? onRoute("worker") : onOpenAuth("register", "worker")}>{user?.role === "worker" ? "Acessar minha área" : "Criar conta gratuita"}</button></div> : <><div className="landing-plans" key={audience}>{plans.map(plan => <Plan key={plan.id} plan={plan} onChoose={() => onChoosePlan(plan.id, audience)} />)}</div><p className="landing-plan-note">Demonstração comercial: preços e funcionalidades são hipóteses para validação. Não há cobrança real. Ofertas sob proposta dependem de preço e escopo aprovados.</p></>}
      </section>
    </main>
    <footer className="landing-footer"><span>Escuta Aí Brasil</span><p>Demonstração com dados fictícios. Evite inserir dados pessoais reais.</p><button className="btn ghost" onClick={() => onRoute("landing")}>Voltar ao início</button></footer>
  </div>;
}
let root: Root | undefined;
export function mountLanding(element: HTMLElement, props: LandingProps) { root ??= createRoot(element); root.render(<StrictMode><Landing {...props} /></StrictMode>); }
export function unmountLanding() { root?.unmount(); root = undefined; }
