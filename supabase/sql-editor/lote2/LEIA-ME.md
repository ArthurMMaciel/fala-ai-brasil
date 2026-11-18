# Lote 2 no SQL Editor de produção: troca do gate e empresa pré-cadastrada

O formato é o mesmo do lote 1 (`../LEIA-ME.md`). O responsável roda os scripts no SQL Editor de produção. Não há db push nem backup: o risco foi aceito pelo responsável em 2026-11-17.

## Antes de começar

- O lote 1 (00 a 04) precisa estar aplicado e conferido.
- **Antes do passo 01:** verifique na fila de representantes da Operação as empresas reais do piloto. Depois do 01, só o representante verificado vê manifestações, responde e vê os números da própria empresa. O passo 01 recusa rodar se não houver nenhum representante verificado.
- **Teste em transação desfeita antes de cada passo**, com liberação escrita do responsável na sessão do Back:
  - `gate_tx` antes do 01;
  - `empresa_tx` antes do 02 e do 03;
  - `reivindicacao_tx` antes do 04.

  Os arquivos ficam em `supabase/tests/tx/out/`.
- O alvo de Instant Rollback do front é o informado pelo Gestor no dia.

## Ordem

| Passo | Arquivo | Esperado |
|---|---|---|
| 01 | `01_aplicar_20261117130000.sql` e depois `01_conferir_20261117130000.sql` | todas as linhas `ok = true` |
| 02 | `02_aplicar_20261118120000.sql` e depois `02_conferir_20261118120000.sql` | todas as linhas `ok = true` |
| — | Edge Function `cnpj-lookup`, publicada pelo DevOps (só depois do 02, porque grava no cache) | — |
| 03 | `03_aplicar_20261118130000.sql` e depois `03_conferir_20261118130000.sql` | todas as linhas `ok = true` |
| 04 | `04_aplicar_20261118140000.sql` e depois `04_conferir_20261118140000.sql` | todas as linhas `ok = true` |

- Cada `aplicar` roda entre `begin` e `commit`, com trava de versão e da anterior, e registra a versão em `schema_migrations`.
- O 04 também recusa rodar sem a troca do gate e sem a estrutura do 02.
- O front da busca por CNPJ, do contato e da fila de avisos só entra depois do 03 e da função.
- Depois de cada passo aplicado, avise o Back. Ele move o arquivo de `supabase/pending` para `supabase/migrations` e confere com `migration list`, em modo de leitura.

## Se algo falhar

Vale o mesmo do lote 1:
- Erro no `aplicar`: nada foi gravado. Rode `rollback;` sozinho e avise o Back.
- Erro de lock timeout: espere e rode de novo.
- Erro "já está registrada": rode só o `conferir`.
- `conferir` com `false`: pare e avise.

## Rollbacks (`supabase/tests/rollback/`), na ordem inversa

| Ordem | Arquivo | Observação |
|---|---|---|
| R1 | `20261118140000_rollback.sql` | Empresas já reivindicadas continuam cadastradas. |
| R2 | `20261118130000_rollback.sql` | Relatos, empresas pré-cadastradas e trilha de avisos ficam. |
| R3 | `20261118120000_rollback.sql` | Recusa se houver empresa pré-cadastrada (ela tem relatos). Exporte contatos, avisos, opt-outs e cache antes. |
| R4 | `20261117130000_rollback.sql` | Só com decisão registrada: reabre os casos para vínculo não verificado. Exige o R1 antes. |
