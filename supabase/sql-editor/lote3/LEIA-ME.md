# Lote 3 no SQL Editor de produção: título do relato original fora da lista da empresa

O formato é o mesmo dos lotes 1 e 2. O responsável roda o script no SQL Editor de produção. Não há db push nem backup.

- **O que muda:** a empresa deixa de receber o título que o trabalhador escreveu no relato original (achado EAB-2026-1067). Na lista, no detalhe, na fila de atenção e no PDF, o título da empresa passa a ser "Manifestação EAB-…".
- **Antes de rodar:** o teste em transação desfeita `supabase/tests/tx/out/titulo_tx.sql`, com liberação escrita do responsável na sessão do Back.

| Passo | Arquivo | Esperado |
|---|---|---|
| 01 | `01_aplicar_20261123120000.sql` e depois `01_conferir_20261123120000.sql` | todas as linhas `ok = true` |

- **Se algo falhar:**
  - Erro no `aplicar`: nada foi gravado. Rode `rollback;` sozinho e avise o Back.
  - `conferir` com `false`: pare e avise.
- **Rollback:** `supabase/tests/rollback/20261123120000_rollback.sql`. Só com decisão registrada, porque volta a expor o título original.
- **Já exposto:** os títulos que as empresas já viram e os PDFs já gerados não têm como ser recolhidos.
