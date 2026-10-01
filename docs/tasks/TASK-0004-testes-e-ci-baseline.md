# TASK-0004 — Criar baseline de testes e CI

- Status: proposta
- Área: QA/DevOps
- Prioridade: P1
- Estimativa: 2–3 dias
- Impacto: reduz regressão e torna mudanças verificáveis

## Problema
Não existem testes, lint ou pipeline.
## Contexto
A POC já possui múltiplos fluxos e código monolítico.
## Objetivo
Automatizar build, typecheck, testes e verificação de dependências.
## Escopo
Runner leve, testes das regras críticas, smoke dos fluxos e workflow CI.
## Fora de escopo
Cobertura arbitrária de 100% e matriz multi-browser extensa.
## Critérios de aceite
PR/branch executa checks; falha bloqueia merge; documentação de execução local.
## Riscos
Testes frágeis acoplados à marcação.
## Dependências
Git/remoto.
## Segurança
CI com permissões mínimas, dependências fixadas e sem secrets em forks/logs.
## Dados envolvidos
Fixtures sintéticas.
## Observabilidade
Tempo/taxa de falha do pipeline.
## Rollback
Workflow pode ser desabilitado preservando comandos locais.
## Testes necessários
Provar falha e sucesso de cada check.
## Definição de pronto
Build, testes e scan básico reproduzíveis localmente e no CI.
