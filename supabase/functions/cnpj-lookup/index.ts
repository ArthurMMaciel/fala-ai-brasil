// Edge Function cnpj-lookup (ADR-0017). Contrato:
//   POST /functions/v1/cnpj-lookup, corpo {"cnpj": "..."} (nunca na URL), Authorization: Bearer <JWT de uma conta>.
//   200 {"status":"found","company":{...},"source":...} | 200 {"status":"manual","reason":...} | 400 {"status":"invalid"}
//   401 sem conta (a chave anon também é um JWT válido, por isso a conta é conferida com auth.getUser).
// Chaves: as novas, que o Supabase injeta como dicionário JSON por nome de chave (SUPABASE_PUBLISHABLE_KEYS e
// SUPABASE_SECRET_KEYS; usa 'default', ou a primeira, se não houver 'default'). As legadas (SUPABASE_ANON_KEY e
// SUPABASE_SERVICE_ROLE_KEY, descontinuadas até o fim de 2026) ficam só como reserva. Fonte:
// https://supabase.com/docs/guides/functions/secrets e https://supabase.com/docs/guides/api/api-keys (2026-11-18).
// ALLOWED_ORIGINS (lista separada por vírgula) é configuração do DevOps para o CORS do site.
// Deploy, verify_jwt e monitoramento ficam com o DevOps. A lógica está em lookup.ts.
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { lookupCnpj, type CacheEntry, type CacheRow, type Provider, type ProviderResult } from './lookup.ts';

const TIMEOUT_MS = 4000;
const URLS: Record<Provider, (cnpj: string) => string> = {
  minhareceita: (cnpj) => `https://minhareceita.org/${cnpj}`,
  brasilapi: (cnpj) => `https://brasilapi.com.br/api/cnpj/v1/${cnpj}`,
};

function pickKey(dictVar: string, legacyVar: string): string {
  try {
    const dict = JSON.parse(Deno.env.get(dictVar) ?? '{}') as Record<string, unknown>;
    const value = typeof dict.default === 'string' ? dict.default : Object.values(dict).find((v) => typeof v === 'string');
    if (typeof value === 'string' && value) return value;
  } catch {
    // dicionário ausente ou inválido: usa a chave legada
  }
  return Deno.env.get(legacyVar) ?? '';
}

const url = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = pickKey('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
const serviceKey = pickKey('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') ?? '').split(',').map((o) => o.trim()).filter(Boolean);
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });

function cors(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  if (!allowedOrigins.includes(origin)) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    Vary: 'Origin',
  };
}

function json(req: Request, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...cors(req) } });
}

async function fetchProvider(provider: Provider, cnpj: string): Promise<ProviderResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(URLS[provider](cnpj), { signal: controller.signal, headers: { Accept: 'application/json' } });
    if (res.status === 404) { await res.body?.cancel(); return { status: 'not_found' }; }
    if (!res.ok) { await res.body?.cancel(); return { status: 'error' }; }
    const raw = await res.json();
    return raw && typeof raw === 'object' ? { status: 'found', raw } : { status: 'error' };
  } catch {
    return { status: 'error' };
  } finally {
    clearTimeout(timer);
  }
}

const deps = {
  async quotaTake(userId: string) {
    const { data, error } = await service.rpc('cnpj_quota_take', { p_user: userId });
    return !error && data === true;
  },
  async cacheGet(cnpj: string): Promise<CacheRow | null> {
    const { data, error } = await service.rpc('cnpj_cache_get', { p_cnpj: cnpj });
    if (error || !Array.isArray(data) || data.length === 0) return null;
    return data[0] as CacheRow;
  },
  async cachePut(cnpj: string, e: CacheEntry) {
    const { error } = await service.rpc('cnpj_cache_put', {
      p_cnpj: cnpj, p_natural_person: e.natural_person, p_legal_name: e.legal_name, p_trade_name: e.trade_name,
      p_cadastral_situation: e.cadastral_situation, p_city: e.city, p_state: e.state, p_main_cnae: e.main_cnae,
      p_legal_nature: e.legal_nature, p_provider: e.provider,
    });
    if (error) throw new Error('cache_put');
  },
  fetchProvider,
  log(event: { result: string; provider: string | null; ms: number }) {
    console.log(JSON.stringify(event));  // sem CNPJ, conta, IP nem corpo (D10)
  },
  now: () => performance.now(),
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== 'POST') return json(req, 405, { status: 'method_not_allowed' });

  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return json(req, 401, { status: 'unauthorized' });
  const { data: auth, error: authError } = await authClient.auth.getUser(token);
  if (authError || !auth?.user?.id || auth.user.role !== 'authenticated') return json(req, 401, { status: 'unauthorized' });

  let cnpj: unknown = null;
  try {
    const text = await req.text();
    if (text.length > 200) return json(req, 400, { status: 'invalid' });
    cnpj = (JSON.parse(text) as { cnpj?: unknown })?.cnpj;
  } catch {
    return json(req, 400, { status: 'invalid' });
  }
  const { http, body } = await lookupCnpj(cnpj, auth.user.id, deps);
  return json(req, http, body);
});
