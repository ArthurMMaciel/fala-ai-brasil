import "./styles.css";
import {
  aiAnalyses,
  auditLogs,
  companies,
  companyResponses,
  complaints as seedComplaints,
  demoPassword,
  histories as seedHistories,
  metrics,
  users,
} from "./mockData";
import { AiAnalysis, Company, Complaint, ComplaintStatus, ComplaintStatusHistory, RiskLevel, User } from "./models";

type Route =
  | "landing"
  | "login"
  | "register"
  | "onboarding"
  | "worker"
  | "companies"
  | "new-complaint"
  | "case"
  | "admin"
  | "admin-cases"
  | "admin-case"
  | "admin-companies"
  | "admin-ai"
  | "admin-ranking";

interface AppState {
  route: Route;
  user: User | null;
  landingAudience: "worker" | "company";
  authAudience: "worker" | "company";
  onboardingStep: number;
  selectedCompanyId: string;
  caseId: string;
  adminCaseId: string;
  complaintStep: number;
  search: string;
  complaintDraft: {
    category: string;
    title: string;
    originalContent: string;
    expectedOutcome: string[];
    incidentDate: string;
    recurrence: string;
    communicationChannels: string[];
  };
  communicationInput: string;
  communicationError: string;
  complaints: Complaint[];
  histories: ComplaintStatusHistory[];
  modal: "company-response" | null;
  filters: Record<string, string>;
  selectedTab: string;
}

const state: AppState = {
  route: "landing",
  user: null,
  landingAudience: "worker",
  authAudience: "worker",
  onboardingStep: 0,
  selectedCompanyId: "c-aurora",
  caseId: "m-001",
  adminCaseId: "m-003",
  complaintStep: 0,
  search: "",
  complaintDraft: {
    category: "",
    title: "",
    originalContent:
      "Meu gerente Carlos, do time financeiro de Maringá, me chamou na sala 302 e disse que eu deveria aguentar a pressão porque todo mundo passa por isso. Desde então tenho recebido cobranças à noite e nos fins de semana.",
    expectedOutcome: ["Receber uma resposta"],
    incidentDate: "Últimas semanas",
    recurrence: "Recorrente",
    communicationChannels: [],
  },
  communicationInput: "",
  communicationError: "",
  complaints: [...seedComplaints],
  histories: [...seedHistories],
  modal: null,
  filters: {},
  selectedTab: "Resumo",
};

const app = document.querySelector<HTMLDivElement>("#app")!;

