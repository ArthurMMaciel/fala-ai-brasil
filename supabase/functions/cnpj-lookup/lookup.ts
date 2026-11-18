// Lógica da busca de CNPJ (ADR-0017, aceita em 2026-11-17/18). Sem APIs do Deno: o index.ts injeta banco, rede e log,
// e scripts/test-cnpj-lookup.mjs testa tudo com provedor simulado.
//
// Regras:
// - CNPJ validado (dígitos, inclusive alfanumérico) antes de qualquer chamada (D3);
// - cota por conta antes do cache e do provedor (D9);
// - cache próprio primeiro; renovado depois de 30 dias; se o provedor falhar, o cache vencido ainda serve (aceitação);
// - Minha Receita, depois BrasilAPI só em erro ou timeout; 404 = não encontrado, sem reserva (D7);
// - só a lista branca sai da função e entra no cache (D4); pessoa física sem nome (D5);
// - log só com resultado, provedor e tempo: nunca CNPJ, conta, IP ou corpo (D10).

export type Provider = 'minhareceita' | 'brasilapi';
export const PROVIDERS: Provider[] = ['minhareceita', 'brasilapi'];

export interface CacheEntry {
  natural_person: boolean;
  legal_name: string | null;
  trade_name: string | null;
  cadastral_situation: string | null;
  city: string | null;
  state: string | null;
  main_cnae: string | null;
  legal_nature: string | null;
  provider: Provider;
}
export interface CacheRow extends CacheEntry { stale: boolean }

export type ProviderResult = { status: 'found'; raw: Record<string, unknown> } | { status: 'not_found' } | { status: 'error' };

export interface Deps {
  quotaTake(userId: string): Promise<boolean>;
  cacheGet(cnpj: string): Promise<CacheRow | null>;
  cachePut(cnpj: string, entry: CacheEntry): Promise<void>;
  fetchProvider(provider: Provider, cnpj: string): Promise<ProviderResult>;
  log(event: { result: string; provider: string | null; ms: number }): void;
  now(): number;
}

export type LookupBody =
  | { status: 'found'; company: { legal_name: string; trade_name: string | null; cadastral_situation: string | null; city: string | null; state: string | null }; source: Provider | 'cache' }
  | { status: 'manual'; reason: 'natural_person' | 'unavailable' | 'not_found' | 'rate_limited' }
  | { status: 'invalid' };

export function normalizeCnpj(value: unknown): string {
  return String(value ?? '').replace(/[^0-9A-Za-z]/g, '').toUpperCase();
}

// Mesma regra de private.valid_cnpj (ADR-0014): 12 posições alfanuméricas + 2 dígitos; valor = código ASCII - 48.
export function isValidCnpj(cnpj: string): boolean {
  if (!/^[0-9A-Z]{12}[0-9]{2}$/.test(cnpj) || /^(.)\1{13}$/.test(cnpj)) return false;
  const v = [...cnpj].map((c) => c.charCodeAt(0) - 48);
  const dv = (len: number, weights: number[]) => {
    const s = weights.reduce((acc, w, i) => acc + v[i] * w, 0) % 11;
    return s < 2 ? 0 : 11 - s;
  };
  return dv(12, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]) === v[12] && dv(13, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]) === v[13];
}

// Naturezas jurídicas em que a razão social identifica uma pessoa (ADR-0017 D5). Conferir com a tabela oficial da
// Receita (Tabela de Natureza Jurídica, CONCLA) antes do deploy: 213-5 Empresário (Individual); 230-5 e 231-3 EIRELI;
// 232-1 Sociedade Unipessoal de Advocacia; grupo 4 (4xx-x), Pessoas Físicas.
export const NATURAL_PERSON_NATURES = new Set(['2135', '2305', '2313', '2321']);

function digits(value: unknown): string {
  return String(value ?? '').replace(/\D/g, '');
}
function text(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  const t = value.trim();
  return t ? t.slice(0, max) : null;
}

