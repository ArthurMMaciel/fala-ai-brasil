import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
import ts from 'typescript';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const require = createRequire(import.meta.url);
function compile(file, extra = '', customRequire = require) {
  const module = { exports: {} };
  const code = ts.transpileModule(readFileSync(file, 'utf8') + extra, { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2021 } }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: customRequire });
  return module.exports;
}
const catalog = compile('src/commercial.ts').commercialCatalog;
const model = compile('src/editorial-model.ts');
const ui = compile('src/editorial-ui.tsx');
const stories = compile('src/editorial-landing.tsx', '', name => name === './editorial-ui' ? ui : require(name));
const tracking = compile('src/editorial-tracking.tsx', '', name => name === './editorial-ui' ? ui : name === './editorial-model' ? model : require(name));
const experience = compile('src/editorial-experience.tsx', '', name => name === './editorial-ui' ? ui : name === './editorial-model' ? model : name === './editorial-tracking' ? tracking : require(name));
const landing = compile('src/landing-react.tsx', '\nexport { Landing };', name => ({ './commercial': { commercialCatalog: catalog }, './editorial-ui': ui, './editorial-landing': stories, './editorial-experience': experience }[name] ?? require(name)));

// Minimal host for the legacy renderer: checks transitions and bound actions without a browser.
function app() {
  let reactMounted = false, props, markup = '', buttons = [];
  const main = { focus() {} };
  const element = {
    get innerHTML() { return markup; },
    set innerHTML(value) {
      assert.equal(reactMounted, false, 'Desmontar React antes de substituir seu HTML');
      markup = value;
      buttons = [...value.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)].map(([, attributes, label]) => {
        const dataset = Object.fromEntries([...attributes.matchAll(/data-([\w-]+)="([^"]*)"/g)].map(([, key, val]) => [key.replace(/-([a-z])/g, (_, c) => c.toUpperCase()), val]));
        return { dataset, label, disabled: /\bdisabled\b/.test(attributes), handlers: {}, addEventListener(type, action) { this.handlers[type] = action; }, click() { assert.equal(this.disabled, false); this.handlers.click?.({ preventDefault() {} }); } };
      });
    },
    querySelector(selector) { return selector === 'main' ? main : null; },
    querySelectorAll(selector) { return selector === '[data-route]' ? buttons.filter(b => b.dataset.route) : selector === '[data-action]' ? buttons.filter(b => b.dataset.action) : []; },
  };
  const context = vm.createContext({
    commercialCatalog: catalog,
    experienceRoutes: experience.experienceRoutes,
    mountExperience() { reactMounted = true; },
    mountLanding(_, next) { reactMounted = true; props = next; },
    unmountLanding() { reactMounted = false; },
    // Cadastro real (ADR-0009) fica desligado no host de teste; contas demo seguem locais.
    isAccountServiceConfigured: () => false, loadAccount: async () => null, readRedirectError: () => null,
    registerAccount: async () => ({ ok: false, message: 'indisponível' }), resendConfirmation: async () => ({ ok: true, value: null }),
    signIn: async () => ({ ok: false, message: 'indisponível' }), signOut: async () => {}, loadPartnerPhoto: async () => ({ url: null }), uploadPartnerPhoto: async () => ({ ok: false, message: 'indisponível' }),
    isDemoEmail: email => email.endsWith('@escutaai.demo'), minPasswordLength: 8, validateRegistration: () => null,
    brazilianStates: ['SP'], showToast() {}, profileLabels: {}, splitStreet: () => null, streetTypeLabels: { street: 'Rua' },
    document: { createElement() { return { relList: { supports: () => true } }; }, querySelector: () => element },
    window: { scrollTo() {}, matchMedia: () => ({ matches: true }) },
    requestAnimationFrame: callback => callback(), console, URL, Intl, Date, AbortController,
  });
  const source = readFileSync('src/main.js', 'utf8').replace(/^import .*;\r?\n/gm, '');
  vm.runInContext(source + '\nglobalThis.api={state:o,route:m,responses:ve};', context);
  return { get props() { return props; }, get html() { return markup; }, api: context.api, button(action) { const button = buttons.find(b => b.dataset.action === action || b.dataset.route === action); assert.ok(button, `Botão ${action} encontrado`); return button; } };
}