function setRoute(route: Route, extra: Partial<AppState> = {}) {
  Object.assign(state, extra, { route });
  render();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function currentWorkerComplaints() {
  return state.complaints.filter((complaint) => complaint.userId === "u-worker");
}

function companyById(id: string) {
  return companies.find((company) => company.id === id)!;
}

function complaintById(id: string) {
  return state.complaints.find((complaint) => complaint.id === id)!;
}

function analysisByComplaint(id: string): AiAnalysis {
  return aiAnalyses.find((analysis) => analysis.complaintId === id) ?? makeAnalysis(complaintById(id));
}

function makeAnalysis(complaint: Complaint): AiAnalysis {
  return {
    complaintId: complaint.id,
    suggestedCategory: complaint.category,
    riskLevel: complaint.riskLevel,
    piiDetected: ["nome próprio", "área específica", "local interno"],
    confidence: 0.86,
    sanitizedVersion: complaint.sanitizedContent,
    suggestedMessage:
      "A Ecoa Voz recebeu uma manifestação anonimizada relacionada ao ambiente de trabalho. Pedimos retorno institucional sobre escuta, apuração e providências gerais, preservando a identidade da pessoa manifestante.",
    requiresHumanReview: complaint.riskLevel !== "baixo",
  };
}

function fmtDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function riskBadge(risk: RiskLevel) {
  const color = risk === "baixo" ? "green" : risk === "medio" ? "yellow" : "red";
  return `<span class="badge ${color}">${risk}</span>`;
}

function statusBadge(status: ComplaintStatus) {
  const color = status.includes("Respondida") || status.includes("Finalizada") ? "green" : status.includes("Revisão") ? "yellow" : "";
  return `<span class="badge ${color}">${status}</span>`;
}

function render() {
  app.innerHTML = `
    <div class="app-shell ${state.route.startsWith("admin") ? "admin admin-surface" : ""}">
      ${topbar()}
      ${page()}
      ${state.modal ? responseModal() : ""}
    </div>
  `;
  bind();
}

function topbar() {
  const audience = state.landingAudience;
  return `
    <header class="topbar">
      <button class="brand" data-route="landing" aria-label="Ir para início">
        <span class="brand-mark">EV</span>
        <span>Ecoa Voz</span>
      </button>
      <nav class="nav-actions">
        ${state.user ? `<span class="muted small">${state.user.name} · ${state.user.role === "admin" ? "Empresa" : "Trabalhador"}</span>` : ""}
        ${state.user?.role === "worker" ? `<button class="btn ghost" data-route="worker">Minha área</button><button class="btn ghost" data-route="companies">Empresas</button>` : ""}
        ${state.user?.role === "admin" ? `<button class="btn ghost" data-route="admin">Operação</button>` : ""}
        ${state.user ? `<button class="btn" data-action="logout">Sair</button>` : `<button class="btn ghost" data-action="open-auth" data-mode="login" data-audience="${audience}">Entrar</button><button class="btn primary" data-action="open-auth" data-mode="register" data-audience="${audience}">Cadastrar</button>`}
      </nav>
    </header>
  `;
}

function page() {
  switch (state.route) {
    case "login":
    case "register":
      return authPage(state.route);
    case "onboarding":
      return onboardingPage();
    case "worker":
      return workerLayout(workerDashboard());
    case "companies":
      return workerLayout(companySearchPage());
    case "new-complaint":
      return workerLayout(newComplaintPage());
    case "case":
      return workerLayout(casePage(state.caseId));
    case "admin":
      return adminLayout(adminDashboard());
    case "admin-cases":
      return adminLayout(adminCases());
    case "admin-case":
      return adminLayout(adminCaseDetail(state.adminCaseId));
    case "admin-companies":
      return adminLayout(adminCompanies());
    case "admin-ai":
      return adminLayout(aiSupervision());
    case "admin-ranking":
      return adminLayout(rankingPage());
    default:
      return landingPage();
  }
}

function landingPage() {
  const isCompany = state.landingAudience === "company";
  return `
    <main>
      <div class="audience-switch" role="group" aria-label="Escolha seu perfil">
        <button class="audience-option ${!isCompany ? "active" : ""}" data-action="set-audience" data-audience="worker" aria-pressed="${!isCompany}">Sou empregado</button>
        <button class="audience-option ${isCompany ? "active" : ""}" data-action="set-audience" data-audience="company" aria-pressed="${isCompany}">Sou empresa</button>
      </div>
      <section class="hero">
        <div>
          <span class="eyebrow">${isCompany ? "Escuta responsável para empresas" : "Escuta psicossocial com proteção de identidade"}</span>
          <h1>${isCompany ? "Transforme escuta em confiança e ação." : "Sua voz pode ser ouvida sem expor quem você é."}</h1>
          <p class="lead">${isCompany ? "Receba manifestações protegidas, responda com responsabilidade e acompanhe indicadores que ajudam sua organização a construir relações de trabalho mais saudáveis." : "Relate situações do ambiente de trabalho, acompanhe o retorno da empresa e ajude a construir relações profissionais mais responsáveis."}</p>
          <div class="nav-actions hero-actions">
            <button class="btn primary" data-action="open-auth" data-mode="register" data-audience="${isCompany ? "company" : "worker"}">${isCompany ? "Cadastrar minha empresa" : "Quero fazer uma manifestação"}</button>
            <button class="btn" data-action="open-auth" data-mode="login" data-audience="${isCompany ? "company" : "worker"}">Já tenho uma conta</button>
          </div>
        </div>
        <aside class="hero-panel" aria-label="Demonstração de relato protegido">
          <div class="voice-card-head">
            <div>
              <strong>${isCompany ? "Painel de responsividade" : "Manifestação em preparo"}</strong>
              <p class="small muted" style="color:#cbe0df;margin:7px 0 0">${isCompany ? "Dados úteis, sem exposição de identidade" : "Identidade não compartilhada com a empresa"}</p>
            </div>
            <div class="pulse"></div>
          </div>
          <div class="voice-lines">
            <span class="voice-line"></span><span class="voice-line"></span><span class="voice-line"></span>
          </div>
          <div class="ai-strip">
            ${isCompany
              ? `<div class="ai-step"><span>Manifestações respondidas</span><strong>92%</strong></div><div class="ai-step"><span>Tempo de primeira resposta</span><strong>1,2 dia</strong></div><div class="ai-step"><span>Casos com retorno</span><strong>84%</strong></div>`
              : `<div class="ai-step"><span>Conteúdo analisado</span><strong>OK</strong></div><div class="ai-step"><span>Dados identificáveis revisados</span><strong>OK</strong></div><div class="ai-step"><span>Empresa convidada a responder</span><strong>Em breve</strong></div>`}
          </div>
        </aside>
      </section>
      <section class="section grid three">
        ${isCompany
          ? `${infoCard("Escute com segurança.", "Receba uma versão protegida do relato, adequada para análise e encaminhamento institucional.")}${infoCard("Responda com rastreabilidade.", "Centralize retornos, prazos e histórico de cada manifestação em uma jornada clara.")}${infoCard("Evolua com evidências.", "Acompanhe responsividade, tempo de resposta e tratamento dos casos com indicadores objetivos.")}`
          : `${infoCard("Você conta o que aconteceu.", "Escreva do seu jeito, com linguagem humana e sem precisar transformar sua experiência em termos técnicos.")}${infoCard("A Ecoa Voz protege sua identidade.", "A plataforma organiza o relato e prepara uma versão sem dados que facilitem identificação perante a empresa.")}${infoCard("A empresa é convidada a ouvir.", "O retorno, a velocidade e o tratamento recebido compõem indicadores de responsividade observável.")}`}
      </section>
      <section class="section tight">
        <div class="notice">
          ${isCompany ? `<strong>Valor para sua organização:</strong> canal protegido, comunicação organizada e indicadores de responsividade — sem transformar o índice em certificação do ambiente de trabalho.` : `<strong>Compromissos de confiança:</strong> sua identidade não é compartilhada com a empresa; você acompanha todo o processo; a plataforma não substitui serviços de emergência ou atendimento clínico.`}
        </div>
      </section>
    </main>
  `;
}

function infoCard(title: string, copy: string) {
  return `<article class="card"><h3>${title}</h3><p class="muted">${copy}</p></article>`;
}

function authPage(mode: "login" | "register") {
  const isLogin = mode === "login";
  const isCompany = state.authAudience === "company";
  return `
    <main class="form-shell">
      <section class="auth-box">
        <span class="eyebrow">${isCompany ? "Portal da empresa" : "Portal do empregado"}</span>
        <h2>${isLogin ? (isCompany ? "Acesse o espaço da sua empresa." : "Entre para acompanhar seus relatos.") : (isCompany ? "Cadastre sua empresa." : "Crie uma conta para acompanhar seus relatos.")}</h2>
        <p class="muted">${isCompany ? "Gerencie manifestações protegidas, respostas e indicadores de responsividade." : "Seu cadastro é usado para você acompanhar seus relatos. Seus dados de identificação não são enviados à empresa relacionada."}</p>
        <form data-form="auth">
          ${!isLogin ? (isCompany ? `<div class="field"><label>Nome da empresa</label><input name="name" value="Aurora Tecnologia" required /></div><div class="field"><label>CNPJ</label><input name="cnpj" value="12.345.678/0001-90" required /></div>` : `<div class="field"><label>Nome ou apelido</label><input name="name" value="Ana" required /></div>`) : ""}
          <div class="field"><label>Email</label><input name="email" type="email" value="${isLogin ? (isCompany ? "admin@iterah.demo" : "usuario@iterah.demo") : ""}" required /></div>
          <div class="field"><label>Senha</label><input name="password" type="password" value="${isLogin ? demoPassword : ""}" required /></div>
          ${!isLogin ? `<div class="field"><label>Confirmação de senha</label><input name="confirm" type="password" required /></div>
          <label class="small"><input name="terms" type="checkbox" required /> Aceito os termos de uso.</label><br />
          <label class="small"><input name="privacy" type="checkbox" required /> Li a política de privacidade.</label>` : ""}
          <div class="nav-actions" style="margin-top:18px">
            <button class="btn primary" type="submit">${isLogin ? "Entrar" : "Criar conta"}</button>
            <button class="btn" type="button" data-action="switch-auth-audience">${isCompany ? "Sou empregado" : "Sou empresa"}</button>
          </div>
        </form>
      </section>
      <aside class="card">
        <h3>Acessos demo</h3>
        <p class="muted small">${isCompany ? "Empresa: admin@iterah.demo / 123456" : "Empregado: usuario@iterah.demo / 123456"}</p>
        <div class="notice">A POC usa dados fictícios e não promete anonimato absoluto na internet. A promessa visual é: sua identidade não é compartilhada com a empresa.</div>
      </aside>
    </main>
  `;
}

const onboardingSteps = [
  {
    title: "Seu contexto",
    intro: "Antes de você falar sobre o que aconteceu, queremos entender um pouco do seu contexto.",
    fields: [
      ["Qual é sua relação atual com a empresa?", ["Trabalho atualmente nela", "Trabalhei anteriormente", "Prestador(a) / terceirizado(a)", "Candidato(a) em processo seletivo", "Outro"]],
      ["Há quanto tempo você tem ou teve vínculo?", ["Menos de 3 meses", "3 a 12 meses", "1 a 3 anos", "Mais de 3 anos", "Prefiro não informar"]],
      ["Em qual formato você trabalha ou trabalhava?", ["Presencial", "Híbrido", "Remoto", "Externo / campo", "Outro"]],
      ["Você lidera ou liderava outras pessoas?", ["Sim", "Não", "Prefiro não informar"]],
    ],
  },
  {
    title: "Como está sua experiência",
    intro: "Essas respostas ajudam a organizar sua experiência sem revelar quem você é.",
    fields: [
      ["Nas últimas semanas, com que frequência o trabalho tem causado tensão, medo, exaustão ou sobrecarga?", ["Nunca", "Raramente", "Às vezes", "Frequentemente", "Quase todos os dias"]],
      ["Você sente que pode falar sobre problemas sem medo de consequências?", ["1", "2", "3", "4", "5"]],
      ["Quando um problema é reportado, a empresa costuma ouvir e agir?", ["Sim", "Às vezes", "Raramente", "Não", "Nunca reportei"]],
      ["Quais situações mais aparecem no seu dia a dia?", ["Sobrecarga", "Cobrança excessiva", "Conflitos", "Assédio ou humilhação", "Falta de apoio", "Metas incompatíveis", "Falta de autonomia", "Jornada excessiva"]],
    ],
  },
  {
    title: "Por que você veio até aqui",
    intro: "Você pode pular perguntas opcionais. Situações sensíveis recebem revisão com cuidado adicional.",
    fields: [
      ["O que melhor descreve o motivo de você estar aqui hoje?", ["Quero relatar algo que aconteceu comigo", "Presenciei algo acontecendo com outra pessoa", "É um problema recorrente na equipe", "Quero registrar um alerta antes que piore", "Outro"]],
      ["Isso ainda está acontecendo?", ["Sim", "Não", "Não sei"]],
      ["Você sente que há risco imediato para você ou outra pessoa?", ["Sim", "Não", "Não tenho certeza"]],
    ],
  },
  {
    title: "Confiança e expectativa",
    intro: "Última etapa. Queremos entender o que você espera desse acompanhamento.",
    fields: [
      ["Se a empresa pudesse receber seu relato sem saber quem você é, isso ajudaria?", ["1", "2", "3", "4", "5"]],
      ["O que você espera que aconteça depois de enviar um relato?", ["Quero apenas ser ouvido(a)", "Quero que a empresa dê um retorno", "Quero que a empresa investigue internamente", "Quero que o problema não aconteça com outras pessoas", "Quero acompanhar providências"]],
    ],
  },
];

function onboardingPage() {
  if (state.onboardingStep > 3) {
    return `
      <main class="form-shell">
        <section class="wizard-box">
          <span class="eyebrow">Pesquisa concluída</span>
          <h2>Obrigado. Você não precisa se encaixar em um formulário para ser ouvido.</h2>
          <p class="lead">Essas respostas servem apenas para nos ajudar a compreender melhor seu contexto.</p>
          <button class="btn primary" data-route="worker">Ir para minha área</button>
        </section>
      </main>
    `;
  }
  const step = onboardingSteps[state.onboardingStep];
  return `
    <main class="form-shell">
      <section class="wizard-box">
        <div class="progress"><span style="width:${((state.onboardingStep + 1) / 4) * 100}%"></span></div>
        <p class="muted small" style="margin-top:14px">Etapa ${state.onboardingStep + 1} de 4</p>
        <h2>${step.title}</h2>
        <p class="muted">${step.intro} Você pode pular perguntas opcionais.</p>
        ${step.fields
          .map(
            ([question, options], index) => `
            <div class="field">
              <label>${question}</label>
              <div class="option-grid">${(options as string[]).map((option, o) => `<button class="option ${o === 0 ? "selected" : ""}" data-action="select-option" type="button">${option}</button>`).join("")}</div>
              ${state.onboardingStep === 2 && index === 2 ? `<div class="notice warn small">Obrigado por nos contar. Situações de risco imediato precisam de atenção humana. Sua manifestação poderá receber prioridade e revisão antes de qualquer contato automático.</div>` : ""}
            </div>`,
          )
          .join("")}
        <div class="nav-actions">
          <button class="btn" data-action="skip-onboarding">Pular por enquanto</button>
          <button class="btn primary" data-action="next-onboarding">${state.onboardingStep === 3 ? "Concluir" : "Continuar"}</button>
        </div>
      </section>
      <aside class="card">
        <h3>Privacidade visual</h3>
        <p class="muted">Sua identidade não será enviada à empresa. Você poderá revisar a versão compartilhada antes do envio.</p>
      </aside>
    </main>
  `;
}

function workerLayout(content: string) {
  return `
    <main class="portal-layout">
      <aside class="sidebar">
        ${sideLink("worker", "Início")}
        ${sideLink("companies", "Empresas")}
        ${sideLink("new-complaint", "Nova manifestação")}
        ${sideLink("case", "Acompanhamento")}
      </aside>
      <section class="content">${content}</section>
    </main>
  `;
}

function adminLayout(content: string) {
  return `
    <main class="portal-layout">
      <aside class="sidebar">
        ${sideLink("admin", "Visão geral")}
        ${sideLink("admin-cases", "Manifestações")}
        ${sideLink("admin-companies", "Empresas")}
        ${sideLink("admin-ai", "IA / Supervisão")}
        ${sideLink("admin-ranking", "Ranking")}
        <button class="side-link" type="button">Relatórios</button>
        <button class="side-link" type="button">Configurações</button>
      </aside>
      <section class="content">${content}</section>
    </main>
  `;
}

function sideLink(route: Route, label: string) {
  return `<button class="side-link ${state.route === route ? "active" : ""}" data-route="${route}">${label}</button>`;
}

function workerDashboard() {
  const workerComplaints = currentWorkerComplaints();
  return `
    <div class="page-head">
      <div><h2>Olá, ${state.user?.name ?? "Ana"}. Como podemos ajudar hoje?</h2><p class="muted">Acompanhe seus relatos e comece uma nova escuta quando precisar.</p></div>
      <button class="btn primary" data-route="companies">Fazer uma nova manifestação</button>
    </div>
    <div class="grid four">
      ${metric("Em acompanhamento", workerComplaints.filter((c) => !["Finalizada", "Encerrada sem resposta"].includes(c.status)).length)}
      ${metric("Aguardando empresa", workerComplaints.filter((c) => c.status.includes("Aguardando")).length)}
      ${metric("Respondidas", workerComplaints.filter((c) => c.status === "Respondida").length)}
      ${metric("Finalizadas", workerComplaints.filter((c) => c.status === "Finalizada").length)}
    </div>
    <section style="margin-top:24px">
      <h3>Seus últimos relatos</h3>
      <div class="grid two">
        ${workerComplaints
          .slice(0, 4)
          .map((complaint) => caseCard(complaint))
          .join("")}
      </div>
    </section>
    <section class="card" style="margin-top:24px">
      <h3>O que acontece depois que eu envio?</h3>
      <p class="muted">A Ecoa Voz revisa o conteúdo, prepara uma versão sem dados identificáveis, convida a empresa a responder e mantém você informado com linguagem simples.</p>
    </section>
  `;
}

function metric(label: string, value: string | number, hint = "") {
  return `<article class="metric-card"><span class="muted small">${label}</span><div class="metric-value">${value}</div>${hint ? `<p class="muted small">${hint}</p>` : ""}</article>`;
}

function caseCard(complaint: Complaint) {
  const company = companyById(complaint.companyId);
  return `
    <article class="card">
      <div class="nav-actions" style="justify-content:space-between"><strong>${company.tradeName}</strong>${statusBadge(complaint.status)}</div>
      <h3 style="margin-top:12px">${complaint.title}</h3>
      <p class="muted small">${complaint.category} · ${fmtDate(complaint.createdAt)}</p>
      <p class="muted">${complaint.sanitizedContent.slice(0, 128)}...</p>
      <button class="btn" data-route="case" data-case="${complaint.id}">Acompanhar</button>
    </article>
  `;
}

function companySearchPage() {
  const query = state.search.toLowerCase();
  const results = companies.filter((company) => `${company.tradeName} ${company.legalName} ${company.cnpj}`.toLowerCase().includes(query));
  return `
    <div class="page-head">
      <div><h2>Pesquisar empresa</h2><p class="muted">Digite o nome ou CNPJ da empresa relacionada ao relato.</p></div>
    </div>
    <div class="field"><input data-input="search" value="${state.search}" placeholder="Digite o nome ou CNPJ da empresa" /></div>
    ${results.length === 0 ? `<div class="empty"><div><h3>Nenhuma empresa encontrada</h3><p class="muted">Você pode revisar a busca ou seguir com cadastro manual em uma próxima versão.</p></div></div>` : ""}
    <div class="grid three">
      ${results
        .map(
          (company) => `
          <article class="card">
            <span class="badge">Empresa encontrada na base pública</span>
            <h3 style="margin-top:12px">${company.tradeName}</h3>
            <p class="muted small">${company.legalName}</p>
            <p class="muted small">CNPJ ${company.cnpj.slice(0, 8)}***/${company.cnpj.slice(-2)} · ${company.city}/${company.state}</p>
            <p class="muted">${company.industry}</p>
            <button class="btn primary" data-action="select-company" data-company="${company.id}">É sobre esta empresa</button>
          </article>`,
        )
        .join("")}
    </div>
  `;
}

const complaintTopics = ["Sobrecarga / excesso de trabalho", "Pressão ou cobrança excessiva", "Assédio / humilhação", "Conflito com liderança", "Conflito com colegas", "Falta de apoio", "Jornada / disponibilidade", "Discriminação", "Insegurança / medo de demissão", "Outro"];
const expectedOutcomes = ["Apenas registrar", "Receber uma resposta", "Que a empresa investigue", "Que alguma prática seja revista", "Que haja acompanhamento", "Outro"];

function newComplaintPage() {
  const company = companyById(state.selectedCompanyId);
  const stepTitle = ["Tema", "Relato", "Meio de comunicação", "O que você espera", "Revisão por IA"][state.complaintStep];
  return `
    <div class="page-head">
      <div><h2>Nova manifestação</h2><p class="muted">Empresa selecionada: <strong>${company.tradeName}</strong>. Etapa ${state.complaintStep + 1} de 5 · ${stepTitle}</p></div>
    </div>
    <section class="wizard-box">
      <div class="progress"><span style="width:${((state.complaintStep + 1) / 5) * 100}%"></span></div>
      ${complaintStep()}
    </section>
  `;
}

function complaintStep() {
  if (state.complaintStep === 0) {
    return `
      <h2>O que melhor descreve o que aconteceu?</h2>
      <div class="option-grid">${complaintTopics.map((topic) => `<button class="option ${state.complaintDraft.category === topic ? "selected" : ""}" data-action="topic" data-value="${topic}">${topic}</button>`).join("")}</div>
      <div class="nav-actions" style="margin-top:18px"><button class="btn primary" data-action="next-complaint">Continuar</button></div>
    `;
  }
  if (state.complaintStep === 1) {
    return `
      <h2>Conte o que aconteceu do seu jeito.</h2>
      <p class="muted">Você não precisa escrever de forma perfeita. Explique como se estivesse contando para alguém de confiança.</p>
      <div class="notice">Evite colocar seu nome, telefone, e-mail ou informações que facilitem sua identificação. Antes de enviar, a Ecoa Voz também fará uma revisão para proteger sua identidade.</div>
      <div class="field" style="margin-top:16px"><label>Título curto</label><input data-draft="title" value="${state.complaintDraft.title || "Sobrecarga e cobranças fora do horário"}" /></div>
      <div class="field"><label>Relato</label><textarea data-draft="originalContent">${state.complaintDraft.originalContent}</textarea></div>
      <div class="grid two"><div class="field"><label>Quando isso aconteceu?</label><input data-draft="incidentDate" value="${state.complaintDraft.incidentDate}" /></div><div class="field"><label>Isso é recorrente?</label><input data-draft="recurrence" value="${state.complaintDraft.recurrence}" /></div></div>
      <div class="nav-actions"><button class="btn" data-action="prev-complaint">Voltar</button><button class="btn primary" data-action="next-complaint">Continuar</button></div>
    `;
  }
  if (state.complaintStep === 2) {
    return `
      <h2>Meio de comunicação</h2>
      <p class="muted">Informe como a Ecoa Voz pode contatar a empresa sobre esta manifestação. Você pode adicionar mais de um e-mail, telefone fixo ou celular.</p>
      <div class="contact-entry">
        <div class="field contact-field">
          <label for="communication-channel">E-mail ou telefone da empresa</label>
          <input id="communication-channel" data-input="communication-channel" value="${escapeHtml(state.communicationInput)}" placeholder="Ex.: ouvidoria@empresa.com.br ou (11) 99999-9999" aria-describedby="communication-help communication-error" />
        </div>
        <button class="btn primary" type="button" data-action="add-communication">Adicionar meio de comunicação</button>
      </div>
      <p id="communication-help" class="muted small">Para telefones brasileiros, inclua o DDD. Aceitamos formatos com espaços, parênteses, hífen e +55.</p>
      ${state.communicationError ? `<p id="communication-error" class="field-error" role="alert">${state.communicationError}</p>` : ""}
      <div class="contact-list" aria-live="polite">
        ${state.complaintDraft.communicationChannels.length
          ? state.complaintDraft.communicationChannels.map((channel, index) => `<div class="contact-chip"><span>${escapeHtml(channel)}</span><button type="button" data-action="remove-communication" data-index="${index}" aria-label="Remover ${escapeHtml(channel)}">×</button></div>`).join("")
          : `<div class="empty-contact">Nenhum meio adicionado ainda.</div>`}
      </div>
      <div class="nav-actions" style="margin-top:18px"><button class="btn" data-action="prev-complaint">Voltar</button><button class="btn primary" data-action="next-complaint" ${state.complaintDraft.communicationChannels.length ? "" : "disabled"}>Continuar</button></div>
    `;
  }
  if (state.complaintStep === 3) {
    return `
      <h2>O que você espera?</h2>
      <div class="option-grid">${expectedOutcomes.map((outcome) => `<button class="option ${state.complaintDraft.expectedOutcome.includes(outcome) ? "selected" : ""}" data-action="outcome" data-value="${outcome}">${outcome}</button>`).join("")}</div>
      <div class="nav-actions" style="margin-top:18px"><button class="btn" data-action="prev-complaint">Voltar</button><button class="btn primary" data-action="next-complaint">Preparar revisão por IA</button></div>
    `;
  }
  return `
    <div class="nav-actions" style="justify-content:flex-start"><div class="spinner"></div><span class="muted">Estamos preparando seu relato para envio seguro.</span></div>
    <div class="grid four" style="margin:18px 0">
      ${["conteúdo analisado", "categoria identificada", "dados identificáveis revisados", "versão anonimizada preparada"].map((item) => `<div class="ai-step"><span>${item}</span><strong>OK</strong></div>`).join("")}
    </div>
    <div class="comparison">
      <div class="text-panel"><h3>Seu relato original</h3><p>${highlightOriginal(state.complaintDraft.originalContent)}</p></div>
      <div class="text-panel"><h3>Versão que será enviada à empresa</h3><p>${sanitizedDraft()}</p><span class="badge green">Identidade protegida perante a empresa</span></div>
    </div>
    <div class="nav-actions" style="margin-top:18px"><button class="btn" data-action="prev-complaint">Quero ajustar meu relato</button><button class="btn primary" data-action="submit-complaint">Aprovar e enviar</button></div>
  `;
}

function escapeHtml(value: string) {
  return value.replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]!);
}

