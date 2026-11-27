import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Landing oficial (React): entradas por hash para o login e o cadastro do app e contato gravado pela mesma RPC do app.
const compile = file => ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const asUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const commercialUrl = asUrl(compile('src/domain/commercial.ts'));
const entry = await import(asUrl(compile('src/domain/entry-routes.ts').replace(/from ['"]\.\/commercial['"]/, `from '${commercialUrl}'`)));
const contact = await import(asUrl(compile('src/domain/landing-contact.ts')));
const entryUrl = asUrl(compile('src/domain/entry-routes.ts').replace(/from ['"]\.\/commercial['"]/, `from '${commercialUrl}'`));
const brandUrl = asUrl(compile('src/domain/brand.ts'));
const site = await import(asUrl(compile('src/domain/site-pages.ts').replace(/from ['"]\.\/entry-routes['"]/, `from '${entryUrl}'`).replace(/from ['"]\.\/brand['"]/, `from '${brandUrl}'`)));
const plain = value => JSON.parse(JSON.stringify(value));
const pages = ['inicio', 'empresa', 'parceiros', 'patrocinio', 'intelligence', '404'];
const pageSource = page => readFileSync(`src/landing-site/pages/${page}.tsx`, 'utf8').replace(/^\/\/.*$/gm, '');

test('entrar e cadastrar abrem as telas do app com o público certo', () => {
  assert.deepEqual(plain(entry.authEntryFromHash('#entrar')), { mode: 'login', audience: 'worker', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#cadastrar')), { mode: 'register', audience: 'worker', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#cadastrar-empresa')), { mode: 'register', audience: 'company', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#entrar-empresa')), { mode: 'login', audience: 'company', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#cadastrar-parceiro')), { mode: 'register', audience: 'partner', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#entrar-intelligence')), { mode: 'login', audience: 'intelligence', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#entrar-patrocinador')), { mode: 'login', audience: 'sponsor', planId: '' });
  assert.deepEqual(plain(entry.authEntryState(entry.authEntryFromHash('#cadastrar-plano-company-essential'))), { authAudience: 'company', landingAudience: 'company', selectedPlanId: 'company-essential', commercialAudience: 'company' });
  assert.equal(entry.authEntryState(entry.authEntryFromHash('#entrar')).commercialAudience, undefined);
});

test('Intelligence e Patrocínio ocultos no cadastro: as entradas abrem o cadastro de empresa ou o genérico, sem plano; o login segue', () => {
  assert.deepEqual([...entry.hiddenAudiences], ['intelligence', 'sponsor']);
  assert.deepEqual(plain(entry.authEntryFromHash('#cadastrar-patrocinador')), { mode: 'register', audience: 'worker', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#cadastrar-intelligence')), { mode: 'register', audience: 'company', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#cadastrar-plano-intelligence-radar')), { mode: 'register', audience: 'company', planId: '' });
  assert.deepEqual(plain(entry.authEntryFromHash('#cadastrar-plano-company-essential')), { mode: 'register', audience: 'company', planId: 'company-essential' });
  assert.equal(entry.isVisibleAudience('partner'), true);
  assert.equal(entry.visibleRegisterAudience('sponsor'), 'worker');
  const main = readFileSync('src/app/main.js', 'utf8');
  assert.match(main, /Object\.keys\(E\)\.filter\(s=>s!=="studies"&&s!=="intelligence"&&isVisibleAudience\(s\)\)/, 'seletor de tipo de conta sem público oculto');
  assert.match(main, /options\.filter\(i=>isVisibleAudience\(i\[0\]\)\|\|i\[0\]===e\)/, 'menu de acesso sem público oculto');
});

test('hash desconhecido não abre nada (termos, privacidade e tokens seguem com o app)', () => {
  for (const hash of ['', '#', '#termos', '#privacidade', '#access_token=x&type=signup', '#cadastrar-constructor', '#cadastrar-trabalhador', '#cadastrar-plano-nao-existe', '#entrar-plano-company-essential', '#cadastrar-empresa-extra', '#cadastrar/empresa']) assert.equal(entry.authEntryFromHash(hash), null, hash);
});

test('contato: perfil e origem como no form do app; site não é enviado e honeypot vai para p_website', () => {
  const base = { nome: 'Pessoa Teste', email: 'teste@example.com', telefone: '(11) 91234-5678', organizacao: 'Org Teste', botField: '' };
  assert.deepEqual(plain(contact.landingContactInput({ ...base, perfil: 'Empresa', pagina: 'empresa' })), { profile: 'company', origin: 'company', name: 'Pessoa Teste', email: 'teste@example.com', phone: '(11) 91234-5678', organization: 'Org Teste', website: '' });
  assert.deepEqual(plain(contact.landingContactInput({ ...base, perfil: 'Intelligence', pagina: 'inicio' })).origin, 'intelligence');
  assert.deepEqual(plain(contact.landingContactInput({ ...base, perfil: 'Intelligence', pagina: 'inicio' })).profile, 'company');
  assert.equal(contact.landingContactInput({ ...base, perfil: 'Parceiro', pagina: 'patrocinio' }).origin, 'sponsor');
  assert.equal(contact.landingContactInput({ ...base, perfil: 'Trabalhador', pagina: 'empresa' }).organization, '');
  assert.equal(contact.landingContactInput({ ...base, perfil: 'Empresa', pagina: 'empresa', botField: 'spam' }).website, 'spam');
  assert.equal(contact.landingContactInput({ ...base, perfil: '', pagina: 'empresa' }), null);
  assert.equal(contact.landingContactInput({ ...base, perfil: 'constructor', pagina: 'empresa' }), null);
});

test('páginas da landing (React): links válidos, contato ligado ao serviço, nada de Netlify nem asset de outro domínio', () => {
  const parts = readFileSync('src/landing-site/site-parts.tsx', 'utf8');
  for (const page of pages) {
    const source = pageSource(page);
    for (const [, hash] of source.matchAll(/href="\/(#(?:entrar|cadastrar)[^"]*)"/g)) assert.ok(entry.authEntryFromHash(hash), `${page}: ${hash}`);
    assert.doesNotMatch(source, /\.html|data-netlify|data-ajax|fala-ai-brasil\.vercel\.app|images\.unsplash\.com|fonts\.googleapis|fonts\.gstatic|name="site"|href="#"|dangerouslySetInnerHTML/, page);
    const forms = [...source.matchAll(/<ContactForm [^>]*\/>/g)].map(m => m[0]);
    if (page === '404') { assert.equal(forms.length, 0); continue; }
    assert.equal(forms.length, 1, page);
    assert.match(forms[0], new RegExp(`pagina="${page}"`), page);
  }
  for (const page of Object.values(site.sitePages)) for (const hash of [page.entrar, page.cadastrar]) assert.ok(entry.authEntryFromHash(hash.replace(/^\//, '')), `${page.id}: ${hash}`);
  assert.match(parts, /submitContactSolicitation\(input\)/);
  assert.match(parts, /<input id="tel" name="telefone" required/);
  assert.match(parts, /Não escreva relatos/);
  assert.doesNotMatch(parts, /dangerouslySetInnerHTML|innerHTML/);
  // Honeypot escondido de verdade (pedido do responsável, 2026-11-23): fora da tela, sem display:none, fora do leitor e do Tab.
  assert.match(parts, /<p className="hp" aria-hidden="true"><label>Não preencha: <input name="bot-field" tabIndex=\{-1\} autoComplete="off" \/><\/label><\/p>/);
  const css = readFileSync('src/landing-site/landing.css', 'utf8');
  assert.match(css, /#escuta-site \.hp\{position:absolute;left:-10000px;[^}]*overflow:hidden/);
  assert.doesNotMatch(css.match(/#escuta-site \.hp\{[^}]*\}/)[0], /display:none|visibility:hidden/);
  assert.match(css, /#escuta-site \[hidden\]\{display:none\}/, 'atributo hidden volta a valer depois do reset');
  assert.equal(readFileSync('vite.config.mjs', 'utf8').includes('rollupOptions'), false, 'só o index.html é entrada do build');
  for (const page of pages) assert.throws(() => readFileSync(`${page}.html`), `${page}.html saiu`);
});

test('rotas da landing: caminho de cada página, 404, SEO e retorno de confirmação esperando o app', () => {
  assert.equal(site.sitePageFromPath('/'), 'inicio');
  assert.equal(site.sitePageFromPath('/empresa'), 'empresa');
  assert.equal(site.sitePageFromPath('/parceiros/'), 'parceiros');
  assert.equal(site.sitePageFromPath('/empresa.html'), 'empresa');
  assert.equal(site.sitePageFromPath('/inicio.html'), 'inicio');
  assert.equal(site.sitePageFromPath('/qualquer-coisa'), '404');
  for (const page of Object.values(site.sitePages)) assert.match(page.title, /^RH Escuta\.Aí \| /, page.id);
  for (const page of Object.values(site.sitePages)) if (page.id !== '404') assert.ok(page.description, page.id);
  assert.equal(site.showsLandingImmediately({ search: '', hash: '' }, []), true);
  assert.equal(site.showsLandingImmediately({ search: '', hash: '#contato' }, []), true);
  assert.equal(site.showsLandingImmediately({ search: '?code=x', hash: '' }, []), false);
  assert.equal(site.showsLandingImmediately({ search: '', hash: '#access_token=x&type=recovery' }, []), false);
  assert.equal(site.showsLandingImmediately({ search: '', hash: '' }, ['sb-abc-auth-token']), false);
});

test('Intelligence e Patrocínio ocultos por enquanto (mesma lista do cadastro): fora do menu, dos caminhos e do contato; endereço leva ao início', () => {
  assert.deepEqual(site.siteMenu.map(item => item.id), ['inicio', 'empresa', 'parceiros']);
  assert.deepEqual(site.contactProfiles, ['Trabalhador', 'Empresa', 'Parceiro']);
  assert.equal(site.sitePageFromPath('/intelligence'), 'inicio');
  assert.equal(site.sitePageFromPath('/patrocinio.html'), 'inicio');
  const parts = readFileSync('src/landing-site/site-parts.tsx', 'utf8');
  assert.match(parts, /caminhos\.filter\(item => isVisibleSitePage\(item\.id\)\)/);
  assert.match(parts, /isVisibleSitePage\('patrocinio'\) \? <> <a href="\/patrocinio"/);
  const vercel = JSON.parse(readFileSync('vercel.json', 'utf8'));
  const redirects = vercel.redirects.map(({ source, destination }) => ({ source, destination }));
  assert.deepEqual(redirects, plain(site.siteRedirects), 'vercel.json igual a siteRedirects');
  assert.ok(vercel.redirects.every(r => r.permanent === false), 'redirecionamentos temporários');
  assert.ok(vercel.rewrites.some(r => r.destination === '/index.html'), 'caminhos da landing caem no app');
});