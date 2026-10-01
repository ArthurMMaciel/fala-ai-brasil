# ADR-0002 — Monólito modular antes de serviços distribuídos

- Estado: Proposta
- Data: 2026-09-30

## Contexto

O produto é uma POC e a equipe técnica tem uma pessoa.

## Problema

Precisamos de limites claros sem assumir a carga operacional de microserviços.

## Opções

Monólito simples sem módulos; monólito modular; microserviços desde o início.

## Decisão

Proposta: API em monólito modular e um worker apenas para tarefas assíncronas, compartilhando PostgreSQL com fronteiras lógicas.

## Motivo

Entrega e operação simples, transações consistentes e caminho de extração futuro.

## Consequências

Exige disciplina de dependências internas. Serviços serão extraídos somente com evidência de escala/isolamento.

## Riscos

Módulos degradarem em acoplamento; mitigar com testes e contratos.

## Alternativas rejeitadas

Microserviços agora, por custo operacional sem demanda comprovada.