function communicationType(value: string): "E-mail" | "Telefone fixo" | "Celular" | null {
  const input = value.trim();
  if (/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/i.test(input)) return "E-mail";

  let digits = input.replace(/\D/g, "");
  if ((digits.length === 12 || digits.length === 13) && digits.startsWith("55")) digits = digits.slice(2);
  const validAreaCode = /^[1-9]\d/.test(digits);
  if (validAreaCode && /^\d{2}[2-5]\d{7}$/.test(digits)) return "Telefone fixo";
  if (validAreaCode && /^\d{2}9\d{8}$/.test(digits)) return "Celular";
  return null;
}

function addCommunicationChannel() {
  const value = state.communicationInput.trim();
  const type = communicationType(value);
  if (!type) {
    state.communicationError = "Digite um e-mail válido ou um telefone brasileiro com DDD.";
    return render();
  }
  if (state.complaintDraft.communicationChannels.some((item) => item.toLowerCase() === value.toLowerCase())) {
    state.communicationError = "Este meio de comunicação já foi adicionado.";
    return render();
  }
  state.complaintDraft = { ...state.complaintDraft, communicationChannels: [...state.complaintDraft.communicationChannels, `${type}: ${value}`] };
  state.communicationInput = "";
  state.communicationError = "";
  render();
}

