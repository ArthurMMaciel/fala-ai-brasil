export type Role = "worker" | "admin" | "commercial";
export type RiskLevel = "baixo" | "medio" | "alto";
export type ComplaintStatus =
  | "Recebida"
  | "Em análise"
  | "Revisão necessária"
  | "Empresa sendo contatada"
  | "Aguardando resposta da empresa"
  | "Respondida"
  | "Em mediação"
  | "Finalizada"
  | "Encerrada sem resposta";

export interface User {
  id: string;
  name: string;
  email: string;
  role: Role;
  createdAt: string;
}

export interface UserProfile {
  userId: string;
  employmentRelationship: string;
  tenure: string;
  workModel: string;
  leadershipRole: string;
  psychologicalContextAnswers: Record<string, string | string[]>;
}

export interface CompanyContact {
  name: string;
  email: string;
  phone: string;
  role: string;
}

export interface Company {
  id: string;
  cnpj: string;
  legalName: string;
  tradeName: string;
  industry: string;
  city: string;
  state: string;
  email: string;
  phone: string;
  verificationStatus: "verificada" | "base_publica" | "pendente";
}

export interface Complaint {
  id: string;
  userId: string;
  companyId: string;
  category: string;
  title: string;
  originalContent: string;
  sanitizedContent: string;
  expectedOutcome: string[];
  riskLevel: RiskLevel;
  status: ComplaintStatus;
  createdAt: string;
  updatedAt: string;
  incidentDate?: string;
  recurrence?: string;
  communicationChannels?: string[];
  companyContacts?: CompanyContact[];
  contextAnswers?: Record<string, string | string[]>;
  usefulFeedback?: "Sim" | "Parcialmente" | "Não";
}

export interface AiAnalysis {
  complaintId: string;
  suggestedCategory: string;
  riskLevel: RiskLevel;
  piiDetected: string[];
  confidence: number;
  sanitizedVersion: string;
  suggestedMessage: string;
  requiresHumanReview: boolean;
}

export interface CompanyResponse {
  id: string;
  complaintId: string;
  content: string;
  createdAt: string;
}

export interface ComplaintStatusHistory {
  complaintId: string;
  status: ComplaintStatus;
  timestamp: string;
  actor: "worker" | "ai" | "admin" | "company";
  note: string;
}

export interface AuditLog {
  id: string;
  complaintId: string;
  actor: string;
  action: string;
  timestamp: string;
  result: string;
}

export interface CompanyReputationMetrics {
  companyId: string;
  complaintsReceived: number;
  responseRate: number;
  averageFirstResponseTime: number;
  treatedCasesRate: number;
  userFeedbackScore: number;
  recurrenceIndicator: number;
  score: number | null;
}
