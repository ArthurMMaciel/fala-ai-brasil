# Memória permanente do projeto

Atualizado em: 2026-10-08

## Visão

Permitir que uma pessoa relate situações psicossociais do trabalho, preserve sua identidade perante a empresa, acompanhe o tratamento e receba retorno; permitir que empresas respondam com rastreabilidade e evoluam sua responsividade.

## Arquitetura atual

Aplicação Vite + TypeScript sem framework, renderizada por template strings em um único processo de navegador. Todo estado é volátil e os dados são simulados. Não existe servidor nem persistência.

## Direção técnica vigente

- Evoluir incrementalmente para uma aplicação web + API + PostgreSQL.
- Manter a POC utilizável enquanto se cria a fundação.
- Começar com monólito modular; separar serviços apenas por necessidade comprovada.
- Preferir jobs em PostgreSQL antes de adotar broker dedicado.
- Separar fisicamente/logicamente identidade, relato original e versão compartilhável.
- Exigir revisão humana para risco médio/alto; bloquear automação externa em risco alto.

## Decisões pendentes

- Identidade oficial definida: Escuta Aí Brasil. Os nomes anteriores foram descontinuados em 2026-10-01.
- Estratégia de autenticação (sessão server-side é preferência inicial, ainda não decidida).
- Provedor de infraestrutura e regiões de dados.
- Base legal, consentimentos, retenção e atendimento a direitos do titular.
- Canal de comunicação com empresas e comprovação de domínio/representação.
- Uso, modelo, provedor e fronteiras de IA.

## Tecnologias atuais

- TypeScript 5.9.3, Vite 5.4.21, HTML e CSS.
- Sem runtime de produção definido.
- Proposta legada não ratificada: Go, chi, pgx, PostgreSQL, goose e OpenTelemetry.

## Tecnologias rejeitadas ou adiadas

- Microserviços: adiados; aumentam operação sem benefício atual.
- Kubernetes: adiado; inadequado ao tamanho da equipe e estágio.
- Broker dedicado: adiado; avaliar após demanda real.
- IA autônoma: rejeitada para decisões sensíveis; IA deve começar assistiva.

## Riscos conhecidos

- POC pode executar HTML inserido pelo usuário por uso de `innerHTML`.
- Credenciais demo e autorização existem apenas no cliente.
- Não há isolamento entre organizações nem separação real de dados sensíveis.
- A promessa de proteção de identidade ainda não é sustentada por controles técnicos.
- Não há testes, logs, backups, deploy reproduzível ou resposta a incidentes.

## Regras permanentes

- Nunca expor texto original à empresa.
- Evitar promessa de anonimato absoluto; comunicar proteção de identidade e limites.
- Não usar relatos reais na POC.
- Não enviar dados sensíveis a IA/terceiros sem avaliação aprovada.
- Alterações estruturais exigem ADR; trabalho relevante exige tarefa.

## Alterações recentes

