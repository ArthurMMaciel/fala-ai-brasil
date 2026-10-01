# Memória permanente do projeto

Atualizado em: 2026-09-30

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

- Landing segmentada entre empregado e empresa.
- Passo de meios de comunicação na manifestação, com validação de e-mail/telefone.
- Baseline publicada na branch `main` do repositório `ArthurMMaciel/fala-ai-brasil` em 2026-09-30.

## Aprendizados e incidentes

- Nenhum incidente de produção: não há produção.
- Documentos antigos misturam arquitetura desejada e estado implementado; a governança nova separa explicitamente os dois.
