# TASK-0017 — Implantar rotina de governança e manutenção técnica

- Status: proposta
- ClickUp: [TASK-0017](https://app.clickup.com/t/86aktn6eh)
- Lista ClickUp: Escuta Aí Brasil (`901329218347`); status remoto na criação: `to do`
- Área: Liderança técnica / Engenharia
- Prioridade: P1
- Responsável: liderança técnica do projeto
- Estimativa: 1–2 dias para implantação; revisão semanal de até 30 minutos
- Impacto: tornar prioridades, riscos e critérios de entrega verificáveis por uma equipe pequena.

## Problema
Existem tarefas para segurança, testes e fundação do MVP, mas falta uma rotina operacional da liderança técnica para acompanhar esses trabalhos, tratar bloqueios e manter documentação e execução alinhadas.

## Contexto
O projeto é uma POC local com dados sintéticos, mantida pelo responsável técnico e Codex. O ClickUp será usado para acompanhamento do trabalho, com referências aos documentos versionados. A existência de uma tarefa não comprova implementação nem autoriza piloto com dados reais.

## Objetivo
Implantar uma rotina leve de manutenção e revisão técnica com responsáveis, prioridades, evidências de conclusão e decisões pendentes visíveis no ClickUp.

## Escopo
- Definir revisão semanal de backlog, bloqueios, riscos e dívida técnica, com responsável e registro da próxima ação.
- Consultar o ClickUp antes de criar ou alterar tarefas; reutilizar tarefas equivalentes e manter referências cruzadas com `docs/tasks/`.
- Revisar o backlog existente e registrar a sequência imediata: XSS (TASK-0002), testes/CI (TASK-0004) e dependências (TASK-0012), respeitando as dependências documentadas.
- Documentar checklist de conclusão: critérios de aceite, validações proporcionais ao risco, revisão de segurança/privacidade, documentação e rollback quando aplicável.
- Definir comandos e evidências para verificar a saúde atual da POC; registrar ausência de testes/CI até sua implementação nas tarefas próprias.
- Registrar decisões humanas pendentes e aplicar os gates de `docs/ROADMAP.md` antes de promover trabalho para piloto.
- Executar e registrar um primeiro ciclo de revisão usando somente metadados técnicos e dados sintéticos.

## Fora de escopo
Implementar as tarefas existentes, importar automaticamente todo o backlog, alterar arquitetura ou autenticação, configurar deploy, contratar serviços, criar automações recorrentes ou enviar dados psicossociais ao ClickUp.

## Critérios de aceite
- Procedimento de manutenção versionado em `docs/runbooks/TECHNICAL_MAINTENANCE.md`, com responsável, frequência, comandos e forma de registro.
- Checklist de conclusão aplicável a mudanças futuras, com referência às regras do `AGENTS.md`.
- Primeiro ciclo registrado na tarefa do ClickUp, com riscos, bloqueios, prioridades e próxima ação vinculados às tarefas locais relevantes.
- Cada trabalho selecionado possui responsável, prioridade, critérios de aceite e vínculo local/ClickUp; duplicatas são verificadas antes da criação.
- Divergências entre código, memória e backlog são registradas com evidência e ação de correção.
- Decisões pendentes e bloqueios do piloto permanecem explícitos, sem tratar capacidades planejadas como implementadas.

## Riscos
- Segurança e privacidade: exposição de credenciais ou conteúdo sensível em descrição/comentários; compartilhar apenas metadados técnicos.
- Dados: divergência entre status local e ClickUp; reconciliar referências e evidências no ciclo semanal.
- Operação: burocracia ou dependência de uma pessoa; limitar a revisão a 30 minutos e manter procedimento reproduzível.
- Custo: chamadas e trabalho manual desnecessários; consultas sob demanda, sem novos serviços ou automações pagas.

## Dependências
Contexto, memória, roadmap e backlog existentes. TASK-0002, TASK-0004 e TASK-0012 são trabalhos acompanhados, não pré-requisitos para iniciar esta rotina.

## Segurança
Token pessoal do ClickUp permanece no `.env` ignorado pelo Git e é utilizado apenas em chamadas locais à API oficial. Nunca incluir o valor em logs, documentação ou front-end. Uso autorizado pelo responsável em 2026-10-07 para gestão técnica de tarefas.

## Dados envolvidos
Títulos, status, prioridades, critérios de aceite e referências técnicas. Nenhuma identidade, relato real, dado psicossocial ou credencial deve ser compartilhado.

## Observabilidade
Acompanhar tarefas sem responsável/critério de aceite, bloqueios sem próxima ação e divergências de status. Registrar resultado do ciclo e data da próxima revisão, sem conteúdo sensível.

## Rollback
Suspender o procedimento e preservar as tarefas/documentos e seus vínculos. Revogar o token no ClickUp se o acesso local precisar ser encerrado. Não excluir tarefas automaticamente.

## Testes necessários
Executar os comandos de saúde disponíveis e registrar resultados; simular triagem de duplicata e bloqueio com metadados sintéticos; verificar links e ausência de segredos nos documentos.

## Definição de pronto
Procedimento e checklist publicados no repositório, primeiro ciclo comprovado no ClickUp e sequência de trabalho registrada. A criação desta tarefa não significa que a rotina já foi implantada.
