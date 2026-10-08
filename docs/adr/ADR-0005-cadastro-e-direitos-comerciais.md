# ADR-0005 — Cadastro e direitos comerciais por organização

- Estado: regras comerciais aceitas; desenho de implementação proposto
- Data: 2026-10-08
- Tarefas: [TASK-0019](../tasks/TASK-0019-cadastro-planos-e-endereco.md), [TASK-0018](../tasks/TASK-0018-integracao-stripe-pagamentos.md)

## Decisão
Funcionário permanece gratuito. Demais personas selecionam plano no cadastro: um mês de calendário gratuito e cobrança mensal a partir do segundo, mensal imediato ou anual com 5% de desconto sobre doze mensalidades. Seleção/upgrade também disponíveis na própria conta. A relação de assinaturas com estudos e patrocínios avulsos continua pendente de esclarecimento.

## Desenho proposto
Identidade/usuário, vínculo organizacional, assinatura, pagamento e direitos comerciais são estados distintos. Servidor valida catálogo, organização e confirmação Stripe; navegador não libera acesso real. Trial é acesso temporário, sem receita paga. Mensal/anual requerem pagamento confirmado; upgrade pendente mantém direitos atuais até confirmação. Benefícios pagos nunca ampliam permissões de relatos ou prioridade de atendimento.

Administrador financeiro autorizado gerencia assinantes, receita, pendências, vencimentos e histórico por organização. Não confundir titular da assinatura com todos os usuários vinculados à organização nem disponibilizar lista de clientes a uma empresa. Na POC, somente a própria conta tem gestão comercial, e os registros são voláteis.

## Pendências para produção
Preços finais, limites/benefícios, método exigido no trial, conversão após o mês gratuito, elegibilidade para nova gratuidade, política de upgrade/prorrata, carência/inadimplência, cancelamento/reembolso, conta Stripe e fiscalização. Desconto anual inicial de 5% não é parcelamento aprovado. Trial não deve ser reaplicado em upgrade.

## Consequências
Novas personas comerciais não herdam papel de administrador da empresa. POC mantém o portal empresarial legado, sem alegar autorização real. Implementação segura depende de auth, RBAC/tenancy, API, dados e auditoria. Tarifas e custos de atendimento devem ser considerados na margem.
