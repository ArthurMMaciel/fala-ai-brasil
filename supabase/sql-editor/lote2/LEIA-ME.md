# Lote 2 no SQL Editor de produção: troca do gate, empresa pré-cadastrada e aba Contratados

**Aplicado em produção em 2026-11-19** (passos 01 a 05, conferidos pelo responsável). Os arquivos das migrations estão em `supabase/migrations`.

O formato é o mesmo do lote 1 (`../LEIA-ME.md`, aplicado e conferido em 2026-11-18). O responsável roda os scripts no SQL Editor de produção. Não há db push nem backup: o risco foi aceito pelo responsável.

## Antes de começar

1. Verifique, na fila de representantes da Operação, as 3 empresas reais do piloto. Depois do passo 01, só o representante verificado vê manifestações, responde e vê os números da própria empresa. O passo 01 recusa rodar se não houver nenhum representante verificado.
2. Antes de cada passo, rode o teste em transação desfeita, com liberação escrita do responsável na sessão do Back:
   - `gate_tx` antes do 01;
   - `empresa_tx` antes do 02 e do 03;
   - `reivindicacao_tx` antes do 04;
   - `contratados_tx` antes do 05.

   Os arquivos ficam em `supabase/tests/tx/out/`.

## Ordem

| Passo | Arquivo | Esperado |
|---|---|---|
| 01 | `01_aplicar_20261117130000.sql` e `01_conferir_…` (troca do gate) | todas as linhas `ok = true` |
| 02 | `02_aplicar_20261118120000.sql` e `02_conferir_…` (estrutura da empresa pré-cadastrada) | todas as linhas `ok = true` |
| — | Edge Function `cnpj-lookup`, opcional para o fluxo 1 (o cadastro manual cobre); só depois do 02 | — |
| 03 | `03_aplicar_20261118130000.sql` e `03_conferir_…` (funções e aviso) | todas as linhas `ok = true` |
| 04 | `04_aplicar_20261118140000.sql` e `04_conferir_…` (reivindicação no cadastro) | todas as linhas `ok = true` |
| 05 | `05_aplicar_20261118150000.sql` e `05_conferir_…` (aba Contratados; pedido de contato só por vínculo verificado) | todas as linhas `ok = true` |

- Cada `aplicar` roda entre `begin` e `commit`, tem trava de versão e da anterior e registra a versão em `schema_migrations`.
- **Se algo falhar**, vale o mesmo do lote 1:
  - Erro no `aplicar`: nada foi gravado. Rode `rollback;` sozinho e avise o Back.
  - Erro de lock timeout: espere e rode de novo.
  - Erro "já está registrada": rode só o `conferir`.
  - `conferir` com `false`: pare e avise.
- Depois de cada passo, avise o Back. Ele move o arquivo de `supabase/pending` para `supabase/migrations` (feito em 2026-11-19).

## Rollbacks (`supabase/tests/rollback/`), na ordem inversa

| Ordem | Arquivo | Observação |
|---|---|---|
| R1 | `20261118150000_rollback.sql` | |
| R2 | `20261118140000_rollback.sql` | Empresas já reivindicadas continuam cadastradas. |
| R3 | `20261118130000_rollback.sql` | Relatos, pré-cadastradas e trilha de avisos ficam. |
| R4 | `20261118120000_rollback.sql` | Recusa se houver empresa pré-cadastrada. Exporte contatos, avisos, opt-outs e cache antes. |
| R5 | `20261117130000_rollback.sql` | Só com decisão registrada: reabre os casos para vínculo não verificado. Exige o R2 antes. |
