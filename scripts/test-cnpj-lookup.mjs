import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Edge Function cnpj-lookup (ADR-0017): lógica testada com provedor e banco simulados. Os dados abaixo são inventados;
// os nomes dos campos são os que a Minha Receita e a BrasilAPI devolveram em 2026-11-18 (mesmo formato nas duas).
const output = ts.transpileModule(readFileSync('supabase/functions/cnpj-lookup/lookup.ts', 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 },
}).outputText;
const lk = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

const CNPJ = '11222333000181';  // dígitos válidos, valor de teste já usado nos smokes
const company = {
  razao_social: 'EMPRESA FICTICIA DE TESTE LTDA', nome_fantasia: 'FICTICIA', descricao_situacao_cadastral: 'ATIVA',
  municipio: 'CAMPINAS', uf: 'SP', cnae_fiscal: 111301, codigo_natureza_juridica: 2062, opcao_pelo_mei: false,
  qsa: [{ nome_socio: 'PESSOA INVENTADA', cnpj_cpf_do_socio: '***123456**' }], email: 'contato@ficticia.invalid',
  ddd_telefone_1: '1100000000', logradouro: 'RUA INVENTADA', capital_social: 1000,
};
const mei = { ...company, razao_social: 'PESSOA INVENTADA 12345678900', codigo_natureza_juridica: 2135, opcao_pelo_mei: true };

function makeDeps({ quota = true, cache = null, results = {}, putFails = false } = {}) {
  const calls = { fetch: [], put: [], logs: [], quota: 0 };
  return {
    calls,
    deps: {
      async quotaTake() { calls.quota += 1; return quota; },
      async cacheGet() { return cache; },
      async cachePut(cnpj, entry) { if (putFails) throw new Error('x'); calls.put.push({ cnpj, entry }); },
      async fetchProvider(provider) { calls.fetch.push(provider); return results[provider] ?? { status: 'error' }; },
      log(event) { calls.logs.push(event); },
      now: () => 0,
    },
  };
}

test('CNPJ: mesma regra do banco, inclusive alfanumérico; inválido não chama nada', async () => {
  assert.equal(lk.isValidCnpj('11222333000181'), true);
  assert.equal(lk.isValidCnpj('12ABC34501DE35'), true);
  assert.equal(lk.isValidCnpj('11222333000182'), false);
  assert.equal(lk.isValidCnpj('11111111111111'), false);
  assert.equal(lk.normalizeCnpj(' 11.222.333/0001-81 '), '11222333000181');
  const { deps, calls } = makeDeps();
  const r = await lk.lookupCnpj('11.222.333/0001-82', 'u1', deps);
  assert.equal(r.http, 400);
  assert.equal(calls.quota, 0);
  assert.equal(calls.fetch.length, 0);
});

test('pessoa física: MEI, empresário individual, EIRELI, grupo 4 e natureza ausente', () => {
  assert.equal(lk.isNaturalPerson(company), false);
  assert.equal(lk.isNaturalPerson(mei), true);
  assert.equal(lk.isNaturalPerson({ ...company, opcao_pelo_mei: null, codigo_natureza_juridica: 2135 }), true);
  assert.equal(lk.isNaturalPerson({ ...company, codigo_natureza_juridica: 2305 }), true);
  assert.equal(lk.isNaturalPerson({ ...company, codigo_natureza_juridica: '412-0' }), true);
  assert.equal(lk.isNaturalPerson({ ...company, codigo_natureza_juridica: null, opcao_pelo_mei: null }), true);
});

test('lista branca: sem QSA, contato, endereço ou capital; pessoa física sem nome', () => {
  const e = lk.toWhitelist(company, 'minhareceita');
  assert.deepEqual(Object.keys(e).sort(), ['cadastral_situation', 'city', 'legal_name', 'legal_nature', 'main_cnae', 'natural_person', 'provider', 'state', 'trade_name']);
  assert.equal(e.main_cnae, '0111301');
  assert.equal(e.legal_nature, '2062');
  assert.equal(JSON.stringify(e).includes('PESSOA INVENTADA'), false);
  assert.equal(JSON.stringify(e).includes('ficticia.invalid'), false);
  const p = lk.toWhitelist(mei, 'brasilapi');
  assert.equal(p.natural_person, true);
  assert.equal(p.legal_name, null);
  assert.equal(p.trade_name, null);
});

