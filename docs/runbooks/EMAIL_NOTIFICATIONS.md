# Notificações por e-mail: teste da porta 465 e plano da função de envio (ADR-0020)

- Estado: **em produção desde 2026-11-24 03:10 UTC.** A `send-notifications` está publicada e agendada a cada 5 minutos, e a conferência do lote 4 deu tudo verdadeiro (rodada `succeeded`, resposta 200). Para desligar já: `supabase/sql-editor/lote4/02_desligar_envio.sql` ([PILOT_SUSPENSION](PILOT_SUSPENSION.md#notificações-por-e-mail-desligar-já)).
- Escopo aprovado pelo responsável ("Aprovo", repassado pelo Gestor em 2026-11-23): notificação automática **só para contas da plataforma**:
  - o trabalhador dono do relato;
  - os usuários verificados da empresa.

  O contato indicado pelo trabalhador e o e-mail da Receita **não** recebem nada automático. Para eles, vale só o aviso manual da ADR-0023.
- Quem executa: o responsável. Publicar e apagar função, criar secret e criar segredo no Vault são ações em produção.
- Relacionadas: ADR-0020 (revisão de 2026-11-23), ADR-0009 (Gmail do Auth), [EDGE_FUNCTION_DEPLOY](EDGE_FUNCTION_DEPLOY.md), [PILOT_SUSPENSION](PILOT_SUSPENSION.md#conta-gmail-do-auth-bloqueada).

## Teste da porta 465 (2026-11-24, cerca de 15 minutos)

**Resultado (2026-11-24, feito pelo responsável):** `{"tls":true,"code":"220","error":null,"ms":1177,"open":true}`. A porta está aberta. A `smtp-probe` foi apagada do projeto (`functions delete` confirmado) e removida do repositório. Os passos abaixo ficam como registro.

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
- **Texto fixo por tipo e motivo** (revisão de 2026-11-26, ADR-0020): trabalhador, liberação, resposta devolvida, encerramento e aviso à empresa não cadastrada. Os textos estão em `supabase/functions/send-notifications/send.ts` (`message`). O link vai em texto, sem token, protocolo ou conteúdo. Os textos finais passam por produto e jurídico.
- **Ordem com a migration 20261126130000:** aplicar o lote 5, passo 02, e só depois publicar a função nova (mesmo comando de deploy abaixo). A função nova também roda no banco antigo, sem os avisos à empresa não cadastrada.
- **Teto diário:** 300 envios, contados pelos `sent` do dia, para deixar folga ao Auth dentro do limite do Gmail. O limite exato do SMTP é "a confirmar" (ADR-0009). O excedente fica para o dia seguinte.
- **Novas tentativas:** 5 min, 30 min, 2 h, 6 h e 24 h. Na **sexta** falha, a linha fica `failed` (decisão de 2026-11-24, que segue o código do Back: as cinco esperas são usadas, num total de cerca de 32 h, o que cobre um bloqueio do Gmail de até 24 h). Mostrar as linhas `failed` na Operação ainda está pendente.
- **Erro de autenticação SMTP** (senha de app revogada ou conta bloqueada): o lote para sem gastar tentativas e o caso é tratado como incidente ([conta bloqueada](PILOT_SUSPENSION.md#conta-gmail-do-auth-bloqueada)).
- **Reserva de linhas:** `for update skip locked` para duas rodadas não pegarem a mesma linha. Uma queda entre o envio e a marcação pode gerar uma duplicata rara, aceitável com texto genérico.
- **Logs:** só `id` da linha, `kind`, resultado e tempo. Nunca e-mail, nome, protocolo, texto do servidor SMTP ou a senha.
- **Opt-out do trabalhador** em Meu perfil (ADR-0020 D8). A linha nasce `suppressed`.

### Publicação passo a passo (responsável, na máquina dele)

Pré-requisitos, todos marcados antes de começar:
- [ ] ADR-0020 revisada (2026-11-23) e a parte de dados registrada pelo Back.
- [ ] Código da `send-notifications` e da migration da fila revisados pelo DevOps. A CI precisa estar verde na `main` com o SHA aprovado. Atualizar o repositório local com `git pull` e conferir `git log -1`.
- [ ] Horário de pouco uso. Nenhum segredo é colado em chat, task, commit ou arquivo do repositório.

**Passo 1. Extensões (painel).** Database > Extensions: habilitar `pg_cron` e `pg_net`. Conferir que `supabase_vault` está habilitada; o normal é vir habilitada. Se alguma não puder ser habilitada no Free, parar e avisar o DevOps.

**Passo 2. Migration da fila e dos gatilhos (SQL Editor).** Rodar o `aplicar` e o `conferir` que o Back entregar, como nos lotes anteriores. Daqui em diante, as mudanças de situação geram linhas `pending` na fila, mas nada é enviado.

**Passo 3. Gerar o segredo do agendador (PowerShell).** O valor vai direto para a área de transferência, sem aparecer na tela:

```powershell
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); (-join ($b | ForEach-Object { $_.ToString('x2') })) | Set-Clipboard
```

O mesmo valor vai para dois lugares, nos passos 4 e 6. Guardar no gerenciador de senhas, no item da plataforma, até terminar.

**Passo 4. Secrets da função (painel, de preferência).** Edge Functions > Secrets (ou Project Settings > Edge Functions):
- `GMAIL_USER`: o endereço do Gmail do Auth;
- `GMAIL_APP_PASSWORD`: uma senha de app **própria das notificações**, gerada na mesma conta Google. Foi a escolha do responsável em 2026-11-24. Revogar uma não derruba a outra;
- `NOTIFY_CRON_SECRET`: o valor do passo 3.

Por que o painel: `supabase secrets set NOME=valor` no terminal deixa o valor no histórico do PowerShell. Se for pela CLI, usar `--env-file` com um arquivo temporário fora de qualquer repositório e apagá-lo logo depois:

```bash
npx supabase secrets set --env-file "%TEMP%
otify.env" --project-ref <ref-de-producao>
```

**Passo 5. Publicar a função** (preparação e login como no [EDGE_FUNCTION_DEPLOY](EDGE_FUNCTION_DEPLOY.md), passos 1 a 4). Ela vai sem verificação de JWT, porque quem chama é o agendador. A proteção é o `x-cron-secret`:

```bash
npx supabase functions deploy send-notifications --project-ref <ref-de-producao> --use-api --no-verify-jwt
```

Conferir sem segredo. Esperado: `401`:

```powershell
curl.exe -s -o NUL -w "%{http_code}" -X POST https://<ref-de-producao>.supabase.co/functions/v1/send-notifications
```

**Passo 6. Vault (painel, de preferência).** Integrations > Vault (ou Project Settings > Vault), com o caminho exato "a confirmar":
- `project_url`: `https://<ref-de-producao>.supabase.co`;
- `notify_cron_secret`: o valor do passo 3.

Se for pelo SQL Editor com `vault.create_secret`, o texto do segredo fica no histórico do editor. Nesse caso, apagar a consulta salva logo depois.

**Passo 7. Teste controlado, antes de ligar o agendamento.**
1. Com uma conta de teste do próprio responsável, gerar uma mudança de situação num caso de teste, de modo que exista 1 linha `pending` na fila.
2. Chamar a função uma vez pelo SQL Editor, com o mesmo comando do agendamento (o `select net.http_post(...)` do passo 8, sem o `cron.schedule`).
3. Conferir:
   - a linha passou a `sent`;
   - o e-mail chegou na caixa de teste, em português, com o link em texto;
   - os logs da função (Edge Functions > `send-notifications` > Logs) têm só id, tipo e resultado.

**Passo 8. Ligar o agendamento (SQL Editor).** É o último passo, e o que liga o envio. Vale o texto final que o Back entregar. Referência:

```sql
select cron.schedule(
  'send-notifications',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notify_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);
```

Conferir em Integrations > Cron (ou `select * from cron.job_run_details order by start_time desc limit 5;`) que as rodadas terminam com `succeeded`.

**Passo 9.** `npx supabase logout` e registro na TASK-0042: data, SHA, versão da função e resultado do passo 7.

### Rollback

- **Parar o envio já** (SQL Editor). As linhas continuam na fila, e nada se perde:

  ```sql
  select cron.unschedule('send-notifications');
  ```

- **Contenção total:**
  - `npx supabase functions delete send-notifications --project-ref <ref-de-producao>`;
  - se houver suspeita sobre a senha de app, trocá-la (inventário no [PILOT_SUSPENSION](PILOT_SUSPENSION.md)). O SMTP do Auth também precisa da senha nova.
- **Remover a fila e os gatilhos:** pela migration de reversão do Back.
- **Conta Gmail bloqueada:** seguir [conta bloqueada](PILOT_SUSPENSION.md#conta-gmail-do-auth-bloqueada) e rodar o `cron.unschedule` primeiro.

### Custo e consumo

- Zero. São cerca de 9 mil invocações por mês (uma a cada 5 minutos), dentro das 500 mil do Free ([preço](https://supabase.com/docs/guides/functions/pricing)).
- O volume de e-mail no piloto de referência (3 empresas, até 5 casos novos por dia) fica muito abaixo do teto de 300.

## Pedido de exclusão dos avisos (opt-out)

Decisão do responsável em 2026-11-27: ele mesmo atende os pedidos ("Eu mesmo").

- **De onde vem:** o aviso à empresa não cadastrada termina com "responda a este e-mail pedindo a exclusão". As respostas chegam à caixa do remetente (`GMAIL_USER`).
- **Como registrar:** script `supabase/sql-editor/manutencao/05_opt_out_aviso.sql`, no SQL Editor de produção.
  1. Preencha no topo o e-mail que pediu a exclusão (`EMAIL_AQUI`) e/ou o CNPJ da empresa (`CNPJ_AQUI`), e o e-mail da sua conta de equipe (`SEU_EMAIL_DE_EQUIPE_AQUI`).
  2. Rode o arquivo inteiro uma vez. Com CNPJ, saem da lista o e-mail da Receita desse CNPJ e os contatos que já foram destino de aviso dessa empresa.
  3. Confira o resultado: uma linha por e-mail tratado, sem mostrar e-mail algum, com `gravado_na_lista = true`. `ja_existia = true` indica que o pedido já estava registrado.
  4. Não salve a consulta com os campos preenchidos.
- **Efeito:** grava só o hash do e-mail (`private.notice_opt_outs`), o mesmo que `ops_add_opt_out` faz na Operação. A equipe não consegue mais aprovar aviso para esse e-mail, e um aviso aprovado e ainda não enviado não sai, porque a fila confere o opt-out na hora do envio.
- **Responder a quem pediu:** opcional. Se responder, não cite manifestação nem empresa além do que o aviso já dizia.
- **Escopo:** vale para o aviso à empresa não cadastrada. O trabalhador desliga os próprios avisos em Meu perfil.
