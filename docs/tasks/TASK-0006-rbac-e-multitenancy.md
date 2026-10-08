# TASK-0006 — Implementar RBAC e isolamento por organização

- Status: proposta
- ClickUp: [TASK-0006](https://app.clickup.com/t/86aktn721)
- Área: Segurança/Backend
- Prioridade: P1
- Estimativa: 5–8 dias
- Impacto: impede acesso entre empresas e papéis

## Problema
Admin, empresa e operação estão misturados; não existe tenant.
## Contexto
IDOR ou escalada exporia relatos sensíveis.
## Objetivo
Aplicar papéis e escopo organizacional server-side em cada recurso.
## Escopo
Organizations, memberships, policies, autorização por recurso e acesso excepcional auditado.
## Fora de escopo
ABAC complexo ou motor externo de políticas.
## Critérios de aceite
Matriz de acesso implementada; troca de ID/tenant falha; empresa nunca vê original/identidade.
## Riscos
Filtro de tenant esquecido e superpoder administrativo.
## Dependências
TASK-0005, TASK-0007 e TASK-0008.
## Segurança
Negação por padrão, IDs opacos e testes horizontais/verticais.
## Dados envolvidos
Organizações, memberships, casos e decisões de acesso.
## Observabilidade
Negações e acesso excepcional com actor/resource/request_id.
## Rollback
Desabilitar novos portais, mantendo negação; nunca relaxar política.
## Testes necessários
Matriz completa, IDOR, enumeração e mudanças concorrentes de membership.
## Definição de pronto
Revisão de segurança e testes de isolamento automatizados.
