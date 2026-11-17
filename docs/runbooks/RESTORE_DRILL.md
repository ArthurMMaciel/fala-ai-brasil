# Ensaio de restauração (TASK-0010)

Objetivo: provar que uma cópia lógica do banco de produção pode ser restaurada, e medir quanto tempo isso leva (RTO). O teste copia os dados do remoto e os restaura no Supabase local. Depois confere se cada tabela tem o mesmo número de linhas nos dois lados.

**Este procedimento lê produção inteira e traz dado pessoal para a máquina. Só roda com liberação escrita do responsável na sessão do DevOps.**

## Quando

Antes de 30/11. Segundo o Gestor, até lá não há relato real no banco, então uma cópia que vaze expõe menos. Os cadastros de teste já feitos em produção podem ter nome, e-mail ou CPF de pessoas reais ("a confirmar" com o responsável). O roteiro trata a cópia como sigilosa de qualquer forma.

## Pré-requisitos

- Supabase local rodando (Docker), com as mesmas migrations da produção:
  - `npx supabase migration list` sem divergência;
  - a 180000 (TASK-0035 passo d) aplicada nos dois lados, ou em nenhum.
- Front e Back avisados com antecedência: o passo 3 roda `db reset` no banco local compartilhado e apaga os dados de teste deles.
- A senha do banco de produção é digitada pelo responsável quando o CLI pedir. Ela não vai para arquivo, variável persistente ou log.
- Lembrete: o `SUPABASE_ACCESS_TOKEN` desta máquina é de outra conta. Confirmar que o projeto vinculado (`supabase/.temp/project-ref`) é o ouvira-brasil antes de começar.

## Onde a cópia fica

- Pasta fora de qualquer repositório: `%USERPROFILE%\restore-drill\AAAAMMDD\`.
- O `.gitignore` do repositório já cobre `*.dump` e `backups/`, mas a cópia nem deve passar pela pasta do projeto.
- Cifragem, em uma de duas opções (o responsável escolhe):
  - **A (com GPG):** cifrar `data.sql` com a chave pública do responsável logo após o dump, e apagar o texto claro. Depende da chave estar pronta (R4.3).
  - **B (sem GPG):** a cópia fica em texto claro só durante o ensaio e é descartada logo após a contagem, com descarte verificado (passo 6). É a alternativa se a chave não ficar pronta até 19/11.

## Passos

1. **Contagem no remoto.** Roda com `db query --read-only`, que só faz leitura, em um único SELECT:

   ```sql
   select tablename,
          (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', schemaname, tablename), false, true, '')))[1]::text::bigint as linhas
   from pg_tables
   where schemaname = 'public'
   order by tablename;
   ```

   Salvar a saída em `contagem-remoto.txt` na pasta do ensaio. A saída contém só nomes de tabela e números.

2. **Dump do remoto.** Comandos da documentação oficial ([backup-restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)), com o projeto vinculado:

   ```bash
   npx supabase db dump --linked -f schema.sql
   ```

   ```bash
   npx supabase db dump --linked -f data.sql --use-copy --data-only
   ```

   - Na versão 3 do CLI, `--linked` ainda funciona mas está marcado como obsoleto. Na 4, o equivalente é `--remote`.
   - Anotar a hora de início e de fim.
   - O dump padrão exclui os schemas `auth` e `storage`. Contas de login e arquivos do Storage ficam fora deste ensaio (ver "Limites").

3. **Banco local zerado com o schema das migrations:**

   ```bash
   npx supabase db reset
   ```

4. **Carga dos dados no local.** O `session_replication_role = replica` desliga os gatilhos e as chaves estrangeiras durante a carga, porque `auth.users` não vem no dump:

   Esta máquina não tem `psql` instalado (conferido em 2026-11-17). Usa-se o `psql` do próprio container do banco local, lendo o arquivo pela entrada padrão:

   ```bash
   docker exec -i supabase_db_voz-psicosocial psql -U postgres -d postgres --single-transaction -v ON_ERROR_STOP=1 -c "SET session_replication_role = replica" -f - < data.sql
   ```

   - O nome do container vem de `project_id` no `supabase/config.toml`. Conferir com `docker ps`.
   - Se a carga falhar por chave duplicada em `supabase_migrations.schema_migrations`, refazer o dump do passo 2 com `-x supabase_migrations.schema_migrations`. Não está confirmado se o dump inclui essa tabela.
   - Anotar a hora de início e de fim. Esse tempo mais o do dump é o RTO medido do caminho lógico.

5. **Contagem no local.** Rodar o mesmo SELECT do passo 1 no banco local, pelo container (`docker exec -i ... psql -U postgres -d postgres -c "<select>"`), e comparar com `contagem-remoto.txt`. O critério de aceite é a mesma contagem em todas as tabelas de `public`.

6. **Descarte:**
   - apagar `data.sql`, `schema.sql` e, se houver, o `.gpg` que não for guardado;
   - conferir com `dir` que a pasta ficou vazia;
   - rodar `npx supabase db reset` de novo, para tirar os dados reais do banco local. O Docker guarda o banco local num volume, e o reset o reescreve;
   - avisar Front e Back que o banco local voltou ao seed.

7. **Registro na TASK-0010** (sem nenhum dado):
   - data e versão do CLI;
   - tamanho do dump;
   - tempos do dump e da carga;
   - número de tabelas comparadas e divergências;
   - opção de cifragem usada;
   - confirmação do descarte.

## Limites do ensaio

- Ele prova o caminho lógico (`db dump`). Não prova a restauração do backup diário ou do PITR pelo painel: essa substitui o banco de produção e deixa o projeto fora do ar. O ensaio da restauração pelo painel exigiria restaurar num projeto novo (Duplicate Project), o que pode ter custo e fica para decisão do responsável.
- O schema `auth` (contas de login) não entra. Dumpá-lo traz e-mail e hash de senha para a máquina. Se o responsável quiser cobrir o `auth`, isso precisa de uma decisão própria.
- O Storage não entra. Hoje há um bucket público (`partner-media`, fotos de perfil de parceiro) e nenhum backup do Supabase cobre arquivos.
- Comparar a contagem de linhas não detecta coluna corrompida. É uma prova mínima, proporcional ao prazo.

## Rollback

O ensaio não altera produção: o passo 1 só lê, e o dump também só lê. No local, `npx supabase db reset` volta ao seed.
