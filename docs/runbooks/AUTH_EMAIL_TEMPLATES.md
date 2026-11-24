# Modelos de e-mail do Auth em português

- Estado: **preparado em 2026-11-23, não aplicado.** Quem aplica é o responsável, no painel de produção.
- Motivo: no teste do responsável, a recuperação de senha funcionou, mas o e-mail chegou com o modelo padrão do Supabase, em inglês ("Reset your password").
- Fonte das variáveis: [Email templates](https://supabase.com/docs/guides/auth/auth-email-templates), conferida em 2026-11-23.
- Relacionadas: ADR-0009 (SMTP pelo Gmail do responsável), [PILOT_SUSPENSION](PILOT_SUSPENSION.md).

## Onde colar

Supabase > projeto de produção > **Authentication > Emails** ([Email Templates](https://supabase.com/dashboard/project/_/auth/templates)). Para cada modelo abaixo:
1. abrir o modelo;
2. trocar o **Subject**;
3. trocar o corpo (**Message body**, em HTML) pelo bloco `html` correspondente;
4. salvar.

Regras dos textos:
- Sem promessa de anonimato ou de sigilo absoluto.
- Sem dado de relato, empresa, situação ou protocolo.
- Sem `{{ .Data }}`: o nome e os metadados da conta não entram no e-mail, que pode cair numa caixa compartilhada.
- O link é sempre `{{ .ConfirmationURL }}`. Ele já leva o `redirect_to` que o app envia (`VITE_SITE_URL` ou a origem do site).
- A validade do link segue a configuração do projeto. Os textos dizem "por tempo limitado" para não fixar um prazo que pode mudar.

## Quais modelos o app usa

Conferido no código em 2026-11-23:

| Modelo no painel | Usado? | Onde no app |
|---|---|---|
| Confirm sign up | sim | `signUp` e `resend` (`src/services/account.ts`) |
| Reset password | sim | `resetPasswordForEmail` (`src/services/account.ts`) |
| Change email address | sim | `updateUser({ email })` em Meu perfil (`src/services/profile.ts`) |
| Magic link | **não** | o app não chama `signInWithOtp`. Traduzir mesmo assim é opcional, para o caso de o painel enviar o modelo em algum fluxo |
| Invite user | não | sem convite pelo painel no piloto |

---

## 1. Confirm sign up

**Subject:**

```text
Confirme seu cadastro na Escuta Aí Brasil
```

**Message body:**

```html
<div style="font-family: Arial, Helvetica, sans-serif; font-size: 16px; line-height: 1.5; color: #1f2937; max-width: 560px;">
  <h2 style="color: #1e3a8a; margin: 0 0 16px;">Confirme seu cadastro</h2>
  <p>Olá.</p>
  <p>Recebemos um pedido de cadastro na Escuta Aí Brasil com este endereço de e-mail. Para ativar a conta, confirme pelo botão abaixo.</p>
  <p style="margin: 24px 0;">
    <a href="{{ .ConfirmationURL }}" style="background: #1e3a8a; color: #ffffff; padding: 12px 20px; border-radius: 6px; text-decoration: none; display: inline-block;">Confirmar meu e-mail</a>
  </p>
  <p>O link vale por tempo limitado e só pode ser usado uma vez. Se ele expirar, peça um novo na tela de entrada.</p>
  <p>Se você não fez este cadastro, ignore esta mensagem. Nenhuma conta será ativada sem a confirmação.</p>
  <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;">
  <p style="font-size: 13px; color: #6b7280;">Escuta Aí Brasil. Mensagem automática; não responda a este e-mail.</p>
</div>
```

## 2. Reset password

**Subject:**

```text
Redefinição de senha da Escuta Aí Brasil
```

**Message body:**

```html
<div style="font-family: Arial, Helvetica, sans-serif; font-size: 16px; line-height: 1.5; color: #1f2937; max-width: 560px;">
  <h2 style="color: #1e3a8a; margin: 0 0 16px;">Redefinir sua senha</h2>
  <p>Olá.</p>
  <p>Recebemos um pedido para redefinir a senha da conta ligada a este e-mail na Escuta Aí Brasil. Para escolher uma nova senha, use o botão abaixo.</p>
  <p style="margin: 24px 0;">
    <a href="{{ .ConfirmationURL }}" style="background: #1e3a8a; color: #ffffff; padding: 12px 20px; border-radius: 6px; text-decoration: none; display: inline-block;">Criar nova senha</a>
  </p>
  <p>O link vale por tempo limitado e só pode ser usado uma vez.</p>
  <p>Se você não pediu a redefinição, ignore esta mensagem. Sua senha atual continua valendo.</p>
  <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;">
  <p style="font-size: 13px; color: #6b7280;">Escuta Aí Brasil. Mensagem automática; não responda a este e-mail.</p>
</div>
```

## 3. Change email address

Com "Secure email change" ligado, o Supabase manda este modelo **para os dois endereços**, o atual e o novo, e a troca só vale depois das duas confirmações. Por isso, o texto serve para quem recebe em qualquer um dos dois.

**Subject:**

```text
Confirme a troca de e-mail na Escuta Aí Brasil
```

**Message body:**

```html
<div style="font-family: Arial, Helvetica, sans-serif; font-size: 16px; line-height: 1.5; color: #1f2937; max-width: 560px;">
  <h2 style="color: #1e3a8a; margin: 0 0 16px;">Confirme a troca de e-mail</h2>
  <p>Olá.</p>
  <p>Recebemos um pedido para trocar o e-mail de acesso de uma conta na Escuta Aí Brasil de <strong>{{ .Email }}</strong> para <strong>{{ .NewEmail }}</strong>.</p>
  <p>Se o pedido foi seu, confirme pelo botão abaixo.</p>
  <p style="margin: 24px 0;">
    <a href="{{ .ConfirmationURL }}" style="background: #1e3a8a; color: #ffffff; padding: 12px 20px; border-radius: 6px; text-decoration: none; display: inline-block;">Confirmar a troca</a>
  </p>
  <p>O link vale por tempo limitado e só pode ser usado uma vez.</p>
  <p>Se você não pediu esta troca, não clique no link. Entre na plataforma e altere sua senha.</p>
  <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;">
  <p style="font-size: 13px; color: #6b7280;">Escuta Aí Brasil. Mensagem automática; não responda a este e-mail.</p>
</div>
```

## 4. Magic link (opcional; o app não usa)

**Subject:**

```text
Seu link de acesso à Escuta Aí Brasil
```

**Message body:**

```html
<div style="font-family: Arial, Helvetica, sans-serif; font-size: 16px; line-height: 1.5; color: #1f2937; max-width: 560px;">
  <h2 style="color: #1e3a8a; margin: 0 0 16px;">Seu link de acesso</h2>
  <p>Olá.</p>
  <p>Recebemos um pedido de acesso à Escuta Aí Brasil com este endereço de e-mail. Para entrar, use o botão abaixo.</p>
  <p style="margin: 24px 0;">
    <a href="{{ .ConfirmationURL }}" style="background: #1e3a8a; color: #ffffff; padding: 12px 20px; border-radius: 6px; text-decoration: none; display: inline-block;">Entrar</a>
  </p>
  <p>O link vale por tempo limitado e só pode ser usado uma vez.</p>
  <p>Se você não pediu este acesso, ignore esta mensagem.</p>
  <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;">
  <p style="font-size: 13px; color: #6b7280;">Escuta Aí Brasil. Mensagem automática; não responda a este e-mail.</p>
</div>
```

---

## Conferências no painel (só leitura, antes de colar)

1. **Secure email change:** Authentication > **Sign In / Providers** > **Email** > "Secure email change".
   - Recomendação: **ligado**. A troca de e-mail passa a pedir confirmação no endereço atual e no novo. Sem isso, quem tomar uma sessão aberta troca o e-mail com uma única confirmação, enviada ao endereço novo.
   - O nome exato do menu pode variar com a versão do painel: "a confirmar".
2. **URL Configuration:** Authentication > **URL Configuration** ([URL Configuration](https://supabase.com/dashboard/project/_/auth/url-configuration)).
   - **Site URL:** `https://fala-ai-brasil.vercel.app`. É o destino padrão quando o app não manda `redirectTo`. A [documentação](https://supabase.com/docs/guides/auth/redirect-urls) chama essa configuração de crítica para confirmação e redefinição de senha. Não pode ficar `http://localhost:3000`.
   - **Redirect URLs** (lista de permitidos): deve conter `https://fala-ai-brasil.vercel.app/**`. O app envia como destino `VITE_SITE_URL` ou a origem do site. Um destino fora da lista faz o Supabase cair na Site URL.
   - Não incluir os domínios de prévia da Vercel nem `localhost` em produção, salvo decisão do responsável.
3. **Remetente:** Authentication > **SMTP**. Conferir que o nome do remetente aparece como "Escuta Aí Brasil", se esse campo existir, e não o nome pessoal. O endereço continua o Gmail do responsável (ADR-0009).

## Teste depois de colar

Com uma conta de teste do próprio responsável, nunca com conta de usuário real:
1. pedir a redefinição de senha na tela de entrada e conferir o assunto e o texto em português, e que o link abre `fala-ai-brasil.vercel.app`;
2. criar uma conta de teste e conferir o e-mail de confirmação;
3. em Meu perfil, trocar o e-mail da conta de teste. Conferir que os dois endereços recebem a mensagem, se o "Secure email change" estiver ligado.

Os e-mails de teste contam no limite diário do Gmail (ADR-0009).

## Rollback

Antes de colar, copiar o assunto e o corpo atuais de cada modelo para um arquivo local, fora do repositório. Para voltar, basta colar esse texto de volta. Se o painel tem um botão de restaurar o padrão é "a confirmar". Nada no código muda.
