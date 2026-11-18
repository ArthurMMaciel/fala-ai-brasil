import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Fluxo 2: aba "Contratados" da empresa (list_my_contracted_partners, migration 20261118150000 em supabase/pending).
test('Contratados: tolerante à função ausente, só da empresa aberta e atrás da verificação do representante', () => {
  const service = readFileSync('src/services/account.ts', 'utf8');
  assert.match(service, /rpc\("list_my_contracted_partners"\)/);
  assert.match(service, /error\.code === "PGRST202" \|\| error\.code === "42883"\) return \{ missing: true \}/);
  const portal = readFileSync('src/portals/portal-live.tsx', 'utf8');
  assert.match(portal, /\['contracted', 'Contratados'\]/);
  assert.match(portal, /result\.rows\.filter\(row => row\.companyId === companyId\)/);
  assert.match(portal, /ainda não está ativa no banco/);
  // O gate da verificação libera só parceiros e perfil; Contratados fica atrás dele.
  assert.match(portal, /companyAccessPending\(verification\) && view !== 'partners' && view !== 'profile'/);
});
