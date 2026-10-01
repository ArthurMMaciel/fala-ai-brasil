# Engenharia do Produto - Ecoa Voz / Voz Psicossocial

> **Status deste documento:** proposta legada de arquitetura, não descrição do que está implementado nem decisão automaticamente aceita. Consulte `docs/architecture/CURRENT_STATE_AUDIT.md` e os ADRs em `docs/adr/` antes de executar.

Este documento detalha a transformacao da POC atual em um MVP robusto, com backend em Go, banco PostgreSQL em Docker no inicio, arquitetura preparada para operacao real, seguranca, LGPD, auditoria, observabilidade e evolucao modular.

O objetivo e servir como guia pratico para engenharia: o que precisa ser feito, em qual ordem, quais tecnologias usar, quais responsabilidades cada parte do sistema deve assumir e quais requisitos funcionais e nao funcionais precisam nascer junto com o produto.

## 1. Objetivo Tecnico do MVP

Construir uma plataforma web com:

- Front-end para trabalhador, admin/operacao e empresa.
- Backend em Go com API HTTP.
- PostgreSQL como banco transacional.
- Docker Compose para ambiente local.
- Persistencia real de usuarios, empresas, manifestacoes, status, respostas, analises de IA e auditoria.
- Regras de seguranca para proteger relato original e identidade do trabalhador.
- Fila/processamento assincrono para IA, emails, metricas e tarefas demoradas.
- Observabilidade desde o primeiro ciclo de desenvolvimento.

O MVP deve ser simples de operar, mas nao deve nascer descartavel. A regra e: cortar escopo de produto, nao cortar fundamentos de seguranca, rastreabilidade e arquitetura.

## 2. Stack Recomendada

### Backend

- Linguagem: Go 1.23+.
- Roteador HTTP: `chi`.
- Banco: PostgreSQL 16+.
- Driver PostgreSQL: `pgx`.
- Migracoes: `goose`.
- Config: variaveis de ambiente com parser simples, por exemplo `caarlos0/env` ou implementacao propria.
- Logs: `log/slog` nativo do Go.
- Auth: JWT com refresh token ou sessoes server-side.
- Senhas: `bcrypt` ou `argon2id`.
- Validacao: validadores explicitos por caso de uso; evitar depender apenas de tags magicas.
- Testes: `testing`, `httptest`, `testcontainers-go` ou banco Docker dedicado.
- Observabilidade: OpenTelemetry, Prometheus e logs estruturados.

### Front-end

Curto prazo:

- Manter Vite + TypeScript e conectar na API real.
- Extrair a POC de `src/main.ts` para modulos por feature.

Medio prazo:

- Avaliar React, Vue ou Svelte se a UI crescer.
- Separar `apps/web` da raiz atual.
- Criar client HTTP tipado.
- Criar camada de estado por feature.

### Banco e Infra Local

- PostgreSQL em Docker Compose.
- Redis em Docker Compose se houver fila/cache no MVP.
- Mailpit ou Mailhog para emails locais.
- Adminer, pgAdmin ou TablePlus como ferramenta opcional.

### Fila / Jobs

Opcoes para MVP:

- Simples: tabela `jobs` no PostgreSQL com worker Go.
- Intermediario: Redis + Asynq.
- Robusto: NATS, RabbitMQ ou SQS em cloud.

Recomendacao inicial: comecar com Postgres-backed jobs para reduzir complexidade. Migrar para Redis/NATS quando volume ou isolamento operacional pedir.

## 3. Preparacao da Maquina

### Instalar Go

Instalar Go 1.23+.

Verificar:

```bash
go version
```

Configurar variaveis se necessario:

```bash
go env GOPATH
go env GOMODCACHE
```

### Instalar Docker

Instalar Docker Desktop ou Docker Engine.

Verificar:

```bash
docker version
docker compose version
```

### Instalar Node

Manter Node para o front-end atual.

Verificar:

```bash
node --version
npm --version
```

### Ferramentas Go Recomendadas

Instalar ferramentas de desenvolvimento:

```bash
go install github.com/pressly/goose/v3/cmd/goose@latest
go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
go install github.com/air-verse/air@latest
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
```

Uso esperado:

- `goose`: migracoes.
- `sqlc`: queries tipadas, se adotado.
- `air`: hot reload local.
- `golangci-lint`: lint e qualidade.

## 4. Estrutura de Monorepo Recomendada

Estrutura alvo:

