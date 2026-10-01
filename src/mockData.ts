import {
  AiAnalysis,
  AuditLog,
  Company,
  CompanyReputationMetrics,
  CompanyResponse,
  Complaint,
  ComplaintStatus,
  ComplaintStatusHistory,
  RiskLevel,
  User,
  UserProfile,
} from "./models";

export const users: User[] = [
  { id: "u-worker", name: "Ana", email: "usuario@iterah.demo", role: "worker", createdAt: "2026-09-01T09:00:00" },
  { id: "u-admin", name: "Equipe Ecoa", email: "admin@iterah.demo", role: "admin", createdAt: "2026-09-01T09:00:00" },
];

export const demoPassword = "123456";

export const userProfiles: UserProfile[] = [
  {
    userId: "u-worker",
    employmentRelationship: "Trabalho atualmente nela",
    tenure: "1 a 3 anos",
    workModel: "Híbrido",
    leadershipRole: "Não",
    psychologicalContextAnswers: {
      tensionFrequency: "Frequentemente",
      speakSafety: "2",
      companyActs: "Raramente",
      situations: ["Sobrecarga", "Cobrança excessiva", "Falta de apoio"],
      reason: "Quero relatar algo que aconteceu comigo",
      stillHappening: "Sim",
      immediateRisk: "Não",
      anonymousHelp: "5",
      expectations: ["Quero que a empresa dê um retorno", "Quero acompanhar se alguma providência foi tomada"],
    },
  },
];

export const companies: Company[] = [
  company("c-aurora", "12.345.678/0001-90", "Aurora Tecnologia Ltda.", "Aurora Tecnologia", "Tecnologia", "Maringá", "PR", "contato@auroratec.demo", "(44) 3000-0101", "verificada"),
  company("c-nova", "22.118.441/0001-10", "Nova Essencial Serviços S.A.", "Nova Essencial", "Serviços corporativos", "Curitiba", "PR"),
  company("c-lumina", "31.909.103/0001-77", "Lumina Alimentos Ltda.", "Lumina Alimentos", "Alimentos", "Campinas", "SP"),
  company("c-via", "44.100.200/0001-31", "Via Serena Logística S.A.", "Via Serena", "Logística", "Contagem", "MG"),
  company("c-arco", "19.334.789/0001-55", "Arco Norte Varejo Ltda.", "Arco Norte", "Varejo", "Recife", "PE"),
  company("c-porto", "58.221.006/0001-14", "Porto Claro Energia S.A.", "Porto Claro", "Energia", "Niterói", "RJ"),
  company("c-vereda", "63.554.903/0001-00", "Vereda Saúde Integrada Ltda.", "Vereda Saúde", "Saúde", "Goiânia", "GO"),
  company("c-atlas", "10.222.333/0001-98", "Atlas Educação Digital Ltda.", "Atlas Educação", "Educação", "Florianópolis", "SC"),
  company("c-mosaico", "70.901.220/0001-46", "Mosaico Financeira S.A.", "Mosaico Financeira", "Financeiro", "São Paulo", "SP"),
  company("c-serra", "87.142.987/0001-12", "Serra Azul Mineração Ltda.", "Serra Azul", "Mineração", "Belo Horizonte", "MG"),
  company("c-boreal", "29.548.670/0001-89", "Boreal Contact Center Ltda.", "Boreal Contact", "Atendimento", "Fortaleza", "CE"),
  company("c-mangue", "90.311.765/0001-37", "Mangue Verde Indústria Ltda.", "Mangue Verde", "Indústria", "Belém", "PA"),
];

function company(
  id: string,
  cnpj: string,
  legalName: string,
  tradeName: string,
  industry: string,
  city: string,
  state: string,
  email = "responsavel@empresa.demo",
  phone = "(11) 3000-0000",
  verificationStatus: Company["verificationStatus"] = "base_publica",
): Company {
  return { id, cnpj, legalName, tradeName, industry, city, state, email, phone, verificationStatus };
}

const statuses: ComplaintStatus[] = [
  "Recebida",
  "Em análise",
  "Revisão necessária",
  "Empresa sendo contatada",
  "Aguardando resposta da empresa",
  "Respondida",
  "Em mediação",
  "Finalizada",
  "Encerrada sem resposta",
];
const categories = ["Sobrecarga", "Pressão excessiva", "Assédio / humilhação", "Conflito com liderança", "Falta de apoio", "Jornada / disponibilidade", "Discriminação", "Insegurança"];
const risks: RiskLevel[] = ["baixo", "medio", "alto"];

export const complaints: Complaint[] = Array.from({ length: 20 }).map((_, index) => {
  const id = `m-${String(index + 1).padStart(3, "0")}`;
  const companyId = index < 6 ? "c-aurora" : companies[index % companies.length].id;
  const riskLevel = risks[index % risks.length];
  const status = statuses[(index + 2) % statuses.length];
  return {
    id,
    userId: index < 4 ? "u-worker" : `u-${index}`,
    companyId,
    category: categories[index % categories.length],
    title: [
      "Carga concentrada em fechamento de sprint",
      "Cobranças em canais fora do expediente",
      "Humilhação em reunião de equipe",
      "Falta de apoio depois de mudança de meta",
    ][index % 4],
    originalContent:
      index % 3 === 0
        ? "Meu gerente Carlos, do time financeiro de Maringá, me chamou na sala 302 e disse que eu deveria aguentar a pressão porque todo mundo passa por isso. Desde então tenho recebido cobranças à noite e nos fins de semana."
        : "Tenho sentido que a equipe está sem espaço para falar. As metas mudaram sem conversa, as cobranças ficaram públicas e quem pede ajuda é visto como alguém pouco comprometido.",
    sanitizedContent:
      index % 3 === 0
        ? "Uma liderança da área relatada chamou o(a) colaborador(a) para uma conversa reservada e associou a pressão a algo esperado. O relato menciona cobranças fora do horário e sensação de exposição."
        : "O relato descreve metas alteradas sem diálogo, cobranças públicas e receio de pedir apoio por possível julgamento de comprometimento.",
    expectedOutcome: ["Receber uma resposta", "Que alguma prática seja revista"],
    riskLevel,
    status,
    createdAt: `2026-09-${String((index % 12) + 1).padStart(2, "0")}T10:${String(index * 3).padStart(2, "0")}:00`,
    updatedAt: `2026-09-${String((index % 12) + 2).padStart(2, "0")}T11:20:00`,
    incidentDate: "Últimas semanas",
    recurrence: index % 2 === 0 ? "Recorrente" : "Uma vez",
    usefulFeedback: index % 5 === 0 ? "Parcialmente" : undefined,
  };
});

