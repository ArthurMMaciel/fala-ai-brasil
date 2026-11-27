# Lote 5 no SQL Editor de produção: até 3 contatos e avisos por evento (ADR-0023 e ADR-0020, revisões de 2026-11-26)

O formato é o mesmo dos lotes anteriores. Não há backup.

- **Passo 01: até 3 contatos por manifestação.**
  - O trabalhador pode indicar até 3 contatos da empresa por manifestação; o banco recusa o 4º.
  - Cada contato tem e-mail e/ou telefone e a própria marca de "possivelmente envolvido".
  - O aviso à empresa não cadastrada continua limitado a 1 por manifestação e 1 por empresa a cada 30 dias.
  - A equipe escolhe o destino do aviso: um contato com e-mail e não envolvido, ou a Receita.
  - **Compatível com o front em produção:** o formato antigo (um contato) continua aceito, e as funções de uma linha devolvem o contato padrão. O front novo usa `notice_contacts` e as funções `_list`.
- **Passo 02: motivo do aviso e aviso automático à empresa não cadastrada.**
  - Cada linha da fila ganha um motivo fixo: liberação, resposta devolvida, encerramento ou novidade. Com ele, a send-notifications usa um texto curto por evento.
  - A aprovação de um aviso pela equipe (`ops_decide_notice`, com as mesmas travas de hoje) põe o envio na fila.
  - O e-mail de destino não fica gravado na fila: o banco o resolve no envio e confere de novo opt-out, empresa ainda não cadastrada nem bloqueada, e Receita diferente de contato envolvido.
  - Depois do envio, o aviso vira `sent`; depois da falha definitiva, vira `bounced`.
  - **Compatível com a função publicada:** a versão atual da send-notifications não recebe os avisos de empresa, que esperam na fila. Logo depois do passo 02, publique a versão nova da função (runbook `docs/runbooks/EMAIL_NOTIFICATIONS.md`).
  - A versão nova também funciona antes do passo 02, só sem os avisos.
- **Antes de rodar:** o teste em transação desfeita, com liberação escrita do responsável na sessão do Back:
  - `supabase/tests/tx/out/contatos3_tx.sql` cobre o passo 01;
  - `supabase/tests/tx/out/avisos2_tx.sql` cobre os passos 01 e 02 juntos.

  Os dois passaram no banco local.

| Passo | Arquivo | Esperado |
|---|---|---|
| 01 | `01_aplicar_20261126120000.sql` e depois `01_conferir_20261126120000.sql` | todas as linhas `ok = true` |
| 02 | `02_aplicar_20261126130000.sql` e depois `02_conferir_20261126130000.sql` | todas as linhas `ok = true`; em seguida, publicar a send-notifications |

- **Se algo falhar:**
  - Erro no `aplicar`: nada foi gravado. Rode `rollback;` sozinho e avise o Back.
  - `conferir` com `false`: pare e avise.
- **Rollback, na ordem inversa:**
  1. `supabase/tests/rollback/20261126130000_rollback.sql`: os avisos ainda não enviados saem da fila e continuam `approved`, para envio à mão.
  2. `supabase/tests/rollback/20261126120000_rollback.sql`: recusa se alguma manifestação já tiver mais de 1 contato.
