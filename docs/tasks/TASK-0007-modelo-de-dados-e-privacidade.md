# TASK-0007 — Definir modelo de dados e privacidade

- Status: proposta
- Área: Dados/Privacidade/DBA
- Prioridade: P1
- Estimativa: 4–6 dias
- Impacto: evita acoplamento e exposição de dados sensíveis

## Problema
Tipos da POC não separam identidade, original, compartilhável, auditoria e analytics.
## Contexto
O produto lida com dados pessoais sensíveis e risco de reidentificação.
## Objetivo
Definir esquema, classificação, finalidade, retenção e acesso antes da persistência real.
## Escopo
ERD, constraints, criptografia, versões compartilháveis, retenção/exclusão e DPIA inicial.
## Fora de escopo
Data warehouse e IA.
## Critérios de aceite
Mapa/dicionário aprovados; nenhuma tabela mistura conteúdo privado e compartilhável; deleção/retenção executáveis.
## Riscos
Criptografia sem gestão de chaves; exclusão inconsistente; analytics reidentificável.
## Dependências
Validação de produto/jurídico e TASK-0006.
## Segurança
Chaves e permissões separadas; acesso ao original auditado.
## Dados envolvidos
Todos os dados pessoais e operacionais.
## Observabilidade
Qualidade, falha de retenção e acesso, sem conteúdo em logs.
## Rollback
Migrações expand/contract e backup antes de mudanças.
## Testes necessários
Constraints, migrações, retenção, exclusão e acesso.
## Definição de pronto
ADR e esquema inicial aprovados, com DPIA/RIPD encaminhado.
