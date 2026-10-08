# TASK-0013 — Refinar seletor de perfil e onboarding obrigatório

- Status: concluída
- ClickUp: [TASK-0013](https://app.clickup.com/t/86aktn738)
- Conclusão: 2026-10-01
- Área: Frontend/Produto/Acessibilidade
- Prioridade: P1
- Estimativa: 1 dia
- Impacto: melhora a clareza de entrada e garante contexto mínimo do empregado

## Problema

Os seletores de empregado e empresa não possuíam acabamento visual, e o onboarding permitia avançar sem respostas reais ou abandonar o formulário.

## Contexto

A escolha da persona altera landing, cadastro e login. As respostas do onboarding serão necessárias para contextualizar a jornada.

## Objetivo

Criar um seletor segmentado claro e tornar todas as respostas do onboarding obrigatórias.

## Escopo

Estilos responsivos e acessíveis, persistência das escolhas em memória, perguntas simples e múltiplas, validação por etapa, confirmação de senha e remoção do botão de pular.

## Fora de escopo

Persistência no backend, autenticação real e definição jurídica dos formulários.

## Critérios de aceite

- As duas personas possuem estados ativo, hover e foco claros.
- A seleção continua responsiva em telas pequenas.
- Nenhuma etapa avança com pergunta sem resposta.
- Perguntas múltiplas aceitam uma ou mais opções.
- Não existe ação para pular o onboarding.

## Riscos

A obrigatoriedade pode aumentar abandono e coleta de dados; revisar minimização antes do piloto.

## Dependências

Backend e governança de dados antes de persistir respostas reais.

## Segurança

As regras deverão ser revalidadas no servidor; validação no cliente não é controle de segurança.

## Dados envolvidos

Contexto laboral e percepções psicossociais sensíveis, ainda somente em memória na POC.

## Observabilidade

No MVP, medir abandono por etapa sem registrar o conteúdo das respostas em logs.

## Rollback

Reverter o commit; não reintroduzir o botão de pular sem decisão de produto e privacidade.

## Testes necessários

Build, seleção simples/múltipla, etapa incompleta, confirmação de senha, responsividade e navegação por teclado.

## Definição de pronto

Build aprovado, fluxo obrigatório funcional, identidade visual consistente e documentação atualizada.