```text
.
├── apps/
│   └── web/
│       ├── src/
│       ├── package.json
│       └── vite.config.ts
├── services/
│   ├── api/
│   │   ├── cmd/api/main.go
│   │   ├── internal/
│   │   │   ├── domain/
│   │   │   ├── application/
│   │   │   ├── transport/http/
│   │   │   └── infrastructure/
│   │   ├── go.mod
│   │   └── go.sum
│   └── worker/
│       └── cmd/worker/main.go
├── db/
│   ├── migrations/
│   └── seeds/
├── deployments/
│   ├── docker-compose.yml
│   └── local.env.example
├── arquiteturas/
├── README.md
└── ENGENHARIA.md
```

No primeiro momento, pode-se criar apenas:

```text
services/api/
db/migrations/
deployments/docker-compose.yml
```

## 5. Fundacao do Backend

### Objetivo

Criar o nucleo tecnico minimo para qualquer feature futura:

- Servidor HTTP.
- Health check.
- Config por ambiente.
- Logger estruturado.
- Conexao PostgreSQL.
- Migracoes.
- Middleware de request ID.
- Middleware de erro.
- Padrao de resposta JSON.
- Teste de smoke da API.

### Passos

1. Criar pasta `services/api`.
2. Inicializar modulo Go:

```bash
cd services/api
go mod init github.com/seu-org/voz-psicosocial/services/api
```

3. Instalar libs iniciais:

```bash
go get github.com/go-chi/chi/v5
go get github.com/jackc/pgx/v5/pgxpool
go get github.com/pressly/goose/v3
go get golang.org/x/crypto/bcrypt
go get github.com/google/uuid
```

4. Criar `cmd/api/main.go`.
5. Criar `internal/config`.
6. Criar `internal/transport/http`.
7. Criar `internal/infrastructure/postgres`.
8. Criar endpoint:

```text
GET /healthz
```

Resposta esperada:

```json
{
  "status": "ok"
}
```

9. Criar endpoint de prontidao:

```text
GET /readyz
```

Esse endpoint deve validar conexao com PostgreSQL.

### Conceitos Importantes

- `healthz`: processo esta vivo.
- `readyz`: processo esta pronto para receber trafego.
- `request_id`: cada request precisa ser rastreavel.
- `graceful shutdown`: servidor deve finalizar conexoes antes de encerrar.
- `timeouts`: configurar timeout de leitura, escrita e idle no servidor HTTP.

## 6. PostgreSQL Local em Docker

### Objetivo

Ter banco local reproduzivel, facil de subir e proximo de producao.

Arquivo sugerido: `deployments/docker-compose.yml`.

Servicos:

- `postgres`
- `redis` opcional
- `mailpit` opcional
- `adminer` opcional

Configuracao inicial:

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: voz
      POSTGRES_PASSWORD: voz_local
      POSTGRES_DB: voz_psicosocial
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U voz -d voz_psicosocial"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  postgres_data:
```

Subir:

```bash
docker compose -f deployments/docker-compose.yml up -d
```

Parar:

```bash
docker compose -f deployments/docker-compose.yml down
```

Reset local:

```bash
docker compose -f deployments/docker-compose.yml down -v
docker compose -f deployments/docker-compose.yml up -d
```

## 7. Migracoes Iniciais

### Primeira leva de tabelas

Criar migracoes para:

- `users`
- `user_profiles`
- `companies`
- `company_users`
- `complaints`
- `complaint_private_contents`
- `complaint_public_contents`
- `complaint_status_history`
- `ai_analyses`
- `review_tasks`
- `review_decisions`
- `company_responses`
- `audit_logs`

### Regras de Modelagem

- Usar UUID como chave primaria.
- Usar `created_at`, `updated_at` e, quando fizer sentido, `deleted_at`.
- Usar enums controlados no dominio Go e `CHECK constraints` no banco.
- Evitar apagar dados sensiveis sem politica explicita.
- Separar texto original de texto compartilhavel.
- Registrar toda mudanca relevante em tabelas de historico/auditoria.

### Exemplo Conceitual

```text
complaints
  id
  user_id
  company_id
  category
  risk_level
  status
  incident_date
  recurrence
  created_at
  updated_at

complaint_private_contents
  complaint_id
  original_content_encrypted
  encryption_key_ref
  created_at

complaint_public_contents
  complaint_id
  title
  sanitized_content
  expected_outcome
  created_at
  updated_at
