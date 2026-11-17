// Monta um teste "migration em transação" para rodar em produção sem gravar nada.
// Uso: node supabase/tests/tx/build.mjs <checks.sql> <migration1.sql> [migration2.sql ...] > saida.sql
//
// O arquivo gerado é uma única instrução DO (o `supabase db query` não aceita várias instruções):
//   1) tudo roda dentro de um bloco com tratador de exceção (subtransação): COMMIT/ROLLBACK ficam proibidos;
//   2) cada migration é aplicada instrução por instrução, com EXECUTE, e pulada se a versão já constar em
//      supabase_migrations.schema_migrations (estado real de produção);
//   3) o corpo de <checks.sql> roda em seguida (ele usa as variáveis `res` e `falhas` declaradas aqui);
//   4) termina com raise exception 'RESULTADOS ...': o Postgres desfaz migrations, dados de teste e tudo mais.
// Limitação: ALTER TYPE ... ADD VALUE não pode ser usado na mesma transação que o valor novo; as migrations do piloto
// não usam enum novo. Os locks de DDL (ALTER TABLE) ficam presos até o fim da execução, em geral segundos.
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';

// Divide SQL em instruções respeitando comentários, strings '...', identificadores "..." e corpos $tag$...$tag$.
export function splitSql(sql) {
  const out = [];
  let cur = '';
  let i = 0;
  while (i < sql.length) {
    const c = sql[i];
    const two = sql.slice(i, i + 2);
    if (two === '--') {
      const j = sql.indexOf('\n', i);
      const end = j === -1 ? sql.length : j + 1;
      cur += sql.slice(i, end);
      i = end;
    } else if (two === '/*') {
      const j = sql.indexOf('*/', i + 2);
      if (j === -1) throw new Error('comentário /* sem fim');
      cur += sql.slice(i, j + 2);
      i = j + 2;
    } else if (c === "'" || c === '"') {
      let j = i + 1;
      while (j < sql.length) {
        if (sql[j] === c && sql[j + 1] === c) { j += 2; continue; }
        if (sql[j] === c) break;
        j += 1;
      }
      if (j >= sql.length) throw new Error(`aspas ${c} sem fim`);
      cur += sql.slice(i, j + 1);
      i = j + 1;
    } else if (c === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i));
      if (m) {
        const tag = m[0];
        const j = sql.indexOf(tag, i + tag.length);
        if (j === -1) throw new Error(`corpo ${tag} sem fim`);
        cur += sql.slice(i, j + tag.length);
        i = j + tag.length;
      } else { cur += c; i += 1; }
    } else if (c === ';') {
      if (cur.replace(/--[^\n]*\n?/g, '').trim()) out.push(cur.trim());
      cur = '';
      i += 1;
    } else { cur += c; i += 1; }
  }
  if (cur.replace(/--[^\n]*\n?/g, '').trim()) out.push(cur.trim());
  return out;
}

// Escolhe uma tag de dollar-quote que não aparece no texto.
function quote(text) {
  let n = 0;
  while (text.includes(`$s${n}$`)) n += 1;
  return `$s${n}$${text}$s${n}$`;
}

function main() {
  const [checksPath, ...migrations] = process.argv.slice(2);
  if (!checksPath || migrations.length === 0) {
    console.error('uso: node supabase/tests/tx/build.mjs <checks.sql> <migration.sql> [...]');
    process.exit(2);
  }
  const checks = readFileSync(checksPath, 'utf8');
  if (/\b(commit|rollback)\b\s*;/i.test(checks)) throw new Error('checks contém COMMIT/ROLLBACK');
  const declMatch = /^--\s*declare:\s*(.*)$/m.exec(checks);
  const extraDecl = declMatch ? declMatch[1] : '';

  let body = '';
  for (const path of migrations) {
    const version = /^(\d{14})_/.exec(basename(path))?.[1];
    if (!version) throw new Error(`nome de migration sem versão: ${path}`);
    const stmts = splitSql(readFileSync(path, 'utf8'));
    for (const s of stmts) if (/^\s*(commit|rollback|begin)\b/i.test(s)) throw new Error(`${path}: controle de transação`);
    body += `\n    -- ${basename(path)} (${stmts.length} instruções)\n`;
    body += `    if exists (select 1 from supabase_migrations.schema_migrations where version = '${version}') then\n`;
    body += `      res := res || jsonb_build_object('${version}', 'já aplicada em produção; pulada');\n    else\n`;
    for (const s of stmts) body += `      execute ${quote(s)};\n`;
    body += `      res := res || jsonb_build_object('${version}', 'aplicada na transação de teste');\n    end if;\n`;
  }

  process.stdout.write(`-- GERADO por supabase/tests/tx/build.mjs. Não editar: editar ${basename(checksPath)} e as migrations.
-- Migrations: ${migrations.map((m) => basename(m)).join(', ')}
-- Execução em produção só com liberação escrita do responsável: npx supabase db query --linked < este_arquivo
-- Nada é gravado: subtransação sem COMMIT possível e exceção final. Única sobra: sequências avançadas.
do $tx$
declare
  res jsonb := '{}'::jsonb;
  falhas jsonb := '[]'::jsonb;
  ${extraDecl}
begin
  begin  -- trava: nada pode commitar daqui para dentro
${body}
    -- Verificações (${basename(checksPath)})
${checks.split('\n').map((l) => `    ${l}`).join('\n')}

    execute 'reset role';
    res := res || jsonb_build_object('falhas', falhas, 'aprovado', jsonb_array_length(falhas) = 0);
    raise exception 'RESULTADOS %', res;
  exception when others then
    if sqlerrm like 'RESULTADOS %' then raise; end if;
    raise exception 'ABORTADO (nada gravado): % [%]', sqlerrm, sqlstate;
  end;
end $tx$;
`);
}

main();
