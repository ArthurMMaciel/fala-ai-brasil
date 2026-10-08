# ADR-0004 — Stripe como provedor de cobrança

- Estado: Aceita para escolha do provedor; desenho da integração proposto
- Data: 2026-10-07
- Decisor: responsável do projeto, conforme confirmação nesta sessão
- Tarefa: [TASK-0018](../tasks/TASK-0018-integracao-stripe-pagamentos.md)

## Contexto e decisão
O responsável escolheu Stripe para pagamento dos clientes dos planos e pacotes. A POC ainda não possui cobrança. Registrar a escolha permite refinamento e testes sintéticos; não autoriza cobrança real, uso de credenciais Stripe nem deploy.

## Desenho proposto
Checkout hospedado, catálogo autorizado no servidor e Billing para assinatura com cartão; webhook validado e processamento idempotente; direitos comerciais isolados por organização; conciliação e portal de gestão comercial. Essas escolhas de implementação serão validadas nas subtarefas antes de codificar.

## Limites e consequências
Pix avulso depende da habilitação da conta. Pix Automático não está disponível para contas brasileiras segundo a [documentação consultada](https://docs.stripe.com/payments/pix) em 2026-10-07. Renovação manual por Pix exige aprovação do modelo comercial; não equivale a débito automático.

Compartilhar somente dados mínimos de cobrança; nunca relatos ou identidade dos manifestantes. Dados de cartão ficam no provedor. Base legal, retenção, região/DPA, elegibilidade, custos e regras comerciais precisam de avaliação antes de produção. Trabalhador permanece gratuito.

## Alternativas e saída
Outros provedores não foram comparados: a seleção veio do responsável. Se a conta não atender a requisito obrigatório, registrar bloqueio e levar a decisão ao responsável. Preservar catálogo e registros de cobrança internos com IDs mapeados para permitir migração futura; não garantir portabilidade de métodos de pagamento.
