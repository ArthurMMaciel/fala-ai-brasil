export type CommercialAudience = "company" | "partner" | "intelligence" | "sponsor";
export type SubscriptionMode = "trial" | "monthly" | "annual";
export type SubscriptionStatus = "trialing" | "pending" | "active" | "expired";

export interface CommercialPlan {
  id: string;
  audience: CommercialAudience;
  name: string;
  monthlyCents: number | null;
}

// Valores demonstrativos; estudos/patrocínios não reutilizam ticket avulso como mensalidade.
export const commercialCatalog: CommercialPlan[] = [
  { id: "company-essential", audience: "company", name: "Essencial", monthlyCents: 150000 },
  { id: "company-management", audience: "company", name: "Gestão", monthlyCents: 390000 },
  { id: "company-multi", audience: "company", name: "Multiunidade", monthlyCents: null },
  { id: "partner-presence", audience: "partner", name: "Presença", monthlyCents: 24900 },
  { id: "partner-professional", audience: "partner", name: "Profissional", monthlyCents: 49900 },
  { id: "partner-national", audience: "partner", name: "Nacional", monthlyCents: 89900 },
  { id: "intelligence-radar", audience: "intelligence", name: "Radar", monthlyCents: 250000 },
  { id: "intelligence-benchmark", audience: "intelligence", name: "Benchmark", monthlyCents: 590000 },
  { id: "intelligence-institutional", audience: "intelligence", name: "Institucional", monthlyCents: null },
  { id: "intelligence-project", audience: "intelligence", name: "Projeto sob proposta", monthlyCents: null },
  { id: "sponsor-content", audience: "sponsor", name: "Conteúdo", monthlyCents: null },
  { id: "sponsor-event", audience: "sponsor", name: "Evento", monthlyCents: null },
  { id: "sponsor-study", audience: "sponsor", name: "Estudo público", monthlyCents: null },
];

export const subscriptionModes: Record<SubscriptionMode, string> = {
  trial: "1 mês grátis · mensal a partir do 2º mês",
  monthly: "Mensal · pagamento imediato",
  annual: "Anual · 5% de desconto",
};

export function annualAmount(monthlyCents: number): number {
  return Math.round(monthlyCents * 12 * 95 / 100);
}

export function addCalendarMonths(date: Date, months: number): Date {
  const result = new Date(date);
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}

export interface CommercialSubscription {
  userId: string;
  audience: CommercialAudience;
  planId: string;
  mode: SubscriptionMode;
  status: SubscriptionStatus;
  nextBillingAt: string | null;
  paidCents: number;
  pendingChange?: { planId: string; mode: "monthly" | "annual" };
}

export function createDemoSubscription(userId: string, planId: string, mode: SubscriptionMode, now = new Date()): CommercialSubscription {
  const plan = commercialCatalog.find(item => item.id === planId);
  if (!plan || !Object.prototype.hasOwnProperty.call(subscriptionModes, mode)) throw new Error("Selecione um plano e uma modalidade válidos.");
  const trial = mode === "trial";
  return { userId, audience: plan.audience, planId, mode, status: trial ? "trialing" : "pending", nextBillingAt: trial ? addCalendarMonths(now, 1).toISOString() : null, paidCents: 0 };
}

export function hasDemoCommercialAccess(subscription: CommercialSubscription, now = new Date()): boolean {
  return (subscription.status === "active" || subscription.status === "trialing") && subscription.nextBillingAt !== null && now < new Date(subscription.nextBillingAt);
}

export function confirmDemoPayment(subscription: CommercialSubscription, now = new Date()): CommercialSubscription {
  const pending = subscription.pendingChange;
  const planId = pending?.planId ?? subscription.planId;
  const mode = pending?.mode ?? subscription.mode;
  const plan = commercialCatalog.find(item => item.id === planId);
  if (!plan || plan.audience !== subscription.audience || plan.monthlyCents === null) throw new Error("Esta oferta precisa de preço aprovado em uma proposta.");
  if (!pending && subscription.status !== "pending") throw new Error("Não há pagamento pendente.");
  return { ...subscription, planId, mode, status: "active", paidCents: subscription.paidCents + (mode === "annual" ? annualAmount(plan.monthlyCents) : plan.monthlyCents), nextBillingAt: addCalendarMonths(now, mode === "annual" ? 12 : 1).toISOString(), pendingChange: undefined };
}
