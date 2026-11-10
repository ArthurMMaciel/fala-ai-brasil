# TASK-0044 — Ajustes de layout das telas principais

- Status: em-andamento (itens 1, 2, 3, 4, 5, 7, 8 e 9 prontos e testados; item 6 pendente; aguarda push na main)
- ClickUp: [TASK-0044](https://app.clickup.com/t/17tu7rpcpdf)
- Área: Frontend/Acessibilidade
- Prioridade: P1 (item 1 é bug em produção); demais P2
- Estimativa: 1 dia
- Impacto: um bug de acessibilidade corrigido e as telas principais mais claras, sem mudar regra de negócio

## Problema
A auditoria de 2026-11-09 encontrou, na main 4c64555:
1. no portal da empresa e do parceiro, os botões do topo verde-escuros sobre fundo verde, com contraste perto de 1:1;
2. texto de "demonstração" e "dados fictícios" na landing;
3. Início do trabalhador dominado por números zerados e gráfico vazio, com cartão órfão no funil;
4. no celular, a arte do cadastro ocupando cerca de 40% da primeira tela;
5. formulário de contato do Dashboard da empresa repetindo o Meu perfil, com o CNPJ quebrando linha;
6. dois tratamentos de logo;
7. no celular, o seletor de personas rolando sem indicação;
8. fila da Operação sem idade dos itens;
9. rodapé sem os canais de emergência.

## Contexto
Tese visual "calma institucional": verde profundo como moldura, superfícies claras, Lora em títulos editoriais, Inter na operação e telas de produto respondendo "em que situação estou, o que faço agora, o que vem depois". Aprovado pelo responsável em 2026-11-09: itens 1, 2, 3, 4, 5, 7, 8 e 9; item 2 sem o rodapé do e-mail (Back); item 5 com o resumo e o link "Editar no Meu perfil".

## Objetivo
Corrigir o contraste e aplicar os ajustes aprovados, reaproveitando `system.css` e as classes existentes, sem dependência nova.

## Escopo
- Item 1: regra em `system.css` que devolve o texto branco aos botões do topo quando há portal aberto.
- Itens 2 e 9: sem aviso de demonstração na landing e no rodapé; rodapé com "Não é um canal de emergência. Em risco imediato, procure ajuda: CVV 188, SAMU 192 ou Polícia Militar 190."
- Item 3: bloco "Sua manifestação mais recente" (ou "Comece por aqui"), funil sem cartão órfão e estado vazio no lugar do gráfico zerado.
- Item 4: abaixo de 640 px a arte do cadastro e do login sai.
- Item 5: resumo dos dados da empresa com "Editar no Meu perfil"; `updateCompanyContact` removido.
- Item 7: esmaecimento à direita do seletor de personas no celular.
- Item 8: coluna "Aguardando" e os mais antigos primeiro na Fila de revisão.

## Fora de escopo
- Item 6 (logo), que depende da escolha do responsável.
- Rodapé do e-mail de confirmação (arquivo do Back).
- Mudanças de regra de negócio, de banco ou de texto jurídico além do aprovado.

## Critérios de aceite
- Botões do topo da empresa com contraste de pelo menos 4,5:1.
- Nenhum texto de demonstração ou dados fictícios visível na landing.
- Sem rolagem horizontal em 375 px nas telas alteradas.
- Nenhuma funcionalidade removida: o contato da empresa continua editável no Meu perfil.

## Riscos
Baixos: mudanças de CSS e de apresentação. O item 5 retira um formulário, mas o dado continua editável no Meu perfil.

## Dependências
Nenhuma dependência nova. Conflita em `worker-portal-live.tsx` (funil) e `portal-live.tsx` com o commit B da TASK-0035; a ordem de push foi combinada com o Gestor e o Back.

## Segurança
Sem impacto: nenhum dado novo é exibido nem enviado.

## Dados envolvidos
Os mesmos já exibidos nas telas.

## Observabilidade
Nenhuma.

## Rollback
Cada item está num commit próprio; reverter o commit do item.

## Testes necessários
- `npm test`, `tsc` e build em cada commit; `scripts/test-ops-queue.mjs` para o item 8.
- Navegador com dados do banco local, em desktop e 375 px, para cada item visível.

## Definição de pronto
Commits na main, testes e build verdes e as telas conferidas no navegador.

## Progresso em 2026-11-10
- Commits sobre a main 7ba76b9: `b0b9e38` (item 1), `f778c60` (itens 2 e 9), `60c018b` (item 7), `15cfd2e` (item 4), `8f79a71` (item 3), `18133e9` (item 5), `3ebadb6` (item 8) e `4d855d6` (remoção do `updateCompanyContact`).
- Conferido no navegador:
  - item 1: contraste medido de cerca de 10:1;
  - landing e rodapé sem texto de demonstração;
  - seletor e cadastro em 375 px;
  - Início com e sem manifestação;
  - Dashboard da empresa levando ao Meu perfil;
  - fila com "há 28 h".
- Prints de antes e depois guardados fora do Git.
- Pendente: item 6 (logo), à espera da escolha do responsável.
- Pendente: push na main, que depende da liberação escrita do responsável.
