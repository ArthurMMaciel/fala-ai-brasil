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
  vm.runInNewContext(code, { module, exports: module.exports, require: customRequire, URL });
  return module.exports;
}
const catalog = compile('src/domain/commercial.ts').commercialCatalog;
const model = compile('src/editorial/editorial-model.ts');
const ui = compile('src/editorial/editorial-ui.tsx');
const stories = compile('src/editorial/editorial-landing.tsx', '', name => name === './editorial-ui' ? ui : require(name));
const accountRules = compile('src/domain/account-rules.ts');
const htmlSafety = compile('src/domain/html-safety.ts');
const contactService = compile('src/services/contact-solicitations.ts', '', name => name === './account' ? { isAccountServiceConfigured: () => false } : name === '../domain/account-rules' ? accountRules : require(name));
const contactForm = compile('src/landing/contact-solicitation-form.tsx', '', name => name === '../services/contact-solicitations' ? contactService : name === '../domain/account-rules' ? accountRules : require(name));
const showcase = compile('src/landing/persona-showcase.tsx', '', name => name === './contact-solicitation-form' ? contactForm : require(name));
const tracking = compile('src/editorial/editorial-tracking.tsx', '', name => name === './editorial-ui' ? ui : name === './editorial-model' ? model : require(name));
const experience = compile('src/editorial/editorial-experience.tsx', '', name => name === './editorial-ui' ? ui : name === './editorial-model' ? model : name === './editorial-tracking' ? tracking : require(name));
const landing = compile('src/landing/landing-react.tsx', '\nexport { Landing };', name => ({ '../domain/commercial': { commercialCatalog: catalog }, '../editorial/editorial-ui': ui, '../editorial/editorial-landing': stories, '../editorial/editorial-experience': experience, './persona-showcase': showcase }[name] ?? require(name)));

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
    isAccountServiceConfigured: () => false, loadAccount: async () => null, readRedirectError: () => null, consumeEmailConfirmation: async () => null, passwordRulesMarkup: () => "",
    registerAccount: async () => ({ ok: false, message: 'indisponível' }), resendConfirmation: async () => ({ ok: true, value: null }),
    signIn: async () => ({ ok: false, message: 'indisponível' }), signOut: async () => {}, loadPartnerPhoto: async () => ({ url: null }), uploadPartnerPhoto: async () => ({ ok: false, message: 'indisponível' }),
    isDemoEmail: email => email.endsWith('@escutaai.demo'), listPublicSponsors: async () => [], minPasswordLength: 8, validateRegistration: () => null,
    escapeHtml: htmlSafety.escapeHtml, safeHttpUrl: htmlSafety.safeHttpUrl,
    brazilianStates: ['SP'], showToast() {}, createCampaign: async () => ({ ok: false, message: 'indisponível' }), deleteCampaignDraft: async () => ({ ok: true }), listCampaigns: async () => [], submitCampaign: async () => ({ ok: true }), campaignKindForPlan: () => null, campaignKindLabels: {}, campaignStatusLabels: {}, isActiveCampaign: () => false, validateCampaign: () => null, profileLabels: {}, splitStreet: () => null, streetTypeLabels: { street: 'Rua' },
    document: { createElement() { return { relList: { supports: () => true } }; }, querySelector: () => element },
    window: { scrollTo() {}, matchMedia: () => ({ matches: true }) },
    requestAnimationFrame: callback => callback(), console, URL, Intl, Date, AbortController,
  });
  const source = readFileSync('src/app/main.js', 'utf8').replace(/^import .*;\r?\n/gm, '');
  vm.runInContext(source + '\nglobalThis.api={state:o,route:m,responses:ve};', context);
  return { get props() { return props; }, get html() { return markup; }, api: context.api, button(action) { const button = buttons.find(b => b.dataset.action === action || b.dataset.route === action); assert.ok(button, `Botão ${action} encontrado`); return button; } };
}

