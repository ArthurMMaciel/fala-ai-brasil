# TASK-0009 — Implementar auditoria e observabilidade

- Status: proposta
- ClickUp: [TASK-0009](https://app.clickup.com/t/86aktn72e)
- Área: SRE/Segurança
- Prioridade: P1
- Estimativa: 4–6 dias
- Impacto: torna operação e acesso sensível rastreáveis

## Problema
Não há logs, métricas, alertas nem trilha confiável.
## Contexto
Auditoria simulada hoje é dado mock mutável.
## Objetivo
Separar telemetria técnica de eventos auditáveis e definir alertas essenciais.
## Escopo
Schema append-only, logs redigidos, métricas RED/jobs, dashboards e alertas mínimos.
## Fora de escopo
SIEM complexo e retenção longa sem requisito.
## Critérios de aceite
Ações críticas têm ator/ação/recurso/resultado; nenhum payload sensível aparece em logs; alertas testados.
## Riscos
Vazamento via telemetria e custo de ingestão.
## Dependências
TASK-0008 e TASK-0006.
## Segurança
Integridade, acesso restrito e relógio confiável.
## Dados envolvidos
Metadados de operação e segurança.
## Observabilidade
É o próprio escopo; incluir custo/volume.
## Rollback
Desativar exportação externa preservando auditoria local.
## Testes necessários
Redação, falha do exporter, eventos obrigatórios e alertas sintéticos.
## Definição de pronto
Plano implementado, dashboard mínimo e acesso revisado.

## Levantamento de trilhas existentes (2026-11-17, só leitura, sem migration)

Fonte: as migrations em `supabase/migrations/` (vale a última definição de cada função) e `src/`. Não existe `supabase/functions/`. Ficou fora o ambiente remoto (pgaudit, log do Postgres, log de Auth do Supabase); isso precisa de leitura em produção, que depende de liberação.

### Proteção comum às tabelas de trilha

As tabelas `complaint_reviews`, `original_access_log`, `company_response_reviews` e `profile_change_log` têm RLS ligada, nenhuma policy e `revoke all` de anon e authenticated. Só recebem insert, e só por funções `security definer`. O cliente não edita nem apaga. Ainda assim, não são append-only:
- não há trigger que bloqueie update ou delete, então o dono (SQL Editor) e o `service_role` podem alterar;
- `complaint_id ... on delete cascade`: apagar a manifestação apaga a trilha, e apagar a conta do trabalhador apaga as manifestações e, em cascata, as trilhas;
- `reviewer_id` e `actor_user_id` usam `on delete set null`, então quem operou se perde quando a conta é removida.

### Mapa

| Decisão ou acesso | Trilha hoje | Onde | Lacuna |
|---|---|---|---|
| Liberação da manifestação à empresa | Sim: revisor, decisão, motivo, data; evento com actor `platform` | `complaint_reviews`; `ops_decide_complaint` (20261106140000) | Motivo opcional na liberação; não fica registrado qual texto compartilhável foi liberado (reenvio após ajuste sobrescreve a versão) |
| Retenção, exclusão, anonimização | Não existe mecanismo nem trilha | — | Política e mecanismo inexistentes; exclusões em cascata somem sem registro |
| Revisão da resposta da empresa | Sim: revisor, decisão, resumo, motivo, data | `company_response_reviews`; `ops_decide_response`, `ops_correct_response_summary` (20261109170000) | Resumo atual é sobrescrito em `company_responses` (o anterior só sobrevive na trilha); conteúdo da resposta sem versão |
| Edição de perfil de trabalhador e empresa | Sim: ator, entidade, nomes dos campos, origem, justificativa, referência, data | `profile_change_log`; `update_worker_profile`, `update_company_profile`, `ops_change_document` | Sem valor anterior/novo (decisão C3); impossível reconstituir histórico |
| Criação de perfil e vínculo em `company_users` | Não | `add_profile`, `create_profile` | Inclusão de membro ou troca de papel só por SQL, sem trilha |
| Edição de parceiro, patrocinador, mídia, conexões | Não (só `updated_at`) | policies de update direto; `partner_set_connection` | Sem quem/quando por mudança |
| Leitura do relato original pela operação | Sim: justificativa obrigatória (10 a 500), revisor, data, na mesma transação da leitura | `original_access_log`; `ops_read_original` | Leitura direta da tabela pelo SQL Editor ou `service_role` não registra; pgaudit não verificado |
| Quem vira equipe ou responsável por documento; login da equipe | Não: `private.platform_admins` e `private.document_officers` só têm `created_at` | concessão por SQL manual | Sem quem concedeu, motivo ou revogação (revogar é delete); login não verificado no Auth remoto |
| Encerramento pela pessoa trabalhadora | Sim: evento com actor `worker` | `close_complaint` | `worker_feedback` sobrescrito |
| Avaliação da resposta | A própria linha em `response_ratings` | `rate_response` | Sem histórico próprio |
| Sinalização de alto risco | Não existe no modelo | — | Decisão não modelada (ver ADR-0012 e a pausa do piloto) |
| Campanhas e contato comercial | Parcial: `reviewed_at`/`review_note`; `contacted_by`/`contacted_at` | migrations de campanhas e `set_contact_solicitation_status` | Sem revisor nas campanhas; voltar o contato a `waiting_contact` apaga quem e quando |

### Conteúdo do relato em trilhas e logs

- Nenhuma tabela de trilha copia, de forma estruturada, o relato original, a versão compartilhável, o título ou a identidade. As notas de `complaint_events` são textos fixos. `profile_change_log` guarda só nomes de campo.
- Há texto livre que pode receber trecho do relato se a equipe ou a empresa o digitar:
  - `complaint_reviews.reason`, que é concatenado na nota do evento visível ao trabalhador;
  - `original_access_log.justification`, cujo placeholder em `src/portals/ops-portal-live.tsx` convida a descrever o conteúdo;
  - `company_response_reviews.reason/worker_summary`;
  - `response_ratings.comment`;
  - `profile_change_log.evidence_ref`, que pode receber número de documento.
- Funções: só `raise exception` com mensagens fixas, sem `raise notice/log`. Front: nenhum `console.*`, nenhuma telemetria ou analytics, nenhum storage do navegador.

### Defeito encontrado

`ops_decide_complaint` grava a nota `'Ajuste solicitado pela equipe: ' || v_reason`. O prefixo tem 31 caracteres, a nota aceita até 500 e o motivo também. Um motivo com mais de 469 caracteres faz o pedido de ajuste falhar com erro de check. A correção é pequena (limitar o motivo a 469 ou não concatenar) e pede migration aprovada.

### Lacunas priorizadas para o piloto (proposta, sem migration)

1. Trilha que sobreviva à exclusão: trocar cascade por restrict ou anonimização nas trilhas, ou copiar para uma trilha sem FK. Depende da política de retenção (decisão do responsável).
2. Bloquear update e delete nas tabelas de trilha com trigger, inclusive para o dono, salvo rotina de retenção registrada.
3. Concessão e revogação de equipe e de responsável por documento por função com trilha (quem, motivo, quando).
4. Registro do texto compartilhável efetivamente liberado (hash ou versão) na decisão de liberação.
5. Orientação no front para que justificativas e motivos não reproduzam o relato; limite o defeito do motivo.
6. Verificar, com liberação, o log de Auth e o pgaudit no projeto remoto.