function highlightOriginal(text: string) {
  return text
    .replaceAll("Carlos", `<span class="redacted">Carlos</span>`)
    .replaceAll("financeiro", `<span class="redacted">financeiro</span>`)
    .replaceAll("Maringá", `<span class="redacted">Maringá</span>`)
    .replaceAll("sala 302", `<span class="redacted">sala 302</span>`);
}

function sanitizedDraft() {
  return `Uma <span class="replaced">liderança da área relatada</span> chamou o(a) colaborador(a) para uma <span class="replaced">conversa reservada</span> e associou a pressão a algo esperado. O relato menciona cobranças fora do horário e sensação de exposição.`;
}

function casePage(id: string) {
  const complaint = complaintById(id);
  const company = companyById(complaint.companyId);
  const response = companyResponses.find((item) => item.complaintId === id);
  return `
    <div class="page-head">
      <div><h2>${company.tradeName}</h2><p class="muted">${complaint.title} · ${statusBadge(complaint.status)}</p></div>
      ${riskBadge(complaint.riskLevel)}
    </div>
    <div class="grid two">
      <section class="card">
        <h3>Status do caso</h3>
        <div class="timeline">${state.histories.filter((history) => history.complaintId === id).map(timelineItem).join("")}</div>
      </section>
      <section class="card">
        <h3>Sua manifestação foi revisada e encaminhada com proteção de identidade.</h3>
        <p class="muted">${complaint.sanitizedContent}</p>
        <div class="notice">Sua identidade não é compartilhada com a empresa.</div>
      </section>
    </div>
    <section class="card" style="margin-top:18px">
      <h3>${response ? "A empresa respondeu" : "Aguardando resposta da empresa"}</h3>
      <p class="muted">${response?.content ?? "A empresa foi convidada a responder. Assim que houver retorno, ele aparecerá aqui."}</p>
      ${response ? `<p><strong>Esse retorno foi útil?</strong></p><div class="nav-actions"><button class="btn">Sim</button><button class="btn">Parcialmente</button><button class="btn">Não</button></div><p style="margin-top:18px"><strong>O caso pode ser encerrado?</strong></p><div class="nav-actions"><button class="btn primary">Sim, considero finalizado</button><button class="btn">Quero continuar acompanhando</button></div>` : ""}
    </section>
  `;
}

