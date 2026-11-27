# Lote 5 no SQL Editor de produção: até 3 contatos por manifestação (ADR-0023, revisão de 2026-11-26)

O formato é o mesmo dos lotes anteriores. Não há backup.

- **O que muda:**
  - o trabalhador pode indicar até 3 contatos da empresa por manifestação; o banco recusa o 4º;
  - cada contato tem e-mail e/ou telefone e a própria marca de "possivelmente envolvido";
  - o aviso à empresa não cadastrada continua 1 por manifestação e 1 por empresa a cada 30 dias, e a equipe escolhe o contato de destino (com e-mail e não envolvido) ou a Receita.
- **Compatível com o front em produção:** o formato antigo (um contato) continua aceito, e as funções de uma linha devolvem o contato padrão. O front novo usa `notice_contacts` e as funções `_list`.
- **Antes de rodar:** o teste em transação desfeita `supabase/tests/tx/out/contatos3_tx.sql`, com liberação escrita do responsável na sessão do Back. Ele já passou no banco local.

| Passo | Arquivo | Esperado |
|---|---|---|
| 01 | `01_aplicar_20261126120000.sql` e depois `01_conferir_20261126120000.sql` | todas as linhas `ok = true` |

- **Se algo falhar:**
  - Erro no `aplicar`: nada foi gravado. Rode `rollback;` sozinho e avise o Back.
  - `conferir` com `false`: pare e avise.
- **Rollback:** `supabase/tests/rollback/20261126120000_rollback.sql`. Recusa se alguma manifestação já tiver mais de 1 contato.
