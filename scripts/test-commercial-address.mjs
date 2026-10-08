import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

async function loadTypeScript(file) {
  const output = ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
}
const commercial = await loadTypeScript('src/commercial.ts');
const address = await loadTypeScript('src/address.ts');

test('anual aplica 5% a doze mensalidades em centavos', () => {
  assert.equal(commercial.annualAmount(150000), 1710000);
  assert.equal(commercial.annualAmount(24900), 283860);
  assert.equal(commercial.annualAmount(101), 1151);
});

test('trial dura um mÃªs de calendÃ¡rio e vence sem receita paga', () => {
  const now = new Date('2026-01-31T12:00:00.000Z');
  const subscription = commercial.createDemoSubscription('demo', 'company-essential', 'trial', now);
  assert.equal(subscription.nextBillingAt, '2026-02-28T12:00:00.000Z');
  assert.equal(subscription.paidCents, 0);
  assert.equal(commercial.hasDemoCommercialAccess(subscription, new Date('2026-02-27T11:59:59Z')), true);
  assert.equal(commercial.hasDemoCommercialAccess(subscription, new Date('2026-02-28T12:00:00Z')), false);
});

test('vencimento anual respeita fevereiro em ano nÃ£o bissexto', () => {
  assert.equal(commercial.addCalendarMonths(new Date('2024-02-29T10:00:00Z'), 12).toISOString(), '2025-02-28T10:00:00.000Z');
});

test('cadastro pago aguarda confirmaÃ§Ã£o e confirmaÃ§Ã£o duplicada nÃ£o altera receita', () => {
  const now = new Date('2026-10-08T12:00:00Z');
  const pending = commercial.createDemoSubscription('demo', 'partner-presence', 'monthly', now);
  assert.equal(pending.status, 'pending');
  assert.equal(commercial.hasDemoCommercialAccess(pending, now), false);
  const paid = commercial.confirmDemoPayment(pending, now);
  assert.equal(paid.status, 'active');
  assert.equal(paid.paidCents, 24900);
  assert.equal(commercial.hasDemoCommercialAccess(paid, now), true);
  assert.throws(() => commercial.confirmDemoPayment(paid, now), /pagamento pendente/);
});

test('upgrade pendente preserva o plano e sÃ³ muda apÃ³s pagamento', () => {
  const now = new Date('2026-10-08T12:00:00Z');
  const current = commercial.createDemoSubscription('demo', 'company-essential', 'trial', now);
  current.pendingChange = { planId: 'company-management', mode: 'annual' };
  assert.equal(current.planId, 'company-essential');
  assert.equal(commercial.hasDemoCommercialAccess(current, now), true);
  const upgraded = commercial.confirmDemoPayment(current, now);
  assert.equal(upgraded.planId, 'company-management');
  assert.equal(upgraded.paidCents, 4446000);
  assert.equal(upgraded.pendingChange, undefined);
  assert.equal(upgraded.nextBillingAt, '2027-10-08T12:00:00.000Z');
});

test('oferta sob proposta tem trial gratuito, mas pagamento exige preÃ§o aprovado', () => {
  const subscription = commercial.createDemoSubscription('demo', 'intelligence-project', 'trial');
  assert.equal(subscription.status, 'trialing');
  assert.equal(subscription.paidCents, 0);
  assert.equal(typeof subscription.nextBillingAt, 'string');
  const pending = commercial.createDemoSubscription('demo', 'intelligence-project', 'monthly');
  assert.equal(pending.status, 'pending');
  assert.equal(pending.nextBillingAt, null);
  assert.throws(() => commercial.confirmDemoPayment(subscription), /proposta/);
  assert.throws(() => commercial.createDemoSubscription('demo', 'unknown', 'monthly'));
  assert.throws(() => commercial.createDemoSubscription('demo', 'company-essential', 'constructor'));
});

test('alteraÃ§Ã£o para plano de outra persona Ã© rejeitada', () => {
  const subscription = commercial.createDemoSubscription('demo', 'company-essential', 'trial');
  subscription.pendingChange = { planId: 'partner-presence', mode: 'monthly' };
  assert.throws(() => commercial.confirmDemoPayment(subscription), /proposta/);
});

test('CEP vÃ¡lido aceita mÃ¡scara, sem converter letras em dÃ­gitos', async () => {
  assert.equal(address.isValidPostalCode('01001-000'), true);
  assert.equal(address.isValidPostalCode('01001000'), true);
  for (const code of ['01001a000', '010010000', '0100100', '', '01001 000']) assert.equal(address.isValidPostalCode(code), false);
  let requested = false;
  await assert.rejects(address.lookupPostalCode('invalid', new AbortController().signal, async () => { requested = true; }), /8/);
  assert.equal(requested, false);
});

