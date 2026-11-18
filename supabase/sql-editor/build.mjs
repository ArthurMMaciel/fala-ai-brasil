// Gera, para cada migration, um arquivo para o responsável colar no SQL Editor de produção (sem db push).
// Uso: node supabase/sql-editor/build.mjs   (regrava supabase/sql-editor/0N_aplicar_<versão>.sql)
//
// Cada arquivo gerado:
//   - roda entre begin e commit: ou entra tudo, ou nada;
//   - começa com uma trava que recusa rodar se a versão já estiver registrada ou se a anterior não estiver;
//   - traz a migration como está no repositório (CRLF trocado por LF);
//   - termina gravando a versão em supabase_migrations.schema_migrations (version, name, statements), como o CLI faz,
//     para que um db push futuro não tente reaplicar. `statements` usa o mesmo divisor dos testes tx; o CLI compara só
//     a versão ao decidir o que aplicar.
import { readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { splitSql } from '../tests/tx/build.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const migDir = join(here, '..', 'migrations');

// Ordem aprovada. A 20261117130000 (troca do gate) fica de fora: está em supabase/pending.
const PLAN = [
  { file: '20261109180000_resposta_revisada_ativa.sql', after: '20261109170000' },
  { file: '20261117120000_representante_verificado_estrutura.sql', after: '20261109180000' },
  { file: '20261117140000_aceite_termos_privacidade.sql', after: '20261117120000' },
  { file: '20261117150000_pausa_do_piloto.sql', after: '20261117140000' },
];

function quote(text) {
  let n = 0;
  while (text.includes(`$s${n}$`)) n += 1;
  return `$s${n}$${text}$s${n}$`;
}

PLAN.forEach(({ file, after }, idx) => {
  const [, version, name] = /^(\d{14})_(.+)\.sql$/.exec(file);
  const sql = readFileSync(join(migDir, file), 'utf8').replace(/\r\n/g, '\n');
  const stmts = splitSql(sql);
  for (const s of stmts) {
    if (/^\s*(begin|commit|rollback|start\s+transaction)\b/i.test(s)) throw new Error(`${file}: controle de transação`);
    if (/alter\s+type\s+[^;]*\badd\s+value\b/i.test(s)) throw new Error(`${file}: ALTER TYPE ADD VALUE não roda em transação`);
  }
  const n = String(idx + 1).padStart(2, '0');
  const out = `-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/migrations/${file}. Não editar à mão.
-- Passo ${n} de ${String(PLAN.length).padStart(2, '0')}. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode \`rollback;\` sozinho e avise o Back.
-- Depois de rodar: ${n}_conferir_${version}.sql (todas as linhas com ok = true).
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '${version}') then
    raise exception 'A migration ${version} já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '${after}') then
    raise exception 'Falta a ${after} (passo anterior). Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration ${file} (${stmts.length} instruções) ========
${sql.trimEnd()}
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('${version}', '${name}', array[
${stmts.map((s) => quote(s)).join(',\n')}
]::text[]);

commit;
`;
  const target = join(here, `${n}_aplicar_${version}.sql`);
  writeFileSync(target, out);
  process.stderr.write(`${basename(target)}: ${stmts.length} instruções\n`);
});
