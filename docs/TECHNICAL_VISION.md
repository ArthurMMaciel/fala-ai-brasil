# Visão técnica

## Objetivo

Chegar a um MVP operável por uma equipe pequena, com segurança e privacidade verificáveis, sem distribuir o sistema prematuramente.

## Arquitetura recomendada para o MVP

- Front-end web tipado, organizado por features.
- API em monólito modular, com contratos versionados.
- PostgreSQL como fonte transacional e, inicialmente, fila de jobs.
- Worker separado apenas para tarefas assíncronas e integrações.
- Armazenamento lógico separado para identidade, conteúdo privado e conteúdo compartilhável.
- Sessões seguras e RBAC com escopo de organização.
- Logs estruturados sem conteúdo sensível, métricas essenciais e trilha de auditoria dedicada.

## Princípios

1. Modularidade antes de distribuição.
2. Contratos explícitos e migrações reversíveis.
3. Menor privilégio e negação por padrão.
4. Privacidade por desenho e minimização.
5. Observabilidade proporcional ao risco.
6. Serviços gerenciados simples quando reduzirem carga operacional sem lock-in crítico.
7. IA assistiva, avaliada e auditável; nunca autoridade final em caso sensível.

## Horizonte

- Agora: governança, Git, proteção contra XSS, testes mínimos e decisões de identidade/dados.
- Em breve: API, banco, auth, tenancy, auditoria e ambientes.
- Depois: comunicações reais, analytics governado e IA assistiva.
- Futuro: escala horizontal, separação de workloads e data platform conforme volume comprovado.

## Limites

Não adotar microserviços, Kubernetes, event streaming, data lake, RAG ou múltiplos bancos na fundação sem requisito mensurável e ADR.
