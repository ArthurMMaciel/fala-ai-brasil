# Lote 4 no SQL Editor de produção: avisos por e-mail às contas da plataforma (ADR-0020)

**Situação em 2026-11-24:**
- **00, extensões:** conferido.
- **01, fila (`20261123130000`):** aplicado em produção e conferido pelo responsável (itens 1 a 7) e, em leitura, pelo Back (versão, hash das instruções, tabela, gatilhos e contagens). A migration está em `supabase/migrations`. A fila já acumula avisos, sem enviar.
- **Secrets da função** (`GMAIL_USER`, `GMAIL_APP_PASSWORD` nova e só para as notificações, `NOTIFY_CRON_SECRET`) e **Vault** (`project_url`, `notify_cron_secret`): cadastrados pelo painel.
- **`send-notifications`:** publicada com `--no-verify-jwt`; POST sem segredo responde 401.
- **02, agendar:** rodado. A conferência deu tudo verdadeiro (job ativo a cada 5 minutos, rodada `succeeded` às 03:10 UTC, resposta 200). **Envio ligado.**

O formato é o mesmo dos lotes anteriores. A ordem segue o runbook [EMAIL_NOTIFICATIONS](../../../docs/runbooks/EMAIL_NOTIFICATIONS.md). O passo 02 é o que liga o envio e vem por último. Não há backup.

## Antes de começar

- O teste em transação desfeita `supabase/tests/tx/out/avisos_tx.sql` precisa passar, com liberação escrita do responsável na sessão do Back.
- A função `supabase/functions/send-notifications` precisa da revisão do DevOps.

## Ordem

| Passo | O quê | Quem |
|---|---|---|
| 00 | Habilitar `pg_cron` e `pg_net` no painel e rodar `00_conferir_extensoes.sql` | responsável |
| 01 | `01_aplicar_20261123130000.sql` e depois `01_conferir_20261123130000.sql` (fila, gatilhos, interface da função e opt-out). A partir daqui a fila acumula, sem enviar | responsável |
| — | Secrets da função no próprio terminal: `GMAIL_USER`, `GMAIL_APP_PASSWORD` e `NOTIFY_CRON_SECRET` | responsável |
| — | Publicar a `send-notifications` com `--no-verify-jwt` e testar com uma conta de teste (runbook EDGE_FUNCTION_DEPLOY) | responsável, com o DevOps |
| — | Criar pela tela do Vault `project_url` e `notify_cron_secret`, este com o mesmo valor de `NOTIFY_CRON_SECRET`. Não por SQL, para o valor não ficar no histórico | responsável |
| 02 | `02_agendar_envio.sql` e, uns 10 minutos depois, `02_conferir_agendamento.sql` | responsável |

## Se algo falhar

- **Erro no `aplicar` ou no `agendar`:** nada foi gravado. Rode `rollback;` sozinho e avise o Back.
- **Resposta 401 em `02_conferir_agendamento`:** o `notify_cron_secret` do Vault está diferente do `NOTIFY_CRON_SECRET` da função.
- **Linhas com `last_error_code = 'smtp_auth'`:** senha de app revogada ou conta bloqueada. Desligue o envio e siga o PILOT_SUSPENSION.

## Rollback

- **Desligar já:** `02_desligar_envio.sql`. As linhas ficam na fila.
- **Fila e opt-out:** `supabase/tests/rollback/20261123130000_rollback.sql`, depois de desligar o envio e apagar a função.