```

## 8. Camadas do Backend

### Domain

Contem entidades, value objects e regras puras.

Exemplos:

- `Complaint`
- `ComplaintStatus`
- `RiskLevel`
- `CanSendToCompany()`
- `RequiresHumanReview()`

Nao deve conhecer:

- HTTP.
- SQL.
- JSON.
- Frameworks.
- Provedor de IA.

### Application

Contem casos de uso.

Exemplos:

- `RegisterUser`
- `CreateComplaint`
- `AnalyzeComplaint`
- `ReviewComplaint`
- `SendComplaintToCompany`
- `SubmitCompanyResponse`
- `CloseComplaint`

Essa camada orquestra dominio, repositorios, transacoes, auditoria e eventos.

### Infrastructure

Implementa detalhes externos:

- PostgreSQL.
- Email.
- IA.
- Fila.
- Criptografia.
- Storage.

### Transport

Expoe interfaces:

- HTTP REST.
- Webhooks.
- Jobs internos.

Handlers devem ser finos: parseiam request, chamam caso de uso e retornam resposta.

## 9. Modulos Funcionais

### 9.1 Autenticacao

Funcionalidades:

- Cadastro de trabalhador.
- Login.
- Logout.
- Refresh de sessao.
- Recuperacao de senha.
- Verificacao de email.
- Perfis e permissoes.

Requisitos:

- Senha nunca armazenada em texto puro.
- Rate limit em login.
- Bloqueio temporario por tentativas excessivas.
- Tokens com expiracao curta.
- Refresh token revogavel.
- Auditoria de login administrativo.

### 9.2 Onboarding Psicossocial

Funcionalidades:

- Coletar contexto de trabalho.
- Coletar percepcao de seguranca psicologica.
- Coletar expectativa de acompanhamento.
- Permitir pular perguntas opcionais.

Requisitos:

- Perguntas versionadas.
- Respostas associadas ao usuario e/ou manifestacao.
- Minimizar coleta de dados.
- Separar dados de perfil de dados de caso.

### 9.3 Empresas

Funcionalidades:

- Buscar empresa.
- Visualizar dados publicos.
- Marcar empresa como verificada, pendente ou base publica.
- Associar usuario de empresa.
- Manter contatos institucionais.

Requisitos:

- Uma empresa nao pode ver relatos de outra.
- Usuario empresa so acessa caso explicitamente enviado a ela.
- Alteracoes de contato geram auditoria.

### 9.4 Manifestacoes

Funcionalidades:

- Criar manifestacao.
- Informar categoria sugerida ou livre.
- Informar data/periodo.
- Informar recorrencia.
- Informar expectativa.
- Salvar rascunho.
- Enviar para analise.
- Acompanhar timeline.

Requisitos:

- Criacao deve gerar status `Recebida`.
- Conteudo original deve ser protegido.
- Toda manifestacao deve ter status atual e historico.
- Trabalhador so acessa as proprias manifestacoes.
- Admin acessa de acordo com permissao.

### 9.5 IA, Anonimizacao e Risco

Funcionalidades:

- Classificar categoria.
- Detectar PII: nomes, locais, datas, areas pequenas, cargos unicos, eventos raros.
- Sugerir texto anonimizado.
- Sugerir risco.
- Sugerir mensagem institucional.
- Marcar necessidade de revisao humana.

Conceitos complexos:

- Risco de reidentificacao: mesmo sem nome, combinacoes de area, data, cargo e evento podem identificar a pessoa.
- Privacidade diferencial nao e requisito do MVP, mas agregacoes e rankings devem evitar grupos pequenos.
- Explicabilidade operacional: a IA deve registrar motivos suficientes para revisao humana.
- Defesa contra prompt injection: relatos podem conter instrucoes maliciosas tentando manipular a IA.
- Separacao de contexto: a IA nao deve receber mais dados pessoais do que o necessario.

Requisitos:

- Nunca enviar automaticamente caso de risco alto.
- Persistir prompt version, modelo, saida, confianca e decisao.
- Permitir reprovar sugestao da IA.
- Permitir editar texto protegido.
- Gerar auditoria de toda aprovacao.

### 9.6 Revisao Humana

Funcionalidades:

- Fila por risco, idade do caso e categoria.
- Atribuicao de revisores.
- Revisao do texto original.
- Revisao da versao protegida.
- Aprovacao, edicao, bloqueio ou pedido de complemento.

Requisitos:

- Acesso ao original deve ser restrito e auditado.
- Revisao deve registrar justificativa.
- Dois pares de olhos para casos de alto risco pode ser requisito futuro.
- SLA de revisao deve ser medido.

### 9.7 Comunicacao com Empresa

Funcionalidades:

- Enviar convite.
- Gerar link seguro para caso.
- Disponibilizar relato protegido.
- Receber resposta.
- Atualizar status.

Requisitos:

- Empresa nao ve original.
- Empresa nao ve identidade do trabalhador.
- Link deve expirar ou exigir login.
- Resposta gera evento na timeline.
- Conteudo ofensivo ou identificavel na resposta pode exigir moderacao.

### 9.8 Timeline e Feedback

Funcionalidades:

- Mostrar historico do caso.
- Mostrar resposta da empresa.
- Permitir avaliar utilidade.
- Permitir finalizar ou continuar acompanhamento.

Requisitos:

- Linguagem simples para trabalhador.
- Eventos internos sensiveis nao devem vazar.
- Diferenciar status operacional de texto exibido ao usuario.

### 9.9 Metricas e Ranking

Funcionalidades:

- Calcular volume por empresa.
- Calcular taxa de resposta.
- Calcular tempo medio de primeira resposta.
- Calcular casos tratados.
- Calcular feedback agregado.
- Gerar ranking de responsividade.

Conceitos complexos:

- Evitar ranking com amostra pequena.
- Evitar expor metricas que permitam inferir identidade.
- Separar indicador operacional de diagnostico psicossocial.
- Score deve ser explicavel e recalculavel.

Requisitos:

- Volume minimo para publicar score.
- Janelas temporais claras.
- Snapshots historicos.
- Empresas nao compram nota.
- Ranking nao e certificacao.

## 10. Requisitos Nao Funcionais

### Seguranca

- TLS obrigatorio fora do ambiente local.
- Criptografia em repouso para campos sensiveis.
- RBAC por perfil.
- Auditoria de acesso a relato original.
- Rate limiting.
- Protecao contra CSRF se usar cookies.
- Protecao contra XSS no front-end.
- Headers seguros.
- Segredos fora do repositorio.

### Privacidade e LGPD

- Consentimento versionado.
- Base legal documentada.
- Minimização de dados.
- Retencao definida.
- Exclusao/anomizacao sob solicitacao quando aplicavel.
- Relato original segregado.
- Logs sem dados sensiveis.
- Acesso administrativo justificado.

### Confiabilidade

- Backups automaticos.
- Migracoes reversiveis quando possivel.
- Health checks.
- Graceful shutdown.
- Retry com backoff para tarefas externas.
- Idempotencia em envio de notificacoes.
- Dead-letter para jobs com falha.

### Performance

- P95 de API abaixo de 300ms para operacoes simples.
- P95 abaixo de 1s para listagens filtradas.
- Paginacao obrigatoria em listagens.
- Indices em filtros frequentes.
- Processamento de IA fora do request sincrono quando demorado.

### Observabilidade

- Logs estruturados em JSON.
- Request ID.
- Trace ID.
- Metricas RED: rate, errors, duration.
- Metricas de fila.
- Metricas de IA: latencia, erro, custo, taxa de revisao.
- Dashboards por modulo.

### Manutenibilidade

- Casos de uso pequenos e testaveis.
- Domínio sem dependencia de framework.
- Migrations versionadas.
- Contratos de API documentados.
- Testes de regras criticas.
- Lint no CI.

### Escalabilidade

- API stateless.
- Banco com indices e pool configurado.
- Jobs separados da API.
- Arquitetura preparada para separar worker.
- Cache apenas onde houver necessidade clara.

## 11. Infraestrutura Robusta

### Local

Recursos:

- Docker Compose.
- PostgreSQL.
- Redis opcional.
- Mailpit.
- Variaveis em `.env.local`.
- Seeds para desenvolvimento.

### Staging

Recursos recomendados:

- 1 instancia/container para API.
- 1 instancia/container para worker.
- PostgreSQL gerenciado pequeno.
- Redis gerenciado se adotado.
- Storage de secrets.
- Logs centralizados.
- Domínio separado.
- Dados ficticios ou anonimizados.

### Producao MVP

Recursos recomendados:

- API com pelo menos 2 replicas.
- Worker com pelo menos 1 replica.
- PostgreSQL gerenciado com backup automatico.
- Redis/fila gerenciada se necessario.
- Load balancer.
- TLS gerenciado.
- Secret manager.
- Observabilidade centralizada.
- Alertas.
- Rotina de backup e restore testada.

### Capacidade Inicial Sugerida

Para inicio:

- API: 1 vCPU / 512MB a 1GB RAM por replica.
- Worker: 1 vCPU / 512MB RAM.
- Postgres: 1 a 2 vCPU / 1 a 2GB RAM.
- Storage: comecar pequeno, mas com backup.

Escalar quando:

- Latencia P95 subir de forma consistente.
- Pool de conexoes saturar.
- Jobs acumularem.
- Custo/latencia de IA impactar experiencia.
- Listagens ficarem lentas por falta de indice.

## 12. CI/CD

Pipeline minimo:

```text
pull request
  -> npm build
  -> go test ./...
  -> go vet ./...
  -> golangci-lint run
  -> checar migracoes
  -> build da imagem Docker
