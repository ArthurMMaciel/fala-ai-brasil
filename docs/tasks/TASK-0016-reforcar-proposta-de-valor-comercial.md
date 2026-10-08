# TASK-0016 — Reforçar proposta de valor comercial por persona

- Status: concluída
- ClickUp: [TASK-0016](https://app.clickup.com/t/86aktn73t)
- Conclusão: 2026-10-05
- Área: Produto/Frontend/Monetização
- Prioridade: P2
- Estimativa: pequena
- Impacto: torna a demonstração comercial orientada a problemas, resultados e decisão de compra

## Problema

As visões comerciais da POC apresentavam funcionalidades, métricas sintéticas e preços, mas não defendiam com firmeza por que cada persona deveria pagar. Faltavam dor de compra, transformação, lógica econômica, critérios de sucesso e jornada até o resultado.

## Contexto

O feedback veio após a implementação inicial da TASK-0015. Não existem cases, clientes ou resultados reais; portanto, a narrativa deve ser convincente sem fabricar prova social ou prometer retorno não medido.

## Objetivo

Transformar cada visão comercial em um argumento de compra testável: problema, promessa, resultado do piloto, lógica de valor, scorecard, jornada e diferenciação dos planos.

## Escopo

- Narrativa comercial específica para Empresa, Hub, Intelligence, Estudos e Patrocínio.
- Identificação de comprador e gatilho de compra.
- Três resultados esperados por persona.
- Lógica econômica e scorecard de piloto.
- Jornada visual em quatro etapas.
- Planos com perfil ideal, resultado contratado e justificativa da faixa.
- Proposta de piloto pago de 90 dias.

## Fora de escopo

Cases reais, depoimentos, calculadora de ROI com dados de clientes, checkout, CRM, cobrança, contratos e garantia de resultado.

## Critérios de aceite

- Cada persona responde claramente: para quem, qual problema, qual transformação e como medir.
- Os planos diferenciam resultado e complexidade, não apenas quantidade de telas.
- Nenhuma métrica sintética é apresentada como resultado comprovado.
- Preços continuam identificados como hipóteses.
- Interface funciona em desktop e possui adaptação responsiva estática.
- Build TypeScript/Vite aprovado.

## Riscos

- Promessa comercial exceder capacidade atual da POC.
- Confundir scorecard proposto com resultado já obtido.
- Fixar preço sem entrevistas e pilotos pagos.

## Dependências

Entrevistas com compradores, validação de disposição a pagar e apuração do custo real de suporte/revisão humana.

## Segurança

Sem mudança em autenticação, autorização ou tratamento de dados. A narrativa preserva os limites de acesso por persona.

## Dados envolvidos

Somente conteúdo estático e dados sintéticos.

## Observabilidade

Na implementação real, medir seleção de persona, CTA, proposta, piloto e conversão sem capturar conteúdo sensível.

## Rollback

Reverter as seções comerciais enriquecidas para a versão simples da TASK-0015.

## Testes necessários

- `npm.cmd run build` aprovado em 2026-10-05.
- Revisão estática das cinco personas, cinco scorecards, vinte etapas de jornada e quinze planos.
- Servidor local respondeu `HTTP 200` em `http://127.0.0.1:5173/`.
- `git diff --check` sem erros; apenas avisos de normalização LF/CRLF preexistentes no ambiente.
- Inspeção visual automatizada pendente porque nenhum navegador está conectado à sessão.

## Definição de pronto

Narrativas e planos revisados, documentação atualizada e build aprovado.


## Atualiza??o visual ? 08/10/2026

A apresenta??o comercial foi alinhada ? marca Escuta A? Brasil: paleta verde, azul e amarela, wordmark, hero e cart?es de valor. A sele??o de persona passou para o topo da p?gina inicial em ?Como voc? quer acessar??, e o conte?do muda conforme o perfil. ?Estudos? deixou de ser persona de entrada; projetos aplicados aparecem dentro de Intelligence como ?Projeto sob proposta?, com pre?o dependente de escopo.
