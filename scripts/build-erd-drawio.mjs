import { writeFileSync } from 'node:fs';

// Gera arquiteturas/06-banco-de-dados-mvp.drawio a partir da migration v2 (manter em sincronia ao mudar o esquema).
const tables = [
  { id: 'users', name: 'auth.users', x: 320, y: 60, color: ['#ffe6cc', '#d79b00'], rows: ['PK id', 'email · email_confirmed_at'] },
  { id: 'workers', name: 'workers', x: 40, y: 60, rows: ['PK id', 'FK user_id (unique)', 'full_name', 'cpf', 'FK address_id'] },
  { id: 'partners', name: 'partners', x: 600, y: 60, rows: ['PK id', 'FK user_id (unique)', 'display_name', 'document_type (cpf|cnpj)', 'document', 'specialty', 'description', 'FK avatar_media_id', 'FK address_id'] },
  { id: 'media', name: 'media', x: 880, y: 60, color: ['#d5e8d4', '#82b366'], rows: ['PK id', 'FK partner_id', 'kind (image|video)', 'storage_path (image)', 'external_url (video)', 'mime_type · size_bytes'] },
  { id: 'companies', name: 'companies', x: 40, y: 380, rows: ['PK id', 'legal_name · trade_name', 'cnpj (unique)', 'FK address_id', 'FK created_by'] },
  { id: 'addresses', name: 'addresses', x: 320, y: 380, color: ['#e1d5e7', '#9673a6'], rows: ['PK id', 'zip_code', 'street_type (street|avenue|…)', 'street_name', 'number · complement', 'neighborhood', 'city · state'] },
  { id: 'sponsors', name: 'sponsors', x: 600, y: 380, rows: ['PK id', 'FK user_id (unique)', 'name · cnpj', 'FK address_id'] },
  { id: 'cu', name: 'company_users', x: 40, y: 620, rows: ['PK FK company_id', 'PK FK user_id', 'role (owner|member)'] },
  { id: 'subs', name: 'subscriptions', x: 600, y: 580, color: ['#d5e8d4', '#82b366'], rows: ['PK id', 'FK company_id | partner_id | sponsor_id', '(exatamente um preenchido)', 'FK plan_id · mode · status', 'next_billing_at · paid_cents'] },
  { id: 'plans', name: 'plans', x: 880, y: 580, color: ['#d5e8d4', '#82b366'], rows: ['PK id', 'audience · name · monthly_cents'] },
];
// [origem tabela, linha, destino tabela, linha, início, fim]
const relations = [
  ['workers', 1, 'users', 0, 'ERzeroToOne'], ['partners', 1, 'users', 0, 'ERzeroToOne'], ['sponsors', 1, 'users', 0, 'ERzeroToOne'],
  ['cu', 1, 'users', 0, 'ERzeroToMany'], ['cu', 0, 'companies', 0, 'ERzeroToMany'], ['media', 1, 'partners', 0, 'ERzeroToMany'],
  ['workers', 4, 'addresses', 0, 'ERzeroToOne'], ['companies', 3, 'addresses', 0, 'ERzeroToOne'], ['partners', 8, 'addresses', 0, 'ERzeroToOne'], ['sponsors', 3, 'addresses', 0, 'ERzeroToOne'],
  ['subs', 1, 'sponsors', 0, 'ERzeroToMany'], ['subs', 3, 'plans', 0, 'ERzeroToMany'],
];
const esc = value => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const cells = ['<mxCell id="title" value="Escuta Aí Brasil — Banco do MVP v2 (entidades por tipo)" style="text;html=1;fontSize=20;fontStyle=1;align=left;" vertex="1" parent="1"><mxGeometry x="40" y="0" width="900" height="36" as="geometry"/></mxCell>'];
for (const table of tables) {
  const [fill, stroke] = table.color ?? ['#dae8fc', '#6c8ebf'];
  cells.push(`<mxCell id="${table.id}" value="${esc(table.name)}" style="swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;startSize=26;horizontalStack=0;resizeParent=1;resizeParentMax=0;collapsible=0;html=1;fillColor=${fill};strokeColor=${stroke};fontSize=14;" vertex="1" parent="1"><mxGeometry x="${table.x}" y="${table.y}" width="220" height="${26 + table.rows.length * 26}" as="geometry"/></mxCell>`);
  table.rows.forEach((row, i) => cells.push(`<mxCell id="${table.id}-${i}" value="${esc(row)}" style="text;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;spacingLeft=4;html=1;fontSize=13;" vertex="1" parent="${table.id}"><mxGeometry y="${26 + i * 26}" width="220" height="26" as="geometry"/></mxCell>`));
}
relations.forEach(([from, fromRow, to, toRow, start], i) => cells.push(`<mxCell id="rel-${i}" style="edgeStyle=orthogonalEdgeStyle;html=1;startArrow=${start};endArrow=ERmandOne;" edge="1" parent="1" source="${from}-${fromRow}" target="${to}-${toRow}"><mxGeometry relative="1" as="geometry"/></mxCell>`));
cells.push('<mxCell id="note" value="RLS em todas as tabelas. Uma conta pode ter vários perfis (workers, partners, sponsors, company_users); o portal vem de current_profiles(). Cadastro via trigger e add_profile() chamando private.create_profile(). Fotos no bucket partner-media; vídeos só por link. Assinatura liga a exatamente um de company/partner/sponsor." style="rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=12;align=left;spacingLeft=8;" vertex="1" parent="1"><mxGeometry x="40" y="760" width="1060" height="50" as="geometry"/></mxCell>');
writeFileSync('arquiteturas/06-banco-de-dados-mvp.drawio', `<mxGraphModel adaptiveColors="auto"><root><mxCell id="0"/><mxCell id="1" parent="0"/>${cells.join('')}</root></mxGraphModel>\n`, 'utf8');
console.log('arquiteturas/06-banco-de-dados-mvp.drawio atualizado');
