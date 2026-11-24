// Gera, para cada migration, um arquivo para o responsável colar no SQL Editor de produção (sem db push).
// Uso: node supabase/sql-editor/build.mjs   (regrava supabase/sql-editor/0N_aplicar_<versão>.sql e lote2/0N_aplicar_<versão>.sql)
//
// Cada arquivo gerado:
//   - roda entre begin e commit: ou entra tudo, ou nada;
//   - começa com uma trava que recusa rodar se a versão já estiver registrada ou se a anterior não estiver;
//   - traz a migration como está no repositório (CRLF trocado por LF);
//   - termina gravando a versão em supabase_migrations.schema_migrations (version, name, statements), como o CLI faz,
//     para que um db push futuro não tente reaplicar. `statements` usa o mesmo divisor dos testes tx; o CLI compara só
//     a versão ao decidir o que aplicar.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { splitSql } from '../tests/tx/build.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const supabaseDir = join(here, '..');

const ADMIN_GUARD = `
  if not exists (select 1 from private.platform_admins) then
    raise exception 'Ninguém na equipe (private.platform_admins). Rode o passo 00 antes: sem equipe, as respostas ficariam presas em revisão. Nada foi feito.';
  end if;`;
const VERIFIED_GUARD = `
  if not exists (select 1 from public.company_users where verification_status = 'verified') then
    raise exception 'Nenhum representante verificado. Verifique antes as empresas reais na fila da Operação: depois deste passo, só vínculo verificado vê manifestações. Nada foi feito.';
  end if;`;

// Lote 1: aplicado pelo responsável em 2026-11-18. Lote 2: troca do gate e empresa pré-cadastrada (ADR-0012, ADR-0023);
// os arquivos do lote 2 podem estar em supabase/pending até serem aplicados.
const BATCHES = [
  { out: '.', applied: true, plan: [
    { file: '20261109180000_resposta_revisada_ativa.sql', after: '20261109170000', guard: ADMIN_GUARD,
      warn: 'a partir deste passo, toda resposta de empresa espera a revisão do operador antes de chegar ao trabalhador.' },
    { file: '20261117120000_representante_verificado_estrutura.sql', after: '20261109180000' },
    { file: '20261117140000_aceite_termos_privacidade.sql', after: '20261117120000' },
    { file: '20261117150000_pausa_do_piloto.sql', after: '20261117140000' },
  ] },
  { out: 'lote2', applied: true, plan: [
    { file: '20261117130000_representante_verificado_gate.sql', after: '20261117150000', guard: VERIFIED_GUARD,
      warn: 'a partir deste passo, só representante verificado vê manifestações e responde; confira antes a fila da Operação.' },
    { file: '20261118120000_empresa_pre_cadastrada_estrutura.sql', after: '20261117130000' },
    { file: '20261118130000_empresa_pre_cadastrada_funcoes.sql', after: '20261118120000' },
    { file: '20261118140000_reivindicacao_cnpj.sql', after: '20261118130000' },
    { file: '20261118150000_empresa_contratados.sql', after: '20261118140000' },
  ] },
  // Lote 3: título do relato original fora da lista da empresa (aprovado em 2026-11-23).
  { out: 'lote3', plan: [
    { file: '20261123120000_titulo_sem_conteudo_para_empresa.sql', after: '20261118150000' },
  ] },
];

function source(file) {
  for (const dir of ['migrations', 'pending']) {
    const path = join(supabaseDir, dir, file);
    if (existsSync(path)) return { dir, sql: readFileSync(path, 'utf8').replace(/\r\n/g, '\n') };
  }
  throw new Error(`migration não encontrada: ${file}`);
}

function quote(text) {
  let n = 0;
  while (text.includes(`$s${n}$`)) n += 1;
  return `$s${n}$${text}$s${n}$`;
}

// Lotes já aplicados não são regerados (os arquivos ficam como foram rodados), salvo com --all.
for (const { out: outDir, plan, applied } of BATCHES) {
  if (applied && !process.argv.includes('--all')) continue;
  mkdirSync(join(here, outDir), { recursive: true });
  plan.forEach(({ file, after, guard, warn }, idx) => {
    const [, version, name] = /^(\d{14})_(.+)\.sql$/.exec(file);
    const { dir, sql } = source(file);
    const stmts = splitSql(sql);
    for (const s of stmts) {
      if (/^\s*(begin|commit|rollback|start\s+transaction)\b/i.test(s)) throw new Error(`${file}: controle de transação`);
      if (/alter\s+type\s+[^;]*\badd\s+value\b/i.test(s)) throw new Error(`${file}: ALTER TYPE ADD VALUE não roda em transação`);
    }
    const n = String(idx + 1).padStart(2, '0');
    const out = `-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/${dir}/${file}. Não editar à mão.
-- Passo ${n} de ${String(plan.length).padStart(2, '0')}. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode \`rollback;\` sozinho e avise o Back.
-- Depois de rodar: ${n}_conferir_${version}.sql (todas as linhas com ok = true).${warn ? `
-- AVISO: ${warn}` : ''}
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '${version}') then
    raise exception 'A migration ${version} já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '${after}') then
    raise exception 'Falta a ${after} (passo anterior). Nada foi feito.';
  end if;${guard ?? ''}
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
    const target = join(here, outDir, `${n}_aplicar_${version}.sql`);
    writeFileSync(target, out);
    process.stderr.write(`${outDir}/${basename(target)}: ${stmts.length} instruções\n`);
  });
}
