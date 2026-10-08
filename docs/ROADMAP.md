# Roadmap

## Fase 0 — Auditoria e organização (agora)

- Governança, memória, riscos, dívida, skills, backlog e ADRs.
- Resolver localização/inicialização do Git e naming.
- Corrigir XSS e criar baseline de testes.

## Fase 1 — Fundação técnica

- Estrutura modular mínima, API, PostgreSQL e migrações.
- Configuração por ambiente, erros, health checks e CI.
- Autenticação, sessões, RBAC e isolamento de organização.
- Modelo de dados privado/compartilhável e auditoria.

## Fase 2 — MVP funcional

- Cadastro/login reais e onboarding minimizado.
- Empresa verificada, manifestação persistida, revisão e timeline.
- Portal da empresa separado e resposta institucional.
- Comunicação idempotente com destino aprovado.
- Cobrança de clientes via Stripe (TASK-0018), após fundação segura e validação comercial/da conta; Checkout, assinaturas com cartão, Boleto BRL condicionado à elegibilidade e Pix avulso condicionado à habilitação. Transferência bancária genérica BRL não está confirmada. Planejamento registrado, ainda sem implementação.

## Fase 3 — Segurança e observabilidade

- Hardening, testes de autorização, gestão de secrets e dependências.
- Logs/métricas/traces, alertas, backups e runbooks testados.
- Revisão de privacidade e preparação do piloto.

## Fase 4 — Dados e analytics

- Eventos confiáveis, qualidade, métricas agregadas e anti-reidentificação.
- Dashboards por perfil e governança de acesso.

## Fase 5 — IA

- Dataset/avaliação, experimento assistivo e revisão humana.
- Auditoria de modelo/prompt, custos, fallback e segurança.

## Fase 6 — Escala e evolução

- Otimização orientada por métricas, HA conforme SLO e extração de serviços só se necessária.
- Evolução de analytics e integrações sob contratos estáveis.

## Gate imediato

Não iniciar piloto com dados reais até fechar: Git, XSS, auth, tenancy, segregação de dados, consentimento/retenção, auditoria, backup e resposta a incidente.
