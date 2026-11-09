# TASK-0038 — Busca de CNPJ por serviço externo, via Edge Function

- Status: proposta (aguardando aprovação do responsável; sem código nem migration)
- ClickUp: (preencher após a criação; texto pronto no fim deste documento)
- Área: Backend/DevOps/Privacidade
- Prioridade: P1 (é a fonte (b) da base de empresas do piloto, ADR-0012 D9)
- Estimativa: 1 a 1,5 dia para a função e os testes (parecer do DevOps, R4.1), mais cerca de 0,5 dia para as RPCs e o teste de banco, depois da migration da ADR-0012
- Impacto: o trabalhador encontra ou pré-cadastra a empresa pelo CNPJ sem expor ao terceiro a própria identidade nem a relação com o empregador
- Decisão estrutural proposta: [ADR-0017](../adr/ADR-0017-busca-de-cnpj-por-servico-externo.md)

## Problema
A ADR-0012 prevê a empresa pré-cadastrada criada a partir de uma busca por CNPJ, mas não define o provedor, o ponto da chamada nem a proteção dos dados. Pelo desenho atual, o front enviaria ao banco os dados da empresa, que podem ser forjados.

## Contexto
O DevOps testou três provedores em 2026-11-08 e recomendou Minha Receita como principal, BrasilAPI como reserva e a chamada por Edge Function (parecer de plataforma, Revisão 4, R4.1). Nenhum provedor tem SLA.

## Objetivo
Implementar a busca com só o CNPJ saindo para o terceiro, sem guardar nem devolver dado de pessoa física, com cache de 30 dias, limite por conta, logs sem a ligação conta–CNPJ e preenchimento manual sempre disponível.

## Escopo
- Edge Function `cnpj-lookup` (D2 a D7, D9 e D10 da ADR-0017).
- Tabelas `private.cnpj_cache` e `private.cnpj_lookup_quota`, com limpeza diária.
- RPCs `preregister_company(p_cnpj)` e `preregister_company_manual(...)`, que substituem o `preregister_company(p jsonb)` da ADR-0012.
- Valor `manual` em `companies.data_source`.

## Fora de escopo
- Tela de busca no portal do trabalhador (Front, depois da aprovação).
- Lista curada (ADR-0012, D9 a).
- Busca no cadastro de empresa sem login (ADR-0017, decisão 4).
- Base própria da Receita.

## Critérios de aceite
Os testes previstos na ADR-0017 passam. Nenhum log da função contém CNPJ ou conta. Com os dois provedores fora do ar, o trabalhador conclui o fluxo pelo preenchimento manual.

## Riscos
Ver a ADR-0017: provedor sem termos e sem SLA, nome de pessoa física no preenchimento manual, varredura por várias contas e primeira Edge Function do projeto.

## Dependências
- Migration da ADR-0012 (`registration_status`, `data_source`).
- Aprovação das decisões 1 a 5 da ADR-0017.
- Definição pelo DevOps do deploy e do monitoramento da função.

## Segurança
- `verify_jwt` ligado, mais a checagem de `role = authenticated`.
- CNPJ só no corpo do POST.
- Tabelas em `private`, sem `grant`.
- Nenhum segredo novo: a função usa a `service_role` que o Supabase já injeta nela.

## Dados envolvidos
- **Saem:** só o CNPJ.
- **Entram:** a lista branca da ADR-0017 (D4), sem nomes quando o CNPJ é de pessoa física.
- **Cota:** guarda conta e contagem, sem o CNPJ.

## Observabilidade
Contagem por resultado (`hit`, `miss`, `fallback`, `manual`, `natural_person`, `rate_limited`, `invalid`), por provedor e por tempo de resposta.

## Rollback
Desligar a função (o front cai no preenchimento manual) e revogar `preregister_company`. As empresas criadas mantêm a origem registrada.

## Testes necessários
Os da ADR-0017: a função com o provedor simulado e `supabase/tests/cnpj_smoke.sql`.

## Definição de pronto
- Função e RPCs no ar com os testes passando.
- Aviso de privacidade atualizado (ADR-0015).
- PROJECT_MEMORY registrado.

## Texto para o ClickUp
Título: TASK-0038 — Busca de CNPJ por serviço externo, via Edge Function

Descrição:
- Busca da empresa pelo CNPJ para a base de empresas do piloto (ADR-0012, D9 b), na Edge Function `cnpj-lookup`.
- Minha Receita como principal e BrasilAPI como reserva, com timeout de 4 s e preenchimento manual.
- Só o CNPJ sai para o terceiro.
- Cache de 30 dias só com a lista branca, sem QSA e sem nome de MEI ou de empresário individual.
- Limite por conta e logs sem a ligação conta–CNPJ.
- A empresa pré-cadastrada nasce no banco a partir do cache, nunca de dados enviados pelo front.
- Prioridade P1.
- Documentos: docs/tasks/TASK-0038-busca-de-cnpj-por-servico-externo.md e docs/adr/ADR-0017-busca-de-cnpj-por-servico-externo.md.
- Status: proposta, aguardando aprovação do responsável.