```

Deploy:

- Ambiente staging automatico na branch principal.
- Producao com aprovacao manual.
- Rodar migracoes antes da nova versao, com cuidado.
- Rollback documentado.

## 13. Contratos de API

Cada endpoint deve definir:

- Metodo.
- Path.
- Autenticacao exigida.
- Perfil permitido.
- Request body.
- Response body.
- Erros possiveis.
- Eventos gerados.
- Auditoria necessaria.

Exemplo:

```text
POST /api/complaints
Perfil: trabalhador

Entrada:
  company_id
  category
  title
  original_content
  expected_outcome
  incident_date
  recurrence

Saida:
  complaint_id
  status
  created_at

Efeitos:
  cria complaint
  salva conteudo original protegido
  cria evento de status Recebida
  agenda job de analise por IA
  cria audit log
```

## 14. Eventos de Dominio

Eventos importantes:

- `UserRegistered`
- `ComplaintCreated`
- `ComplaintAnalysisRequested`
- `ComplaintAnalyzed`
- `HumanReviewRequired`
- `ReviewApproved`
- `ComplaintSentToCompany`
- `CompanyResponded`
- `ComplaintClosed`
- `MetricSnapshotGenerated`

Beneficios:

- Reduz acoplamento.
- Facilita auditoria.
- Permite jobs assincronos.
- Ajuda a evoluir para mensageria real no futuro.

## 15. Politicas Criticas de Produto

### Promessa de Identidade

Usar linguagem:

```text
Protecao de identidade
```

Evitar promessa absoluta:

```text
Anonimato garantido
```

Motivo: em ambientes pequenos, detalhes contextuais podem reidentificar uma pessoa mesmo sem nome.

### Risco Alto

Regra:

```text
Risco alto nunca dispara contato automatico com empresa.
```

Deve ir para revisao humana.

### Ranking

Regra:

```text
Ranking mede responsividade observavel, nao certifica saude psicossocial.
```

Deve haver volume minimo para pontuar.

## 16. Criterios de Aceite do MVP

O MVP pode ser considerado funcional quando:

- Trabalhador cria conta e login.
- Trabalhador busca empresa.
- Trabalhador cria manifestacao.
- Sistema persiste original e versao protegida separadamente.
- Sistema cria timeline.
- IA ou simulador inicial gera categoria, risco e versao protegida.
- Caso medio/alto entra em revisao humana.
- Admin aprova ou edita envio.
- Empresa recebe apenas versao protegida.
- Empresa responde.
- Trabalhador ve resposta.
- Trabalhador avalia retorno.
- Auditoria registra acoes relevantes.
- Metricas basicas por empresa sao calculadas.
- Sistema roda local com Docker Compose.
- Testes cobrem regras criticas.

## 17. Ordem Recomendada de Implementacao

1. Reorganizar repositorio.
2. Criar Docker Compose com PostgreSQL.
3. Criar backend Go com `healthz` e `readyz`.
4. Criar migracoes iniciais.
5. Implementar auth.
6. Implementar empresas.
7. Implementar criacao de manifestacao.
8. Implementar timeline.
9. Implementar admin list/detail.
10. Implementar triagem de IA simulada.
11. Implementar revisao humana.
12. Implementar envio para empresa.
13. Implementar resposta da empresa.
14. Implementar metricas.
15. Conectar front-end atual na API.
16. Adicionar observabilidade.
17. Preparar staging.

## 18. Decisoes a Tomar Antes de Codar Muito

- Auth sera JWT ou sessao server-side?
- IA sera chamada sincronamente no MVP ou sempre via job?
- O provedor de email sera qual?
- Como sera feita criptografia de campos sensiveis?
- Qual volume minimo para ranking?
- Empresa acessa por login completo ou magic link no MVP?
- Admin de alto privilegio precisa de MFA desde o MVP?
- Qual politica de retencao do relato original?

## 19. Definicao de Robustez Para Este Produto

Robustez aqui nao significa microservicos cedo. Significa:

- Regras sensiveis no backend, nao no front-end.
- Dados sensiveis segregados.
- Toda decisao relevante auditada.
- Casos de risco tratados com revisao humana.
- Jobs idempotentes.
- Banco versionado por migracoes.
- API testada.
- Logs e metricas desde o inicio.
- Infra local reproduzivel.
- Deploy com rollback possivel.

Essa e a base correta para sair da POC sem virar um sistema fragil em uma area onde confianca, seguranca e responsabilidade importam muito.
