# TASK-0002 — Eliminar XSS na POC

- Status: proposta
- ClickUp: [TASK-0002](https://app.clickup.com/t/86aktn715)
- Área: Segurança/Frontend
- Prioridade: P0
- Estimativa: 1–2 dias
- Impacto: remove execução de conteúdo inserido pelo usuário

## Problema
Valores de nome, relato, resposta e contato entram em templates de `innerHTML`.
## Contexto
O fluxo já aceita texto livre; payloads HTML podem executar no navegador.
## Objetivo
Garantir encoding seguro e reduzir superfícies HTML dinâmicas.
## Escopo
Inventariar sinks/sources, criar renderização segura, CSP compatível e testes de payloads.
## Fora de escopo
Migração total para framework.
## Critérios de aceite
Payloads comuns de XSS aparecem como texto; nenhum dado não confiável chega cru ao HTML; build e fluxos passam.
## Riscos
Quebrar destaques/redações intencionais.
## Dependências
Baseline de testes da interface pode ser feito em conjunto com TASK-0004.
## Segurança
Cobrir stored/reflected/DOM XSS conceitualmente, inclusive atributos.
## Dados envolvidos
Relato e dados de perfil sintéticos.
## Observabilidade
No backend futuro, métricas de violações CSP sem registrar payload sensível.
## Rollback
Reverter patch; não desativar encoding para recuperar formatação.
## Testes necessários
Unitários do encoder e E2E com `<img onerror>`, tags, aspas e Unicode.
## Definição de pronto
Revisão de segurança concluída e testes automatizados verdes.