export function isNaturalPerson(raw: Record<string, unknown>): boolean {
  if (raw.opcao_pelo_mei === true) return true;
  const nature = digits(raw.codigo_natureza_juridica);
  if (!nature) return true;  // sem natureza: trata como pessoa física (D5)
  return NATURAL_PERSON_NATURES.has(nature) || nature.startsWith('4');
}

// Lista branca (D4). Tudo o mais da resposta (QSA, e-mail, telefone, endereço, capital) é descartado aqui.
export function toWhitelist(raw: Record<string, unknown>, provider: Provider): CacheEntry {
  const natural = isNaturalPerson(raw);
  const legalName = natural ? null : text(raw.razao_social, 160);
  const cnae = digits(raw.cnae_fiscal);
  const nature = digits(raw.codigo_natureza_juridica);
  const state = typeof raw.uf === 'string' ? raw.uf.trim().toUpperCase() : '';
  return {
    natural_person: natural || legalName === null,
    legal_name: legalName,
    trade_name: natural ? null : text(raw.nome_fantasia, 160),
    cadastral_situation: text(raw.descricao_situacao_cadastral, 40),
    city: text(raw.municipio, 80),
    state: /^[A-Z]{2}$/.test(state) ? state : null,
    main_cnae: cnae.length >= 5 && cnae.length <= 7 ? cnae.padStart(7, '0') : null,
    legal_nature: /^\d{3,4}$/.test(nature) ? nature : null,
    provider,
  };
}

function found(entry: CacheEntry, source: Provider | 'cache'): LookupBody {
  return {
    status: 'found',
    company: {
      legal_name: entry.legal_name as string,
      trade_name: entry.trade_name,
      cadastral_situation: entry.cadastral_situation,
      city: entry.city,
      state: entry.state,
    },
    source,
  };
}

export async function lookupCnpj(input: unknown, userId: string, deps: Deps): Promise<{ http: number; body: LookupBody }> {
  const started = deps.now();
  const done = (http: number, body: LookupBody, result: string, provider: string | null) => {
    deps.log({ result, provider, ms: Math.max(0, Math.round(deps.now() - started)) });
    return { http, body };
  };

  const cnpj = normalizeCnpj(input);
  if (!isValidCnpj(cnpj)) return done(400, { status: 'invalid' }, 'invalid', null);
  if (!(await deps.quotaTake(userId))) return done(200, { status: 'manual', reason: 'rate_limited' }, 'rate_limited', null);

  const cached = await deps.cacheGet(cnpj);
  if (cached && !cached.stale) {
    if (cached.natural_person) return done(200, { status: 'manual', reason: 'natural_person' }, 'natural_person', 'cache');
    return done(200, found(cached, 'cache'), 'hit', 'cache');
  }

  let notFound = false;
  for (const [index, provider] of PROVIDERS.entries()) {
    const result = await deps.fetchProvider(provider, cnpj);
    if (result.status === 'not_found') { notFound = true; break; }  // CNPJ inexistente: a reserva não acrescenta nada
    if (result.status === 'error') continue;
    const entry = toWhitelist(result.raw, provider);
    try {
      await deps.cachePut(cnpj, entry);
    } catch {
      // Sem gravar no cache, preregister_company não teria de onde copiar: segue para o manual.
      return done(200, { status: 'manual', reason: 'unavailable' }, 'cache_error', provider);
    }
    if (entry.natural_person) return done(200, { status: 'manual', reason: 'natural_person' }, 'natural_person', provider);
    return done(200, found(entry, provider), index === 0 ? 'miss' : 'fallback', provider);
  }

  // Provedores fora do ar ou sem o CNPJ: o cache vencido ainda serve, se existir.
  if (cached) {
    if (cached.natural_person) return done(200, { status: 'manual', reason: 'natural_person' }, 'natural_person', 'cache');
    return done(200, found(cached, 'cache'), 'stale_hit', 'cache');
  }
  if (notFound) return done(200, { status: 'manual', reason: 'not_found' }, 'not_found', null);
  return done(200, { status: 'manual', reason: 'unavailable' }, 'manual', null);
}
