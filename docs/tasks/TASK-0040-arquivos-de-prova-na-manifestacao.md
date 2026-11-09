# TASK-0040 — Arquivos de prova enviados pelo trabalhador

- Status: proposta (aguardando decisão do responsável; sem código)
- ClickUp: [TASK-0040](https://app.clickup.com/t/17tu7rpcghk)
- Área: Backend/Frontend/DevOps/Privacidade/Jurídico
- Prioridade: P2
- Estimativa: 3 a 5 dias após a aprovação (bucket, quarentena, cópia limpa, RPCs, telas dos três portais e testes). O teste de viabilidade da conversão de PDF vem antes.
- Impacto: o trabalhador anexa provas sem que elas o identifiquem para a empresa
- Decisão estrutural proposta: [ADR-0019](../adr/ADR-0019-arquivos-de-prova-na-manifestacao.md)
- Relacionadas: ADR-0010, TASK-0007, `docs/security/THREAT_MODEL.md`

## Problema
A manifestação não aceita arquivos. Arquivos trazem metadados e conteúdo que identificam o trabalhador, podem conter dado de saúde e podem ser maliciosos. Não há varredura de vírus no Supabase. Nenhum documento define qual plano recebe provas.

## Objetivo
- Original privado, como o relato original: só o trabalhador e a equipe leem, com justificativa registrada.
- A empresa recebe só uma cópia regravada, sem metadados, liberada pela equipe e conforme o plano, por link de 5 minutos e com registro de acesso.
- Limites de tipo e tamanho, quarentena e aviso contra documentos de saúde.

## Escopo
- Bucket `complaint-evidence`.
- Tabelas `complaint_evidence` e `evidence_access_log`.
- Edge Function de quarentena e de cópia limpa.
- RPCs do trabalhador, da equipe e da empresa.
- Telas nos três portais.
- Testes.

## Fora de escopo
- Áudio, vídeo e documentos Office.
- Antivírus próprio (opção (a) da ADR-0019).
- Inclusão do Storage no backup (decisão à parte).

## Critérios de aceite
Os testes previstos na ADR-0019 passam. Nenhum caminho entrega o original à empresa. A cópia limpa não tem metadados.

## Riscos
Ver a ADR-0019: reidentificação pelo conteúdo visível, carga da equipe, dado de saúde, viabilidade da conversão de PDF e ausência de backup do Storage.

## Dependências
- Decisões 1 a 6 da ADR-0019, entre elas a regra de planos.
- TASK-0007 (base legal e retenção).
- Confirmação da cota do Storage pelo DevOps.

## Rollback
Desligar o envio e revogar as RPCs. Os arquivos ficam privados até a decisão de apagar.

## Texto para o ClickUp
Título: TASK-0040 — Arquivos de prova enviados pelo trabalhador

Descrição:
- Anexos JPEG, PNG ou PDF na manifestação, em bucket privado e com quarentena.
- O original nunca vai à empresa.
- A empresa recebe, conforme o plano e após liberação da equipe, uma cópia regravada sem metadados, por link de 5 minutos e com registro de acesso.
- Aviso contra documentos de saúde.
- Retenção conforme a TASK-0007.
- Prioridade P2.
- Documentos: docs/tasks/TASK-0040-arquivos-de-prova-na-manifestacao.md e docs/adr/ADR-0019-arquivos-de-prova-na-manifestacao.md.
- Status: proposta, aguardando decisão do responsável.