export const aiAnalyses: AiAnalysis[] = complaints.map((complaint, index) => ({
  complaintId: complaint.id,
  suggestedCategory: complaint.category,
  riskLevel: complaint.riskLevel,
  piiDetected: index % 3 === 0 ? ["nome de liderança", "local específico", "sala"] : ["área muito específica"],
  confidence: 0.72 + ((index % 4) * 0.06),
  sanitizedVersion: complaint.sanitizedContent,
  suggestedMessage:
    "A Ecoa Voz recebeu uma manifestação anonimizada relacionada ao ambiente de trabalho. Solicitamos retorno institucional sobre como a organização pretende ouvir, apurar e tratar a situação descrita, preservando a identidade da pessoa manifestante.",
  requiresHumanReview: complaint.riskLevel !== "baixo",
}));

export const companyResponses: CompanyResponse[] = [
  {
    id: "r-001",
    complaintId: "m-001",
    content:
      "Agradecemos o relato. O conteúdo foi encaminhado à área responsável para análise. Estamos revisando a distribuição de carga da equipe e retornaremos com uma atualização.",
    createdAt: "2026-09-04T15:40:00",
  },
  {
    id: "r-002",
    complaintId: "m-006",
    content:
      "Recebemos a manifestação e iniciaremos escuta interna com lideranças e pessoas envolvidas no processo. Compartilharemos medidas gerais assim que concluirmos a apuração.",
    createdAt: "2026-09-10T09:15:00",
  },
  {
    id: "r-003",
    complaintId: "m-010",
    content:
      "O relato foi registrado no canal interno de pessoas. A empresa fará uma revisão de ritos de comunicação e dos combinados de disponibilidade fora do expediente.",
    createdAt: "2026-09-14T14:10:00",
  },
];

export const histories: ComplaintStatusHistory[] = complaints.flatMap((complaint) => [
  { complaintId: complaint.id, status: "Recebida", timestamp: complaint.createdAt, actor: "worker", note: "Manifestação recebida." },
  { complaintId: complaint.id, status: "Em análise", timestamp: plusMinutes(complaint.createdAt, 1), actor: "ai", note: "Conteúdo analisado e categoria sugerida." },
  { complaintId: complaint.id, status: complaint.riskLevel === "alto" ? "Revisão necessária" : "Empresa sendo contatada", timestamp: plusMinutes(complaint.createdAt, 6), actor: "ai", note: complaint.riskLevel === "alto" ? "Revisão humana indicada antes de contato." : "Comunicação preparada com proteção de identidade." },
  { complaintId: complaint.id, status: complaint.status, timestamp: complaint.updatedAt, actor: complaint.status === "Respondida" ? "company" : "admin", note: statusNote(complaint.status) },
]);

function plusMinutes(iso: string, minutes: number): string {
  const date = new Date(iso);
  date.setMinutes(date.getMinutes() + minutes);
  return date.toISOString();
}

function statusNote(status: ComplaintStatus): string {
  const map: Record<ComplaintStatus, string> = {
    "Recebida": "Manifestação registrada.",
    "Em análise": "Triagem em andamento.",
    "Revisão necessária": "Aguardando revisão humana.",
    "Empresa sendo contatada": "Contato institucional em preparo.",
    "Aguardando resposta da empresa": "Empresa convidada a responder.",
    "Respondida": "Resposta recebida da empresa.",
    "Em mediação": "Caso mantido em acompanhamento.",
    "Finalizada": "Caso finalizado.",
    "Encerrada sem resposta": "Prazo encerrado sem retorno.",
  };
  return map[status];
}

export const auditLogs: AuditLog[] = complaints.slice(0, 12).flatMap((complaint, index) => [
  { id: `a-${complaint.id}-1`, complaintId: complaint.id, actor: "IA Ecoa", action: "Classificação sugerida", timestamp: plusMinutes(complaint.createdAt, 2), result: complaint.category },
  { id: `a-${complaint.id}-2`, complaintId: complaint.id, actor: index % 2 ? "Operação" : "IA Ecoa", action: "Mensagem preparada", timestamp: plusMinutes(complaint.createdAt, 5), result: complaint.riskLevel === "baixo" ? "Pronta para envio" : "Aguardando aprovação" },
]);

export const metrics: CompanyReputationMetrics[] = companies.map((company, index) => ({
  companyId: company.id,
  complaintsReceived: index === 0 ? 18 : 3 + index * 2,
  responseRate: Math.max(44, 92 - index * 4),
  averageFirstResponseTime: 1.2 + index * 0.6,
  treatedCasesRate: Math.max(35, 86 - index * 3),
  userFeedbackScore: Math.max(2.4, 4.6 - index * 0.14),
  recurrenceIndicator: Math.min(64, 12 + index * 4),
  score: index > 9 ? null : Math.max(51, 91 - index * 3),
}));
