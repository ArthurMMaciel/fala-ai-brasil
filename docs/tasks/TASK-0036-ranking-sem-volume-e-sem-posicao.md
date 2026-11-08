# TASK-0036 — Ranking sem número de manifestações e sem posição

- Status: proposta (modelo aguardando aprovação do responsável; sem migration)
- ClickUp: (preencher após a criação; texto pronto no fim deste documento)
- Área: Backend/Produto/Privacidade
- Prioridade: P1
- Estimativa: 1 a 1,5 dia (função, front dos dois portais e teste de fumaça)
- Impacto: o ranking deixa de expor volume de manifestações por empresa e de criar disputa por posição
- Relacionadas: [ADR-0013](../adr/ADR-0013-resposta-da-empresa-revisada-pela-equipe.md) (prazo e satisfação), ADR-0009 (ranking calculado), ADR-0010

## Problema

`company_ranking()` devolve, para todo usuário autenticado (trabalhador, empresa e parceiro), o número de manifestações liberadas por empresa (`received`) e uma ordem que o front transforma em "Posição". O número revela o volume de conflitos de cada empresa, e a posição cria uma disputa que a decisão do responsável quer evitar. Esconder só na tela não basta: qualquer pessoa logada chama a RPC e lê os dados.

## Estado atual

- Saída: `company_id, name, city, state, received, response_rate, avg_first_response_hours, is_mine`, para empresas com 3 ou mais casos liberados, ordenada por taxa de resposta (decrescente) e tempo médio (crescente).
- Telas: `CompanyRanking` (`src/portals/portal-live.tsx`) mostra as colunas Posição, Empresa, Cidade, Manifestações, Taxa de resposta e Tempo médio, além de uma linha da própria empresa calculada no navegador quando ela não entra no ranking. O portal do trabalhador (`src/portals/worker-portal-live.tsx`) mostra a mesma tabela.

## Proposta

### Saída nova

| Coluna | Situação | Motivo |
|---|---|---|
| `company_id`, `name`, `city`, `state`, `is_mine` | mantém | identificação e destaque da própria empresa |
| `received` | **sai** | é o volume de manifestações |
| `response_rate` (inteiro exato) | **sai**, substituído por `response_band` | com volume baixo, o percentual exato denuncia o volume: 33% é 1 de 3, 67% é 2 de 3 |
| `avg_first_response_hours` (inteiro exato) | **sai**, substituído por `response_time_band` | mesma lógica, e evita disputa por horas |
| `satisfaction_band` | **entra** quando a ADR-0013 for aprovada | nula com menos de 3 avaliações |

Faixas propostas (textos finais com o responsável):
- `response_band`: `high` (80% ou mais), `medium` (50% a 79%), `low` (menos de 50%).
- `response_time_band`: `fast` (até 48 h), `regular` (de 48 h a 7 dias), `slow` (mais de 7 dias), `none` (sem resposta).
- `satisfaction_band`: `high`, `medium`, `low`, com os mesmos cortes da taxa.

O corte mínimo de 3 casos liberados continua, para não comparar empresas com um ou dois casos. O corte é público, então quem aparece tem 3 ou mais; isso não revela o número exato.

### Ordenação

A função passa a ordenar por **nome da empresa**. Manter a ordem por desempenho com as faixas ainda permitiria ler uma posição pela ordem das linhas. O trabalhador continua comparando pelas faixas, e a tela pode oferecer filtro por faixa e por UF. Fica como alternativa: ordenar por faixa e, dentro dela, por nome, o que mostra grupos sem posição individual.

### Tela

- Título "Responsividade das empresas", sem a palavra "Ranking" nem a coluna "Posição".
- Colunas: Empresa, Cidade/UF, Taxa de resposta (selo com a faixa), Tempo de resposta (selo) e, quando aprovada, Satisfação.
- Linha da própria empresa destacada (`is_mine`). Quando ela não entra (menos de 3 casos), a tela mostra só "Sua empresa aparece aqui a partir de 3 manifestações liberadas", sem calcular números no navegador. Hoje a linha própria mostra a contagem.
- Texto de método curto, explicando faixas, corte mínimo e que o tempo em revisão pela equipe não conta.

### Função

Como o tipo de retorno muda, o Postgres não aceita `create or replace`. Proposta sem quebrar o front em produção:

1. Criar `company_responsiveness()` com a saída nova, mantendo `company_ranking()`.
2. Publicar o front que usa a nova função.
3. Na mesma janela, `revoke execute` de `company_ranking()` para `authenticated` e, numa migration seguinte, `drop function`.

Enquanto o passo 3 não acontece, o volume continua legível pela função antiga. A janela deve ser curta e registrada.

`ops_list_companies` (só a equipe) continua com as contagens: a equipe precisa delas para operar.

## Critérios de aceite

- Nenhuma função acessível a `authenticated` ou `anon` devolve contagem de manifestações por empresa nem métricas exatas que permitam deduzi-la.
- A saída nova vem ordenada por nome; a tela não mostra posição.
- `company_ranking()` revogada e removida após o deploy do front.
- Teste de fumaça cobrindo: ausência de `received`, faixas corretas nos limites (79/80%, 48 h), corte de 3, `is_mine`, tempo em revisão fora do cálculo e chamada à função antiga recusada após o `revoke`.

## Riscos

- **Produto:** faixas reduzem a precisão e podem parecer menos úteis às empresas que querem medir melhora. Mitigação: a própria empresa pode ver os números exatos dela numa função separada (`my_company_responsiveness()`, que só devolve os dados da empresa do usuário verificado). Decisão do responsável.
- **Compatibilidade:** o front antigo chama `company_ranking()`. O `revoke` antes do deploy quebra a tela de ranking (a lista fica vazia; o resto do portal não é afetado).
- **Inferência residual:** com poucas empresas no piloto, até faixas podem identificar casos. O corte de 3 continua necessário.

## Rollback

Reconceder `execute` em `company_ranking()` (antes do `drop`) e voltar o front. Depois do `drop`, reaplicar a definição de 20261106140000. Não há dado a migrar.

## Decisões que dependem do responsável

1. Faixas no lugar de números exatos (recomendado) ou números exatos sem a contagem.
2. Ordenação por nome (recomendado) ou por faixa e depois nome.
3. Cortes das faixas e textos dos selos.
4. Se a empresa vê os próprios números exatos numa função à parte.
5. Se o trabalhador continua vendo a tabela (hoje vê).

## Texto para o ClickUp

Título: TASK-0036 — Ranking sem número de manifestações e sem posição
Descrição: Proposta para que `company_ranking` deixe de devolver a contagem de manifestações e números exatos (substituídos por faixas), com ordenação por nome e tela sem posição. Nova função `company_responsiveness()`, com revogação e remoção da antiga após o deploy do front. Prioridade P1. Documento: docs/tasks/TASK-0036-ranking-sem-volume-e-sem-posicao.md. Status: proposta, aguardando aprovação do responsável.
