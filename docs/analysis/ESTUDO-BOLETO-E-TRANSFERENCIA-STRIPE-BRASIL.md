# Estudo — boleto e transferência bancária na Stripe para o Brasil

- Data da verificação: 2026-10-08
- Escopo: cobrança de empresas, parceiros, Intelligence, Estudos e Patrocínio; funcionário permanece gratuito.
- Regra comercial atual: 1 mês de calendário grátis; depois cobrança mensal; mensal imediato; anual com 5% de desconto sobre doze mensalidades.
- Decisão: boleto entra como método elegível para investigação da integração Stripe. Transferência bancária genérica não entra como promessa até confirmação específica da conta brasileira e da moeda BRL.

## Resposta executiva

**Boleto:** sim, a Stripe documenta suporte para conta empresarial no Brasil, cliente no Brasil e BRL. A Stripe gera o boleto/voucher, apresenta uma página hospedada e PDF/número para o cliente, recebe a confirmação do pagamento pela infraestrutura bancária e envia eventos assíncronos para o nosso backend. A confirmação pode levar até 1 dia útil e a liquidação indicada pela documentação é de até 2 dias úteis (T+2). O boleto pode ser usado em Checkout, Payment Intents, Billing, Invoicing, Subscriptions e Customer Portal.

**Transferência bancária:** a resposta é diferente. A documentação geral de Bank transfers descreve contas bancárias virtuais, saldo do cliente e conciliação automática, mas a matriz oficial de suporte lista apenas EUR, GBP, JPY, MXN e USD e não lista BRL nem conta empresarial no Brasil. Portanto, não devemos dizer que a Stripe está pronta para receber uma transferência TED/DOC brasileira em BRL até a conta confirmar essa capacidade no Dashboard ou com o suporte da Stripe.

**O que a Stripe não fará sozinha:** ela não vai “mandar um boleto para nós” como um processo financeiro completo. Ela cria os objetos e links do boleto e envia webhooks ao endpoint do nosso servidor. Nós teremos de persistir a cobrança, associá-la à organização e ao pedido, deduplicar eventos, avisar pessoas autorizadas, liberar direitos somente após confirmação, tratar vencimento, inadimplência, conciliação e auditoria.

## Evidência oficial consultada

