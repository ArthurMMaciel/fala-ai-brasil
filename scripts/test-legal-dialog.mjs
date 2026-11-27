import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Termos e privacidade em modal de leitura obrigatória (pedido do responsável, 2026-11-26).
const compile = file => ts.transpileModule(readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const asUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const docsUrl = asUrl(compile('src/domain/legal-docs.ts'));
const rawUrl = file => asUrl(`export default ${JSON.stringify(readFileSync(file, 'utf8'))};`);

// DOM mínimo: elementos, foco, eventos, rolagem controlada pelo teste e o documento.
function fakeDom() {
  const listeners = {};
  let active = null;
  const make = tag => {
    const el = {
      tagName: tag.toUpperCase(), children: [], attributes: {}, className: '', textContent: '', parent: null, handlers: {}, isConnected: true, id: '', type: '', disabled: false, tabIndex: -1,
      scrollTop: 0, clientHeight: 300, scrollHeight: 1200,
      setAttribute(name, value) { this.attributes[name] = String(value); }, getAttribute(name) { return this.attributes[name] ?? null; }, removeAttribute(name) { delete this.attributes[name]; },
      append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } },
      remove() { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); this.isConnected = false; },
      addEventListener(type, fn) { this.handlers[type] = fn; }, removeEventListener() {},
      focus() { active = this; }, click() { this.handlers.click?.({}); },
      classList: { set: new Set(), add(c) { this.set.add(c); }, remove(c) { this.set.delete(c); }, contains(c) { return this.set.has(c); } },
    };
    return el;
  };
  const body = make('body');
  const app = make('div'); app.id = 'app';
  globalThis.HTMLElement = Object;
  globalThis.window = { addEventListener() {}, removeEventListener() {} };
  globalThis.document = {
    body, createElement: make, getElementById: id => (id === 'app' ? app : null), get activeElement() { return active; },
    addEventListener(type, fn) { (listeners[type] ??= []).push(fn); }, removeEventListener(type, fn) { listeners[type] = (listeners[type] ?? []).filter(f => f !== fn); },
  };
  const find = (node, predicate) => predicate(node) ? node : node.children.map(child => find(child, predicate)).find(Boolean);
  return { body, app, find, key: key => (listeners.keydown ?? []).forEach(fn => fn({ key, shiftKey: false, preventDefault() {} })), get active() { return active; } };
}

async function load(dom) {
  const code = compile('src/app/legal-dialog.ts')
    .replace(/from ["']\.\.\/content\/legal\/termos-de-uso\.md\?raw["']/, `from '${rawUrl('src/content/legal/termos-de-uso.md')}'`)
    .replace(/from ["']\.\.\/content\/legal\/aviso-de-privacidade\.md\?raw["']/, `from '${rawUrl('src/content/legal/aviso-de-privacidade.md')}'`)
    .replace(/from ["']\.\.\/domain\/legal-docs["']/, `from '${docsUrl}'`);
  return import(asUrl(code + `\n// ${Math.random()}`));
}

test('fim do texto: margem de 8 px', async () => {
  fakeDom();
  const { reachedEnd } = await load();
  assert.equal(reachedEnd({ scrollTop: 0, clientHeight: 300, scrollHeight: 1200 }), false);
  assert.equal(reachedEnd({ scrollTop: 895, clientHeight: 300, scrollHeight: 1200 }), true);
  assert.equal(reachedEnd({ scrollTop: 0, clientHeight: 300, scrollHeight: 300 }), true, 'texto que cabe inteiro já libera');
});

test('modal: botão travado até o fim; Esc e clique fora bloqueados antes; depois do fim fecham e devolvem "leu"', async () => {
  const dom = fakeDom();
  const { openLegalDialog, legalDialogTexts } = await load();
  const result = openLegalDialog('terms');
  const dialog = dom.find(dom.body, node => node.attributes.role === 'dialog');
  const overlay = dom.find(dom.body, node => node.className === 'legal-overlay');
  const body = dom.find(dialog, node => node.className === 'legal-dialog-body');
  const button = dom.find(dialog, node => node.className === 'btn primary');
  const hint = dom.find(dialog, node => node.className === 'legal-dialog-hint');
  assert.equal(dialog.attributes['aria-modal'], 'true');
  assert.ok(dialog.attributes['aria-labelledby']);
  assert.equal(body.tabIndex, 0, 'texto rolável com foco de teclado');
  assert.equal(dom.active, body);
  assert.equal(button.disabled, true);
  assert.equal(hint.textContent, legalDialogTexts.hint);
  assert.ok(dom.find(dialog, node => node.className === 'legal-review-banner'), 'marca de revisão jurídica');
  dom.key('Escape');
  overlay.handlers.mousedown({ target: overlay });
  button.click();
  assert.equal(dom.body.children.length, 1, 'continua aberto antes do fim');
  body.scrollTop = 900; body.handlers.scroll();
  assert.equal(button.disabled, false);
  assert.equal(hint.textContent, legalDialogTexts.done);
  dom.key('Escape');
  assert.equal(await result, true);
  assert.equal(dom.body.children.length, 0);
  assert.equal(dom.app.attributes['aria-hidden'], undefined);
});

test('cadastro: links de termos e privacidade abrem o modal (sem nova aba) e marcam a caixa depois da leitura', () => {
  const main = readFileSync('src/app/main.js', 'utf8');
  assert.match(main, /<a href="\/#termos" data-legal="terms">termos de uso<\/a>/);
  assert.match(main, /<a href="\/#privacidade" data-legal="privacy">aviso de privacidade<\/a>/);
  assert.doesNotMatch(main, /href="\/#(termos|privacidade)" target="_blank"/);
  assert.match(main, /import "\.\/legal-dialog";/);
  const dialog = readFileSync('src/app/legal-dialog.ts', 'utf8');
  assert.match(dialog, /checkbox\.checked = true;/);
  assert.match(dialog, /if \(!read \|\| !checkbox \|\| checkbox\.checked\) return;/, 'só marca, nunca desmarca');
  assert.match(readFileSync('src/domain/legal-docs.ts', 'utf8'), /legalRoutes = \{ terms: "termos", privacy: "privacidade" \}/, 'rotas diretas continuam');
});
