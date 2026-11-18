# TASK-0045 — Recuperação de senha e troca do e-mail de acesso

- Status: em-andamento (front pronto localmente; push depende de liberação do responsável)
- Área: Front / Auth
- Prioridade: P1
- Estimativa: 1 dia
- Impacto: todas as contas
- ClickUp: o Gestor cria a tarefa e manda o link. Conferido em 2026-11-18 que ela não existia.
- Decisão: ADR-0024

## Problema

Quem esquece a senha não tem como voltar a entrar. A troca do e-mail de acesso estava desligada.

## Escopo

- "Esqueci minha senha" na tela de login, com resposta neutra e link para o cadastro.
- Tela "Criar nova senha" no retorno do link (`type=recovery`), com a regra de senha do cadastro.
- Troca do e-mail de acesso no Meu perfil, para trabalhador e empresa, com mensagem neutra sobre a confirmação.

## Fora de escopo

- Modelo do e-mail do Supabase.
- Configuração "Secure email change" do projeto (ver Riscos).
- Troca de CPF.
- Qualquer migration.

## Critérios de aceite

- O pedido mostra sempre a mesma mensagem, exista a conta ou não. O limite de envio mostra mensagem neutra própria.
- O link de recuperação abre "Criar nova senha" sem entrar direto na conta. Senha fora da regra é recusada com a mensagem do cadastro. Depois de salvar, aparece mensagem de sucesso e a pessoa entra.
- Link vencido volta ao pedido, com aviso.
- O retorno de confirmação de cadastro continua indo ao login.
- No perfil, a troca de e-mail envia o link e mostra "Enviamos um link de confirmação. A troca só vale depois de confirmar."

## Riscos

- Ver ADR-0024: "Secure email change" não conferida no painel; envio de e-mails compartilhado com o Auth no Gmail.

## Dados envolvidos

- E-mail de acesso, só em `auth.users`. Não há cópia em tabelas do app.

## Rollback

- Reverter o commit do front. Para desligar só a troca de e-mail, `emailChangeEnabled = false`.

## Testes necessários

- `scripts/test-password-recovery.mjs`, `scripts/test-profile.mjs` e `scripts/test-navigation.mjs`.
- tsc e build.
- Conferência local em desktop e 375 px.
- Em produção, depois do push e com liberação: pedido de recuperação com uma conta de teste @example.com, que não recebe e-mail. A recuperação completa precisa de uma caixa real do responsável.

## Evidências

- 2026-11-18 (Front): implementação local. tsc ok, testes passando e build ok. Telas conferidas na prévia local, sem envio de e-mail real.
