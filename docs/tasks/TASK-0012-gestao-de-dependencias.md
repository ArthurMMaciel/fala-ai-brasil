# TASK-0012 — Implantar gestão de dependências

- Status: proposta
- Área: Segurança/DevOps
- Prioridade: P1
- Estimativa: 1–2 dias
- Impacto: reduz risco de supply chain e obsolescência

## Problema
Não há rotina automatizada de auditoria ou atualização.
## Contexto
O projeto tem poucas dependências, mas Vite 5.4.21 está em faixas afetadas por advisories do dev server publicados em 2026. O host atual é local (`127.0.0.1`), o que reduz, mas não elimina a necessidade de correção.
## Objetivo
Auditar lockfile no CI, receber PRs controlados e definir SLA por severidade.
## Escopo
Atualizar Vite/esbuild para linha corrigida após teste de compatibilidade; adicionar `npm audit`/scanner, Dependabot ou Renovate, revisão de licença e pinning de actions.
## Fora de escopo
Plataforma completa de SBOM no primeiro ciclo.
## Critérios de aceite
Vulnerabilidade alta/crítica gera sinal e tarefa; updates passam por build/teste; actions fixadas.
## Riscos
Ruído, updates automáticos inseguros e indisponibilidade de registry.
## Dependências
TASK-0001/0004.
## Segurança
Permissões mínimas, proteção contra scripts de instalação e provenance quando disponível.
## Dados envolvidos
Manifestos e metadados públicos.
## Observabilidade
Tempo para corrigir vulnerabilidade e idade de dependências.
## Rollback
Reverter update por lockfile/commit.
## Testes necessários
Pipeline com caso conhecido e PR de atualização de teste.
## Definição de pronto
Política documentada e automação sem merge automático em produção.
