# ADR-0003 — Escuta Aí Brasil como identidade oficial

- Estado: Aceita
- Data: 2026-10-01

## Contexto

O projeto acumulou referências a nomes anteriores no software, dados demo, documentos e diagramas.

## Problema

A inconsistência de identidade gerava confusão de produto, comunicação e manutenção.

## Opções

Manter aliases temporários; adiar a decisão; consolidar toda a plataforma sob uma única identidade.

## Decisão

Adotar “Escuta Aí Brasil” como nome oficial do produto e `escuta-ai-brasil` como nome técnico do pacote.

## Motivo

Uma identidade única reduz ambiguidade e evita ampliar o custo de migração conforme surgem domínio, integrações e ambientes.

## Consequências

Interfaces, metadados, documentação, dados demonstrativos e novos ativos devem usar Escuta Aí Brasil.

## Riscos

O nome do repositório remoto permanece `fala-ai-brasil`; uma eventual alteração deve ser coordenada para não quebrar integrações.

## Alternativas rejeitadas

Manter múltiplos nomes como aliases públicos, por aumentar confusão sem benefício técnico.
