# TASK-0006 — Provar o isolamento por organização e por pessoa no Supabase

- Status: em-andamento (teste escrito; execução aguarda o projeto Supabase de desenvolvimento)
- ClickUp: [TASK-0006](https://app.clickup.com/t/86aktn721)
- Área: Segurança/Backend
- Prioridade: P0 para o piloto fechado de 30/11 (go/no-go 25/11)
- Prazo: 20/11
- Impacto: impede que uma empresa ou um trabalhador leia ou altere dados de outro

## Problema
O texto original desta tarefa supunha um backend próprio sem tenant. Isso não vale mais. Hoje o produto é Supabase (Postgres com RLS), com papéis por tabela de vínculo:
- trabalhador: `workers.user_id`;
- empresa: `company_users`, com `owner`/`member`;
- parceiro: `partners.user_id`;
- patrocinador: `sponsors`;
- equipe: `private.platform_admins`;
- responsável por documento: `private.document_officers`.

O isolamento depende de RLS nas tabelas e de checagens dentro das funções `security definer`. Faltava uma prova única, versionada e repetível de que nenhuma combinação vaza.

## Modelo atual de acesso (resumo)
- Tabelas de `public` com RLS ligada. Tabelas de trilha e de conteúdo sensível (`complaint_originals`, `complaint_reviews`, `original_access_log`, `company_response_reviews`, `response_ratings`, `profile_change_log`) com `revoke all` de anon e authenticated, acessíveis só por função.
- A empresa lê manifestações só por `list_company_complaints` e `get_company_complaint_timeline`, que exigem `is_company_user` e devolvem a versão compartilhável, nunca o original nem a identidade.
- A equipe lê o original só por `ops_read_original`, com justificativa registrada.
- Funções de `private` não são executáveis pelo cliente.

## Objetivo
Um teste local único, `supabase/tests/isolation_smoke.sql`, com duas empresas e dois trabalhadores, que prove:
1. A não lê nem escreve nada de B, em todas as tabelas e RPCs expostas;
2. a empresa nunca vê o relato original nem a identidade do trabalhador;
3. anon não vê nada.

## Como o teste funciona
- **Montagem:** empresas A e B, trabalhadora A (caso contra A, liberado e respondido, e outro caso em revisão), trabalhador B (caso contra B, liberado, respondido e avaliado) e uma pessoa da equipe. Cada dado leva um marcador único: nome, CPF, telefone, e-mail, ids, trecho do original, título, versão compartilhada e resposta.
- **Descoberta pelo catálogo:** tabelas, views e funções vêm de `pg_class` e `pg_proc`. Uma tabela ou RPC nova entra na varredura sem editar o teste.
- **Listas esperadas:** o teste falha se aparecer RPC aberta a anon ou a authenticated fora da lista revisada. Na primeira execução as listas são preenchidas e revisadas uma a uma.
- **Catálogo:** falha se existir tabela de `public` com privilégio de cliente e sem RLS. Também informa views e funções de `private` abertas.
- **Atores** anon, empresa A, trabalhador A e trabalhador B. Para cada um:
  - lê toda tabela e view e procura marcadores proibidos;
  - tenta update e delete por id do outro lado em toda coluna de vínculo;
  - tenta inserts que criariam vínculo com o outro lado (resposta, evento, membro de empresa, versão compartilhada);
  - chama toda RPC executável com cada id do outro lado nos parâmetros uuid e argumentos genéricos nos demais;
  - exige erro, ou um resultado sem marcador e sem mudança na impressão digital dos dados do outro lado (md5 das linhas antes e depois, calculado como postgres);
  - cada chamada roda em subtransação desfeita.
- **Chamadas dirigidas, com argumentos válidos:** empresa A respondendo caso de B; trabalhador A avaliando, encerrando ou trocando a versão do caso de B; não equipe usando `ops_read_original`.
- **Resultado:** `RESULTADOS {..., "falhas": [...], "aprovado": true|false}`, e tudo é desfeito.

## Limites conhecidos do teste
- RPCs com parâmetros de texto em formato de enum (por exemplo, a decisão em `ops_*`) recebem texto genérico e falham antes de testar a autorização. A cobertura delas vem das chamadas dirigidas e dos smokes de cada fluxo (`ops_review_smoke`, `response_review_smoke`).
- Parceiro e patrocinador entram só como dados de outras contas presentes no banco. Um cenário próprio de dois parceiros fica para uma segunda versão.
- Storage (buckets) não é coberto.
- A equipe não é testada como ator, porque lê tudo por desenho. O acesso dela ao original é coberto pelo registro de `ops_read_original` (TASK-0009).

## Execução
- Decisão do responsável (17/11): plano Free com um único banco, o de produção, sem Docker e sem projeto de desenvolvimento. Os testes rodam em produção com estas regras:
  - tudo em transação desfeita, sem COMMIT, com trava contra commit;
  - liberação escrita a cada execução;
  - o script é mostrado antes e o resultado depois.
- Como o script cumpre a regra:
  - é uma única instrução `DO`, que sempre termina em exceção, e o Postgres desfaz tudo, inclusive `auth.users`;
  - o corpo inteiro roda dentro de um bloco com tratador de exceção (subtransação). Ali o próprio Postgres proíbe COMMIT e ROLLBACK explícitos, e funções chamadas não podem encerrar transação;
  - erro inesperado sai como `ABORTADO (nada gravado)`.
- O que o rollback não desfaz:
  - a sequência `complaint_protocol_seq` avança, e os números de protocolo de teste ficam pulados;
  - não há `pg_net`, `dblink` nem `pg_cron` nas migrations, então nenhum efeito externo escapa.
- O que é impresso: só marcadores de teste, nomes de tabela e função e contagens. Nenhum dado real.
- Primeira execução: as listas esperadas de RPC estão vazias, então a primeira rodada sai com `aprovado = false` por desenho e serve para preenchê-las e revisá-las. O script nunca rodou antes, porque o banco local caiu, e erros de script saem como `ABORTADO` sem gravar nada.
- Recomendação: rodar antes de 30/11, enquanto não há relato real no banco.
- Resultado: _pendente_.

## Critérios de aceite
- `aprovado = true` no projeto de desenvolvimento com todas as migrations da main.
- Listas esperadas de RPC preenchidas e revisadas.
- Qualquer falha encontrada vira correção com modelo aprovado antes da migration.

## Dependências
TASK-0011/ADR-0012: a troca do gate para representante verificado. Quando ela entrar, o teste ganha vínculos `pending`, `verified` e `revoked`.

## Rollback
O teste não altera o banco. Correções derivadas dele seguem o rollback da própria migration, nunca relaxando política.
