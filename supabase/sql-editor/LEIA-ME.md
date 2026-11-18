# Aplicação manual no SQL Editor de produção (lote de 2026-11-17)

O responsável roda estes arquivos no SQL Editor do Supabase (produção). Não há db push nem cópia do banco.

**Não há backup.** O responsável aceitou esse risco em 2026-11-17 (repassado pelo Gestor). Os rollbacks refazem a estrutura anterior. Os dados gravados depois da aplicação só se salvam se forem exportados antes: verificações de representante, aceites e trilha da pausa. As migrations deste lote não apagam nem alteram dados que já existem. A exceção é a 120000, que acrescenta duas colunas em `company_users`.

## Antes de começar

- O front em produção precisa ser o tolerante (079d14b ou posterior). O alvo de Instant Rollback do front é **661712a**.
- Escolha um horário de pouco uso. Cada passo trava tabelas por poucos segundos. Se houver espera de lock por mais de 5 s, o passo falha sem gravar nada.
- A 20261117130000 (troca do gate) **não** faz parte deste lote. Ela fica em `supabase/pending/`.

## Ordem

| Passo | Arquivo | Esperado |
|---|---|---|
| 00 | `00_incluir_admin.sql` (troque o e-mail; não salve preenchido) | `equipe` ≥ 1 |
| 01 | `01_aplicar_20261109180000.sql` e depois `01_conferir_20261109180000.sql` | todas as linhas `ok = true` |
| 02 | `02_aplicar_20261117120000.sql` e depois `02_conferir_20261117120000.sql` | todas as linhas `ok = true` |
| 03 | `03_aplicar_20261117140000.sql` e depois `03_conferir_20261117140000.sql` | todas as linhas `ok = true` |
| 04 | `04_aplicar_20261117150000.sql` e depois `04_conferir_20261117150000.sql` | todas as linhas `ok = true` |

- Cada arquivo deve ser colado inteiro e rodado uma vez. Não comece um passo antes de o anterior conferir tudo verdadeiro.
- Cada `aplicar` roda entre `begin` e `commit`. A primeira instrução é uma trava, que recusa rodar se a versão já estiver registrada ou se faltar a anterior. A última grava a versão em `supabase_migrations.schema_migrations` (version, name, statements) no mesmo formato do CLI. Conferido: a divisão em instruções bate exatamente com o que o CLI gravou para a 20261109170000. Assim, um db push futuro não tenta reaplicar.
- O passo 00 pode rodar a qualquer momento. As migrations não dependem dele, mas a fila de representantes e a pausa, sim.
- O SQL Editor pode pedir confirmação de "operação destrutiva", porque o passo 01 troca uma policy com `drop policy`. Confirme só se o arquivo for o esperado.
- No fim, avise o Back. O Back confere com `migration list`, em modo de leitura.

## Se algo falhar

- **Erro ao rodar um `aplicar`:** nada foi gravado.
  1. Rode `rollback;` sozinho, para liberar a sessão.
  2. Não rode o passo de novo às cegas.
  3. Mande ao Back a mensagem de erro, que não contém dado pessoal.
  4. Não siga para o passo seguinte.
- **Erro `lock timeout`:** nada foi gravado. Espere alguns minutos e rode o mesmo passo de novo.
- **Erro "já está registrada":** o passo já tinha sido aplicado. Rode só o `conferir`.
- **`conferir` com alguma linha `false`, ou com erro, depois de um `aplicar` sem erro:**
  1. Pare.
  2. Mande o resultado ao Back.
  3. Decida com o Gestor se roda o rollback daquele passo.
- **Problema no site depois de aplicar:** primeiro, o Instant Rollback do front (661712a). Se o problema for do banco, use os rollbacks abaixo.

## Rollbacks (`supabase/tests/rollback/`), na ordem inversa

| Ordem | Arquivo | Observação |
|---|---|---|
| R1 | `20261117150000_rollback.sql` | Reabre manifestações se o piloto estiver pausado. Exporte `pilot_state_log` antes, se tiver linhas. |
| R2 | `20261117140000_rollback.sql` | Recusa se o gate do aceite estiver ligado. Exporte os aceites antes (eles são prova). |
| R3 | `20261117120000_rollback.sql` | Exige R1 antes e a 130000 não aplicada. Exporte a trilha de verificações antes. |
| R4 | `20261109180000_rollback.sql` | Recusa enquanto houver resposta em revisão: a Operação libera ou devolve antes. |

- Cada rollback roda entre `begin` e `commit`, tem trava própria e tira a versão de `schema_migrations`.
- Quando há dados, o rollback para e pede a exportação. Depois de exportar (Download CSV no SQL Editor), troque `v_exportei := false` por `true` e rode de novo.
- Só R3 depende de outro (R1). Um rollback isolado da 180000 deixa um buraco no histórico, e o próximo db push vai pedir `--include-all`.

## Pausar e retomar o piloto

- `05_pausar_piloto.sql` e `06_retomar_piloto.sql`: troque e-mail e motivo e não salve preenchido. Só funcionam depois dos passos 00 e 04.
- No SQL Editor, `auth.uid()` é nulo. Por isso o script assume, só dentro da própria transação, a identidade da sua conta de equipe e chama `ops_set_pilot_state`, que confere a equipe, troca o estado e grava a trilha com você como autor.
- O motivo não pode conter dado de trabalhador, de empresa ou de relato.

## Manutenção

- Os arquivos `0N_aplicar_*` são gerados: `node supabase/sql-editor/build.mjs`. Se uma migration do lote mudar, gere de novo e reenvie para revisão.
- Os demais arquivos são escritos à mão.
