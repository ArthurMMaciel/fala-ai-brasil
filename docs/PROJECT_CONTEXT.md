# Contexto do projeto

## Produto

Escuta Aí Brasil é a direção atual de uma plataforma de escuta psicossocial que conecta pessoas trabalhadoras e empresas com proteção de identidade, acompanhamento, resposta institucional e indicadores de responsividade. O código ainda usa os nomes “Ecoa Voz” e “Voz Psicossocial”; a consolidação da marca está pendente.

## Estágio real em 2026-09-30

- POC front-end local e navegável.
- Dados, credenciais, análises e respostas são mocks em memória.
- Não há backend, API, banco, autenticação real, autorização, multi-tenancy, integrações, telemetria, CI/CD ou deploy configurado.
- O build de produção compila com TypeScript estrito e Vite.
- O diretório atual não contém `.git`; é necessário localizar o repositório esperado ou inicializar/conectar um remoto com autorização.
- Há alterações locais em andamento para landing por persona e meios de comunicação, ainda sem commit.

## Personas e fluxos existentes

1. Empregado/ex-empregado: landing, login/cadastro demo, onboarding, busca de empresa, manifestação, revisão simulada e acompanhamento.
2. Empresa/admin: painel operacional, casos, empresas, supervisão de IA e ranking; hoje empresa e administração ainda estão conceitualmente misturadas.
3. Operação humana: prevista nos diagramas e simulada no mesmo front-end.

## Restrições

- Equipe atual: responsável técnico + Codex.
- Prioridade em base simples, segura e sustentável.
- Não antecipar escala nem IA sofisticada.
- Segurança, privacidade, trilha de auditoria e isolamento organizacional são fundamentos do MVP, não acabamento.

## Fontes de verdade

- Estado atual: código em `src/` e este documento.
- Direção arquitetural: `docs/TECHNICAL_VISION.md` e ADRs aceitos.
- Prioridade: `docs/ROADMAP.md` e `docs/tasks/BACKLOG.md`.
- Memória: `docs/PROJECT_MEMORY.md`.
- Material legado útil: `README.md`, `ENGENHARIA.md` e `arquiteturas/`.
