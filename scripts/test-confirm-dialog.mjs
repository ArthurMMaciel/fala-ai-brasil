import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import ts from 'typescript';

// Modal de confirmação próprio no lugar da janela do navegador (ClickUp 17tu7rpgnev, 2026-11-24).
function sourceFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = `${dir}/${entry.name}`;
    return entry.isDirectory() ? sourceFiles(path) : /\.(ts|tsx|js|jsx)$/.test(entry.name) ? [path] : [];
  });
}

test('nenhuma janela do navegador: window.confirm, window.alert e window.prompt (nem chamadas soltas) no src', () => {
  const found = [];
  for (const file of sourceFiles('src')) {
    const code = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
    code.split(/\r?\n/).forEach((line, index) => {
      if (/\bwindow\.(confirm|alert|prompt)\s*\(/.test(line) || /(^|[^.\w])(alert|prompt)\s*\(/.test(line) || /(^|[^.\w])confirm\s*\((?!\))/.test(line)) found.push(`${file}:${index + 1}`);
    });
  }
  assert.deepEqual(found, []);
});

// DOM mínimo, suficiente para o modal: elementos, foco, eventos e o documento.
function fakeDom() {
  const listeners = {};
  let active = null;
  const make = tag => {
    const el = {
      tagName: tag.toUpperCase(), children: [], attributes: {}, className: '', textContent: '', parent: null, handlers: {}, isConnected: true, type: '', id: '',
      setAttribute(name, value) { this.attributes[name] = String(value); }, getAttribute(name) { return this.attributes[name] ?? null; }, removeAttribute(name) { delete this.attributes[name]; },
      append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } },
      remove() { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); this.isConnected = false; },
      addEventListener(type, fn) { this.handlers[type] = fn; },
      focus() { active = this; }, click() { this.handlers.click?.({}); },
      classList: { set: new Set(), add(c) { this.set.add(c); }, remove(c) { this.set.delete(c); } },
    };
    return el;
  };
  const body = make('body');
  const app = make('div'); app.id = 'app';
  const opener = make('button');
  globalThis.HTMLElement = Object;
  globalThis.document = {
    body, createElement: make, getElementById: id => (id === 'app' ? app : null),
    get activeElement() { return active; },
    addEventListener(type, fn) { listeners[type] = fn; }, removeEventListener(type) { delete listeners[type]; },
  };
  return { body, app, opener, key: (key, shiftKey = false) => listeners.keydown?.({ key, shiftKey, preventDefault() {} }), get active() { return active; } };
}

const code = ts.transpileModule(readFileSync('src/app/confirm-dialog.ts', 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.ES2022 } }).outputText;
const { confirmAction } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const find = (node, predicate) => predicate(node) ? node : node.children.map(child => find(child, predicate)).find(Boolean);

test('modal: alertdialog com aria-modal, título e texto; foco preso; Esc cancela e devolve o foco', async () => {
  const dom = fakeDom();
  dom.opener.focus();
  const result = confirmAction({ title: 'Apagar?', text: 'Não dá para desfazer.', confirmLabel: 'Apagar', danger: true });
  const dialog = find(dom.body, node => node.attributes.role === 'alertdialog');
  assert.equal(dialog.attributes['aria-modal'], 'true');
  assert.equal(dom.app.attributes['aria-hidden'], 'true', 'o resto do app fica escondido do leitor de tela');
  const [cancel, accept] = find(dialog, node => node.className === 'confirm-actions').children;
  assert.equal(accept.className, 'btn primary danger');
  assert.equal(dom.active, cancel, 'ação destrutiva abre com o foco em Cancelar');
  dom.key('Tab'); assert.equal(dom.active, accept);
  dom.key('Tab'); assert.equal(dom.active, cancel, 'Tab não sai do modal');
  dom.key('Tab', true); assert.equal(dom.active, accept);
  dom.key('Escape');
  assert.equal(await result, false);
  assert.equal(dom.active, dom.opener, 'o foco volta para quem abriu');
  assert.equal(dom.app.attributes['aria-hidden'], undefined);
  assert.equal(dom.body.children.length, 0);
});

test('modal: botão principal confirma; ação comum abre com o foco no botão principal', async () => {
  const dom = fakeDom();
  const result = confirmAction({ title: 'Liberar?', text: 'A empresa passa a ver.', confirmLabel: 'Liberar' });
  const accept = find(dom.body, node => node.className === 'btn primary');
  assert.equal(dom.active, accept);
  accept.click();
  assert.equal(await result, true);
});
