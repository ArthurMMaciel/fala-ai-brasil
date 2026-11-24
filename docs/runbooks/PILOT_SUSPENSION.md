# Runbook — Incidente e suspensão do piloto

Vale para o piloto fechado a partir de 30/11. Usa só o que existe em 2026-11-17. O que falta está marcado **Lacuna**.

## Parâmetros do piloto (definidos pelo responsável, comunicados pelo Gestor em 2026-11-17)

- Referência: 3 empresas e até 5 casos novos por dia. São números de referência, não limites. O piloto se ajusta com a experiência, e não há gatilho automático nem critério operacional de pausa.
- Operador único: o próprio responsável. **Lacuna aceita:** não há substituto do operador.
- A pausa do piloto ([ADR-0021](../adr/ADR-0021-pausa-do-piloto.md)) fica reservada a incidente de segurança ou privacidade (SEV-1 abaixo). A ADR foi aceita em 2026-11-17 e está implementada em produção pela migration `20261117150000`. **O mecanismo foi testado em produção em 2026-11-24** (ver "Pausar novas entradas").

## Quem faz o quê

| Papel | Quem | Pode |
|---|---|---|
| Aciona e decide | Responsável técnico | Única pessoa com acesso de escrita à Vercel e ao Supabase de produção. Decide suspender, reabrir e comunicar. |
| Conduz o registro | Gestor | Abre o registro do incidente, mantém a linha do tempo e redige as comunicações para o responsável aprovar. |
| Apoio técnico | DevOps, Back, Front | Diagnosticam e preparam comandos. Não executam nada em produção sem liberação escrita do responsável. |

Qualquer pessoa que perceber um problema avisa o responsável e o Gestor. O aviso não inclui conteúdo de relato, dado pessoal nem segredo, só o identificador (protocolo, id da empresa, nome da chave).

**Lacuna aceita (2026-11-17):** não há plantão, contato fora do horário nem substituto do responsável. Na ausência dele, ninguém executa contenção em produção.

## Severidade

- **SEV-1:**
  - relato, identidade de trabalhador ou dado pessoal visível a quem não deveria;
  - segredo de produção exposto;
  - empresa vendo dados de outra.

  Contenção imediata.
- **SEV-2:** produção fora do ar ou com erro em fluxo crítico (cadastro, envio de relato, resposta da empresa), sem exposição de dados.
- **SEV-3:** falha parcial com contorno.

## 1. Conter