function timelineItem(history: ComplaintStatusHistory) {
  return `<div class="timeline-item"><span class="muted small">${fmtDate(history.timestamp)}</span><div class="timeline-copy"><span class="dot"></span><div><strong>${history.status}</strong><p class="muted small">${history.note}</p></div></div></div>`;
}

function adminDashboard() {
  const highRisk = state.complaints.filter((c) => c.riskLevel === "alto");
  return `
    <div class="page-head"><div><h2>Visão geral operacional</h2><p class="muted">Acompanhe triagem, responsividade e casos que exigem atenção humana.</p></div></div>
    <div class="grid four">
      ${metric("Recebidas", state.complaints.length)}
      ${metric("Em análise", state.complaints.filter((c) => c.status === "Em análise").length)}
      ${metric("Aguardando resposta", state.complaints.filter((c) => c.status.includes("Aguardando")).length)}
      ${metric("Alto risco", highRisk.length, "Revisão humana antes de contato")}
    </div>
    <div class="grid two" style="margin-top:22px">
      <section class="card"><h3>Manifestações por categoria</h3>${barChart(categoriesCount())}</section>
      <section class="card"><h3>Volume por período</h3>${barChart({ "1-3 set": 6, "4-7 set": 5, "8-11 set": 7, "12-16 set": 2 })}</section>
    </div>
    <section style="margin-top:22px"><h3>Casos que exigem atenção</h3><div class="grid two">${highRisk.slice(0, 4).map(caseCardAdmin).join("")}</div></section>
  `;
}

