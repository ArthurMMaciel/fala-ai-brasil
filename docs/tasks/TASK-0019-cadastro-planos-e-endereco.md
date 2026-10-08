# TASK-0019 — Cadastro comercial, assinatura e endereço estruturado

- Status: em-andamento
- Prioridade: P1
- ClickUp: [TASK-0019](https://app.clickup.com/t/86aktwda1)
- Dependência: [TASK-0018](TASK-0018-integracao-stripe-pagamentos.md) para cobrança real; TASK-0005/0006/0008 para usuários, autorização e persistência.

## Decisão do responsável em 2026-10-08
Funcionário usa o canal gratuitamente. Demais personas devem escolher plano no cadastro e poderão gerenciá-lo na conta: um mês gratuito, pagando a partir do segundo; mensal imediato; anual com desconto inicial de 5% sobre doze mensalidades. Preços-base continuam hipotéticos. Estudos/patrocínios exigem esclarecer a relação entre assinatura e projeto/cota avulsa.

## Escopo da POC
- Trocar empregado por funcionário na interface.
- Cadastro de todas as personas comerciais com plano/modalidade, separado do cadastro gratuito.
- Área de conta para seleção de upgrade e visualização do estado comercial; confirmação de pagamento explicitamente simulada.
- Controle demonstrativo de assinantes em memória, distinguindo período gratuito, pagamento pendente e pagante ativo.
- Endereço em campos obrigatórios CEP, Rua/Avenida e número; complemento opcional em todos os cadastros.
- Consulta ViaCEP no blur com validação, timeout, tratamento de falhas e proteção contra respostas antigas ([ADR-0006](../adr/ADR-0006-consulta-cep-viacep.md)). Pedido de API CEP autoriza esta integração; produção com dados pessoais ainda depende do gate do piloto.

## Aceite
- Funcionário não recebe seleção de assinatura.
- Três modalidades estão disponíveis por persona comercial; um mês grátis, mensal imediato ou anual = mensal × 12 × 0,95.
- O mês grátis é mês de calendário; não equivale automaticamente a 30 dias. A cobrança começa no segundo mês conforme a política aprovada.
- Cadastro mensal/anual entra como pendente; acesso comercial depende de confirmação. Trial de um mês libera demonstração sem classificar como receita paga.
- Upgrade pendente preserva plano ativo até confirmação; nenhuma ação financeira altera acesso a relatos sensíveis.
- Parceiros/clientes analíticos não recebem o papel de administrador da empresa.
- Campos obrigatórios validados, labels associados e mensagens acessíveis.
- CEP inválido não dispara consulta; somente CEP enviado ao provedor, sem identidade, número, complemento ou conteúdo psicossocial. A conexão direta também expõe IP ao provedor, devendo ser avaliada antes de produção.
- Testes de cálculo, calendário, estados e endereço; build aprovado.

## Riscos e limites
Segurança: controles locais são demonstrativos; backend será autoridade. Privacidade: nenhuma persistência nova de dados pessoais; consulta externa autorizada no pedido e avaliação registrada no ADR-0006. Operação: cobrança real, inadimplência automática e processamento Stripe não existem. Custo: desconto e trial exigem medir margem/atendimento; nenhuma infraestrutura contratada.

## Rollback
Reverter somente alterações desta tarefa; preservar POC anterior e tarefas de Stripe. Desativar consulta de CEP sem impedir preenchimento manual.

## Entrega parcial e validação em 2026-10-08
- Interface e regras demonstrativas entregues, incluindo trial para as cinco personas, anual com 5%, cadastro e gestão/upgrade na conta. Ofertas sem preço mensal liberam trial demonstrativo; pagamento permanece sob proposta.
- `npm.cmd test`: 13 testes aprovados de calendário/cálculo, estados de pagamento, upgrade, separação de personas, consulta no blur, respostas antigas e preservação da edição manual. Consulta de exemplo público `01001-000` retornou logradouro na API oficial; nenhuma identidade ou endereço pessoal usado.
- `npm.cmd run build` aprovado; `git diff --check` sem erros de whitespace.
- Navegador integrado sem conexão disponível; revisão visual/interação ponta a ponta pendente.
- Consulta ViaCEP ativada dentro da autorização para API CEP, com decisão e avaliação de dados registradas no ADR-0006. Endereço permite preenchimento manual em falha ou CEP sem logradouro.
- Relação entre assinaturas e projetos/cotas avulsas pendente. Produção e cobrança real dependem da TASK-0018 e da fundação técnica; não há controle real de usuários pagantes ainda.