test('consulta transmite somente CEP e retorna logradouro como texto', async () => {
  const signal = new AbortController().signal;
  const street = await address.lookupPostalCode('01001-000', signal, async (url, options) => {
    assert.equal(url, 'https://viacep.com.br/ws/01001000/json/');
    assert.equal(options.credentials, 'omit');
    assert.equal(options.referrerPolicy, 'no-referrer');
    assert.equal(options.signal, signal);
    assert.equal(options.body, undefined);
    return new Response(JSON.stringify({ logradouro: '<script>alert(1)</script>' }));
  });
  assert.equal(street, '<script>alert(1)</script>');
});

test('CEP inexistente, genÃ©rico e erro HTTP permitem mensagem de recuperaÃ§Ã£o', async () => {
  for (const data of [{ erro: true }, { erro: 'true' }]) {
    await assert.rejects(address.lookupPostalCode('99999999', new AbortController().signal, async () => new Response(JSON.stringify(data))), /CEP/);
  }
  await assert.rejects(address.lookupPostalCode('01001000', new AbortController().signal, async () => new Response('{}')), /manualmente/);
  await assert.rejects(address.lookupPostalCode('01001000', new AbortController().signal, async () => new Response('', { status: 503 })), /manualmente/);
});

function fakeAddressForm(lookup) {
  globalThis.window = { setTimeout, clearTimeout };
  const input = new EventTarget();
  Object.assign(input, { value: '', validationMessage: '', isConnected: true, setCustomValidity(message) { this.validationMessage = message; } });
  const street = { value: '' };
  const status = { textContent: '' };
  address.bindAddressLookup({ querySelector(selector) { return selector.includes('postalCode') ? input : selector.includes('street') ? street : status; } }, lookup);
  return { input, street, status };
}
const tick = () => new Promise(resolve => setImmediate(resolve));

test('blur consulta uma vez, mantÃ©m nÃºmero fora da API e CEP invÃ¡lido nÃ£o consulta', async () => {
  let calls = 0;
  const form = fakeAddressForm(async code => { calls++; assert.equal(code, '01001000'); return 'PraÃ§a da SÃ©'; });
  form.input.value = '01001a000';
  form.input.dispatchEvent(new Event('blur'));
  assert.equal(calls, 0);
  assert.match(form.input.validationMessage, /8/);
  form.input.value = '01001000';
  form.input.dispatchEvent(new Event('input'));
  form.input.dispatchEvent(new Event('blur'));
  await tick();
  assert.equal(form.street.value, 'PraÃ§a da SÃ©');
  assert.equal(form.input.value, '01001-000');
  form.input.dispatchEvent(new Event('blur'));
  assert.equal(calls, 1);
});

test('resposta antiga de CEP nÃ£o sobrescreve uma consulta mais recente', async () => {
  const pending = [];
  const form = fakeAddressForm((code, signal) => new Promise(resolve => pending.push({ code, signal, resolve })));
  form.input.value = '01001000';
  form.input.dispatchEvent(new Event('blur'));
  form.input.value = '20040002';
  form.input.dispatchEvent(new Event('input'));
  form.input.dispatchEvent(new Event('blur'));
  assert.equal(pending[0].signal.aborted, true);
  pending[1].resolve('Rua nova');
  await tick();
  pending[0].resolve('Rua antiga');
  await tick();
  assert.equal(form.street.value, 'Rua nova');
});

test('ediÃ§Ã£o manual durante consulta Ã© preservada e falha permite recuperaÃ§Ã£o', async () => {
  let resolveLookup;
  const form = fakeAddressForm(() => new Promise(resolve => { resolveLookup = resolve; }));
  form.input.value = '01001000';
  form.input.dispatchEvent(new Event('blur'));
  form.street.value = 'Rua digitada';
  resolveLookup('Rua consultada');
  await tick();
  assert.equal(form.street.value, 'Rua digitada');
  assert.match(form.status.textContent, /preservada/);
  const failing = fakeAddressForm(async () => { throw new Error('Falha externa; preencha manualmente.'); });
  failing.input.value = '01001000';
  failing.input.dispatchEvent(new Event('blur'));
  await tick();
  assert.match(failing.status.textContent, /manualmente/);
});

