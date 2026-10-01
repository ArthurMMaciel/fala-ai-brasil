# TASK-0005 — Implementar autenticação e sessões

- Status: proposta
- Área: Backend/Segurança
- Prioridade: P1
- Estimativa: 5–8 dias
- Impacto: permite identidade real com controle básico

## Problema
Credenciais demo estão no bundle e não há autenticação real.
## Contexto
O produto tratará dados sensíveis e perfis distintos.
## Objetivo
Cadastro/login/verificação/recuperação e sessões revogáveis seguras.
## Escopo
Hash de senha, cookies seguros, rotação/revogação, rate limit, MFA admin e eventos de segurança.
## Fora de escopo
SSO empresarial na primeira versão.
## Critérios de aceite
Sessões expiram/revogam; senha nunca é armazenada/logada em claro; fluxos de erro não enumeram contas.
## Riscos
Account takeover e bloqueio indevido.
## Dependências
TASK-0008 e decisões de provedor de e-mail.
## Segurança
OWASP ASVS proporcional, SameSite/HttpOnly/Secure, CSRF e brute force.
## Dados envolvidos
E-mail, hash, sessões e eventos.
## Observabilidade
Sucesso/falha de login, rate limit e revogação sem credenciais.
## Rollback
Feature flag/convites fechados; migrações reversíveis sem apagar contas.
## Testes necessários
Happy path, senha inválida, brute force, CSRF, expiração, revogação e MFA admin.
## Definição de pronto
Threat model atualizado, testes verdes e runbook de credencial comprometida.