function categoriesCount() {
  return state.complaints.reduce<Record<string, number>>((acc, item) => {
    acc[item.category] = (acc[item.category] ?? 0) + 1;
    return acc;
  }, {});
}

function barChart(data: Record<string, number>) {
  const max = Math.max(...Object.values(data));
  return `<div class="chart">${Object.entries(data).map(([label, value]) => `<div class="bar"><span class="small muted">${label}</span><div class="bar-track"><div class="bar-fill" style="width:${(value / max) * 100}%"></div></div><strong>${value}</strong></div>`).join("")}</div>`;
}

function caseCardAdmin(complaint: Complaint) {
  return `<article class="card"><div class="nav-actions" style="justify-content:space-between"><strong>${complaint.id}</strong>${riskBadge(complaint.riskLevel)}</div><h3>${companyById(complaint.companyId).tradeName}</h3><p class="muted">${complaint.category} · ${complaint.status}</p><button class="btn" data-route="admin-case" data-admin-case="${complaint.id}">Visualizar</button></article>`;
}

function adminCases() {
  const filtered = state.complaints.filter((complaint) => {
    return (!state.filters.status || complaint.status === state.filters.status) && (!state.filters.risk || complaint.riskLevel === state.filters.risk);
  });
  return `
    <div class="page-head"><div><h2>Manifestações</h2><p class="muted">Filtre por empresa, status, risco, categoria e período.</p></div></div>
    <div class="filters">
      <select data-filter="status"><option value="">Status</option>${[...new Set(state.complaints.map((c) => c.status))].map((s) => `<option ${state.filters.status === s ? "selected" : ""}>${s}</option>`).join("")}</select>
      <select data-filter="risk"><option value="">Risco</option><option value="baixo">baixo</option><option value="medio">médio</option><option value="alto">alto</option></select>
      <select><option>Empresa</option><option>Aurora Tecnologia</option></select>
      <select><option>Categoria</option><option>Sobrecarga</option><option>Pressão excessiva</option></select>
      <select><option>Período</option><option>Últimos 7 dias</option></select>
    </div>
    <div class="table-wrap"><table><thead><tr><th>ID</th><th>Empresa</th><th>Categoria</th><th>Data</th><th>Status</th><th>Risco</th><th>Última ação</th><th></th></tr></thead><tbody>
      ${filtered.map((c) => `<tr><td>${c.id}</td><td>${companyById(c.companyId).tradeName}</td><td>${c.category}</td><td>${fmtDate(c.createdAt)}</td><td>${statusBadge(c.status)}</td><td>${riskBadge(c.riskLevel)}</td><td>${fmtDate(c.updatedAt)}</td><td><button class="btn" data-route="admin-case" data-admin-case="${c.id}">Visualizar</button></td></tr>`).join("")}
    </tbody></table></div>
  `;
}

function adminCaseDetail(id: string) {
  const complaint = complaintById(id);
  const company = companyById(complaint.companyId);
  const analysis = analysisByComplaint(id);
  const tabs = ["Resumo", "Relato", "IA", "Comunicação", "Auditoria"];
  return `
    <div class="page-head"><div><h2>${complaint.id} · ${company.tradeName}</h2><p class="muted">${complaint.category} · ${statusBadge(complaint.status)} · ${riskBadge(complaint.riskLevel)}</p></div></div>
    <div class="tabs">${tabs.map((tab) => `<button class="tab ${state.selectedTab === tab ? "active" : ""}" data-action="tab" data-value="${tab}">${tab}</button>`).join("")}</div>
    <section class="card">${adminTab(complaint, company, analysis)}</section>
  `;
}