- [Boleto payments](https://docs.stripe.com/payments/boleto): Brasil/BRL, mínimo R$ 5,00, máximo R$ 49.999,99, confirmação até 1 dia útil, liquidação até T+2, recorrência suportada, Checkout/Billing/Invoicing/Subscriptions/Customer Portal suportados, vencimento padrão de 3 dias configurável entre 0 e 60 dias, e ausência de reembolso padrão para Boleto.
- [Payment method support](https://docs.stripe.com/payments/payment-methods/payment-method-support): Boleto aparece como BRL/BR/BR; Bank transfers aparecem em EUR, GBP, JPY, MXN e USD, sem BRL/BR.
- [Bank transfer payments](https://docs.stripe.com/payments/bank-transfers): transferências usam conta bancária virtual e customer balance, têm confirmação atrasada, podem receber valor a maior ou menor e exigem reconciliação; a própria página não lista o Brasil nas moedas/localizações suportadas.
- [Subscriptions com bank transfer](https://docs.stripe.com/billing/subscriptions/bank-transfer): o modelo usa `send_invoice`, `days_until_due` e `customer_balance`; o cliente precisa abastecer o saldo a cada fatura.
- [Boleto pricing](https://stripe.com/br/pricing/local-payment-methods): a página brasileira mostra R$ 3,45 por boleto pago; tarifas e elegibilidade contratuais precisam ser confirmadas na conta.
- [Events](https://docs.stripe.com/api/events/types): Checkout com método assíncrono usa `checkout.session.async_payment_succeeded`/`async_payment_failed`; assinaturas e faturas usam, entre outros, `invoice.paid`, `invoice.payment_failed`, `customer.subscription.updated` e `customer.subscription.deleted`.

## Boleto: fluxo recomendado para a Escuta Aí Brasil

### Contratação avulsa ou primeira mensalidade

1. O usuário escolhe a organização, produto, plano, modalidade e Boleto.
2. O servidor verifica sessão, organização, catálogo e preço aprovado. O navegador nunca envia preço, tenant ou `Price ID` arbitrário.
3. O servidor cria ou recupera o Customer Stripe e cria Checkout Session/PaymentIntent em BRL com Boleto habilitado e uma chave de idempotência vinculada ao pedido.
4. A Stripe gera o PaymentIntent, o número do boleto e os detalhes de apresentação. O servidor salva somente os IDs técnicos, valor, moeda, vencimento, estado e URL autorizada do boleto; nunca relato ou identidade de manifestante em metadata.
5. A plataforma mostra “boleto gerado — aguardando pagamento”, permite abrir/baixar o boleto e informa o vencimento. Gerar boleto não é pagamento confirmado e não libera o plano pago.
6. O cliente paga em banco, caixa eletrônico, agência ou internet banking. A Stripe recebe a confirmação bancária de forma assíncrona.
7. O webhook chega ao backend. O backend verifica assinatura do webhook sobre o corpo bruto, persiste o evento, deduplica por `event.id` e operação, valida Customer, pedido, organização, valor, moeda e produto e só então marca o pagamento como pago e ativa o direito comercial.
8. O backend atualiza a conta, registra auditoria técnica e dispara uma notificação mínima para o administrador financeiro autorizado. A notificação não inclui conteúdo psicossocial.

### Renovação recorrente

Existem dois desenhos e eles não devem ser confundidos:

- **Boleto como método recorrente em Billing/Subscriptions:** a Stripe documenta Boleto como recorrente, mas cada ciclo continua sendo uma cobrança assíncrona. Precisamos confirmar na conta o comportamento de renovação, prazo, emissão, notificações e estado da assinatura.
- **Fatura enviada (`send_invoice`):** é o desenho mais explícito para cobrança corporativa por boleto. Cada ciclo gera fatura, vencimento e página hospedada; o acesso continua ativo somente enquanto a fatura estiver paga conforme a política de carência.

Boleto não é débito automático. Ele exige ação do cliente em cada ciclo. Para o primeiro MVP, a recomendação é tratar boleto recorrente como **fatura por ciclo**, com vencimento e carência definidos, em vez de prometer renovação automática.

## Estados que o nosso domínio precisa ter

Não usar um único `status` para representar tudo:

| Objeto interno | Estados mínimos |
|---|---|
| Pedido | criado, checkout_aberto, aguardando_pagamento, pago, expirado, cancelado |
| Boleto | gerado, disponível, vencido, pago, falho, cancelado |
| Fatura | rascunho, aberta, paga, vencida, incobrável, anulada |
| Pagamento | pendente, confirmado, falho, reembolsado, contestado/irregular |
| Assinatura/direito | trialing, pendente, ativo, em_carência, suspenso, cancelado, encerrado |

Durante o mês grátis, a assinatura pode estar `trialing`, mas não é pagante. Ao final de 1 mês, a cobrança mensal ou anual precisa de uma regra aprovada. Se o boleto estiver pendente, o direito não deve virar “ativo pago” por causa do redirect ou da geração do PDF.

## Webhooks e idempotência

Para Checkout assíncrono, considerar `checkout.session.completed` apenas como sessão concluída, não como confirmação universal de pagamento; usar `checkout.session.async_payment_succeeded` para método atrasado. Para Billing/Invoicing, considerar `invoice.paid`, `invoice.payment_failed`, `invoice.overdue`, `invoice.voided`, `customer.subscription.updated` e `customer.subscription.deleted`, conforme o fluxo final. A lista definitiva deve ser testada no sandbox.

Cada evento precisa de:

- assinatura Stripe verificada por ambiente;
- corpo bruto preservado apenas durante a verificação;
- registro técnico mínimo do `event.id`, tipo, objeto relacionado e timestamps;
- deduplicação por evento e por efeito de negócio;
- transação que atualiza pagamento, fatura e direito sem dupla ativação;
- retry com backoff e fila de falha;
- consulta do estado atual Stripe quando eventos chegarem fora de ordem;
- resposta rápida `2xx` somente depois de persistir o evento de forma segura.

## Vencimento, lembretes e inadimplência

Antes de ligar Boleto, decidir:

- validade do boleto: a documentação indica padrão de 3 dias e faixa configurável de 0–60;
- quando enviar lembrete antes e depois do vencimento;
- se o período de carência mantém acesso comercial;
- se o vencimento suspende apenas módulos comerciais ou também usuários administrativos;
- se um novo boleto substitui o anterior ou cria nova fatura;
- se boleto vencido pode ser pago, cancelado ou precisa ser recriado;
- quem pode reemitir, conceder desconto ou marcar pagamento manual;
- como a plataforma trata pagamento após vencimento, pagamento a maior, duplicidade e boleto de valor errado.

Minha recomendação de primeira política: boleto vence em prazo curto aprovado pelo financeiro; o plano fica `pending` antes do primeiro pagamento; renovações entram em carência limitada; vencido o prazo, suspende-se o direito comercial novo sem apagar dados nem afetar o acesso gratuito do funcionário; reemissão cria uma nova tentativa vinculada à mesma fatura ou a uma nova fatura conforme a regra contábil.

## Reembolso e risco operacional

A documentação oficial de Boleto indica ausência de reembolso parcial ou total pelo fluxo padrão. Isso muda a operação: a política comercial deve dizer como devolver valores, se necessário, por processo financeiro separado e auditado. Não marcar o boleto como “reembolsado” sem prova externa da devolução. Pagamento confirmado não significa que o dinheiro possa ser devolvido pelo mesmo método automaticamente.

Boleto também não tem chargeback padrão, mas a Stripe pode contatar a empresa em caso de irregularidade bancária. Deve existir uma fila financeira para investigar divergências e não uma ativação irreversível.

## Transferência bancária: opções reais

### Opção A — Transferência Stripe nativa

Não assumir disponibilidade no Brasil. A matriz oficial atual não lista BRL/BR para Bank transfers. Só pode entrar no produto se a conta brasileira mostrar a capacidade no Dashboard, com moeda, produto e termos compatíveis confirmados pela Stripe. Se habilitada, o desenho seria Customer + customer balance + funding instructions + invoice/PaymentIntent + reconciliação automática/manual.

### Opção B — Transferência direta para banco da empresa

É possível operacionalmente, mas fica fora da Stripe. A plataforma teria de gerar instruções, identificar o pedido, receber comprovante ou extrato, conferir titular/valor/data, aprovar manualmente ou integrar com o banco, e manter conciliação e antifraude próprios. Não devemos liberar acesso apenas porque alguém anexou um comprovante. Isso cria custo, risco de fraude e responsabilidade operacional; exige provedor bancário, base legal, controles e tarefa própria.

### Opção C — Outro PSP brasileiro

Pode oferecer TED/Pix/boleto com recursos locais, mas seria uma nova decisão de provedor. O contrato, tarifas, liquidação, webhooks, antifraude, fiscal e plano de saída precisariam ser avaliados. Não trocar a Stripe automaticamente; registrar comparação e aprovação.

## Comparação para decisão

| Critério | Boleto Stripe | Transferência Stripe | Transferência manual |
|---|---|---|---|
| Conta BR/BRL | Documentada como suportada | Não aparece na matriz oficial | Depende do banco da empresa |
| Geração de cobrança | Stripe gera voucher/PDF/URL | Stripe gera instruções se elegível | Plataforma/banco |
| Confirmação | Assíncrona, até 1 dia útil | Assíncrona, customer balance | Manual ou integração bancária |
| Conciliação | Stripe identifica boleto/pagamento | Stripe tenta reconciliar saldo | Nossa responsabilidade |
| Recorrência | Suportada, mas exige ação do cliente | Suportada onde elegível, exige saldo | Nossa responsabilidade |
| Reembolso | Sem reembolso padrão documentado | Há caminhos para saldo/conta conforme região | Nossa responsabilidade |
| Melhor uso inicial | B2B brasileiro com fatura | Só após elegibilidade BRL confirmada | Plano contingencial, não MVP |

## Impacto no produto e nos dados

Precisamos exibir método, estado, valor, vencimento, instruções e última atualização na conta financeira. O domínio de cobrança deve ficar separado do relato original, identidade do manifestante, diagnóstico, conteúdo e indicadores psicossociais. Metadata Stripe deve conter apenas IDs opacos de organização/pedido e versão do catálogo.

O email do Customer Stripe é necessário para envio de fatura e comunicação de cobrança, mas não deve ser usado para compartilhar informações de casos. Acessos financeiros devem ser RBAC por organização e auditados. A empresa não deve ver clientes de outra organização.

## Plano de implementação recomendado

1. ST-01: validar na conta brasileira Boleto, BRL, recorrência, tarifa, limites, vencimento e capacidade do Dashboard; registrar evidência.
2. ST-02: adicionar entidades/estados de boleto, fatura, tentativa, pagamento e direito, com vínculo por organização.
3. ST-03: implementar Checkout Boleto para mensal inicial e avulso em sandbox; não implementar transferência genérica ainda.
4. ST-04: implementar webhooks assíncronos e de invoice, deduplicação, ordenação e reconciliação.
5. ST-05: decidir `send_invoice`, carência, reemissão, suspensão e política de reembolso fora do fluxo Stripe padrão.
6. ST-06: acompanhar boleto gerado, pago, vencido, taxa de conversão, tempo até pagamento, valor a maior/menor, inadimplência e custo por cobrança.
7. ST-07: testar boleto criado, abandono, pagamento assíncrono, vencimento, duplicata, fora de ordem, valor divergente, falha de webhook e segregação de ambientes.

## Critério de go-live

Não liberar cobrança real apenas porque a conta Stripe mostra Boleto. O gate exige: capacidade BR/BRL confirmada, preços e benefícios aprovados, política de 1 mês grátis aprovada, regra de conversão, emissão fiscal avaliada, webhooks testados, carência e reembolso documentados, monitoramento e operação financeira treinados, secrets protegidos e autorização humana registrada.

## Conclusão

Para o MVP brasileiro, Boleto Stripe é tecnicamente viável e mais promissor que uma transferência bancária genérica dentro da Stripe. A melhor primeira implementação é Boleto via Checkout para contratação e Invoicing/Billing para cobranças de ciclo, com confirmação assíncrona e direitos liberados somente após webhook validado. Transferência bancária deve ficar como “não confirmada para BRL/conta brasileira” até a Stripe validar a conta; se for requisito indispensável, comparar um PSP brasileiro ou desenhar integração bancária separada, sem misturar os domínios.