test('marca volta à landing repetidamente após login/cadastro e a persona continua navegável', () => {
  const screen = app();
  for (let i = 0; i < 3; i++) {
    screen.props.onOpenAuth(i % 2 ? 'register' : 'login', 'company');
    assert.match(screen.html, /brand\/escuta-ai-brasil.svg/);
    screen.button('landing').click();
    assert.equal(screen.api.state.route, 'landing');
    screen.props.onAudienceChange('partner');
    assert.equal(screen.props.audience, 'partner');
    assert.equal(screen.api.state.commercialAudience, 'partner');
  }
});

test('cada plano abre cadastro da persona correta com seleção preservada', () => {
  const screen = app();
  for (const plan of catalog) {
    screen.props.onAudienceChange(plan.audience);
    screen.props.onChoosePlan(plan.id, plan.audience);
    assert.equal(screen.api.state.route, 'register');
    assert.equal(screen.api.state.authAudience, plan.audience);
    assert.equal(screen.api.state.selectedPlanId, plan.id);
    assert.match(screen.html, new RegExp(`value="${plan.id}" selected`));
    screen.button('landing').click();
  }
});

test('landing mostra apenas planos do perfil ativo e acesso gratuito para trabalhador', () => {
  const screen = app();
  for (const audience of ['worker', 'company', 'partner', 'intelligence', 'sponsor']) {
    screen.props.onAudienceChange(audience);
    const html = renderToStaticMarkup(React.createElement(landing.Landing, screen.props));
    assert.match(html, /id="solucoes-e-planos"/);
    assert.match(html, /brand\/escuta-ai-brasil.svg/);
    assert.doesNotMatch(html, /brand-mark|Funcionário/);
    assert.equal((html.match(/class="landing-plan"/g) || []).length, catalog.filter(p => p.audience === audience).length);
    for (const plan of catalog) assert.equal(html.includes(`aria-label="Escolher plano ${plan.name}"`), plan.audience === audience);
    if (audience === 'worker') assert.match(html, /Criar conta gratuita/);
  }
});

test('avaliação e finalização do caso respondem e não duplicam o encerramento', () => {
  const screen = app();
  const response = screen.api.responses[0];
  assert.ok(response);
  screen.api.route('case', { caseId: response.complaintId });
  screen.button('case-feedback').click();
  assert.match(screen.html, /Sua avaliação: Sim/);
  screen.button('case-close').click();
  assert.match(screen.html, /Você considerou este caso finalizado/);
  const count = screen.api.state.histories.length;
  screen.button('case-close').click();
  assert.equal(screen.api.state.histories.length, count);
  screen.button('case-follow').click();
  assert.match(screen.html, /Você continuará acompanhando/);
});

test('desmontagem descarta a raiz React antes de remontar a landing', () => {
  let created = 0, unmounted = 0;
  const lifecycle = compile('src/landing-react.tsx', '', name => name === 'react-dom/client' ? { createRoot() { created++; return { render() {}, unmount() { unmounted++; } }; } } : ({ './commercial': { commercialCatalog: catalog }, './editorial-ui': ui, './editorial-landing': stories, './editorial-experience': experience }[name] ?? require(name)));
  lifecycle.mountLanding({}, {});
  lifecycle.mountLanding({}, {});
  assert.equal(created, 1);
  lifecycle.unmountLanding();
  assert.equal(unmounted, 1);
  lifecycle.mountLanding({}, {});
  assert.equal(created, 2);
});

test('sessão comercial é mantida na landing e plano escolhido segue para a própria conta', () => {
  const screen = app();
  screen.api.state.user = { id: 'demo-company', name: 'Empresa demo', role: 'admin' };
  screen.api.state.subscriptions.push({ userId: 'demo-company', audience: 'company', planId: 'company-essential', mode: 'monthly', status: 'pending', nextBillingAt: null, paidCents: 0 });
  screen.props.onAudienceChange('company');
  const html = renderToStaticMarkup(React.createElement(landing.Landing, screen.props));
  assert.match(html, /Minha área/);
  assert.match(html, />Sair</);
  assert.doesNotMatch(html, />Entrar</);
  screen.props.onChoosePlan('company-management', 'company');
  assert.equal(screen.api.state.route, 'commercial-account');
  assert.match(screen.html, /value="company-management" selected/);
  screen.button('landing').click();
  screen.props.onLogout();
  assert.equal(screen.api.state.user, null);
});
