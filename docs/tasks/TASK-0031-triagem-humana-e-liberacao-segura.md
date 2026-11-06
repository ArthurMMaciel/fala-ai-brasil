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

## Progresso em 2026-11-06

Modelo aprovado e implementado (ADR-0010): estados de revisão, fila e decisões da equipe com trilha, acesso ao original com justificativa, área de Operação com visão geral, fila, manifestações, empresas e solicitações de contato. Migrations 20261106130000/130100 aplicadas no remoto (confirmado por `migration list` na mesma data); teste de fumaça validado em banco local (ver abaixo).

### Validação e correções (2026-11-06, tarde)

- `supabase migration list` (somente leitura) mostra as 11 migrations até 20261106130100 aplicadas no projeto remoto, inclusive 20261105170000 (`contact_solicitations`), que a ADR-0011 condicionava a decisões de privacidade.
- Banco local descartável (`supabase start`, Docker) criado do zero com as 11 migrations e a nova `20261106140000_revisao_lock_e_ranking.sql`, sem erro.
- Migration 20261106140000 (só `create or replace`, sem mudança de tabela, política ou permissão):
  - `ops_decide_complaint` lê o status com `for update`: decisões simultâneas não geram duas decisões nem dois eventos; a segunda recebe erro.
  - `company_ranking` mede a primeira resposta a partir do primeiro evento `shared` (liberação), não da criação; casos antigos sem esse evento usam a criação.
- Testes de fumaça locais: `rls_smoke` 12/12, `campaigns_smoke` 8/8, `complaints_smoke` 13/13, `content_contact_smoke` 8/8, `ops_review_smoke` 21/21 (4 casos novos: decisão repetida recusada, trava da linha, uma única liberação e ranking a partir da liberação). `npm test` 42/42 e build sem erro.
- A concorrência foi verificada pela definição da função e pela recusa de decisão repetida; não houve teste com duas conexões simultâneas.
- Pendente: aplicar 20261106140000 no remoto (requer autorização), verificação de representante (TASK-0011) e convite seguro (TASK-0029).

## Critérios de aceite

- Versão compartilhável começa vazia e exige elaboração consciente; não há cópia automática do original.
- Caso solicitado para compartilhamento fica indisponível à empresa até decisão autorizada, inclusive via RPC direta.
- Operador tem papel mínimo, decisão auditada e não vê original por padrão.
- Alto risco não dispara contato externo automático.
- RLS/RPC negam leitura cruzada, acesso sem representante verificado e repetição indevida.
- Migração trata casos já compartilhados explicitamente; testes cobrem falha, concorrência e rollback.

## Riscos

Segurança/privacidade: críticos. Operação: fila humana, SLA e acesso excepcional. Dados: novos estados e trilha de auditoria. Custo: revisão por caso. Rollback: suspender novas liberações mantendo negação por padrão; não restaurar compartilhamento direto.
