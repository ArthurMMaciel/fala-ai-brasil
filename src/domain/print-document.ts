// PDF da manifestação, fase 1 (TASK-0043): documento montado no navegador e salvo pelo "Salvar como PDF".
// Regras: nenhum dado de identidade; o relato original só entra na versão do trabalhador, se ele marcar;
// a versão da empresa leva só a versão compartilhável.

export interface PrintTimelineItem { title: string; date: string; text: string }
export interface PrintSection { heading: string; text?: string; note?: string; items?: string[]; timeline?: PrintTimelineItem[] }
export interface PrintDocument { fileName: string; eyebrow: string; title: string; meta: [string, string][]; sections: PrintSection[]; footer: string[] }

export const emergencyLine = "Em caso de risco imediato, procure ajuda: CVV 188, SAMU 192 ou Polícia Militar 190. A Escuta Aí Brasil não é um canal de emergência.";

function fileName(protocol: string): string {
  return `manifestacao-${protocol.replace(/[^A-Za-z0-9-]/g, "")}`;
}

export interface WorkerPrintInput {
  protocol: string; title: string; statusText: string; createdAt: string; generatedAt: string;
  companyName: string; category: string; incidentPeriod: string | null; recurrence: string | null; expectedOutcomes: string[];
  shared: string | null; sharedReleased: boolean; timeline: PrintTimelineItem[]; feedbackText: string | null;
  original: string; includeOriginal: boolean;
}

export function buildWorkerPrint(input: WorkerPrintInput): PrintDocument {
  const sections: PrintSection[] = [];
  if (input.includeOriginal && input.original.trim()) sections.push({ heading: "Seu relato original", note: "Só você vê este texto. A empresa não recebe o relato original.", text: input.original });
  if (input.shared?.trim()) sections.push({ heading: input.sharedReleased ? "Versão que a empresa recebeu" : "Versão em revisão pela equipe", text: input.shared });
  if (input.expectedOutcomes.length) sections.push({ heading: "O que você espera", items: input.expectedOutcomes });
  sections.push({ heading: "Acompanhamento", timeline: input.timeline });
  if (input.feedbackText) sections.push({ heading: "Sua avaliação", text: input.feedbackText });
  return {
    fileName: fileName(input.protocol),
    eyebrow: "Comprovante da manifestação",
    title: input.title,
    meta: [["Protocolo", input.protocol], ["Situação", input.statusText], ["Empresa", input.companyName], ["Assunto", input.category], ["Quando aconteceu", input.incidentPeriod ?? "—"], ["Recorrência", input.recurrence ?? "—"], ["Criada em", input.createdAt], ["Gerado em", input.generatedAt]],
    sections,
    footer: ["Documento pessoal com informações do seu relato. Guarde com cuidado.", emergencyLine],
  };
}

export interface CompanyPrintInput {
  protocol: string; title: string; statusText: string; receivedAt: string; generatedAt: string;
  companyName: string; category: string; shared: string; timeline: PrintTimelineItem[]; feedbackText: string | null;
}

export function buildCompanyPrint(input: CompanyPrintInput): PrintDocument {
  const sections: PrintSection[] = [{ heading: "Versão compartilhada", text: input.shared }, { heading: "Histórico", timeline: input.timeline }];
  if (input.feedbackText) sections.push({ heading: "Avaliação do retorno", text: input.feedbackText });
  return {
    fileName: fileName(input.protocol),
    eyebrow: "Manifestação recebida",
    title: input.title,
    meta: [["Protocolo", input.protocol], ["Situação", input.statusText], ["Assunto", input.category], ["Recebida em", input.receivedAt], ["Gerado em", input.generatedAt]],
    sections,
    footer: [`Versão compartilhável revisada pela equipe Escuta Aí Brasil. Não contém a identidade de quem relatou. Não tente identificar a pessoa. Gerado por ${input.companyName} em ${input.generatedAt}.`],
  };
}

/** Data e hora para o documento impresso (fuso do navegador). */
export function printDateTime(date: Date = new Date()): string {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }).format(date);
}
