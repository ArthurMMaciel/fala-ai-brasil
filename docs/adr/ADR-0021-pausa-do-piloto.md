# ADR-0021 — Pausa do piloto pela operação

- Estado: **Aceita**, pelo responsável em 2026-11-17 ("Aprovo todas", repassado pelo Gestor), com a pausa sem incluir o cadastro. Formulário de contato fora da pausa até decisão. Implementação: `20261117150000`, aplicada em produção em 2026-11-18 (lote 1 do SQL Editor).
- Tarefas: piloto fechado de 30/11 (go/no-go 25/11); relacionadas TASK-0009, TASK-0011, TASK-0029
- Relacionadas: ADR-0010 (revisão humana), ADR-0012 (representante e convite), ADR-0013 (resposta revisada)

## Contexto

O piloto abre com relato real. Se aparecer um incidente (vazamento, falha de isolamento, volume acima da capacidade da equipe, caso de alto risco sem tratamento), hoje a única forma de parar a entrada é tirar o site do ar ou alterar funções por SQL. As duas param também o acompanhamento dos casos já abertos.

## Decisão proposta

D1. **Interruptor no banco, não no front.** Uma linha de configuração da plataforma diz se o piloto está `open` ou `paused`. As funções de entrada leem esse estado e recusam com mensagem fixa quando pausado. O front só mostra o aviso; esconder botão sem gate no banco não conta como pausa.

D2. **O que a pausa suspende**:
- `create_complaint` (nova manifestação);
- `add_profile` e o cadastro de perfil novo em `private.create_profile` para trabalhador e empresa. Ver os riscos sobre o cadastro, que roda num gatilho do Auth;
- convites e lembretes da ADR-0012, quando existirem. Hoje não há envio automático;
- `submit_contact_solicitation` (formulário público), como opção do responsável.

D3. **O que a pausa preserva**:
- trabalhador: ver os próprios casos, reenviar ajuste (`share_complaint`), encerrar (`close_complaint`), avaliar resposta;
- empresa: ver casos já liberados e responder;
- equipe: tudo, inclusive liberar e revisar casos que já estavam na fila. A equipe pode, por decisão própria, segurar novas liberações com `held`, que já existe.
- Nenhum dado é apagado ou escondido.

D4. **Quem liga e desliga.** Só a equipe (`platform_admins`), por `ops_set_pilot_state(p_state, p_reason)`, com motivo obrigatório de 10 a 500 caracteres. Cada mudança grava, numa tabela só de inserção, quem, quando, estado anterior, novo estado e motivo. O motivo não deve conter conteúdo de relato.

D5. **Mensagem ao usuário.** Texto fixo, sem citar incidente: "Novas manifestações estão temporariamente suspensas. Quem já tem caso aberto continua acompanhando normalmente." O texto final fica com o responsável.

## Modelo previsto

| Objeto | Colunas | Quem lê | Quem escreve |
|---|---|---|---|
| `private.platform_settings` (linha única) | `pilot_state` (`open`/`paused`), `updated_at`, `updated_by` | funções `security definer`; público só via `public.pilot_state()` | `ops_set_pilot_state` |
| `public.pilot_state_log` | `id`, `previous_state`, `new_state`, `reason`, `actor_user_id`, `created_at` | equipe via `ops_*` | só `ops_set_pilot_state` (RLS ligada, sem policy, `revoke all`) |
| `public.pilot_state() → text` | — | anon e authenticated (o front precisa saber antes do formulário) | — |
| `private.assert_pilot_open()` | — | chamada no início das funções de D2 | — |

O estado inicial é `open`. Valores novos de check ou enum ficam em migration separada, conforme o padrão.

## Riscos

- **Cadastro pelo gatilho do Auth:** se `private.create_profile` recusar durante a pausa, o Supabase devolve erro genérico no signUp e a conta em `auth.users` não é criada. A alternativa é deixar o cadastro passar e bloquear só a manifestação. **Recomendação:** pausar só `create_complaint` e convites; manter cadastro aberto, salvo decisão contrária do responsável.
- **Pausa esquecida:** o estado aparece na tela da Operação e em `ops_metrics`. A trilha mostra desde quando.
- **Corrida:** uma manifestação iniciada antes da pausa e enviada depois é recusada. O front preserva o texto digitado e mostra a mensagem. Nada fica gravado pela metade, porque `create_complaint` é uma transação.
- **Abuso interno:** qualquer pessoa da equipe pode pausar. A trilha e o motivo obrigatório inibem; uma segunda pessoa para reabrir é opção do responsável.

## Testes de fumaça previstos

- pausado: `create_complaint` recusada para trabalhador;
- pausado: trabalhador ainda lê, reenvia ajuste, encerra e avalia; empresa lê e responde caso liberado; equipe libera caso da fila;
- não equipe não muda o estado; motivo curto recusado;
- cada mudança gera uma linha na trilha;
- `pilot_state()` responde para anon sem expor quem pausou nem o motivo;
- o isolamento da TASK-0006 continua passando com o piloto pausado.

## Rollback

Voltar o estado para `open` desfaz a pausa sem migration. Remover o recurso: as funções voltam à versão anterior (sem a chamada a `assert_pilot_open`) e as tabelas novas podem ser apagadas, perdendo só a trilha da pausa. Antes disso, exportar a trilha.

## Decisões que dependem do responsável

1. Se a pausa suspende também o cadastro de contas novas (recomendação: não).
2. Se o formulário público de contato entra na pausa.
3. Texto da mensagem ao usuário.
4. Se reabrir exige segunda pessoa da equipe.
