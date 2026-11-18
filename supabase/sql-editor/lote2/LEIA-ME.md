# Lote 2 no SQL Editor de produção: troca do gate (20261117130000)

O formato é o mesmo do lote 1 (`../LEIA-ME.md`, aplicado e conferido em 2026-11-18). O responsável roda os scripts no SQL Editor de produção. Não há db push nem backup: o risco foi aceito pelo responsável.

Por ora, o lote 2 tem só a 130000. As migrations da empresa pré-cadastrada (20261118120000 a 20261118140000, em `supabase/pending`) ganham scripts quando forem liberadas para aplicar.

## Antes de começar

1. Verifique, na fila de representantes da Operação, as 3 empresas reais do piloto. Depois deste passo, só o representante verificado vê manifestações, responde e vê os números da própria empresa. O script recusa rodar se não houver nenhum representante verificado.
2. Rode o teste em transação desfeita (`supabase/tests/tx/out/gate_tx.sql`), com liberação escrita do responsável na sessão do Back.

## Passo

| Passo | Arquivo | Esperado |
|---|---|---|
| 01 | `01_aplicar_20261117130000.sql` e depois `01_conferir_20261117130000.sql` | todas as linhas `ok = true` |

- **Se algo falhar**, vale o mesmo do lote 1:
  - Erro no `aplicar`: nada foi gravado. Rode `rollback;` sozinho e avise o Back.
  - Erro de lock timeout: espere e rode de novo.
  - Erro "já está registrada": rode só o `conferir`.
  - `conferir` com `false`: pare e avise.
- Depois de aplicado, avise o Back. Ele move o arquivo de `supabase/pending` para `supabase/migrations`.
- **Rollback:** `supabase/tests/rollback/20261117130000_rollback.sql`, só com decisão registrada, porque reabre os casos para vínculo não verificado.
