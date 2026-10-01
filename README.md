# Ecoa Voz / Voz Psicossocial

> **Status:** POC local. A direção atual do produto é “Escuta Aí Brasil”, com naming ainda pendente de decisão formal. Para o estado real, prioridades e governança, consulte [`docs/PROJECT_CONTEXT.md`](docs/PROJECT_CONTEXT.md), [`docs/ROADMAP.md`](docs/ROADMAP.md) e [`docs/tasks/BACKLOG.md`](docs/tasks/BACKLOG.md).

Plataforma de escuta psicossocial para trabalhadores relatarem situacoes do ambiente de trabalho com protecao de identidade, acompanhamento de status, resposta institucional da empresa e indicadores agregados de responsividade.

Este repositorio hoje contem uma POC front-end em TypeScript/Vite com dados simulados. O objetivo deste documento e orientar a evolucao para um MVP real, com backend em Go, arquitetura preparada para seguranca, auditoria, privacidade e crescimento.

## Estado Atual

Implementado atualmente:

- Front-end em Vite + TypeScript puro.
- Estado em memoria no navegador.
- Dados simulados em `src/mockData.ts`.
- Fluxos navegaveis de trabalhador e administrador.
- Modelos de dominio em `src/models.ts`.
- Diagramas de arquitetura e fluxos por persona em `arquiteturas/`.

Ainda nao existe:

- Backend.
- Banco de dados.
- Autenticacao real.
- API HTTP.
- Motor real de IA.
- Persistencia de manifestacoes, historico, respostas ou auditoria.
- Controle real de permissoes.
- Criptografia de dados sensiveis.
- Logs imutaveis.
- Esteiras de teste, observabilidade e deploy.

## Visao do Produto

O produto deve permitir que uma pessoa trabalhadora:

1. Crie uma conta e informe contexto minimo.
2. Busque ou selecione a empresa relacionada.
3. Registre uma manifestacao em linguagem natural.
4. Revise uma versao protegida/anonimizada antes do envio.
5. Acompanhe status, timeline e retorno institucional.
6. Avalie se a resposta foi util e se o caso pode ser encerrado.

Tambem deve permitir que a operacao/admin:

1. Acompanhe volume, risco, categorias e prazos.
2. Revise casos sensiveis antes de qualquer contato externo.
3. Compare relato original e versao anonimizada.
4. Aprove, edite ou bloqueie sugestoes da IA.
5. Registre comunicacoes e respostas.
6. Consulte trilha de auditoria.
7. Monitore indicadores agregados por empresa.

E deve permitir que empresas:

1. Recebam apenas a versao protegida do relato.
2. Respondam institucionalmente.
3. Acompanhem prazos e historico dos casos destinados a elas.
4. Melhorem indicadores por comportamento observavel: resposta, tempo e tratamento.

## Principios Arquiteturais

- Protecao de identidade antes de integracao com empresas.
- Separacao clara entre relato original e versao compartilhavel.
- Human in the loop para casos medios e altos.
- Nenhuma automacao externa para casos de alto risco antes de revisao humana.
- Auditoria de decisoes humanas e automatizadas.
- Ranking como indicador de responsividade, nao certificacao de saude psicossocial.
- LGPD como requisito de arquitetura, nao camada posterior.
- Backend orientado a dominio, com contratos estaveis e testaveis.
- MVP simples, mas com fundacao robusta.

## Arquitetura Alvo

Fluxo macro:

```text
Trabalhador
  -> Web App
  -> API Go
  -> Banco transacional
  -> Motor de triagem/IA
  -> Fila de revisao humana
  -> Empresa
  -> Timeline / Feedback
  -> Metricas agregadas / Ranking
```

Componentes principais:

```text
apps/
  web/                 Front-end do trabalhador, admin e empresa

services/
  api/                 Backend principal em Go
  worker/              Processamento assincrono: IA, notificacoes, metricas

internal/
  domain/              Entidades e regras de negocio
  application/         Casos de uso
  transport/http/      Handlers REST
  infrastructure/      Banco, email, storage, IA, filas

db/
  migrations/          Migracoes SQL

arquiteturas/
  *.svg                Diagramas de produto e fluxos
```

## Backend em Go

Stack sugerida para o MVP:

- Go 1.23+.
- `net/http` ou `chi` para roteamento HTTP.
- PostgreSQL como banco principal.
- `pgx` para acesso ao banco.
- `sqlc` ou repository pattern manual para queries tipadas.
- `goose` ou `tern` para migracoes.
- JWT ou sessoes server-side para autenticacao.
- OpenTelemetry para tracing e metricas.
- Zap ou slog para logs estruturados.
- Testes com `testing`, `httptest` e banco de teste.