function adminTab(complaint: Complaint, company: Company, analysis: AiAnalysis) {
  if (state.selectedTab === "Relato") {
    return `<div class="comparison"><div><h3>Original</h3><p>${highlightOriginal(complaint.originalContent)}</p></div><div><h3>Versão anonimizada</h3><p>${complaint.sanitizedContent}</p><span class="badge green">Trechos alterados destacados</span></div></div>`;
  }
  if (state.selectedTab === "IA") {
    return `<div class="grid two"><div><h3>Classificação sugerida</h3><p>${analysis.suggestedCategory}</p><h3>Nível de risco</h3>${riskBadge(analysis.riskLevel)}<h3 style="margin-top:16px">Dados identificáveis encontrados</h3><p class="muted">${analysis.piiDetected.join(", ")}</p><h3>Confiança</h3><p>${Math.round(analysis.confidence * 100)}%</p></div><div><h3>Mensagem sugerida para empresa</h3><textarea>${analysis.suggestedMessage}</textarea><div class="nav-actions"><button class="btn primary">Aprovar ação da IA</button><button class="btn">Editar</button><button class="btn danger">Reprovar</button><button class="btn">Marcar para revisão humana</button></div></div></div>`;
  }
  if (state.selectedTab === "Comunicação") {
    return `<h3>Timeline de mensagens</h3><div class="timeline">${state.histories.filter((h) => h.complaintId === complaint.id).map(timelineItem).join("")}</div><button class="btn primary" data-action="open-response-modal">Simular resposta da empresa</button>`;
  }
  if (state.selectedTab === "Auditoria") {
    const logs = auditLogs.filter((log) => log.complaintId === complaint.id);
    return `<div class="table-wrap"><table><thead><tr><th>Quem</th><th>Data/hora</th><th>Ação</th><th>Resultado</th></tr></thead><tbody>${logs.map((log) => `<tr><td>${log.actor}</td><td>${fmtDate(log.timestamp)}</td><td>${log.action}</td><td>${log.result}</td></tr>`).join("")}</tbody></table></div>`;
  }
  return `<div class="grid two"><div>${infoCard("Empresa", `${company.legalName}<br>${company.city}/${company.state}`)}${infoCard("Expectativa do usuário", complaint.expectedOutcome.join(", "))}</div><div>${infoCard("Regra human in the loop", hitlCopy(complaint.riskLevel))}<div class="nav-actions"><button class="btn primary">Simular envio para empresa</button><button class="btn">Alterar status manualmente</button></div></div></div>`;
}

function hitlCopy(risk: RiskLevel) {
  if (risk === "baixo") return "Risco baixo: a IA pode preparar e executar fluxo automático.";
  if (risk === "medio") return "Risco médio: IA prepara, mas exige aprovação humana antes do envio.";
  return "Risco alto: nenhum contato automático deve ser executado antes de revisão humana.";
}

function adminCompanies() {
  return `
    <div class="page-head"><div><h2>Empresas</h2><p class="muted">Responsividade observável, sem diagnóstico do ambiente de trabalho.</p></div></div>
    <div class="table-wrap"><table><thead><tr><th>Empresa</th><th>Setor</th><th>Manifestações</th><th>Taxa de resposta</th><th>Tempo médio</th><th>Tratados</th><th>Índice</th></tr></thead><tbody>
      ${companies.map((company) => {
        const m = metrics.find((item) => item.companyId === company.id)!;
        return `<tr><td><strong>${company.tradeName}</strong><br><span class="muted small">${company.city}/${company.state}</span></td><td>${company.industry}</td><td>${m.complaintsReceived}</td><td>${m.responseRate}%</td><td>${m.averageFirstResponseTime.toFixed(1)} dias</td><td>${m.treatedCasesRate}%</td><td>${m.score ? `<strong>${m.score}</strong>` : "Amostra insuficiente"}</td></tr>`;
      }).join("")}
    </tbody></table></div>
    <section class="card" style="margin-top:20px">
      <span class="badge green">Empresa verificada</span>
      <h2>Índice de Responsividade Iterah</h2>
      <p class="muted">Este indicador representa como a organização respondeu às manifestações recebidas pela plataforma. Ele não representa diagnóstico do ambiente de trabalho nem certificação de saúde psicossocial.</p>
      <div class="grid four">${metric("Taxa de resposta", "92%")}${metric("Primeira resposta", "1,2 dias")}${metric("Casos com retorno", "84%")}${metric("Volume mínimo", "Atingido")}</div>
    </section>
  `;
}

function aiSupervision() {
  return `
    <div class="page-head"><div><h2>IA / Supervisão</h2><p class="muted">Regras de triagem e revisão humana para contato seguro.</p></div></div>
    <div class="grid three">
      ${infoCard("Risco baixo", "Badge verde. A IA pode preparar e executar fluxo automático.")}
      ${infoCard("Risco médio", "Badge amarelo. IA prepara, mas exige aprovação humana antes do envio.")}
      ${infoCard("Risco alto", "Badge vermelho. Nenhum contato automático antes de revisão humana.")}
    </div>
    <section class="card" style="margin-top:20px"><h3>Fila de revisão</h3><div class="grid two">${state.complaints.filter((c) => c.riskLevel !== "baixo").slice(0, 6).map(caseCardAdmin).join("")}</div></section>
  `;
}

function rankingPage() {
  const ranked = [...metrics].sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
  return `
    <div class="page-head"><div><h2>Ranking de responsividade</h2><p class="muted">Mede capacidade de ouvir, responder e tratar manifestações recebidas pela plataforma.</p></div></div>
    <div class="notice">Não há compra de nota ou melhoria paga de ranking nesta POC.</div>
    <div class="grid three" style="margin-top:18px">
      ${ranked.map((item, index) => {
        const company = companyById(item.companyId);
        return `<article class="card"><span class="badge">${index + 1}º</span><h3>${company.tradeName}</h3><p class="muted">${company.industry}</p><div class="metric-value">${item.score ?? "Sem nota"}</div><p class="muted small">${item.responseRate}% resposta · ${item.averageFirstResponseTime.toFixed(1)} dias</p></article>`;
      }).join("")}
    </div>
  `;
}

function responseModal() {
  return `
    <div class="modal-backdrop">
      <form class="modal" data-form="company-response">
        <h2>Simular resposta da empresa</h2>
        <p class="muted">Registre um retorno institucional para atualizar o status e a timeline.</p>
        <textarea name="content">Agradecemos o relato. O conteúdo foi encaminhado à área responsável para análise. Estamos revisando a distribuição de carga da equipe e retornaremos com uma atualização.</textarea>
        <div class="nav-actions" style="margin-top:16px"><button class="btn" type="button" data-action="close-modal">Cancelar</button><button class="btn primary" type="submit">Enviar resposta</button></div>
      </form>
    </div>
  `;
}

