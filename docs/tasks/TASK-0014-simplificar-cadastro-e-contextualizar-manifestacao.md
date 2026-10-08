# TASK-0014 — Simplificar cadastro e contextualizar manifestação

- Status: concluída
- ClickUp: [TASK-0014](https://app.clickup.com/t/86aktn73h)
- Conclusão: 2026-10-05
- Área: Frontend/Produto/Privacidade
- Prioridade: P1
- Impacto: reduz coleta fora de contexto e melhora a indicação segura de contatos empresariais

## Problema

O cadastro pessoal misturava criação de conta com perguntas sobre vínculo e experiência em uma empresa. Como a pessoa pode se manifestar sobre empresas diferentes, essas respostas precisam pertencer a cada manifestação. O passo de comunicação aceitava apenas e-mail ou telefone solto e não explicava por que o dado era solicitado.

## Objetivo

Manter o cadastro pessoal focado em identificação e acesso; coletar contexto laboral por manifestação; e estruturar contatos empresariais com finalidade e cautelas explícitas.

## Escopo entregue

- Cadastro pessoal com nome, CPF, endereço, e-mail e senha, sem confirmação de senha nesta etapa da POC.
- Remoção de “Candidato(a) em processo seletivo”.
- Quatro blocos de contexto movidos para o início de cada nova manifestação.
- “Meio de comunicação” renomeado para “Formas de comunicação”.
- Contato empresarial estruturado em nome, e-mail, telefone e cargo.
- Alerta e revisão humana para proprietário, sócio ou pessoa potencialmente envolvida.
- Contatos e respostas contextuais mantidos apenas no estado volátil da POC.

## Critérios de aceite

- O cadastro de trabalhador não contém perguntas laborais nem confirmação de senha.
- Ao criar uma manifestação, todas as perguntas contextuais são obrigatórias e se referem à empresa selecionada.
- A opção de candidato em processo seletivo não aparece no fluxo.
- Um contato só é adicionado quando os quatro campos estão preenchidos e e-mail/telefone são válidos.
- A finalidade dos contatos e o cuidado com proprietário/sócio estão visíveis.
- O build TypeScript/Vite é aprovado.

## Riscos e controles

- CPF e endereço são dados pessoais: não persistir nem usar dados reais antes de base legal, minimização, retenção, segurança e direitos do titular estarem definidos.
- Cargo e contato podem identificar terceiros: coletar apenas contato profissional necessário e validar antes do uso.
- Contato com proprietário ou pessoa envolvida pode gerar retaliação: exigir revisão humana e respeitar a regra de não realizar contato externo automático em alto risco.
- Validação no cliente é apenas experiência de POC e deverá ser repetida no servidor.

## Fora de escopo

Persistência, autenticação real, validação oficial de CPF/endereço, verificação de domínio/representação, envio de mensagens e definição de base legal/retenção.

## Testes

- `npm.cmd run build` aprovado em 2026-10-05.
- Revisão estática dos estados, validações e navegação.
- Inspeção visual pendente: nenhum navegador integrado estava disponível na sessão.

## Rollback

Reverter as alterações desta tarefa. Não restaurar coleta contextual no cadastro sem revisão de produto e privacidade.
