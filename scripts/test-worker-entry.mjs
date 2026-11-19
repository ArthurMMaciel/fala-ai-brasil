import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Fluxo 1 (ADR-0023): o trabalhador precisa chegar à busca por CNPJ sem escolher uma empresa da lista.
test('Nova manifestação e Relatar uma situação abrem o assistente no passo do CNPJ; Empresas tem o atalho visível', () => {
  const portal = readFileSync('src/portals/worker-portal-live.tsx', 'utf8');
  assert.doesNotMatch(portal, /onNew=\{\(\) => setView\('companies'\)\}/, 'nenhum "Nova manifestação" leva à lista de empresas');
  assert.equal((portal.match(/onNew=\{\(\) => startNew\(''\)\}/g) ?? []).length, 2, 'Dashboard e Manifestações');
  assert.match(portal, /<button className="btn" onClick=\{\(\) => onNew\(''\)\}>Minha empresa não está na lista: buscar pelo CNPJ<\/button>/);
  const wizard = readFileSync('src/portals/complaint-wizard.tsx', 'utf8');
  assert.match(wizard, /if \(!chosen && !pending\) return <CompanyStep/, 'sem empresa inicial, o assistente começa pela busca por CNPJ');
});
