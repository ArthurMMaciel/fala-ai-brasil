# Lote 6 no SQL Editor de produção: conta de empresa sem plano (2026-11-27)

O formato é o mesmo dos lotes anteriores. Não há backup.

- **O que muda:** `private.create_profile` deixa de criar assinatura no cadastro de empresa e na reivindicação de empresa pré-cadastrada. Isso vale para o cadastro novo e para a reivindicação.
  - Se o front mandar `plan_id` e `subscription_mode` nesse cadastro, eles são ignorados, então o front atual continua funcionando.
  - Parceiro e patrocinador não mudam: continuam exigindo plano.
- **O que não muda:**
  - nenhuma RLS, RPC, Edge Function ou agendamento depende de a empresa ter assinatura;
  - as assinaturas de empresa que já existem ficam como estão.
- **Antes de rodar:** o teste em transação desfeita, `supabase/tests/tx/out/empresa_sem_plano_tx.sql`, com liberação escrita do responsável na sessão do Back.

| Passo | Arquivo | Esperado |
|---|---|---|
| 01 | `01_aplicar_20261127140000.sql` e depois `01_conferir_20261127140000.sql` | todas as linhas `ok = true` |

- **Se algo falhar:**
  - Erro no `aplicar`: nada foi gravado. Rode `rollback;` sozinho e avise o Back.
  - `conferir` com `false`: pare e avise.
- **Rollback:** `supabase/tests/rollback/20261127140000_rollback.sql`. Ele volta a exigir plano no cadastro de empresa. As empresas cadastradas sem plano nesse intervalo ficam sem assinatura.