### Produção quebrada após deploy (SEV-2)
- Vercel > Project > Deployments: fazer Instant Rollback para o último deploy bom.
- O DevOps informa qual é o deploy bom: o último com o `production-smoke` verde no GitHub Actions.
- Depois, corrigir na `main` ([ENVIRONMENTS](../devops/ENVIRONMENTS.md#push-direto-na-main-desde-2026-11-09)).
- O rollback da Vercel volta só o front. Uma migration já aplicada no banco não volta: o Back prepara uma migration de correção.

### Pausar novas entradas
- **Novas contas:** Supabase > Authentication > configurações de Sign In: desligar "Allow new users to sign up". Isso bloqueia cadastros novos e não afeta quem já tem conta. O caminho exato no painel é "a confirmar".
- **Novos relatos (ADR-0021):** um membro da equipe (`platform_admins`) roda no SQL Editor `supabase/sql-editor/05_pausar_piloto.sql`. O script assume, só na própria transação, a identidade da conta de equipe e chama `ops_set_pilot_state('paused', '<motivo>')`. O motivo tem de 10 a 500 caracteres e não pode conter conteúdo de relato. Com a pausa, `create_complaint` recusa novos relatos, e quem já tem caso aberto continua acompanhando. Para reabrir: `06_retomar_piloto.sql`. Cada mudança fica em `pilot_state_log`. Hoje a tela da Operação não chama `ops_set_pilot_state`, e o caminho é só o SQL Editor.
- **Teste em produção (2026-11-24, feito pelo responsável):** `05_pausar_piloto` deixou o estado `paused` às 02:08:21 UTC, e `06_retomar_piloto` voltou para `open` às 02:08:48 UTC, 27 segundos depois. As duas mudanças ficaram na trilha `pilot_state_log`. **A troca de estado está comprovada em produção.** A recusa de `create_complaint` durante a pausa não foi exercitada nesses 27 segundos; ela é coberta pelo teste em transação da 150000.
- **Retenção já existente:** pela Operação, um relato em revisão pode ficar retido (`held`) antes de chegar à empresa (`ops_decide_complaint`). Isso contém um relato específico, sem pausar o fluxo.

### Revogar o acesso de uma empresa
- A empresa só enxerga dados enquanto o usuário dela estiver em `public.company_users`. As funções e políticas consultam essa tabela a cada requisição.
- Remover a linha corta o acesso aos dados da empresa na requisição seguinte, mesmo com a sessão ainda aberta. A ação é feita pelo responsável no SQL Editor de produção, com o `company_id` e o `user_id` em mãos.
- Para impedir também o login: Supabase > Authentication > Users > o usuário > banir ou excluir. A disponibilidade do "ban" no painel é "a confirmar".
- **Lacuna (Back):** não há função de Operação para suspender uma empresa sem SQL manual nem trilha de auditoria dessa ação. Até existir, registrar à mão no incidente quem removeu, quando e o motivo.

### Segredo exposto (SEV-1)
Segue também [CREDENTIAL_LEAK](CREDENTIAL_LEAK.md). Inventário em 2026-11-17:

| Segredo | Onde é usado | Como trocar |
|---|---|---|
| Chave publishable do Supabase | Front (`VITE_SUPABASE_PUBLISHABLE_KEY` na Vercel) | É pública por desenho, e a proteção real é a RLS. Só se troca se houver abuso. Criar a nova em Supabase > Settings > API Keys, atualizar a variável na Vercel, fazer redeploy e depois revogar a antiga. |
| Chave secret / service_role do Supabase | Edge Function `send-notifications` (em produção desde 2026-11-24). A plataforma injeta a chave pela `SUPABASE_SECRET_KEYS`, com a legada como reserva. Ela só executa `notification_claim` e `notification_mark` | Supabase > Settings > API Keys: gerar outra e revogar a comprometida. A função lê a chave injetada; conferir uma rodada `succeeded` depois da troca (`02_conferir_agendamento.sql`). |
| Senha do banco (Postgres) | CLI (`db push`, `db dump`) na máquina do responsável | Supabase > Settings > Database > reset da senha. |
| SMTP do Auth (senha de app do Gmail do responsável, uso estendido ao piloto; ADR-0009, revisão de 2026-11-17) | Supabase > Authentication > SMTP | Na conta Google, remover a senha de app comprometida, gerar outra e colar no painel do Supabase. Enquanto isso, os e-mails de confirmação e de recuperação param. Trocar a senha da conta Google revoga todas as senhas de app, e aí o mesmo procedimento é obrigatório. |
| `GMAIL_APP_PASSWORD` (senha de app **própria das notificações**, separada da do SMTP do Auth) e `GMAIL_USER` | Secrets da Edge Function `send-notifications` | Primeiro, **desligar o envio**: `supabase/sql-editor/lote4/02_desligar_envio.sql`. Depois, na conta Google, remover só esta senha de app, gerar outra e atualizar o secret (painel: Edge Functions > Secrets). A senha do Auth continua valendo. Religar com `02_agendar_envio.sql`. Trocar a senha da conta Google revoga as duas senhas de app: o Auth **e** as notificações param, e as duas precisam ser refeitas. |
| `NOTIFY_CRON_SECRET` (secret da função) e `notify_cron_secret` (Vault), com o mesmo valor | Cabeçalho `x-cron-secret` da chamada do Cron para a função | Desligar o envio (`02_desligar_envio.sql`), gerar um valor novo (comando do passo 3 do [EMAIL_NOTIFICATIONS](EMAIL_NOTIFICATIONS.md)), atualizar **os dois lugares** com o mesmo valor e religar (`02_agendar_envio.sql`). Valor só num dos lados faz a função responder 401 em toda rodada. |
| `project_url` (Vault) | URL do projeto que o Cron chama | Não é segredo: é a URL pública do projeto. Só muda se o projeto mudar. |
| Token da Vercel e token do GitHub | Contas pessoais do responsável | Revogar no painel de cada serviço. |

Nunca colar um segredo em chat, task ou commit. No registro do incidente entra só o nome da chave e a hora da troca.

**Risco aceito (2026-11-17):** o piloto usa o Gmail do responsável no SMTP (ADR-0009, revisão de 2026-11-17). Os riscos aceitos são o limite diário, o remetente pessoal e a dependência de uma conta pessoal.

**Risco aceito (2026-11-18):** os avisos manuais às empresas não cadastradas saem da mesma conta (ADR-0009, revisão de 2026-11-18). O limite diário é compartilhado com o Auth, e uma denúncia de spam ou um bloqueio derrubam a confirmação de cadastro e a recuperação de senha.

### Notificações por e-mail: desligar já

As notificações automáticas (ADR-0020, `send-notifications`) estão em produção desde 2026-11-24 03:10 UTC, com o Cron a cada 5 minutos.
- **Desligar:** rodar no SQL Editor `supabase/sql-editor/lote4/02_desligar_envio.sql` (`cron.unschedule`). Nada se perde: as mudanças de situação continuam entrando na fila como `pending`.
- **Quando desligar:**
  - suspeita sobre `GMAIL_APP_PASSWORD` ou `NOTIFY_CRON_SECRET`;
  - conta Gmail bloqueada;
  - e-mail saindo para quem não devia;
  - qualquer SEV-1 que envolva a fila ou a função.
- **Conferir:** `02_conferir_agendamento.sql` sem o job. A equipe vê as contagens em `ops_notification_stats()`.
- **Contenção total:** `npx supabase functions delete send-notifications --project-ref <ref-de-producao>` e a troca dos segredos da tabela acima.
- **Religar:** `02_agendar_envio.sql`, depois de resolvida a causa. A fila acumulada sai respeitando o teto de 300 por dia.

### Conta Gmail do Auth bloqueada

Severidade: SEV-2, porque o cadastro é fluxo crítico, sem exposição de dados.

1. **Sinais:**
   - usuários dizem não receber confirmação ou recuperação de senha;
   - o Gmail mostra aviso de limite ou de suspensão;
   - os logs do Auth mostram erro de SMTP. Exportar os logs no mesmo dia, porque a retenção é de 1 dia.
2. **Conter:**
   - desligar as notificações automáticas (`02_desligar_envio.sql`), porque saem da mesma conta Gmail;
   - parar os avisos manuais às empresas até a conta voltar;
   - registrar a hora no incidente.
3. **Limite diário atingido:** a ajuda do Gmail diz que o envio volta em 1 a 24 h. Esperar e não tentar reenviar em massa. Quando voltar, quem não recebeu pode pedir o reenvio da confirmação pelo site, que usa `auth.resend`.
4. **Suspensão ou bloqueio por denúncia:**
   - o responsável segue a recuperação da conta no Google;
   - se a recuperação demorar, trocar o SMTP do Auth para outra conta. Hoje essa conta não existe, então é preciso criá-la, com verificação em duas etapas e senha de app, e colar a senha em Supabase > Authentication > SMTP. É o mesmo procedimento da troca de senha de app no inventário acima;
   - testar a confirmação e a recuperação logo depois.
5. **Não há saída sem SMTP próprio:** sem ele, o Supabase só entrega e-mail do Auth para endereços da equipe da organização.
6. **Reabrir:**
   - conta funcionando;
   - teste de confirmação e de recuperação feito;
   - avisos manuais retomados aos poucos.

**Recomendação:**
- Antes de 30/11, deixar criada, sem configurar, uma conta reserva (de preferência a futura conta da empresa). Assim, o passo 4 leva minutos em vez de depender da criação de conta durante o incidente.
- Quando a conta da empresa existir, migrar para ela o SMTP do Auth e os avisos (ADR-0009, revisão de 2026-11-18).

## 2. Preservar evidências

Anotar a hora do incidente e exportar em até 24 h:
- os logs do Supabase. No Free, a retenção é de 1 dia; no Pro, 7 dias ([TASK-0009](../tasks/TASK-0009-auditoria-e-observabilidade.md));
- os runtime logs da Vercel. No Hobby, a retenção é de 1 hora.

Pela retenção curta, esse passo vem logo depois da contenção. Os eventos de `complaint_events` e da Operação ficam no banco.

## 3. Comunicar

- **Equipe:** o Gestor informa Front, Back e DevOps só com o necessário.
- **Empresas do piloto:** mensagem do responsável, sem citar relato nem trabalhador.
- **Trabalhadores afetados e ANPD:** se houver risco ou dano relevante a titulares, a LGPD (art. 48) exige comunicar a ANPD e os titulares. O prazo e o formato estão no regulamento da ANPD. **Confirmar com o jurídico antes de 30/11:** quem é o controlador, quem é o encarregado (DPO) e qual o prazo aplicável.
- **Lacuna:** não há modelo de mensagem aprovado. O Gestor prepara os rascunhos antes do piloto.
- Casos de alto risco não geram contato externo automático (AGENTS.md). Qualquer contato é decisão humana.

## 4. Recuperar e reabrir

1. Causa corrigida e testada (`npm test`, smoke SQL e `production-smoke` verdes).
2. Se houve perda de dados, seguir [DATA_LOSS](DATA_LOSS.md). Backup e restauração estão descritos na [TASK-0010](../tasks/TASK-0010-backup-e-resposta-a-incidente.md) e no [RESTORE_DRILL](RESTORE_DRILL.md).
3. O responsável reabre: religa o cadastro, recadastra o acesso da empresa se for o caso, e registra a hora.
4. Pós-incidente em até 5 dias úteis, com linha do tempo, causa, impacto e ações.

## Teste antes do go/no-go (25/11)

Simulação de mesa de 30 minutos com o responsável e o Gestor: um SEV-1 de empresa vendo relato de outra. O objetivo é conferir se cada passo acima é executável e quem o faz. Registrar o resultado na TASK-0010.

- Pausa do piloto: **testada em produção em 2026-11-24** (ver "Pausar novas entradas"). No go/no-go, ela entra como comprovada, e não mais como "não comprovada".
