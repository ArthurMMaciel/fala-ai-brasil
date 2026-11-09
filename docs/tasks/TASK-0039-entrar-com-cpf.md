# TASK-0039 — Entrar com CPF e senha (trabalhador)

- Status: proposta (aguardando decisão do responsável; sem código)
- ClickUp: (preencher após a criação; texto pronto no fim deste documento; a consulta de 2026-11-09, só de leitura, não achou tarefa equivalente)
- Área: Backend/Frontend/Segurança/Privacidade
- Prioridade: P2
- Estimativa: 1,5 a 2 dias após a aprovação (função, tabela de tentativas, tela e testes), sem contar o captcha
- Impacto: o trabalhador entra com CPF sem que o login revele quem tem conta
- Decisão estrutural proposta: [ADR-0018](../adr/ADR-0018-entrar-com-cpf.md)
- Relacionadas: TASK-0005 (autenticação e sessões), TASK-0037 (CPF único)

## Problema
O Supabase Auth só entra por e-mail ou telefone. Entrar com CPF exige achar o e-mail no servidor sem expor o e-mail nem a existência da conta, numa plataforma em que ter conta já é informação sensível.

## Objetivo
Login por CPF só para trabalhador, por Edge Function, com resposta e tempo iguais para todos os erros, limite próprio por CPF e por IP, sem CPF, e-mail ou IP em logs, e recuperação de senha só por e-mail.

## Escopo
- Edge Function `cpf-login`.
- Tabela `private.login_attempts` (HMAC do CPF e do IP).
- Opção "Entrar com CPF" na tela de login.
- Testes.

## Fora de escopo
- Captcha (decisão à parte).
- Parceiro pessoa física.
- Recuperação de senha por CPF.

## Critérios de aceite
Os testes previstos na ADR-0018 passam, em especial a resposta e o tempo iguais para CPF existente e inexistente.

## Riscos
Ver a ADR-0018: enumeração residual, força bruta distribuída sem captcha e bloqueio do login por CPF por terceiros.

## Dependências
- Decisões 1 a 5 da ADR-0018.
- Segredo HMAC configurado nas funções pelo DevOps.

## Rollback
Desligar a função e esconder a opção. O login por e-mail não muda.

## Texto para o ClickUp
Título: TASK-0039 — Entrar com CPF e senha (trabalhador)

Descrição:
- Login do trabalhador por CPF e senha, numa Edge Function que acha o e-mail no servidor.
- Mesma resposta e mesmo tempo para CPF inexistente, senha errada e e-mail não confirmado.
- Limite por HMAC do CPF e do IP, que vale também para CPF inexistente.
- Sem CPF, e-mail ou IP em logs, e recuperação de senha só por e-mail.
- Prioridade P2.
- Documentos: docs/tasks/TASK-0039-entrar-com-cpf.md e docs/adr/ADR-0018-entrar-com-cpf.md.
- Status: proposta, aguardando decisão do responsável.
