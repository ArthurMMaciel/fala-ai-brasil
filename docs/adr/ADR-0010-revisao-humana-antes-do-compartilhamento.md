# ADR-0010 — Revisão humana antes de liberar manifestação à empresa

- Estado: Proposta para o piloto fechado de novembro de 2026
- Data: 2026-11-05
- Tarefas: [TASK-0030](../tasks/TASK-0030-fluxos-operacionais-piloto-trabalhador-empresa.md), [TASK-0031](../tasks/TASK-0031-triagem-humana-e-liberacao-segura.md), [TASK-0029](../tasks/TASK-0029-convite-seguro-a-empresa-apos-manifestacao.md)
- Relacionada: ADR-0009

## Contexto

O modelo v3 persiste relato original e versão compartilhável em tabelas distintas. Hoje o trabalhador pode tornar a versão compartilhável imediatamente visível à empresa por `create_complaint(..., true)` ou `share_complaint(...)`. A empresa lê por RPC com escopo organizacional. Não há papel de revisor humano, prova de representação da empresa, triagem de risco ou auditoria de liberação. O primeiro convite empresarial ainda não está implementado. A apresentação comercial propôs cobrar por acesso, mas a orientação atual define leitura e resposta gratuitas, com orientação humana opcional.

## Problema

A confirmação do trabalhador é necessária, mas não comprova que o texto está livre de detalhes identificáveis nem que o destinatário é seguro. A liberação direta pode causar exposição e retaliação. Uma correção apenas no navegador não impede chamada direta às RPCs.

## Opções

1. Manter compartilhamento imediato e acrescentar avisos na interface: rápida, mas não controla a fronteira de dados.
2. Acrescentar estados de revisão e RPCs autorizadas no PostgreSQL/Supabase atual, com fila humana mínima: menor mudança estrutural no MVP, porém aumenta responsabilidade de RLS, funções e operação.
3. Criar API própria antes do piloto: melhor separação de camadas, porém exige nova implantação, autenticação, observabilidade e manutenção no prazo curto.

## Decisão proposta

Adotar a opção 2 para o piloto fechado, sujeita à validação de produto, operação e jurídico:

- Separar **preparação/solicitação** pelo trabalhador de **liberação** para a empresa. Criar estado persistido de revisão, sem acesso empresarial enquanto pendente, retido ou em ajuste.
- O trabalhador mantém a escolha de guardar sem compartilhar. Quando solicitar compartilhamento, a versão passa à fila de revisão; a própria solicitação não envia contato externo.
- Um papel interno de revisão, concedido fora do cadastro público, lê por padrão somente a versão candidata, metadados mínimos e indicadores necessários. Acesso ao original exige via excepcional, justificativa e auditoria própria.
- Operador autorizado registra decisão, motivo e responsável em transação. Aprovação requer verificação de empresa/representante e resultado de triagem; risco alto não aciona contato externo automático.
- `list_company_complaints`, timeline e ranking incluem apenas casos efetivamente liberados. Nenhuma função exposta pode pular o gate, inclusive a API RPC direta.
- Convite inicial contém somente informação mínima e usa destino verificado, conforme TASK-0029. No piloto, a comunicação pode ser manual assistida; automatização exige avaliação posterior.
- Leitura e resposta empresariais não dependem de pagamento. Pedido de orientação especializada é fluxo comercial separado.

## Migração e verificação

1. Inventariar casos atuais e confirmar que são somente fictícios antes de migrar. Não presumir que `status = shared` já passou por revisão.
2. Adicionar estado/registro de revisão e privilégios sem abrir leitura empresarial nova. Fazer migração expand/contract e negar liberação por padrão.
3. Atualizar criação e compartilhamento para solicitar revisão; criar RPC transacional de decisão com verificação server-side do papel e do destino.
4. Ajustar portais e mensagens, testar dois tenants, ator sem papel, repetição/concorrência, caso de alto risco, contato incorreto e ausência de consentimento.
5. Ensaiar com dados sintéticos; registrar evidências no gate da TASK-0033. O deploy público e casos reais requerem autorização separada.

## Consequências

Introduz fila e custo humano por manifestação, estado adicional, migração e procedimento de pausa. Mantém Supabase e as tabelas separadas já existentes; não cria novo fornecedor ou infraestrutura paga. Prazo de resposta dependerá de capacidade operacional aprovada.

## Riscos e decisões pendentes

- Definir categorias e sinais de alto risco, responsável pela triagem e cobertura fora do expediente.
- Definir quem pode aprovar, como comprovar representação empresarial e como revogar acesso.
- Fechar base legal, aviso ao trabalhador, retenção, exclusão e responsabilidades entre organizações.
- Não publicar promessa de anonimato absoluto. Mesmo texto sem nome pode reidentificar por contexto.
- Confirmar destino e política de tratamento de casos existentes antes de aplicar migração.

## Rollback

Suspender novas liberações e convites preservando casos e auditoria. Nunca restaurar o compartilhamento imediato como mecanismo de rollback. Se a fila ficar indisponível, novos pedidos permanecem pendentes e a operação comunica atraso pelo canal aprovado.
