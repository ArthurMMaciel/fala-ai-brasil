import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Landing oficial estática: entradas por hash para o login e o cadastro do app e contato gravado pela mesma RPC do app.
const compile = file => ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const asUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const commercialUrl = asUrl(compile('src/domain/commercial.ts'));
const entry = await import(asUrl(compile('src/domain/entry-routes.ts').replace(/from ['"]\.\/commercial['"]/, `from '${commercialUrl}'`)));
const contact = await import(asUrl(compile('src/domain/landing-contact.ts')));
const plain = value => JSON.parse(JSON.stringify(value));
const pages = ['inicio', 'empresa', 'parceiros', 'patrocinio', 'intelligence', '404'];

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

test('páginas da landing: links válidos, contato ligado ao serviço, nada de Netlify nem asset de outro domínio', () => {
  const config = readFileSync('vite.config.mjs', 'utf8');
  for (const page of pages) {
    assert.ok(config.includes(`'${page}'`), `${page} é entrada do build`);
    const html = readFileSync(`${page}.html`, 'utf8');
    for (const [, hash] of html.matchAll(/href="\/(#(?:entrar|cadastrar)[^"]*)"/g)) assert.ok(entry.authEntryFromHash(hash), `${page}: ${hash}`);
    assert.doesNotMatch(html, /(entrar|cadastrar)\.html|data-netlify|data-ajax|fala-ai-brasil\.vercel\.app|images\.unsplash\.com|fonts\.googleapis|fonts\.gstatic|name="site"|href="\/?index\.html|href="#"/, page);
    const forms = html.match(/<form\b[^>]*>/g) ?? [];
    if (page === '404') { assert.equal(forms.length, 0); continue; }
    assert.deepEqual(forms, [`<form class="form" data-contato data-pagina="${page}" novalidate>`], page);
    assert.match(html, /<script type="module" src="\/src\/landing-site\/contato\.ts"><\/script>/, page);
    assert.match(html, /<input id="tel" name="telefone" required/, page);
    assert.match(html, /Não escreva relatos/, page);
  }
  assert.doesNotMatch(readFileSync('public/landing/site.js', 'utf8'), /fetch\(|data-ajax/);
});

test('Intelligence e Patrocínio ocultos por enquanto: some o link e a página redireciona para o início', () => {
  const css = readFileSync('public/landing/style.css', 'utf8');
  for (const page of ['intelligence', 'patrocinio']) {
    for (const where of ['.menu li:has(> a', '.f-top li:has(> a', '.cam']) assert.ok(css.includes(`${where}[href$="${page}.html"]`), `${page}: ${where}`);
  }
  assert.ok(css.includes('.patro-nota a[href$="patrocinio.html"]'));
  for (const perfil of ['Intelligence', 'Patrocinador']) assert.ok(css.includes(`.perfis label:has(> input[value="${perfil}"])`), perfil);
  const redirects = JSON.parse(readFileSync('vercel.json', 'utf8')).redirects;
  for (const page of ['intelligence', 'patrocinio']) assert.ok(redirects.some(r => r.source === `/${page}.html` && r.destination === '/inicio.html' && r.permanent === false), page);
});
