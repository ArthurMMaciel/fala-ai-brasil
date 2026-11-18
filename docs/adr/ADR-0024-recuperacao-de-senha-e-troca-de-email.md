# ADR-0024 — Recuperação de senha e troca do e-mail de acesso

- Estado: **Aceita**, pelo responsável em 2026-11-18, repassado pelo Gestor: "Aprovo o esqueci minha senha, manda pro Front." e "deixe o usuário trocar qualquer dado, inclusive email, só não o CPF, por enquanto".
- Data: 2026-11-18
- Tarefa: TASK-0045. A tarefa no ClickUp será criada pelo Gestor, que conferiu que ela ainda não existe.
- Relacionadas: ADR-0009 (Auth do Supabase), ADR-0014 (Meu perfil, C5), ADR-0020 (e-mail pelo Gmail).

## Contexto

- Não havia como recuperar a senha. A troca do e-mail de acesso existia no código, mas estava desligada (ADR-0014, C5).

## Decisão

1. **Esqueci minha senha.** O link fica na tela de login e abre um pedido por e-mail.
   - O pedido chama `auth.resetPasswordForEmail` com `redirectTo` igual ao endereço do site (`redirectUrl()`).
   - A resposta é sempre a mesma, exista a conta ou não: "Se houver uma conta com esse e-mail, enviamos um link para criar uma nova senha. Confira também a caixa de spam." Ela vem acompanhada do link para o cadastro.
   - Só o limite de envio do Auth (`over_email_send_rate_limit`, `over_request_rate_limit`, 429) tem mensagem própria, e ela também é neutra. Qualquer outro erro mostra a resposta padrão, para não revelar se a conta existe.
2. **Criar nova senha.** O link do e-mail volta com `type=recovery` no fragmento da URL.
   - O app lê esse tipo antes de o cliente consumir a URL e abre "Criar nova senha", sem entrar na conta.
   - A regra de senha é a mesma do cadastro. A senha é salva com `auth.updateUser({ password })`; depois, o app mostra uma mensagem de sucesso e entra na conta.
   - Link vencido ou já usado leva de volta ao pedido, com aviso.
   - A confirmação de cadastro (`type=signup`) continua como antes. Ela encerra a sessão e leva ao login; o retorno de recuperação não passa por esse caminho.
   - A landing estática não redireciona quem chega com fragmento na URL, então o retorno do link chega ao app.
3. **Troca do e-mail de acesso** no Meu perfil, para trabalhador e empresa. O caminho já existente, `auth.updateUser({ email }, { emailRedirectTo })`, foi ligado.
   - Mensagem: "Enviamos um link de confirmação. A troca só vale depois de confirmar."
   - A tela explica, de forma neutra, que o link pode chegar ao e-mail atual e ao novo, conforme a opção "Secure email change" do projeto.
   - CPF continua travado; CNPJ e razão social continuam como estão (ADR-0014).

## Dados

- O e-mail de acesso só existe em `auth.users`. `workers` e `company_users` não guardam cópia, e `ops_list_representatives` lê `auth.users` na hora. Por isso não há sincronização nem migration.
- `companies.contact_email` é o contato público da empresa e não muda com o login.

## Riscos e pendências

- **Confirmação da troca de e-mail.** Não foi conferido no painel do Supabase se a "Secure email change" está ligada (ADR-0014, C5). Com ela desligada, basta o link no e-mail novo, e quem estiver com a sessão aberta troca o e-mail sem acesso à caixa atual. **Conferir no painel antes do uso em produção (DevOps/responsável).**
- **Envio de e-mails.** O envio sai pelo SMTP do Gmail do Auth (ADR-0020). Os e-mails de recuperação e de troca contam no mesmo limite diário da confirmação de cadastro.
- **Modelo do e-mail de recuperação.** O modelo usado é o padrão do Supabase. O texto do e-mail fica com quem administra o projeto.

## Rollback

- Front: reverter o commit. Sem migration.
- Para desligar só a troca de e-mail, basta `emailChangeEnabled = false` em `src/domain/profile.ts`.