test('cadastro é dividido em etapas e não mostra o resumo de cobrança', () => {
  const screen = app();
  screen.api.route('register', { authAudience: 'worker' });
  assert.equal((screen.html.match(/class="auth-step"/g) || []).length, 3);
  screen.api.route('register', { authAudience: 'company' });
  assert.equal((screen.html.match(/class="auth-step"/g) || []).length, 4);
  assert.match(screen.html, /data-title="Plano"/);
  assert.doesNotMatch(screen.html, /subscription-summary/);
  assert.match(screen.html, /data-step-next/);
});

test('após o cadastro mostra a tela de confirmar e-mail, e o botão leva ao login com o e-mail preenchido', () => {
  const screen = app();
  screen.api.route('login', { authNotice: { email: 'pessoa@example.com', sent: true } });
  assert.match(screen.html, /Falta só um passo/);
  assert.doesNotMatch(screen.html, /data-form="auth"/);
  screen.button('confirmed-login').click();
  assert.match(screen.html, /data-form="auth"/);
  assert.match(screen.html, /value="pessoa@example.com"/);
});

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
    assert.match(html, /\/media\/escuta-ai-brasil-institucional\.mp4/);
    assert.doesNotMatch(html, /\/media\/[a-z]+\.webp/);
    assert.equal((html.match(/class="landing-process"/g) || []).length, 1);
    assert.doesNotMatch(html, /editorial-hero|editorial-section/);
    assert.match(html, /brand\/escuta-ai-brasil.svg/);
    assert.doesNotMatch(html, /brand-mark|Funcionário/);
    assert.equal((html.match(/class="landing-plan"/g) || []).length, catalog.filter(p => p.audience === audience).length);
    for (const plan of catalog) assert.equal(html.includes(`aria-label="Escolher plano ${plan.name}"`), plan.audience === audience);
    if (audience === 'worker') assert.match(html, /Criar conta gratuita/);
    assert.match(html, /id="saiba-mais"/);
    assert.match(html, /Solicitar contato/);
  }
});

test('solicitação de contato exige dados mínimos e mantém o perfil da landing', () => {
  const input = { profile: 'worker', origin: 'worker', name: 'Ana', email: 'ana@example.com', phone: '(11) 98765-4321', organization: '', website: '' };
  assert.equal(contactService.validateContactSolicitation(input), null);
  assert.match(contactService.validateContactSolicitation({ ...input, email: 'inválido' }), /e-mail válido/);
  assert.match(contactService.validateContactSolicitation({ ...input, phone: '123' }), /DDD/);
});

