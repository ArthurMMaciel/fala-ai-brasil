# ADR-0001 — Governança documental e rastreabilidade

- Estado: Aceita
- Data: 2026-09-30

## Contexto

O projeto é mantido por uma pessoa com apoio do Codex e precisa reter contexto entre sessões.

## Problema

Documentos anteriores misturam arquitetura desejada, instrução e estado atual; trabalho e decisões não possuem trilha uniforme.

## Opções

Documentação informal; ferramenta externa; Markdown versionado no repositório.

## Decisão

Usar `docs/`, tarefas, ADRs, `PROJECT_MEMORY.md` e skills locais como governança mínima versionada.

## Motivo

Baixo custo, revisão junto ao código e independência de fornecedor.

## Consequências

Mudanças relevantes devem atualizar tarefa/memória/ADR. Documentos precisam de revisão periódica para não divergir.

## Riscos

Burocracia excessiva e desatualização; mitigar com documentos curtos e proporcionais.

## Alternativas rejeitadas

Ferramenta externa como fonte única, por criar custo e fragmentação neste estágio.
