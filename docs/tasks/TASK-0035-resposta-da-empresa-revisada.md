# TASK-0035 — Resposta da empresa revisada pela equipe

- Status: em-andamento (decisões de 2026-11-08 passadas à ADR-0013; migrations (a), (b) e (d) escritas e testadas no local; db push por passo, com liberação do responsável)
- ClickUp: [TASK-0035](https://app.clickup.com/t/17tu7rpc382)
- Área: Backend/Produto/Privacidade
- Prioridade: P1
- Estimativa: 3 a 4 dias após a aprovação (migrations, funções, portais, Operação e testes)
- Impacto: o trabalhador só recebe resposta revisada, acompanhada de uma descrição da equipe para avaliar se ela valeu a pena
- Decisão estrutural proposta: [ADR-0013](../adr/ADR-0013-resposta-da-empresa-revisada-pela-equipe.md)
- Relacionadas: TASK-0031, [TASK-0036](TASK-0036-ranking-sem-volume-e-sem-posicao.md)

## Problema
Hoje a resposta da empresa chega ao trabalhador assim que é enviada (`respond_complaint` e leitura direta de `company_responses`). Não há filtro contra conteúdo inadequado nem uma leitura que ajude o trabalhador a avaliar a resposta.

## Objetivo
Implementar o fluxo decidido pelo responsável: resposta em revisão, liberada pela equipe com descrição para o trabalhador ou devolvida à empresa com motivo; avaliação do trabalhador; ranking sem punir a empresa pela fila interna.

## Escopo
Estado `answer_in_review`, colunas de revisão em `company_responses`, tabelas `company_response_reviews` e `response_ratings`, RPCs da equipe, do trabalhador e da empresa, mudança de RLS, fila de respostas na Operação e rótulos nos portais.

## Fora de escopo
Notificação por e-mail e edição do texto da empresa pela equipe.

## Critérios de aceite
Ver "Testes de fumaça previstos" na ADR-0013. Nenhuma resposta não liberada é legível pelo trabalhador, nem pela API direta.

## Riscos
Segunda fila humana, confiança do trabalhador na descrição e compatibilidade com o front em produção (ver ADR-0013).

## Rollback
Ver ADR-0013. Nunca tornar visível ao trabalhador uma resposta não revisada.

## Progresso do front (passo c), 2026-11-10
- Commit `1428b95` na main, com push liberado por escrito pelo responsável. Usa as RPCs da 20261109170000, já em produção.
- Trabalhador: descrição da equipe em destaque, texto original da empresa abaixo, "Descrição corrigida em DD/MM" e avaliação por resposta (comentário opcional só para a equipe). A resposta entra na linha do tempo na data de liberação.
- Empresa: "Revisão da equipe" no histórico, aviso enquanto a resposta está em revisão e satisfação no painel "Sua empresa" ("Sem dado" abaixo de 3 avaliações). A empresa nunca recebe a descrição.
- Operação: visão "Respostas em revisão" (em revisão, liberadas, devolvidas; mais antigas primeiro; destaque após 48 h), liberar, devolver, corrigir; métricas e rótulo na trilha.
- Código tolerante: sem a 20261109180000 as respostas seguem liberadas e as falhas das RPCs novas não quebram a tela.
- Testes: `scripts/test-response-review.mjs` (validações iguais às do banco, renderização, empresa sem descrição). Conferido no navegador contra o banco local com a 180000, em desktop e 375 px.
- Próximo: o Back faz o commit C e o db push da 20261109180000, que liga a revisão em produção.

## Texto para o ClickUp
Título: TASK-0035 — Resposta da empresa revisada pela equipe
Descrição: A resposta da empresa passa pela equipe antes de chegar ao trabalhador. A equipe libera com uma descrição para o trabalhador ou devolve à empresa com motivo. O trabalhador avalia se a resposta valeu a pena. O prazo do ranking conta até o envio da empresa. Prioridade P1. Documentos: docs/tasks/TASK-0035-resposta-da-empresa-revisada.md e docs/adr/ADR-0013-resposta-da-empresa-revisada-pela-equipe.md. Status: proposta, aguardando aprovação do responsável.
