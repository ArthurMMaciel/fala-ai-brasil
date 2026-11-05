# TASK-0031 — Implementar triagem humana antes da liberação à empresa

- Status: em-andamento
- ClickUp: [TASK-0031](https://app.clickup.com/t/17tu7rpb56w)
- Área: Backend/Segurança/Privacidade
- Prioridade: P0
- Alvo: 2026-11-18, condicionado à TASK-0030
- Relacionadas: TASK-0030, TASK-0029, TASK-0011, TASK-0006, TASK-0007, TASK-0009
- Decisão estrutural proposta: [ADR-0010](../adr/ADR-0010-revisao-humana-antes-do-compartilhamento.md)

## Problema

Hoje `create_complaint(..., true)` e `share_complaint(...)` tornam a versão compartilhável visível à empresa diretamente após ação do trabalhador. Não existe triagem humana, verificação do representante ou liberação auditada. A tela ainda pré-preenche a versão compartilhável com o relato original.

## Objetivo e sequência

Separar consentimento/preparação pelo trabalhador de liberação efetiva à empresa. Primeiro, remover o pré-preenchimento perigoso e corrigir a linguagem da interface. Depois, registrar ADR, modelar estados de revisão e autorização no servidor, implementar fila humana mínima e só então permitir liberação.

## Progresso em 2026-11-05

A versão compartilhável agora começa vazia tanto no assistente de nova manifestação quanto no compartilhamento posterior de uma manifestação guardada. O texto orienta a escrever uma versão separada, sem promessa absoluta de proteção de identidade. `npm test` passou (38 testes) e `npm run build` passou. Este ajuste reduz cópia acidental do original, mas ainda não impede envio direto pelo RPC; triagem e liberação server-side permanecem bloqueios P0.

## Critérios de aceite

- Versão compartilhável começa vazia e exige elaboração consciente; não há cópia automática do original.
- Caso solicitado para compartilhamento fica indisponível à empresa até decisão autorizada, inclusive via RPC direta.
- Operador tem papel mínimo, decisão auditada e não vê original por padrão.
- Alto risco não dispara contato externo automático.
- RLS/RPC negam leitura cruzada, acesso sem representante verificado e repetição indevida.
- Migração trata casos já compartilhados explicitamente; testes cobrem falha, concorrência e rollback.

## Riscos

Segurança/privacidade: críticos. Operação: fila humana, SLA e acesso excepcional. Dados: novos estados e trilha de auditoria. Custo: revisão por caso. Rollback: suspender novas liberações mantendo negação por padrão; não restaurar compartilhamento direto.
