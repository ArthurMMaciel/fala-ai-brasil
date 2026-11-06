# TASK-0029 — Definir convite seguro à empresa após manifestação

- Status: proposta
- Proposta de modelo: [ADR-0012](../adr/ADR-0012-representante-verificado-e-convite-a-empresa.md) (aguardando aprovação)
- ClickUp: [TASK-0029](https://app.clickup.com/t/17tu7rp9zge)
- Área: Produto/Privacidade/Integrações
- Prioridade: P0 para o piloto fechado de novembro
- Impacto: permitir participação empresarial sem expor o trabalhador
- Relacionadas: TASK-0011, TASK-0007, TASK-0009, TASK-0026, TASK-0027

## Problema
A proposta de enviar e-mail à empresa após a primeira manifestação pode revelar a existência ou o conteúdo de um caso a destinatário incorreto, inclusive a pessoa envolvida. Cadastro e pagamento não podem ser condição para tratar manifestação ou influenciar prioridade.

## Objetivo
Decidir o gatilho, a revisão, o destinatário verificado, o texto mínimo e o percurso da empresa até uma landing e eventual conta, sem revelar identidade, relato original ou detalhes antes da autorização e dos controles exigidos.

## Escopo
- Mapear estados: manifestação recebida, triagem de risco, versão compartilhável autorizada, contato empresarial verificado, revisão humana, envio, entrega/erro e acesso por representante legitimado.
- Propor e revisar o texto do primeiro convite e o link para a landing de Empresa; evitar “você recebeu uma denúncia sobre isso” e qualquer detalhe do caso no e-mail inicial.
- Definir alternativa manual para risco alto e quando o destinatário não for verificado; casos de alto risco não geram contato externo automático.
- Distinguir convite operacional de oferta comercial, sem vincular acesso ao caso a pagamento.
- Registrar ADR para comunicação, autorização e auditoria antes de implementar envio.

## Fora de escopo
Disparo automático agora, cobrança real, exposição de manifestação em landing pública ou envio de relato original.

## Critérios de aceite
- Fluxo aprovado documenta quem autoriza, verifica e audita cada envio; destinatário sugerido pelo trabalhador não é tratado como verificado.
- Nenhum e-mail inicial contém identidade, relato original, versão compartilhável ou detalhes identificáveis; link não permite enumerar casos.
- Risco alto bloqueia envio automático; erro, duplicidade, opt-out e contato incorreto têm procedimento.
- Empresa só acessa dados da própria organização e apenas a versão compartilhável autorizada; pagamento não altera tratamento ou prioridade.
- Testes de destinatário incorreto, link compartilhado, repetição, risco alto e acesso sem autorização estão definidos antes de implementação.

## Riscos e dependências
Segurança: phishing, enumeração e falha de tenancy. Privacidade/dados: retaliação e reidentificação. Operação: triagem humana, entrega e correção de envio indevido. Custo: e-mail e revisão manual. Depende da TASK-0011, decisão de canal/base legal e controles de autorização/auditoria.

## Testes e pronto
Pronto nesta fase quando política, texto, estados, responsáveis, ADR e casos de teste forem aprovados; implementação e envio ficam em etapa posterior.
