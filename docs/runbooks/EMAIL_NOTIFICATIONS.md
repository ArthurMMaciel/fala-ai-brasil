# Notificações por e-mail: teste da porta 465 e plano da função de envio (ADR-0020)

- Estado: **preparado em 2026-11-23, nada executado.** O teste está marcado para 2026-11-24.
- Escopo aprovado pelo responsável ("Aprovo", repassado pelo Gestor em 2026-11-23): notificação automática **só para contas da plataforma**:
  - o trabalhador dono do relato;
  - os usuários verificados da empresa.

  O contato indicado pelo trabalhador e o e-mail da Receita **não** recebem nada automático. Para eles, vale só o aviso manual da ADR-0023.
- Quem executa: o responsável. Publicar e apagar função, criar secret e criar segredo no Vault são ações em produção.
- Relacionadas: ADR-0020 (revisão de 2026-11-23), ADR-0009 (Gmail do Auth), [EDGE_FUNCTION_DEPLOY](EDGE_FUNCTION_DEPLOY.md), [PILOT_SUSPENSION](PILOT_SUSPENSION.md#conta-gmail-do-auth-bloqueada).

## Teste da porta 465 (2026-11-24, cerca de 15 minutos)

A [documentação das Edge Functions](https://supabase.com/docs/guides/functions/limits) bloqueia a saída pelas portas 25 e 587 e não cita a 465. O teste verifica se a função consegue abrir TLS em `smtp.gmail.com:465` e receber a saudação `220`.

O que a função `smtp-probe` faz (`supabase/functions/smtp-probe/index.ts`):
- abre TLS, lê a primeira linha, manda `QUIT` e fecha;
- não autentica, não envia e-mail e não usa segredo;
- responde só `open`, o código de 3 dígitos, a classe do erro e o tempo;
- não grava log próprio.

Passos, com a mesma preparação do [EDGE_FUNCTION_DEPLOY](EDGE_FUNCTION_DEPLOY.md) (passos 1 a 4: CLI, tirar o `SUPABASE_ACCESS_TOKEN` do terminal, `login`, `functions list`):

1. Publicar **sem** verificação de JWT. A função não lê nem devolve dado e fica no ar só durante o teste. Com `verify_jwt` ligado, seria preciso copiar um token de sessão do navegador, o que é pior:

   ```bash
   npx supabase functions deploy smtp-probe --project-ref <ref-de-producao> --use-api --no-verify-jwt
   ```

2. Chamar uma vez:

   ```powershell
   curl.exe -s -X POST https://<ref-de-producao>.supabase.co/functions/v1/smtp-probe
   ```

3. Ler o resultado:
   - `"open":true` e `"code":"220"`: a porta está aberta e o plano abaixo segue;
   - `"tls":false` com `"error"` (por exemplo `PermissionDenied`, `ConnectionRefused` ou `TimedOut`): a porta está bloqueada. **O piloto começa sem notificação automática**;
   - outro código: anotar e mandar ao DevOps.
4. **Apagar no mesmo momento** e conferir que a lista voltou ao estado anterior:

   ```bash
   npx supabase functions delete smtp-probe --project-ref <ref-de-producao>
   ```

   ```bash
   npx supabase functions list --project-ref <ref-de-producao>
   ```

5. `npx supabase logout`.
6. Registrar o resultado na TASK-0042 (data, `open`, `code`, `ms`) e avisar o Gestor. Depois, o DevOps remove `supabase/functions/smtp-probe/` do repositório.

Se o `production-smoke` rodar durante o teste, nada muda: ele não chama a `smtp-probe`.

## Plano da função de envio (só se a 465 abrir)

### Peças

| Peça | Onde | Quem cria |
|---|---|---|
| Fila `private.notification_outbox` e gatilho em `complaint_events` | migration do Back, pelo SQL Editor | Back escreve, responsável aplica |
| Função `send-notifications` | Edge Function | Back escreve, DevOps revisa, responsável publica |
| Senha de app do Gmail | secret da função (`GMAIL_APP_PASSWORD`, mais `GMAIL_USER`) | **responsável**, com `secrets set` no próprio terminal |
| Segredo do agendador | Vault (`notify_cron_secret`) e secret da função (`NOTIFY_CRON_SECRET`), com o mesmo valor | **responsável**, gerado por ele |
| URL do projeto | Vault (`project_url`), valor público | responsável |
| Agendamento | `cron.schedule` a cada 5 minutos, que chama a função por `net.http_post` | migration do Back, pelo SQL Editor |

### pg_cron, pg_net e Vault no plano Free

- A documentação do [Supabase Cron](https://supabase.com/docs/guides/cron), do [pg_net](https://supabase.com/docs/guides/database/extensions/pg_net) e do [agendamento de funções](https://supabase.com/docs/guides/functions/schedule-functions) não restringe nenhum deles a planos pagos. Habilitar fica em Database > Extensions (ou Integrations > Cron).
- **Disponibilidade no Free: "a confirmar" no painel** antes da migration. Hoje, nenhuma migration do repositório usa `pg_cron`, `pg_net` ou Vault.
- Recomendação de uso do Cron: no máximo 8 jobs simultâneos, cada um com até 10 minutos. Aqui é 1 job curto.
- O `pg_net` guarda as respostas por 6 horas em `net._http_response`, e a fila dele é *unlogged*. Por isso, a fila de verdade é a outbox, e o `pg_net` só "acorda" a função.

### Segredo do agendador

- A chamada do Cron leva no cabeçalho `x-cron-secret` o valor guardado no Vault. A função compara com `NOTIFY_CRON_SECRET` e recusa com 401 se não bater.
- **Não usar a chave de serviço no Cron.** O valor decifrado de qualquer segredo passa pela fila do `pg_net` (`net.http_request_queue`) até o envio (ADR-0020 D6). Um segredo próprio, que só abre esta função, limita o estrago.
- A função é publicada com `--no-verify-jwt`, porque quem chama é o Cron e não um usuário. A proteção é o segredo do agendador.

### Envio

- **Destinatários** (escopo aprovado):
  - trabalhador: em todo evento de `complaint_events` com `actor <> 'worker'`;
  - empresa: usuários com vínculo verificado (`is_verified_company_user`), só nos eventos visíveis a ela (liberação `shared`, devolução da resposta, encerramento pelo trabalhador), nunca em `received`, `in_review`, `held` ou `answer_in_review`;
  - nunca `complaint_contacts` nem e-mail da Receita.
- **Agrupamento:** um e-mail por destinatário por rodada, com todas as pendências dele.
- **Texto fixo:** "Há uma atualização na sua manifestação. Entre na plataforma para ver: https://fala-ai-brasil.vercel.app". O link vai em texto, sem token, protocolo, empresa ou situação. Os textos finais passam por produto e jurídico.
- **Teto diário:** 300 envios, contados pelos `sent` do dia, para deixar folga ao Auth dentro do limite do Gmail. O limite exato do SMTP é "a confirmar" (ADR-0009). O excedente fica para o dia seguinte.
- **Novas tentativas:** 5 min, 30 min, 2 h, 6 h e 24 h. Na quinta falha, a linha fica `failed` e aparece na Operação.
- **Erro de autenticação SMTP** (senha de app revogada ou conta bloqueada): o lote para sem gastar tentativas e o caso é tratado como incidente ([conta bloqueada](PILOT_SUSPENSION.md#conta-gmail-do-auth-bloqueada)).
- **Reserva de linhas:** `for update skip locked` para duas rodadas não pegarem a mesma linha. Uma queda entre o envio e a marcação pode gerar uma duplicata rara, aceitável com texto genérico.
- **Logs:** só `id` da linha, `kind`, resultado e tempo. Nunca e-mail, nome, protocolo, texto do servidor SMTP ou a senha.
- **Opt-out do trabalhador** em Meu perfil (ADR-0020 D8). A linha nasce `suppressed`.

### Ordem de publicação

1. ADR-0020 revisada e aceita.
2. Extensões habilitadas no painel e conferidas.
3. Migration da fila e dos gatilhos aplicada e conferida. Até a função existir, as linhas só acumulam.
4. Secrets da função criados pelo responsável: `GMAIL_USER`, `GMAIL_APP_PASSWORD` e `NOTIFY_CRON_SECRET`.
5. Função publicada e testada com uma conta de teste do próprio responsável.
6. Segredos no Vault e `cron.schedule` criados por último. É o passo que liga o envio.

### Rollback

- **Desligar já:** `select cron.unschedule('send-notifications');` no SQL Editor. As linhas continuam na fila.
- **Contenção total:** apagar a função (`functions delete send-notifications`) e trocar a senha de app (inventário no PILOT_SUSPENSION).
- A fila e os gatilhos saem por migration de reversão do Back.

### Custo e consumo

- Zero. São cerca de 9 mil invocações por mês (uma a cada 5 minutos), dentro das 500 mil do Free ([preço](https://supabase.com/docs/guides/functions/pricing)).
- O volume de e-mail no piloto de referência (3 empresas, até 5 casos novos por dia) fica muito abaixo do teto de 300.