test('cota estourada: manual sem consultar cache nem provedor', async () => {
  const { deps, calls } = makeDeps({ quota: false });
  const r = await lk.lookupCnpj(CNPJ, 'u1', deps);
  assert.deepEqual(r.body, { status: 'manual', reason: 'rate_limited' });
  assert.equal(calls.fetch.length, 0);
});

test('cache válido não chama o provedor; vencido renova', async () => {
  const row = { ...lk.toWhitelist(company, 'minhareceita'), stale: false };
  let t = makeDeps({ cache: row });
  let r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.equal(r.body.status, 'found');
  assert.equal(r.body.source, 'cache');
  assert.equal(t.calls.fetch.length, 0);
  t = makeDeps({ cache: { ...row, stale: true }, results: { minhareceita: { status: 'found', raw: company } } });
  r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.equal(r.body.source, 'minhareceita');
  assert.equal(t.calls.put.length, 1);
});

test('Minha Receita em erro cai na BrasilAPI; 404 não chama a reserva', async () => {
  let t = makeDeps({ results: { minhareceita: { status: 'error' }, brasilapi: { status: 'found', raw: company } } });
  let r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.deepEqual(t.calls.fetch, ['minhareceita', 'brasilapi']);
  assert.equal(r.body.source, 'brasilapi');
  assert.equal(t.calls.logs[0].result, 'fallback');
  t = makeDeps({ results: { minhareceita: { status: 'not_found' } } });
  r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.deepEqual(t.calls.fetch, ['minhareceita']);
  assert.deepEqual(r.body, { status: 'manual', reason: 'not_found' });
});

test('os dois fora do ar: manual; com cache vencido, usa o cache', async () => {
  let t = makeDeps();
  let r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.deepEqual(r.body, { status: 'manual', reason: 'unavailable' });
  t = makeDeps({ cache: { ...lk.toWhitelist(company, 'brasilapi'), stale: true } });
  r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.equal(r.body.status, 'found');
  assert.equal(t.calls.logs[0].result, 'stale_hit');
});

test('pessoa física: grava só a marca e responde manual, sem nome', async () => {
  const t = makeDeps({ results: { minhareceita: { status: 'found', raw: mei } } });
  const r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.deepEqual(r.body, { status: 'manual', reason: 'natural_person' });
  assert.equal(t.calls.put[0].entry.legal_name, null);
  assert.equal(JSON.stringify(r.body).includes('PESSOA'), false);
});

test('falha ao gravar o cache: manual (preregister_company não teria de onde copiar)', async () => {
  const t = makeDeps({ putFails: true, results: { minhareceita: { status: 'found', raw: company } } });
  const r = await lk.lookupCnpj(CNPJ, 'u1', t.deps);
  assert.deepEqual(r.body, { status: 'manual', reason: 'unavailable' });
});

test('resposta e log sem dado além do necessário', async () => {
  const t = makeDeps({ results: { minhareceita: { status: 'found', raw: company } } });
  const r = await lk.lookupCnpj('11.222.333/0001-81', 'conta-123', t.deps);
  assert.deepEqual(Object.keys(r.body.company).sort(), ['cadastral_situation', 'city', 'legal_name', 'state', 'trade_name']);
  const logText = JSON.stringify(t.calls.logs);
  assert.equal(logText.includes(CNPJ), false);
  assert.equal(logText.includes('conta-123'), false);
  assert.deepEqual(Object.keys(t.calls.logs[0]).sort(), ['ms', 'provider', 'result']);
});

test('index.ts: CNPJ só no corpo, conta conferida e nada de log do pedido', () => {
  const src = readFileSync('supabase/functions/cnpj-lookup/index.ts', 'utf8');
  assert.match(src, /auth\.getUser\(token\)/);
  assert.match(src, /req\.method !== 'POST'/);
  assert.doesNotMatch(src, /searchParams|url\.search/);
  assert.equal((src.match(/console\./g) ?? []).length, 1);
  assert.doesNotMatch(src, /SERVICE_ROLE_KEY['"]?\)\s*\?\?\s*['"][^'"]+['"]/);
  assert.match(src, /pickKey\('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY'\)/);
  assert.match(src, /pickKey\('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY'\)/);
});
