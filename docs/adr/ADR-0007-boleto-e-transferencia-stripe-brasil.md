# ADR-0007 — Boleto e transferência bancária na cobrança brasileira

- Estado: Boleto aprovado para investigação; transferência bancária genérica bloqueada até validação da conta
- Data: 2026-10-08
- Tarefa: [TASK-0018](../tasks/TASK-0018-integracao-stripe-pagamentos.md)
- Estudo: [ESTUDO-BOLETO-E-TRANSFERENCIA-STRIPE-BRASIL](../analysis/ESTUDO-BOLETO-E-TRANSFERENCIA-STRIPE-BRASIL.md)

## Decisão comercial relacionada
O período gratuito das personas comerciais passa a ser de um mês de calendário. A cobrança mensal começa no segundo mês; continuam disponíveis mensal imediato e anual com 5% de desconto sobre doze mensalidades. Funcionário permanece gratuito.

## Decisão técnica
Boleto entra no desenho de cobrança para conta brasileira em BRL. A Stripe documenta elegibilidade BR, Checkout, Billing, Invoicing, Subscriptions e Customer Portal; confirmação é assíncrona e o boleto exige ação do cliente em cada ciclo. O sistema não libera direito pago por redirect ou geração de boleto, somente após webhook validado e conciliação interna.

Transferência bancária genérica da Stripe não é assumida como disponível. A matriz oficial consultada lista Bank transfers em EUR, GBP, JPY, MXN e USD e não lista Brasil/BRL. O método permanece bloqueado para promessa ou implementação até evidência no Dashboard da conta brasileira ou confirmação formal da Stripe.

## Fluxo aprovado para investigação
Checkout/Billing gera boleto e página hospedada; servidor salva IDs, valor, vencimento e estado; Stripe confirma pagamento por eventos assíncronos; backend deduplica, valida organização/valor/moeda/produto e ativa direitos. Para recorrência, avaliar `send_invoice`/Invoicing com vencimento e carência. Não tratar boleto como débito automático.

## Controles obrigatórios
- Boleto pendente não ativa assinatura paga.
- Webhooks verificados por assinatura, persistidos antes do ACK e idempotentes.
- Estados separados para boleto, fatura, pagamento e direito.
- Metadata sem relatos, identidade, diagnóstico ou conteúdo psicossocial.
- Valor e Price IDs determinados no servidor.
- Reemissão, vencimento, pagamento a maior/menor e reconciliação com operação auditada.
- A documentação consultada indica ausência de reembolso padrão de Boleto; política de devolução precisa de validação financeira/contábil antes do go-live.

## Alternativas
Transferência bancária direta da empresa, fora da Stripe, exigiria integração bancária ou conferência manual e tarefa própria. Outro PSP brasileiro exigiria nova decisão de provedor, comparação de custo/risco e plano de saída.

## Consequências
O MVP ganha um método B2B brasileiro com confirmação bancária delegada à Stripe, mas precisa operar atrasos, vencimentos e renovação manual. A conciliação e o acesso comercial tornam-se mais complexos que no cartão. Nenhuma cobrança real é autorizada por este ADR.
