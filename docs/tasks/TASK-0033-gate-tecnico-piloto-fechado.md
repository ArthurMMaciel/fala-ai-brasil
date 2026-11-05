# TASK-0033 — Validar gate técnico e operar piloto fechado de novembro

- Status: proposta
- ClickUp: [TASK-0033](https://app.clickup.com/t/17tu7rpb56y)
- Área: QA/Segurança/DevOps/Operação
- Prioridade: P0
- Alvo de avaliação: 2026-11-25; abertura condicionada a evidências
- Relacionadas: TASK-0002, TASK-0004, TASK-0005, TASK-0006, TASK-0007, TASK-0009, TASK-0010, TASK-0011, TASK-0029, TASK-0031

## Objetivo

Liberar um piloto por convite, com poucas empresas verificadas e capacidade operacional definida, somente após prova dos controles. Esta tarefa não autoriza deploy público nem uso de dados reais sozinha.

## Gate de entrada de casos reais

- Escopo, base legal, aviso, retenção e responsáveis aprovados.
- XSS e fluxos de autenticação revistos; sessão e acesso entre duas empresas testados.
- Relato original isolado; versão compartilhável só liberada após triagem e verificação.
- Convite mínimo e manual/assistido aprovado; alto risco sem contato automático.
- Auditoria de decisões e acessos sem conteúdo sensível em logs.
- Backup e restauração em ambiente isolado testados; runbook de incidente e suspensão disponível.
- Fluxo ponta a ponta ensaiado com dados fictícios: trabalhador, operação, empresa, resposta, pedido opcional de orientação, erros e revogação.
- Responsáveis de plantão, limite de casos por dia e critério de pausa definidos.

## Decisão go/no-go

Registrar evidências, pendências, riscos residuais e aprovadores técnico, produto, operação e jurídico. Qualquer bloqueio mantém demonstração com dados sintéticos. Abertura de remoto, deploy público e credenciais exigem decisão humana conforme AGENTS.md.

## Riscos e rollback

Segurança/privacidade: exposição de dados sensíveis. Operação: triagem sem capacidade. Custo: backup, e-mail, suporte e horas humanas. Rollback: suspender novas entradas e convites, preservar casos existentes e trilhas, comunicar envolvidos conforme runbook aprovado.
