# Diretrizes para agentes — Escuta Aí Brasil

## Missão

Evoluir a plataforma com pragmatismo, segurança, privacidade e rastreabilidade. O repositório está em transição de POC para MVP; não descreva capacidades planejadas como se já estivessem implementadas.

## Ordem de trabalho

1. Ler `docs/PROJECT_CONTEXT.md`, `docs/PROJECT_MEMORY.md`, `docs/ROADMAP.md` e a tarefa ativa em `docs/tasks/`.
2. Inspecionar o código e o estado do Git antes de alterar.
3. Classificar riscos de segurança, privacidade, dados, operação e custo.
4. Registrar trabalho relevante em tarefa; decisões estruturais em ADR.
5. Fazer a menor mudança coerente, testar e atualizar a documentação afetada.

## Regras obrigatórias

- Não introduzir IA, serviços externos, persistência de dados pessoais ou infraestrutura paga sem tarefa e decisão registradas.
- Nunca enviar relatos, identidade ou dados psicossociais a terceiros sem avaliação de privacidade, base legal e controles documentados.
- Não misturar relato original com versão compartilhável. O acesso ao original deve ser excepcional e auditável.
- Empresa não acessa identidade do manifestante nem dados de outra organização.
- Casos de alto risco não geram contato externo automático.
- Não registrar conteúdo sensível, tokens ou credenciais em logs.
- Secrets ficam fora do código e do Git.
- Mudanças de autenticação, autorização, tenancy, retenção, IA ou arquitetura exigem ADR.
- Evitar novas dependências sem justificar manutenção, segurança e custo.
- Preservar a POC enquanto a fundação do MVP não estiver pronta; evitar refatoração massiva.

## Qualidade mínima

- Critérios de aceite e testes proporcionais ao risco.
- Estados de erro e validação explícitos.
- Acessibilidade básica em fluxos críticos.
- Plano de rollback para mudanças operacionais.
- Atualizar `docs/PROJECT_MEMORY.md` quando houver decisão ou mudança relevante.

## Convenções

- Tarefas: `docs/tasks/TASK-NNNN-titulo.md`.
- ADRs: `docs/adr/ADR-NNNN-titulo.md`.
- Prioridades: P0 crítico/bloqueio, P1 essencial ao MVP, P2 importante, P3 melhoria, P4 futuro.
- Status de tarefa: proposta, pronta, em-andamento, bloqueada, concluída, cancelada.
- Skills locais ficam em `.codex/skills/<nome>/SKILL.md` e complementam, sem substituir, estas regras.

## Bloqueios que exigem decisão humana

- Nome oficial do produto e domínio.
- Provedor de nuvem, identidade, comunicação ou IA.
- Base legal, prazos de retenção e política de exclusão.
- Promessas públicas de anonimato/proteção.
- Abertura de remoto, deploy público ou uso de credenciais.
