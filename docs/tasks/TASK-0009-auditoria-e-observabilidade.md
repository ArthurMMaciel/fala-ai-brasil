# TASK-0009 — Implementar auditoria e observabilidade

- Status: proposta
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
