// Responsividade das empresas (TASK-0036): faixas no lugar de contagem, percentual e posição.
// Os cortes são calculados no banco (company_responsiveness); aqui ficam só rótulos e tons de selo.

export type ResponseBand = "high" | "medium" | "low";
export type ResponseTimeBand = "fast" | "regular" | "slow" | "none";

export const noDataLabel = "Sem dado";

export const responseBandLabels: Record<ResponseBand, string> = {
  high: "Alta (80% ou mais)",
  medium: "Média (50% a 79%)",
  low: "Baixa (menos de 50%)",
};

export const responseTimeBandLabels: Record<ResponseTimeBand, string> = {
  fast: "Rápido (até 48 h)",
  regular: "Regular (até 7 dias)",
  slow: "Lento (mais de 7 dias)",
  none: "Sem resposta",
};

/** Satisfação usa os mesmos cortes da taxa de resposta (ADR-0013); nula até haver 3 avaliações. */
export const satisfactionBandLabels: Record<ResponseBand, string> = {
  high: "Alta",
  medium: "Média",
  low: "Baixa",
};

// Classes de selo já existentes no design system (worker-status).
const tones: Record<string, string> = { high: "respondida", fast: "respondida", medium: "em-revisão", regular: "em-revisão", low: "retida", slow: "retida", none: "em-aberto" };

export function bandLabel(labels: Readonly<Record<string, string>>, band: string | null | undefined): string {
  return band && Object.prototype.hasOwnProperty.call(labels, band) ? labels[band] : noDataLabel;
}

export function bandTone(band: string | null | undefined): string {
  return band && Object.prototype.hasOwnProperty.call(tones, band) ? tones[band] : "em-aberto";
}

/** Tempo exato da própria empresa (my_company_responsiveness), em horas ou dias. */
export function formatHours(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—";
  return value < 48 ? `${value} h` : `${(value / 24).toFixed(1).replace(".", ",")} dias`;
}
