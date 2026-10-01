# TASK-0008 — Criar fundação da API e PostgreSQL

- Status: proposta
- Área: Arquitetura/Backend/DBA
- Prioridade: P1
- Estimativa: 5–8 dias
- Impacto: cria núcleo persistente do MVP

## Problema
Não há backend, API ou banco.
## Contexto
Documentos legados propõem Go/PostgreSQL, ainda sem ADR aceita.
## Objetivo
Criar monólito modular mínimo, banco, migrações, config, erros e health checks.
## Escopo
ADR de stack, servidor, conexão, migrations, transações, config e ambiente local.
## Fora de escopo
Todas as features, broker e Kubernetes.
## Critérios de aceite
Setup reproduzível; health/readiness; migração up/down; erro padronizado; shutdown gracioso.
## Riscos
Stack prematura e ambiente complexo.
## Dependências
TASK-0001 e decisões de TASK-0007.
## Segurança
Usuário DB mínimo, TLS por ambiente, secrets fora do repo e queries parametrizadas.
## Dados envolvidos
Somente esquema/fixtures sintéticas inicialmente.
## Observabilidade
Logs estruturados, request_id, latência e pool DB.
## Rollback
Migrações reversíveis e remoção isolada do serviço.
## Testes necessários
Unitários, integração com DB, health, config inválida e shutdown.
## Definição de pronto
CI verde, documentação local e ADR aceita.