function bind() {
  app.querySelectorAll<HTMLElement>("[data-route]").forEach((element) => {
    element.addEventListener("click", () => {
      const caseId = element.dataset.case;
      const adminCaseId = element.dataset.adminCase;
      setRoute(element.dataset.route as Route, {
        caseId: caseId ?? state.caseId,
        adminCaseId: adminCaseId ?? state.adminCaseId,
        selectedTab: adminCaseId ? "Resumo" : state.selectedTab,
      });
    });
  });

  app.querySelectorAll<HTMLElement>("[data-action]").forEach((element) => {
    element.addEventListener("click", (event) => {
      const action = element.dataset.action!;
      if (action === "logout") return setRoute("landing", { user: null });
      if (action === "set-audience") return setRoute("landing", { landingAudience: element.dataset.audience as "worker" | "company" });
      if (action === "open-auth") return setRoute(element.dataset.mode as "login" | "register", { authAudience: element.dataset.audience as "worker" | "company" });
      if (action === "switch-auth-audience") {
        const authAudience = state.authAudience === "company" ? "worker" : "company";
        return setRoute(state.route, { authAudience, landingAudience: authAudience });
      }
      if (action === "demo-worker") return setRoute("onboarding", { user: users[0], onboardingStep: 0 });
      if (action === "demo-admin") return setRoute("admin", { user: users[1] });
      if (action === "next-onboarding") return setRoute("onboarding", { onboardingStep: state.onboardingStep + 1 });
      if (action === "skip-onboarding") return setRoute("worker", { onboardingStep: 4 });
      if (action === "select-option") return element.classList.toggle("selected");
      if (action === "select-company") return setRoute("new-complaint", { selectedCompanyId: element.dataset.company!, complaintStep: 0 });
      if (action === "topic") return setRoute("new-complaint", { complaintDraft: { ...state.complaintDraft, category: element.dataset.value! } });
      if (action === "outcome") {
        const value = element.dataset.value!;
        const existing = state.complaintDraft.expectedOutcome;
        const next = existing.includes(value) ? existing.filter((item) => item !== value) : [...existing, value];
        return setRoute("new-complaint", { complaintDraft: { ...state.complaintDraft, expectedOutcome: next } });
      }
      if (action === "add-communication") return addCommunicationChannel();
      if (action === "remove-communication") {
        const communicationChannels = state.complaintDraft.communicationChannels.filter((_, index) => index !== Number(element.dataset.index));
        return setRoute("new-complaint", { complaintDraft: { ...state.complaintDraft, communicationChannels }, communicationError: "" });
      }
      if (action === "next-complaint") return setRoute("new-complaint", { complaintStep: Math.min(4, state.complaintStep + 1) });
      if (action === "prev-complaint") return setRoute("new-complaint", { complaintStep: Math.max(0, state.complaintStep - 1) });
      if (action === "submit-complaint") return submitComplaint();
      if (action === "tab") return setRoute("admin-case", { selectedTab: element.dataset.value! });
      if (action === "open-response-modal") return setRoute("admin-case", { modal: "company-response" });
      if (action === "close-modal") return setRoute("admin-case", { modal: null });
      event.preventDefault();
    });
  });

  app.querySelector<HTMLFormElement>('[data-form="auth"]')?.addEventListener("submit", (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget as HTMLFormElement);
    const email = String(form.get("email"));
    const password = String(form.get("password"));
    if (state.route === "register") {
      const name = String(form.get("name") || (state.authAudience === "company" ? "Empresa" : "Pessoa trabalhadora"));
      const user: User = { id: `demo-${Date.now()}`, name, email, role: state.authAudience === "company" ? "admin" : "worker", createdAt: new Date().toISOString() };
      return setRoute(user.role === "admin" ? "admin" : "onboarding", { user, onboardingStep: 0 });
    }
    const user = users.find((item) => item.email === email);
    const expectedRole = state.authAudience === "company" ? "admin" : "worker";
    if (!user || user.role !== expectedRole || password !== demoPassword) {
      alert(`Credencial demo inválida. Use ${state.authAudience === "company" ? "admin@iterah.demo" : "usuario@iterah.demo"} com senha 123456.`);
      return;
    }
    setRoute(user.role === "admin" ? "admin" : "worker", { user });
  });

  app.querySelector<HTMLFormElement>('[data-form="company-response"]')?.addEventListener("submit", (event) => {
    event.preventDefault();
    const complaint = complaintById(state.adminCaseId);
    complaint.status = "Respondida";
    complaint.updatedAt = new Date().toISOString();
    state.histories.push({ complaintId: complaint.id, status: "Respondida", timestamp: complaint.updatedAt, actor: "company", note: "Empresa respondeu pelo painel administrativo." });
    setRoute("admin-case", { modal: null, selectedTab: "Comunicação" });
  });

  app.querySelector<HTMLInputElement>('[data-input="search"]')?.addEventListener("input", (event) => {
    state.search = (event.currentTarget as HTMLInputElement).value;
    render();
  });

  app.querySelector<HTMLInputElement>('[data-input="communication-channel"]')?.addEventListener("input", (event) => {
    state.communicationInput = (event.currentTarget as HTMLInputElement).value;
    state.communicationError = "";
  });
  app.querySelector<HTMLInputElement>('[data-input="communication-channel"]')?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      addCommunicationChannel();
    }
  });

  app.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>("[data-draft]").forEach((element) => {
    element.addEventListener("input", () => {
      const key = element.dataset.draft as keyof AppState["complaintDraft"];
      state.complaintDraft = { ...state.complaintDraft, [key]: element.value };
    });
  });

  app.querySelectorAll<HTMLSelectElement>("[data-filter]").forEach((element) => {
    element.addEventListener("change", () => {
      state.filters[element.dataset.filter!] = element.value;
      render();
    });
  });
}

function submitComplaint() {
  const now = new Date().toISOString();
  const id = `m-${String(state.complaints.length + 1).padStart(3, "0")}`;
  const complaint: Complaint = {
    id,
    userId: "u-worker",
    companyId: state.selectedCompanyId,
    category: state.complaintDraft.category || "Sobrecarga / excesso de trabalho",
    title: state.complaintDraft.title || "Sobrecarga e cobranças fora do horário",
    originalContent: state.complaintDraft.originalContent,
    sanitizedContent:
      "Uma liderança da área relatada chamou o(a) colaborador(a) para uma conversa reservada e associou a pressão a algo esperado. O relato menciona cobranças fora do horário e sensação de exposição.",
    expectedOutcome: state.complaintDraft.expectedOutcome,
    riskLevel: "medio",
    status: "Aguardando resposta da empresa",
    createdAt: now,
    updatedAt: now,
    incidentDate: state.complaintDraft.incidentDate,
    recurrence: state.complaintDraft.recurrence,
    communicationChannels: state.complaintDraft.communicationChannels,
  };
  state.complaints.unshift(complaint);
  state.histories.push(
    { complaintId: id, status: "Recebida", timestamp: now, actor: "worker", note: "Manifestação recebida." },
    { complaintId: id, status: "Em análise", timestamp: now, actor: "ai", note: "Conteúdo analisado e categoria sugerida." },
    { complaintId: id, status: "Empresa sendo contatada", timestamp: now, actor: "ai", note: "Comunicação preparada com proteção de identidade." },
    { complaintId: id, status: "Aguardando resposta da empresa", timestamp: now, actor: "admin", note: "Empresa convidada a responder." },
  );
  setRoute("case", { caseId: id, complaintStep: 0 });
}

render();
