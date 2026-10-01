# Auditoria técnica do estado atual

Data: 2026-09-30

## Escopo inspecionado

Todo código-fonte, configurações, manifestos, lockfile, documentação e diagramas do repositório; `node_modules/` e `dist/` foram tratados como artefatos gerados.

## Stack e dependências

- TypeScript 5.9.3 com `strict`.
- Vite 5.4.21; Rollup/esbuild transitivos.
- Sem framework, biblioteca de UI, cliente HTTP ou dependência de runtime.
- Build validado com sucesso em 2026-09-30.
- A verificação online de vulnerabilidades do npm não foi concluída pelo comando local por falha do ambiente. A conferência manual em advisories oficiais encontrou Vite 5.4.21 dentro das faixas afetadas por vulnerabilidades de leitura de arquivos no dev server publicadas em 2026; o script limita o host a `127.0.0.1`, reduzindo exposição, mas a atualização para uma linha corrigida deve ser priorizada. Rollup 4.63.3 está acima da correção 4.59.0 para o advisory de path traversal conferido. Esbuild 0.21.5 está em faixa afetada por um advisory do servidor próprio do esbuild; esse servidor não é invocado diretamente pelo projeto, mas a dependência deve ser atualizada junto ao Vite.

## Estrutura e maturidade

- `src/main.ts` (~859 linhas): aplicação inteira, roteamento, estado e handlers.
- `src/styles.css` (~677 linhas): estilos globais e responsivos.
- `src/models.ts`: tipos coerentes para a POC.
- `src/mockData.ts`: fixtures completas, inclusive senha demo em texto claro.
- `arquiteturas/`: cinco diagramas úteis e acessíveis, porém representam alvo conceitual.
- `README.md` e `ENGENHARIA.md`: visão extensa, mas sem status decisório/ADR.

Maturidade estimada: protótipo/POC (nível 1 de 5). Serve para validar jornada e linguagem; não suporta usuários ou dados reais.

## Pontos fortes

- Domínio e personas já foram pensados.
- Princípio correto de separar original e versão protegida.
- Human-in-the-loop e bloqueio de risco alto aparecem na visão.
- TypeScript estrito, lockfile e build simples.
- Interface responsiva, fluxo demonstrável e dados sintéticos.
- Documentação anterior já antecipa Go/PostgreSQL, jobs simples e observabilidade.

## Fragilidades

- `innerHTML` recebe valores controláveis pelo usuário; risco de XSS.
- Autenticação e autorização são apenas condicionais no navegador.
- Papel `admin` também representa empresa; não existe separação de funções.
- Todos os dados privados e compartilháveis convivem no mesmo estado.
- “IA” é transformação fixa; confiança e risco são mocks.
- Cadastro aceita usuário local efêmero; sem verificação, recuperação ou consentimento versionado.
- Sem tratamento central de erro, loading real, persistência, concorrência ou idempotência.
- Sem testes, lint, CI, secrets, ambientes, logs, métricas, tracing, alertas ou runbooks.
- Sem banco, migrações, backup, restore ou política de retenção.
- Sem integração real de comunicação ou verificação do contato da empresa.
- Sem `.git` no diretório atual.

## Segurança e privacidade

A promessa visual é superior aos controles reais. A POC não deve receber dados pessoais reais. XSS, IDOR/tenancy, acesso ao relato original, sessões, rate limiting, logs e fornecedores são as áreas críticas antes do piloto.

## Custos e operação

O custo atual é apenas desenvolvimento local. Não há arquitetura implantada para estimar preço com precisão. A maior ameaça de custo no curto prazo é complexidade operacional incompatível com uma equipe de uma pessoa.

## Conclusão

Não é necessária uma reescrita imediata. Primeiro: versionar, corrigir o risco de XSS, criar testes básicos e decidir contratos de identidade/dados. Em seguida, implementar um backend mínimo modular e PostgreSQL, mantendo o front-end como cliente até o crescimento justificar outra tecnologia.