test('solicitações contato aparecem apenas no menu da equipe da plataforma', () => {
  const screen = app();
  screen.api.route('admin-contacts');
  assert.equal(screen.api.state.route, 'landing');
  screen.api.state.user = { id: 'staff', name: 'Equipe', role: 'platform_admin', profile: { type: 'system', id: 'staff' } };
  screen.api.route('admin-contacts');
  assert.equal(screen.api.state.route, 'admin-contacts');
  assert.match(screen.html, /Solicitações contato/);
  assert.match(screen.html, /id="contact-admin-root"/);
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
  const lifecycle = compile('src/landing/landing-react.tsx', '', name => name === 'react-dom/client' ? { createRoot() { created++; return { render() {}, unmount() { unmounted++; } }; } } : ({ '../domain/commercial': { commercialCatalog: catalog }, '../editorial/editorial-ui': ui, '../editorial/editorial-landing': stories, '../editorial/editorial-experience': experience, './persona-showcase': showcase }[name] ?? require(name)));
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

// TASK-0002: dados do usuário ou do banco chegam ao renderer legado (innerHTML) apenas como texto.
const xssPayloads = ['"><img src=x onerror=alert(1)>', '<script>alert(1)</script>', "'><svg onload=alert(1)>", '`${alert(1)}`'];
function assertInert(html, payload, shown = true) {
  assert.doesNotMatch(html, /<img[^>]*onerror/i, 'img com onerror não pode virar elemento');
  assert.doesNotMatch(html, /<script>alert/i, 'script não pode virar elemento');
  assert.doesNotMatch(html, /<svg[^>]*onload/i, 'svg com onload não pode virar elemento');
  assert.doesNotMatch(html, /(href|src)="\s*javascript:/i, 'URL javascript: não pode chegar a href/src');
  if (shown) assert.ok(html.includes(htmlSafety.escapeHtml(payload)), `payload aparece escapado: ${payload}`);
}

test('busca, e-mail do login e nome do usuário aparecem como texto', () => {
  for (const payload of xssPayloads) {
    const screen = app();
    screen.api.route('companies', { search: payload });
    assertInert(screen.html, payload);
    screen.api.route('login', { authNotice: { email: payload } });
    assertInert(screen.html, payload);
    screen.api.route('worker', { user: { name: payload, role: 'worker' } });
    assertInert(screen.html, payload);
  }
});

test('rascunho, relato original e manifestação criada aparecem como texto', () => {
  for (const payload of xssPayloads) {
    const screen = app();
    const draft = { ...screen.api.state.complaintDraft, title: payload, originalContent: `${payload} Carlos`, incidentDate: payload, recurrence: payload };
    let seen = '';
    for (let step = 0; step <= 8; step++) {
      screen.api.route('new-complaint', { complaintStep: step, complaintDraft: draft, onboardingError: payload, communicationError: payload });
      assertInert(screen.html, payload, false);
      seen += screen.html;
    }
    assert.ok(seen.includes(`value="${htmlSafety.escapeHtml(payload)}"`), 'campo de título preserva o texto digitado');
    assert.match(seen, /<span class="redacted">Carlos<\/span>/, 'marcação de redação continua aplicada');
    const base = screen.api.state.complaints[0];
    screen.api.state.complaints.push({ ...base, id: 'm-xss', userId: 'u-worker', title: payload, originalContent: payload, sanitizedContent: payload });
    screen.api.route('case', { caseId: 'm-xss' });
    assertInert(screen.html, payload);
    screen.api.route('admin-case', { user: { name: 'Equipe', role: 'admin' }, adminCaseId: 'm-xss', selectedTab: 'Relato' });
    assert.equal(screen.api.state.route, 'admin-case');
    assertInert(screen.html, payload);
  }
});

test('perfis, campanhas e foto do parceiro do banco não executam HTML nem URL javascript:', () => {
  for (const payload of xssPayloads) {
    const screen = app();
    screen.api.route('choose-profile', { accountProfiles: [{ type: payload, id: payload, name: payload }, { type: 'worker', id: '1', name: 'Pessoa' }] });
    assertInert(screen.html, payload);
  }
  const screen = app();
  const sponsor = { name: 'Patrocinador', role: 'commercial', profile: { type: 'sponsor', id: 's-1' } };
  const campaign = { id: 'c-1', kind: 'banner', title: '<img src=x onerror=alert(1)>', description: '<script>alert(1)</script>', ctaUrl: 'javascript:alert(1)', startsAt: '2026-11-01', endsAt: '2026-11-30', status: 'rejected', reviewNote: '"><svg onload=alert(1)>' };
  screen.api.route('commercial-account', { user: sponsor, sponsorTab: 'campaigns', campaigns: [campaign] });
  assert.doesNotMatch(screen.html, /href="javascript:/i);
  assert.match(screen.html, /javascript:alert\(1\)/, 'link inválido continua visível como texto');
  assertInert(screen.html, campaign.title);
  screen.api.route('commercial-account', { user: sponsor, sponsorTab: 'campaigns', campaigns: [{ ...campaign, ctaUrl: 'https://example.com/campanha' }] });
  assert.match(screen.html, /<a href="https:\/\/example\.com\/campanha"/);
  const partner = { name: '<img src=x onerror=alert(1)>', role: 'commercial', profile: { type: 'partner', id: 'p-1' } };
  screen.api.route('commercial-account', { user: partner, partnerPhotoUrl: 'javascript:alert(1)' });
  assert.doesNotMatch(screen.html, /<img src="javascript:/i);
  assert.match(screen.html, /Nenhuma foto enviada/);
});

// TASK-0002 (revisão DevOps): mídia do parceiro no portal React só aceita http(s) em src/href.
const portalUi = compile('src/portals/ui.tsx');
const portalLive = compile('src/portals/portal-live.tsx', '', name => ({ '../services/account': {}, '../services/data': {}, '../app/toast': {}, './ui': portalUi, '../domain/account-rules': accountRules, '../domain/html-safety': htmlSafety, './profile-live': {}, '../domain/complaint-status': compile('src/domain/complaint-status.ts') }[name] ?? require(name)));
const badUrls = ['javascript:alert(1)', 'JaVaScRiPt:alert(1)', 'data:text/html,<script>alert(1)</script>', 'data:image/svg+xml,<svg onload=alert(1)>', ' javascript:alert(1)'];
const render = (component, props) => renderToStaticMarkup(React.createElement(component, props));

test('conteúdo, avatar e foto do parceiro bloqueiam javascript: e data: em src/href', () => {
  for (const url of badUrls) {
    for (const kind of ['image', 'video']) {
      const html = render(portalLive.ContentMedia, { content: { kind, url, title: 'Conteúdo' } });
      assert.doesNotMatch(html, /(src|href)="/, `${kind} com ${url} não gera src/href`);
      if (kind === 'video') assert.match(html, /Link de vídeo indisponível/);
    }
    for (const large of [false, true]) {
      const html = render(portalLive.PartnerPhoto, { url, name: 'Marina Costa', large });
      assert.doesNotMatch(html, /<img|src="/, `foto com ${url} não gera img`);
      assert.match(html, />MC</, 'mostra as iniciais no lugar da foto');
    }
  }
  assert.match(render(portalLive.ContentMedia, { content: { kind: 'image', url: 'https://cdn.example.com/a.png', title: 'Foto' } }), /<img src="https:\/\/cdn\.example\.com\/a\.png"/);
  assert.match(render(portalLive.ContentMedia, { content: { kind: 'video', url: 'https://www.youtube.com/watch?v=abc', title: 'Vídeo' } }), /<a class="content-video" href="https:\/\/www\.youtube\.com\/watch\?v=abc"/);
  assert.match(render(portalLive.PartnerPhoto, { url: 'https://x.supabase.co/storage/v1/object/public/partner-media/a.jpg', name: 'Marina', large: true }), /<img class="partner-avatar partner-photo large" src="https:/);
});

// Login da equipe (bug achado pelo DevOps): m() checava o.user antes de gravar o usuário recém-autenticado em a.user.
test('conta platform_admin entra direto na Operação e em Solicitações de contato', () => {
  const admin = { name: 'Equipe', role: 'platform_admin', profile: { type: 'system', id: 's-1' } };
  for (const route of ['ops', 'admin-contacts']) {
    const screen = app();
    assert.equal(screen.api.state.user ?? null, null, 'começa sem sessão');
    screen.api.route(route, { user: admin });
    assert.equal(screen.api.state.route, route, `${route} abre no mesmo passo do login`);
    assert.equal(screen.api.state.user?.role, 'platform_admin');
    assert.match(screen.html, route === 'ops' ? /id="ops-root"/ : /id="contact-admin-root"/);
  }
});

test('Operação continua fechada para quem não é da equipe, mesmo vindo no login', () => {
  for (const user of [{ name: 'Pessoa', role: 'worker' }, { name: 'Empresa', role: 'admin' }, null]) {
    const screen = app();
    screen.api.route('ops', { user });
    assert.notEqual(screen.api.state.route, 'ops');
    assert.doesNotMatch(screen.html, /id="ops-root"/);
  }
  const screen = app();
  screen.api.route('ops', { user: { name: 'Equipe', role: 'platform_admin' } });
  screen.api.route('ops', { user: null });
  assert.equal(screen.api.state.route, 'ops', 'saída com user:null não reabre a rota (permanece onde estava, sem gravar)');
});
