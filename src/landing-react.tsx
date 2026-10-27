import { PrototypeBar, Journey, EditorialFooter } from './editorial-ui';
import { WorkerStory, CompanyStory } from './editorial-landing';
import { Experience } from './editorial-experience';
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
// Marcas fictícias para a demonstração; trocar por patrocinadores reais com contrato e autorização de uso de marca.
const sponsors = [
  { slug: "mirante", name: "Fundação Mirante", area: "Pesquisa sobre trabalho" },
  { slug: "lumen", name: "Lumen Saúde Ocupacional", area: "Saúde ocupacional" },
  { slug: "vila-serena", name: "Instituto Vila Serena", area: "Bem-estar e cuidado" },
  { slug: "pontal", name: "Rede Pontal", area: "Rede de apoio profissional" },
  { slug: "aurora-beneficios", name: "Aurora Benefícios", area: "Benefícios corporativos" },
];
function SponsorsStrip() {
  return <section className="sponsors-strip" aria-labelledby="sponsors-title">
    <div className="sponsors-strip-head"><span className="editorial-eyebrow">Quem apoia a escuta</span><h2 id="sponsors-title">Nossos patrocinadores</h2><p>Patrocínios financiam conteúdo, eventos e estudos. Nenhum patrocinador acessa relatos, identidades ou influencia o tratamento das manifestações.</p></div>
    <ul className="sponsors-grid">{sponsors.map(sponsor => <li key={sponsor.slug} className="sponsor-card"><img src={`/sponsors/${sponsor.slug}.svg`} alt={`Marca ${sponsor.name}`} width="320" height="96" loading="lazy" /><strong>{sponsor.name}</strong><span>{sponsor.area}</span></li>)}</ul>
    <p className="sponsors-note">Exemplos ilustrativos com marcas fictícias.</p>
  </section>;
}
function Landing({ audience, selected, story, user, onAudienceChange, onOpenAuth, onChoosePlan, onRoute, onLogout }: LandingProps) {
 const worker = audience === 'worker';
 const company = audience === 'company';
 const plans = commercialCatalog.filter(plan => plan.audience === audience);
 const userRoute = user?.role === 'worker' ? 'worker' : user?.role === 'admin' ? 'company-portal' : 'commercial-account';
 const participate = () => onOpenAuth('register', 'company');
 const navigate = onRoute;
 if (worker) onRoute = route => route === 'report' ? onOpenAuth('register', 'worker') : route === 'tracking' ? onOpenAuth('login', 'worker') : navigate(route);
 return <div className="app-shell editorial-app">
  <a className="skip-link" href="#main-content">Ir para o conteúdo principal</a>
  <PrototypeBar label={worker ? 'Inicial' : selected?.short} />
  <header className="editorial-header"><button className="editorial-wordmark" aria-label="Escuta Aí Brasil — página inicial" onClick={() => onRoute('landing')}>Escuta Aí Brasil</button><nav className="editorial-personas" aria-label="Escolha uma persona">{personas.map(([key, label]) => <button key={key} aria-pressed={audience === key} onClick={() => onAudienceChange(key)}>{key === 'partner' ? 'Parceiros' : key === 'sponsor' ? 'Patrocínio' : label}</button>)}</nav></header>
  <main id="main-content" tabIndex={-1}>
   <section className={`editorial-hero${worker ? ' photographic' : ''}`} key={audience}>
    <div className="editorial-hero-copy"><span className="editorial-eyebrow">{worker ? 'Trabalhador no centro · Acesso gratuito' : company ? 'Para empresas / Responsabilidade na continuidade' : selected?.title}</span><h1>{worker ? 'Sua experiência no trabalho merece ser ouvida' : company ? 'Escutar é o começo. Responder faz parte' : story?.headline}</h1><p className="lead">{worker ? 'Um espaço de escuta psicossocial para contar o que acontece no trabalho, escolher o que compartilhar e acompanhar os próximos passos.' : company ? 'Organize a escuta, o tratamento responsável e os retornos. Sem transformar a experiência de quem trabalha em um indicador de vitrine.' : story?.promise}</p><div className="editorial-actions"><button className="btn primary" onClick={() => worker ? onRoute('report') : company ? participate() : scrollToPlans()}>{worker ? 'Relatar uma situação' : company ? 'Conversar sobre participação' : 'Ver soluções e planos'}</button>{worker && <button className="btn" onClick={() => onRoute('tracking')}>Acompanhar manifestação</button>}</div>{worker && <p className="hero-disclosure">Você decide o que pode seguir adiante. Nesta demonstração, nada é enviado à empresa.</p>}</div>
    {worker && <figure className="editorial-photo"><img src="/figma/retrato-documental.png" alt="Pessoa em pé junto à entrada de um estabelecimento, olhando para a rua." width="420" height="475" fetchPriority="high" /><figcaption>Fotografia ilustrativa. Não representa usuários reais ou evidência.</figcaption></figure>}
   </section>
   {(worker || company) && <div className="editorial-path"><div><h2>A escuta precisa ter continuidade.</h2><p>{worker ? 'Do que você conta ao retorno que acompanha.' : 'A empresa recebe somente a versão compartilhável autorizada. O trabalhador mantém um caminho próprio de acompanhamento.'}</p></div><Journey /></div>}
   {worker ? <WorkerStory onRoute={onRoute} onCompany={() => { onAudienceChange('company'); window.scrollTo({ top: 0 }); }} /> : company ? <CompanyStory onParticipate={participate} /> : <section className="editorial-section"><div><span className="editorial-eyebrow">A solução para você</span><h2>{selected?.title}</h2><p>{story?.problem}</p></div><div className="editorial-section-body">{story?.outcomes.map(item => <article key={item.title}><h3>{item.title}</h3><p>{item.copy}</p></article>)}</div></section>}
   <section className="editorial-final"><div><span className="editorial-eyebrow">10 / {worker ? 'O próximo passo é seu' : 'Responsabilidade compartilhada'}</span><h2>{worker ? 'Você não precisa ter todas as palavras para começar.' : company ? 'O retorno também faz parte da escuta.' : 'Escolha como começar.'}</h2></div><button className="btn primary" onClick={() => worker ? onRoute('report') : company ? participate() : scrollToPlans()}>{worker ? 'Relatar uma situação' : company ? 'Conversar sobre participação' : 'Ver soluções e planos'}</button></section>
   <div className="editorial-commercial" key={`plans-${audience}`}><section id="solucoes-e-planos" className="landing-pricing" tabIndex={-1}><div className="landing-pricing-heading"><span className="editorial-eyebrow">{worker ? 'Seu acesso' : `Planos para ${selected?.short}`}</span><h2>{worker ? 'Para você, o acesso é gratuito.' : 'Soluções, planos e acesso à conta'}</h2><p>{worker ? 'Você não precisa contratar um plano para relatar e acompanhar. O pagamento não define prioridade de atendimento.' : 'Um mês de calendário grátis e mensal a partir do segundo, mensal imediato ou anual com 5% de desconto.'}</p></div>{worker ? <div className="worker-free-access"><strong>R$ 0 <span>para relatar e acompanhar</span></strong><button className="btn primary" onClick={() => user?.role === 'worker' ? onRoute('worker') : onOpenAuth('register', 'worker')}>{user?.role === 'worker' ? 'Acessar minha área' : 'Criar conta gratuita'}</button></div> : <><div className="landing-plans">{plans.map(plan => <Plan key={plan.id} plan={plan} onChoose={() => onChoosePlan(plan.id, audience)} />)}</div><p className="small">Demonstração comercial: preços e funcionalidades são hipóteses para validação. Não há cobrança real. Ofertas sob proposta dependem de preço e escopo aprovados.</p></>}</section></div>
   <SponsorsStrip />
  </main>
  <EditorialFooter onRoute={onRoute}>{user ? <><button onClick={() => onRoute(userRoute)}>Minha área</button><button onClick={onLogout}>Sair</button></> : <><button onClick={() => onOpenAuth('login', audience)}>Entrar</button><button onClick={() => onOpenAuth('register', audience)}>Cadastrar</button></>}<button onClick={() => onRoute('company-portal')}>Área da empresa · demo</button><img className="footer-official-logo" src="/brand/escuta-ai-brasil.svg" alt="Marca oficial Escuta Aí Brasil" width="225" height="45" /></EditorialFooter>
 </div>;
}

let root: Root | undefined;
export function mountLanding(element: HTMLElement, props: LandingProps) { root ??= createRoot(element); root.render(<StrictMode><Landing {...props} /></StrictMode>); }
export function mountExperience(element: HTMLElement, props: { route: string; onRoute: (route: string) => void }) { root ??= createRoot(element); root.render(<StrictMode><Experience {...props} /></StrictMode>); }
export function unmountLanding() { root?.unmount(); root = undefined; }