- Em 2026-10-08 o responsável determinou usar somente a API oficial do ClickUp com `CLICKUP_API_TOKEN` no `.env`; não utilizar o plugin/conector ClickUp. Preferência persistente para consultas e alterações de tarefas. Sem imprimir chave ou enviar dados pessoais.
- Regras comerciais atualizadas pelo responsável: funcionário gratuito; demais personas escolhem primeiro plano no cadastro e gerenciam upgrade na conta. Modalidades: um mês de calendário grátis e mensal a partir do segundo, mensal imediato ou anual com 5% de desconto sobre doze mensalidades (ADR-0005/TASK-0019). Substitui a recomendação anterior de piloto pago e gratuidade de 30 dias exclusiva do Hub. Preços finais permanecem pendentes.
- Regra comercial corrigida pelo responsável em 2026-10-08: um mês de calendário grátis e mensalidade a partir do segundo; mensal imediato ou anual com 5% de desconto. A regra de três meses foi substituída em código, apresentação e documentos.
- Boleto foi incluído no estudo de cobrança. Documentação Stripe consultada indica suporte no Brasil/BRL, geração de voucher/PDF, confirmação até 1 dia útil, liquidação até T+2, recorrência, Checkout/Billing/Invoicing/Subscriptions/Customer Portal, limite de R$ 5 a R$ 49.999,99 e ausência de reembolso padrão. Transferência bancária genérica não aparece na matriz oficial para BRL/conta brasileira; não prometer sem validação da conta (ADR-0007).
- POC demonstra cadastro das cinco personas comerciais, área própria de assinatura, estado pendente/trial/pagante e confirmação simulada. Novas personas não empresariais usam papel demonstrativo `commercial`, sem herdar painel de administrador. Pagamentos, autenticação, autorização e persistência reais continuam ausentes.
- Interface usa funcionário no lugar de empregado. Todos os cadastros exibem CEP, Rua/Avenida e número obrigatórios, complemento opcional. Pedido explícito de API CEP autoriza integração pontual: ViaCEP escolhido como decisão técnica (ADR-0006), com timeout, recuperação manual e proteção contra resposta obsoleta. Somente CEP enviado na aplicação; conexão direta expõe IP ao provedor. Relação de assinaturas com estudos/patrocínios avulsos permanece pendente.

- Stripe escolhida pelo responsável para pagamentos dos clientes em 2026-10-07 (ADR-0004). TASK-0018 criada no ClickUp com 7 subtarefas e levantamento de cartão, Pix avulso, recorrência, webhooks, ciclo comercial e conciliação. Integração ainda não implementada; conta, preços finais e políticas comerciais pendentes. Pix Automático não disponível para contas brasileiras segundo documentação consultada; habilitação de Pix e limites exigem validação da conta antes de lançamento.
- Gestão técnica pelo ClickUp autorizada pelo responsável: lista Escuta Aí Brasil (`901329218347`) no Arthur Workspace e TASK-0001 a TASK-0017 registradas em 2026-10-07, com links em cada documento local. São 11 pendentes (`to do`) e 6 concluídas (`complete`), preservando prioridades e histórico documentado. Consultar duplicatas antes de criar tarefas e manter vínculos locais. A rotina de manutenção da TASK-0017 ainda é proposta.
- API oficial do ClickUp validada para gestão local de tarefas com token em `.env` ignorado pelo Git. Compartilhar somente metadados técnicos; nunca relatos, identidades ou credenciais. Isso não implementa integração no produto.
- As visões comerciais passaram de catálogo de funcionalidades para argumento de compra: comprador, gatilho, problema, promessa, resultados do piloto, lógica econômica, scorecard, jornada e diferenciação de planos por persona.
- Histórico (substituído em 2026-10-08): entrada recomendada de piloto pago de 90 dias e 30 dias sem mensalidade apenas no Hub.
- POC ganhou a página “Soluções e planos” com visões demonstrativas para Empresa, Parceiro do Hub, Intelligence, Estudos e Patrocínio; valores são hipóteses comerciais, sem cobrança real.
- Pessoa trabalhadora permanece como acesso gratuito e monetização não pode definir prioridade de atendimento.
- Suporte da plataforma passou a ter visão interna demonstrativa, separada da operação humana e sem acesso a relato original ou identidade por padrão.
- Cadastro pessoal simplificado para nome, CPF, endereço, e-mail e senha; confirmação de senha adiada.
- Contexto laboral passou a ser coletado por manifestação, sem a opção de candidato em processo seletivo.
- Formas de comunicação agora registram nome, e-mail, telefone e cargo do contato empresarial, com cautela explícita para proprietário/sócio.
- Landing segmentada entre empregado e empresa.
- Passo de formas de comunicação na manifestação, com contato empresarial estruturado e validação de e-mail/telefone.
- Baseline publicada na branch `main` do repositório `ArthurMMaciel/fala-ai-brasil` em 2026-09-30.

## Aprendizados e incidentes

- Nenhum incidente de produção: não há produção.
- Documentos antigos misturam arquitetura desejada e estado implementado; a governança nova separa explicitamente os dois.
