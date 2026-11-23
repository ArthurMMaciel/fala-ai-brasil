import { commercialCatalog } from './commercial';

// Entradas por hash usadas pela landing estática para abrir as telas atuais de login e cadastro (formato aprovado em 17/11).
// #entrar, #cadastrar, #entrar-<público>, #cadastrar-<público>, #cadastrar-plano-<id do catálogo>.
export type EntryAudience = 'worker' | 'company' | 'partner' | 'intelligence' | 'sponsor';
export interface AuthEntry { mode: 'login' | 'register'; audience: EntryAudience; planId: string }

const audiences: Record<string, EntryAudience> = { empresa: 'company', parceiro: 'partner', intelligence: 'intelligence', patrocinador: 'sponsor' };
const planPrefix = 'cadastrar-plano-';

// Públicos ocultos por enquanto (pedido do responsável, 2026-11-23): não aparecem no cadastro nem no menu de acesso.
// Quem já tem conta desses públicos entra normalmente. Para reverter, esvaziar esta lista.
export const hiddenAudiences: readonly string[] = ['intelligence', 'sponsor'];
export function isVisibleAudience(audience: string): boolean { return !hiddenAudiences.includes(audience); }
// Cadastro de público oculto vira o de empresa (Intelligence) ou o genérico (Patrocínio), sem plano escolhido.
export function visibleRegisterAudience(audience: EntryAudience): EntryAudience {
  if (isVisibleAudience(audience)) return audience;
  return audience === 'intelligence' ? 'company' : 'worker';
}

export function authEntryFromHash(hash: string): AuthEntry | null {
  const entry = rawAuthEntry(hash);
  if (!entry || entry.mode !== 'register' || isVisibleAudience(entry.audience)) return entry;
  return { mode: 'register', audience: visibleRegisterAudience(entry.audience), planId: '' };
}

function rawAuthEntry(hash: string): AuthEntry | null {
  const value = String(hash ?? '').replace(/^#\/?/, '');
  if (value === 'entrar') return { mode: 'login', audience: 'worker', planId: '' };
  if (value === 'cadastrar') return { mode: 'register', audience: 'worker', planId: '' };
  if (value.startsWith(planPrefix)) {
    const plan = commercialCatalog.find(item => item.id === value.slice(planPrefix.length));
    return plan ? { mode: 'register', audience: plan.audience, planId: plan.id } : null;
  }
  const match = value.match(/^(entrar|cadastrar)-([a-z]+)$/);
  if (!match || !Object.prototype.hasOwnProperty.call(audiences, match[2])) return null;
  return { mode: match[1] === 'entrar' ? 'login' : 'register', audience: audiences[match[2]], planId: '' };
}

// Mesmo estado que os botões da landing React passam para m(): onOpenAuth e onChoosePlan.
export function authEntryState(entry: AuthEntry): Record<string, string> {
  const state: Record<string, string> = { authAudience: entry.audience, landingAudience: entry.audience, selectedPlanId: entry.planId };
  if (entry.audience !== 'worker') state.commercialAudience = entry.audience;
  return state;
}