Estrutura recomendada:

```text
services/api/
  cmd/api/main.go
  internal/
    domain/
      user.go
      company.go
      complaint.go
      ai_analysis.go
      audit_log.go
    application/
      auth_service.go
      complaint_service.go
      review_service.go
      company_service.go
      metrics_service.go
    transport/http/
      router.go
      auth_handler.go
      complaint_handler.go
      admin_handler.go
      company_handler.go
    infrastructure/
      postgres/
      queue/
      mailer/
      ai/
      crypto/
```

## Modulos do Dominio

### Autenticacao e Usuarios

Responsabilidades:

- Cadastro e login.
- Recuperacao de senha.
- Verificacao de email.
- Perfis: trabalhador, admin/operacao, empresa.
- Controle de sessao e permissoes.

Entidades:

- `users`
- `user_profiles`
- `sessions` ou `refresh_tokens`
- `roles`

### Empresas

Responsabilidades:

- Cadastro/base publica de empresas.
- Dados de contato institucional.
- Status de verificacao.
- Usuarios vinculados a empresa.

Entidades:

- `companies`
- `company_contacts`
- `company_users`
- `company_verification_events`

### Manifestacoes

Responsabilidades:

- Criacao de relato.
- Armazenamento seguro do texto original.
- Versao protegida/anonimizada.
- Categoria, risco, recorrencia e expectativa.
- Status e timeline.

Entidades:

- `complaints`
- `complaint_private_contents`
- `complaint_public_contents`
- `complaint_status_history`
- `complaint_feedback`

Observacao importante: o texto original deve ter tratamento diferente da versao protegida. O acesso ao original precisa ser muito mais restrito.

### IA e Triagem

Responsabilidades:

- Classificar categoria.
- Sugerir nivel de risco.
- Detectar dados identificaveis.
- Gerar versao protegida.
- Sugerir mensagem institucional.
- Informar confianca e motivos da classificacao.

Entidades:

- `ai_analyses`
- `ai_redaction_suggestions`
- `ai_decision_logs`

Regras:

- Risco baixo pode seguir fluxo automatizavel, com auditoria.
- Risco medio exige aprovacao humana antes de contato externo.
- Risco alto bloqueia qualquer contato automatico ate revisao humana.

### Revisao Humana

Responsabilidades:

- Fila de casos sensiveis.
- Aprovar, editar, reprovar ou devolver sugestao da IA.
- Registrar decisao e justificativa.

Entidades:

- `review_tasks`
- `review_decisions`
- `review_assignments`

### Comunicacao com Empresas

Responsabilidades:

- Enviar convite ou notificacao.
- Disponibilizar relato protegido.
- Receber resposta institucional.
- Atualizar timeline do trabalhador.

Entidades:

- `company_case_links`
- `company_responses`
- `outbound_messages`
- `message_delivery_events`

### Auditoria

Responsabilidades:

- Registrar quem fez o que, quando, em qual caso e com qual resultado.
- Registrar decisoes automatizadas e humanas.
- Permitir rastreabilidade sem expor dados alem do necessario.

Entidades:

- `audit_logs`
- `access_logs`
- `data_access_events`

### Metricas e Ranking

Responsabilidades:

- Taxa de resposta.
- Tempo medio de primeira resposta.
- Percentual de casos tratados.
- Feedback de utilidade.
- Indicador de recorrencia.
- Score agregado de responsividade.

Entidades:

- `company_metrics_snapshots`
- `company_scores`
- `ranking_snapshots`

## API Inicial do MVP

Endpoints sugeridos:

```text
POST   /api/auth/register
POST   /api/auth/login
POST   /api/auth/logout
GET    /api/me

GET    /api/companies
GET    /api/companies/{id}

POST   /api/complaints
GET    /api/complaints
GET    /api/complaints/{id}
POST   /api/complaints/{id}/feedback

GET    /api/admin/complaints
GET    /api/admin/complaints/{id}
POST   /api/admin/complaints/{id}/review
POST   /api/admin/complaints/{id}/send-to-company
POST   /api/admin/complaints/{id}/status

GET    /api/company/cases
GET    /api/company/cases/{id}
POST   /api/company/cases/{id}/responses

GET    /api/admin/metrics
GET    /api/ranking
```

## Estados da Manifestacao

Estados iniciais:

```text
Recebida
Em analise
Revisao necessaria
Empresa sendo contatada
Aguardando resposta da empresa
Respondida
Em mediacao
Finalizada
Encerrada sem resposta
```

Regras importantes:

- Todo status deve gerar evento em `complaint_status_history`.
- Mudancas manuais devem gerar `audit_logs`.
- A empresa nunca deve receber texto original identificavel.
- O trabalhador deve ver uma timeline clara e legivel.

## Banco de Dados

Banco recomendado: PostgreSQL.

Tabelas iniciais:

```text
users
user_profiles
companies
company_users
complaints
complaint_private_contents
complaint_public_contents
complaint_status_history
ai_analyses
review_tasks
review_decisions
company_responses
audit_logs
company_metrics_snapshots
```

Cuidados:

- Criptografar campos sensiveis em repouso.
- Separar conteudo original de conteudo compartilhavel.
- Ter indices por `company_id`, `user_id`, `status`, `risk_level` e `created_at`.
- Evitar soft delete generico para dados sensiveis sem politica clara de retencao.
- Registrar acessos a dados sensiveis.

## Seguranca e LGPD

Requisitos minimos para MVP:

- Consentimento explicito e versionado.
- Politica clara de retencao e exclusao.
- Controle de acesso por perfil.
- Criptografia em transito e em repouso.
- Segregacao entre dados identificaveis e relato compartilhavel.
- Auditoria de acesso ao relato original.
- Minimizacao de dados coletados.
- Revisao humana em risco medio/alto.
- Mensagens claras: "protecao de identidade" em vez de promessa de anonimato absoluto.

## Observabilidade

O backend deve nascer com:

- Logs estruturados.
- Request ID por requisicao.
- Metricas de latencia, erro e throughput.
- Tracing para chamadas de IA, banco e notificacao.
- Alertas para falhas de envio, fila parada e erro em processamento de IA.

## Testes

Cobertura minima:

- Testes unitarios de regras de status.
- Testes de permissao por perfil.
- Testes de criacao de manifestacao.
- Testes de bloqueio de envio para risco alto.
- Testes de anonimizacao/sanitizacao com fixtures.
- Testes de handlers HTTP principais.
- Testes de migracoes.

## Roadmap MVP

### Fase 1 - Fundacao

- Criar monorepo organizado em `apps/web` e `services/api`.
- Criar backend Go com health check, config e logs.
- Criar PostgreSQL local via Docker Compose.
- Criar migracoes iniciais.
- Implementar auth basica.
- Migrar modelos do TypeScript para entidades Go/SQL.

### Fase 2 - Manifestacoes

- Criar fluxo real de criacao de manifestacao.
- Persistir relato original e versao protegida.
- Implementar timeline.
- Implementar listagem do trabalhador.
- Implementar detalhe do caso.

### Fase 3 - Admin e Revisao

- Painel admin com filtros.
- Detalhe do caso com abas: resumo, relato, IA, comunicacao e auditoria.
- Fila de revisao humana.
- Registro de decisoes.
- Alteracao controlada de status.

### Fase 4 - IA Assistida

- Integrar provedor de IA.
- Gerar classificacao, risco, PII e versao protegida.
- Persistir analise e confianca.
- Aplicar regras de human in the loop.
- Criar fixtures e testes para casos sensiveis.

### Fase 5 - Empresa e Resposta

- Criar acesso de empresa.
- Disponibilizar relato protegido.
- Permitir resposta institucional.
- Atualizar timeline do trabalhador.
- Medir prazo de resposta.

### Fase 6 - Metricas e Ranking

- Criar snapshots de metricas.
- Calcular score de responsividade.
- Publicar ranking com limites claros.
- Evitar qualquer comunicacao de certificacao.

## Como Rodar a POC Atual

Instalar dependencias:

```bash
npm install
```

Rodar em desenvolvimento:

```bash
npm run dev
```

Gerar build:

```bash
npm run build
```

## Proxima Decisao Tecnica

A proxima etapa recomendada e criar a fundacao do backend Go em `services/api`, com:

- `GET /healthz`
- config por variaveis de ambiente
- logger estruturado
- conexao PostgreSQL
- primeira migracao
- entidade `User`
- entidade `Company`
- entidade `Complaint`

Depois disso, a POC deixa de ser apenas navegavel e passa a ter o primeiro nucleo real de produto.

Para o plano tecnico detalhado de engenharia, stack, instalacao, infraestrutura, requisitos funcionais e nao funcionais, consulte `ENGENHARIA.md`.
