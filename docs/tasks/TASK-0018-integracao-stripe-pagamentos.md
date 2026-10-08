# TASK-0018 — Integrar Stripe para planos, pacotes e pagamentos

- Status: proposta
- ClickUp: [TASK-0018](https://app.clickup.com/t/86aktngf0)
- Área: Integrações / Backend / Produto / Financeiro
- Prioridade: P1
- Data do levantamento: 2026-10-07
- Responsável: liderança técnica; decisões comerciais pelo responsável do produto
- Estimativa: refinar após ST-01 e fundação da API; não estimar prazo de produção sem backend e políticas aprovadas.
- Decisão: [ADR-0004](../adr/ADR-0004-stripe-para-cobranca.md)

## Problema e contexto
A POC apresenta planos comerciais e pacotes com valores hipotéticos, mas não possui cobrança, backend ou persistência. A Stripe foi escolhida pelo responsável como provedor para clientes pagantes. Trabalhadores continuam gratuitos e pagamento não define prioridade de atendimento.

## Objetivo
Permitir contratar planos recorrentes e pacotes avulsos, confirmar pagamentos com rastreabilidade e atualizar os direitos comerciais da própria organização sem ampliar acesso a dados sensíveis.

## Refinamento do responsável em 2026-10-08
- Funcionário gratuito. Demais personas escolhem primeiro plano no cadastro e têm gestão de plano/pagamento/upgrade na própria conta.
- Três opções: um mês de calendário gratuito e mensalidade a partir do segundo; mensal imediato; anual com 5% de desconto sobre doze mensalidades.
- Substitui piloto pago obrigatório e 30 dias grátis apenas no Hub. Valores-base continuam hipotéticos; estudos/patrocínios não devem converter preços avulsos em mensalidades sem definição comercial.
- ST-01 deve fechar preços, trial (método exigido/conversão/elegibilidade), cancelamento e relação com avulsos. ST-02 modela usuário, vínculo organizacional, assinante e direitos separadamente. ST-03 inclui cadastro e área da conta; ST-04 confirma pagamentos e trial no servidor; ST-05 cobre upgrades sem reaplicar gratuidade; ST-06 acompanha pagantes, receita e pendências com acesso financeiro autorizado; ST-07 testa estes fluxos.
- Confirmar um mês por calendário, anual = mensal × 12 × 0,95, pagamento pendente sem liberação e upgrade pendente preservando direitos atuais. Trial não equivale a usuário pagante.
- Demonstração local: [TASK-0019](TASK-0019-cadastro-planos-e-endereco.md); decisão: [ADR-0005](../adr/ADR-0005-cadastro-e-direitos-comerciais.md). Nenhuma cobrança real implementada.

## Levantamento
- Empresa, Hub e Intelligence possuem hipóteses de mensalidade; estudos e patrocínios possuem pacotes/projetos avulsos e ofertas sob proposta. Não publicar os 15 preços da POC como tabela aprovada.
- Stripe Checkout hospedado é a proposta de menor carga operacional; servidor cria a sessão para oferta autorizada. Billing atende recorrência com cartão. Portal do cliente é proposto para gestão comercial.
- Pix para conta brasileira é avulso em BRL; Pix Automático não está disponível para contas no Brasil, segundo a documentação consultada. A página brasileira de preços indica disponibilidade por convite. Confirmar elegibilidade real da conta antes de prometer Pix.
- A documentação Pix lista limite por transação; confirmar limite aplicável à conta e aos projetos de alto ticket antes de oferecer o método. Política de parcelamento ainda não foi aprovada.
- Preços e habilitação da conta são verificações pendentes. Referências públicas de custo: cartão nacional 3,99% + R$ 0,39, Pix 1,19% e Billing 0,7% do volume aplicável, consultadas em 2026-10-07. Tarifas contratuais e produtos adicionais precisam ser confirmados; não somar custos indistintamente.
- Regra comercial atual: um mês gratuito, mensal imediato ou anual com 5% de desconto. Preços, renovação automática ao fim do mês gratuito, elegibilidade e políticas operacionais precisam ser fechados em ST-01.
- Recibo/fatura do provedor não substitui automaticamente emissão fiscal brasileira; definir obrigação e solução com responsável contábil, fora da implementação inicial.
- Base legal, retenção, região de processamento, contrato/DPA e subprocessadores para dados de cobrança devem ser avaliados antes de dados reais. Dados psicossociais não pertencem ao domínio de cobrança.

## Escopo
Planejar e entregar catálogo autorizado no servidor, Checkout, webhooks, direitos comerciais, ciclo de assinatura, reembolso e conciliação. Primeira implementação exclusivamente sandbox. A tarefa principal coordena as sete subtarefas abaixo; cada uma tem entregável e aceite próprios.

## Fora de escopo
Implementação nesta sessão de levantamento; cobrança ou deploy real; Connect/split/repasse a parceiros; comissões; armazenamento de cartão; novos provedores; emissão fiscal automática; impostos automáticos; cobrança por uso e IA adicional. Boleto passa a ser método em estudo nesta tarefa; transferência bancária genérica permanece condicionada à confirmação de suporte para conta brasileira em BRL.

## Critérios de aceite da integração
- ST-01 a ST-07 concluídas com evidências e pendências comerciais resolvidas.
- Cartão avulso e recorrente testados; boleto avulso/recorrente e Pix avulso validados quando habilitados. Se um método obrigatório não estiver disponível, tarefa permanece bloqueada para lançamento.
- Pagamento confirmado no servidor; nenhuma liberação por redirect ou status enviado pelo navegador.
- Duplicatas, eventos fora de ordem e indisponibilidade não geram cobrança ou acesso duplicados.
- Isolamento por organização e vínculo comercial verificados; cobrança não altera permissões de relatos.
- Cancelamento, renovação, inadimplência, reembolso e conciliação cobertos por testes e procedimento operacional.
- Conta, custos e tratamento de dados validados; go-live depende de aprovação humana e do gate do piloto.

## Dependências
TASK-0002 (XSS), TASK-0004 (CI/testes), TASK-0005 (auth), TASK-0006 (tenancy), TASK-0007 (dados/privacidade), TASK-0008 (API/DB), TASK-0009 (auditoria), TASK-0010 (backup/incidentes).
TASK-0015/0016 são contexto comercial concluído, não implementação de cobrança. Levantamento/ST-01 podem começar antes da fundação; cobrança real depende dela.

## Riscos e controles
Segurança: fraude de preço/tenant, replay de webhook e vazamento de secrets; validar no servidor, verificar assinatura, idempotência e menor privilégio.
Privacidade/dados: enviar apenas contato de cobrança necessário, dados fiscais aprovados, IDs opacos e informações de compra. Nunca relato, identidade de manifestante, diagnóstico ou conteúdo sensível em metadata, descrição ou logs.
Operação: acesso divergente do pagamento, indisponibilidade e suporte; estados separados, conciliação e reprocessamento seguro.
Custo: tarifas de pagamento/Billing, contestações e operação manual; validar cenário por ticket e método na ST-01 e monitorar na ST-06.

## Observabilidade
IDs técnicos, falhas por etapa, eventos atrasados, divergências de conciliação, duplicatas e custo. Sem payload completo nem dados sensíveis em logs.

## Rollback
Suspender novas sessões/contratações por configuração. Preservar processamento dos pagamentos já iniciados, webhooks, conciliação e histórico. Revogar credenciais comprometidas e operar pela revisão financeira autorizada. Não apagar dados nem cancelar todas as assinaturas automaticamente.

## Testes e definição de pronto
Matriz sandbox descrita em ST-07; testes de autorização e regressão nos fluxos atuais. Integração concluída somente com evidências das sete subtarefas. Este documento registra planejamento, não capacidade implementada.

## Fontes oficiais
- [Pix: disponibilidade, recorrência e limites](https://docs.stripe.com/payments/pix)
- [Boleto: disponibilidade, vencimento, limites e produtos](https://docs.stripe.com/payments/boleto)
- [Suporte de métodos por país/moeda](https://docs.stripe.com/payments/payment-methods/payment-method-support)
- [Transferências bancárias e conciliação](https://docs.stripe.com/payments/bank-transfers)
- [Boleto e preços de métodos locais](https://stripe.com/br/pricing/local-payment-methods)
- [Preços brasileiros](https://stripe.com/br/pricing)
- [Checkout Sessions](https://docs.stripe.com/api/checkout/sessions)
- [Webhooks: assinatura, retries e deduplicação](https://docs.stripe.com/webhooks)
- [Ciclo de assinatura](https://docs.stripe.com/billing/subscriptions/webhooks)
- [Idempotência](https://docs.stripe.com/api/idempotent_requests)
- [Portal do cliente](https://docs.stripe.com/customer-management)

## Subtarefas
### ST-01 — Validar conta Stripe, boleto, Pix e regras comerciais
- ClickUp: [ST-01](https://app.clickup.com/t/86aktngf4)
Objetivo: fechar a matriz oferta × método × periodicidade antes de configurar preços.
Escopo: confirmar país e entidade da conta, habilitação e tarifas de cartão/boleto/Pix e elegibilidade da atividade; verificar limites de boleto para os pacotes e estudos de alto ticket. Definir quais planos entram no primeiro lançamento e preços aprovados em BRL. Modalidades decididas: um mês de calendário grátis e mensal a partir do segundo, mensal imediato e anual com desconto de 5%. Fechar método exigido no trial, conversão, elegibilidade única por organização, relação de assinatura com projetos/cotas avulsos, parcelamento, vencimento de boleto e cancelamento/reembolso. Registrar custos Payments/Billing e validar emissão fiscal com responsável contábil.
Aceite: matriz aprovada com responsável e decisões pendentes explícitas; teste de elegibilidade de boleto e Pix; confirmar se transferência bancária genérica não está disponível para BRL/conta brasileira ou registrar validação da conta. Nenhuma promessa de Pix Automático para conta brasileira. Caso boleto ou Pix seja requisito e esteja indisponível, registrar bloqueio, sem trocar provedor automaticamente.
Dependências: decisão de produto/financeiro e conta Stripe, sem necessidade de compartilhar secrets no ClickUp.

### ST-02 — Modelar catálogo, pedidos e direitos por organização
- ClickUp: [ST-02](https://app.clickup.com/t/86aktngf9)
Objetivo: manter catálogo e estado comercial no servidor, isolados por organização.
Refinamento: separar usuários e vínculos organizacionais do titular/estado comercial. Distinguir trial, pagamento pendente, pagante ativo, inadimplência, cancelamento e período encerrado; trial nunca conta como receita paga. Não liberar acesso real por cadastro, seleção de plano ou estado do navegador.
Escopo: Product/Price versionados; preços avulsos e recorrentes separados; mapeamento organização ↔ Customer e pedido ↔ Session/PaymentIntent/Subscription/Invoice; valores em centavos BRL; trilha de mudanças. Modelar pagamento pendente, pago, falho, expirado e reembolsado separados de assinatura e acesso. Projetos sob proposta exigem orçamento aprovado. Plano não pode ampliar acesso a relatos ou definir prioridade de atendimento.
Aceite: ADR/modelo aprovados, migrações testadas e constraints impedindo duplicata; cliente não determina preço, tenant ou benefícios; teste de isolamento entre duas organizações. Cobrança nunca apaga casos existentes.
Dependências: ST-01 e TASK-0005/0006/0007/0008. Testes: valores, concorrência, IDOR e transições inválidas.

### ST-03 — Implementar Checkout para cartão e Pix avulso
- ClickUp: [ST-03](https://app.clickup.com/t/86aktngfe)
Objetivo: cliente autorizado contratar oferta aprovada em checkout hospedado.
Refinamento: permitir escolher primeiro plano e modalidade no cadastro de toda persona comercial e atualizar na própria conta. Trial com término calculado por um mês de calendário; modo mensal imediato e anual = mensal × 12 × 0,95. Ofertas sob proposta dependem de aprovação comercial. O retorno do checkout não confirma pagamento.
Escopo: servidor cria Session em modo payment para avulsos e subscription para planos compatíveis; cartão e boleto para recorrência, boleto avulso e Pix avulso condicionados à conta. Idempotency-Key vinculada à tentativa/pedido, allowlist de Price IDs, URLs de retorno fixadas e autenticação/RBAC. Front-end mostra boleto gerado, pendente, vencido, pago ou falho, com navegação acessível. Para boleto recorrente, avaliar Billing/Invoicing com `send_invoice` e nova fatura a cada ciclo; boleto não é débito automático. Transferência bancária genérica permanece fora até confirmação de suporte em BRL.
Aceite: sucesso, recusa, autenticação adicional, abandono e expiração testados; retorno ao site não libera acesso; nenhum PAN/CVC ou secret passa pelo código cliente. Testar adulteração de valor/tenant e duplo clique.
Dependências: ST-01/02; ativação depende de ST-04.

### ST-04 — Processar webhooks e ativação idempotente
- ClickUp: [ST-04](https://app.clickup.com/t/86aktngfg)
Objetivo: confirmar pagamento e atualizar acesso de forma confiável.
Escopo: verificar Stripe-Signature sobre corpo bruto e segredo por ambiente; persistir evento antes do ACK; deduplicação por event.id e operação de negócio; processamento transacional com retries, backoff e recuperação. Suportar eventos repetidos, fora de ordem e falhas concorrentes, consultando estado atual quando necessário. Cobrir Session concluída/pagamento assíncrono/expiração, invoice.paid/payment_failed, subscription.updated/deleted e eventos de reembolso/contestação necessários. Validar tenant, valor, moeda e produto contra pedido interno. Não guardar payload integral sem política aprovada.
Aceite: evento sem assinatura rejeitado; duplicatas não cobram nem ativam duas vezes; confirmação exige estado de pagamento compatível; falha recuperável não perde evento; acesso comercial atualizado sem alterar permissões sensíveis.
Dependências: ST-02/03 e TASK-0009.

### ST-05 — Gerenciar renovação, portal, cancelamento e reembolso
- ClickUp: [ST-05](https://app.clickup.com/t/86aktngfq)
Objetivo: tornar ciclo comercial explícito e operável pelo comprador autorizado.
Refinamento: upgrade na própria conta, sem reaplicar trial; manter direitos atuais enquanto nova contratação estiver pendente. Conversão após um mês, carência, efeitos da prorrata e cancelamento requerem regras de ST-01. Para boleto, definir vencimento, lembretes, suspensão e nova emissão. A documentação consultada informa ausência de reembolso padrão para Boleto, portanto a política de devolução precisa ser operacional e contábil. Gerenciamento autorizado de forma de pagamento pelo portal hospedado, sem capturar cartão na plataforma.
Escopo: Customer Portal criado no servidor para o Customer da própria organização; renovação com cartão, atualização de método, inadimplência, carência e fim de acesso conforme regras aprovadas. Cancelamento no fim do período e eventual imediato, upgrade/downgrade/prorrata somente se aprovados. Reembolso total/parcial com autorização, auditoria e reconciliação; cancelar assinatura não implica reembolso. Renovação manual Pix exige novo pagamento pelo cliente; se não entrar no MVP, interface explica o limite. Tratar contestação sem destruir dados ou prejudicar atendimento gratuito.
Aceite: testes de tenant, renovação falha/recuperada, cancelamento e reembolso; histórico de casos preservado; ação financeira administrativa auditada.
Dependências: ST-01/04 e definição das políticas comerciais.

### ST-06 — Implantar conciliação, métricas e runbook financeiro
- ClickUp: [ST-06](https://app.clickup.com/t/86aktngfv)
Objetivo: detectar divergências entre Stripe e estado interno e recuperar falhas.
Refinamento: controle financeiro autorizado de assinantes por organização, usuários vinculados e pagamentos; métricas separadas de trial, pagantes, pendências e receita. Empresa vê somente sua organização; nenhum relatório financeiro inclui relatos ou identidade de manifestantes.
Escopo: conciliar pedidos/pagamentos/assinaturas/reembolsos por IDs, com paginação e cursor; transações duplicadas, eventos perdidos, pagamentos sem pedido e acesso indevido geram alerta. Definir frequência por volume, limites de API, timeout, retries e acompanhamento de tarifas, receita bruta/líquida e Billing. Documentar indisponibilidade, reprocessamento, chave comprometida, operação manual, estorno e saída do provedor. Logs com IDs técnicos mínimos, sem conteúdo psicossocial, PAN/CVC ou tokens.
Aceite: divergência sintética detectada e corrigida sem duplicação; métricas e acesso operacional revisados; relatórios comerciais não recebem relatos; rollback suspende novos checkouts preservando processamento e conciliação de pagamentos existentes.
Dependências: ST-04/05 e TASK-0009/0010.

### ST-07 — Validar integração em sandbox e gate de lançamento
- ClickUp: [ST-07](https://app.clickup.com/t/86aktngfz)
Objetivo: comprovar integração ponta a ponta antes da cobrança real.
Escopo: testar cartão aprovado/recusado/autenticação adicional, Pix pendente/pago/expirado quando habilitado, abandono sem redirect, webhook inválido/duplicado/fora de ordem, timeout de criação, renovação, inadimplência, reembolso, cancelamento, IDOR e segregação test/live. Verificar acessibilidade, catálogo, dados mínimos, custos e runbooks. Planejar configuração de produção, proteção/rotação de secrets e reversão, sem executar deploy nem cobrança real nesta tarefa de levantamento.
Aceite: evidências sintéticas, regressão/CI e matriz de segurança aprovadas; conta/Pix/região/contrato e regras comerciais confirmados; autorização humana de go-live e gates do ROADMAP registrados antes de operar com dados reais. Falhas críticas bloqueiam lançamento.
Dependências: ST-01 a ST-06, TASK-0002/0004/0005/0006/0007/0008/0009/0010.
