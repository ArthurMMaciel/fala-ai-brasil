# TASK-0003 — Decidir naming do produto

- Status: concluída
- Conclusão: 2026-10-01
- Área: Produto/Arquitetura
- Prioridade: P1
- Estimativa: 0,5 dia de decisão + 1 dia de migração
- Impacto: elimina inconsistência de marca e identificadores

## Problema
Código e documentos usavam nomes anteriores e precisavam de uma identidade única.
## Contexto
Renomear depois de domínios, pacotes e integrações aumenta custo.
## Objetivo
Definir nome público, nome técnico e estratégia de migração.
## Escopo
ADR, inventário de ocorrências e alteração coordenada após aprovação.
## Fora de escopo
Registro de marca e design completo.
## Critérios de aceite
ADR aceita; nomes e domínios pretendidos documentados; código/docs consistentes.
## Riscos
Disponibilidade jurídica e de domínio.
## Dependências
Decisão de produto/jurídico.
## Segurança
Evitar domínios parecidos que favoreçam phishing.
## Dados envolvidos
Nenhum.
## Observabilidade
Não aplicável.
## Rollback
Commit de rename isolado e reversível.
## Testes necessários
Busca global, build e verificação de links/metadados.
## Definição de pronto
Uma identidade oficial sem aliases não explicados.

## Evidência de conclusão

Escuta Aí Brasil foi definida como identidade oficial no ADR-0003 e aplicada ao software, metadados, dados demo, diagramas e documentação.
