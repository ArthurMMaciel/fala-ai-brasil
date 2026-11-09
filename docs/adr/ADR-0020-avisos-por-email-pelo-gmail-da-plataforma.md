# ADR-0020 — Avisos por e-mail pelo Gmail da plataforma

- Estado: **Proposta**, aguardando o responsável. Nenhuma migration, função ou conta foi criada.
- Data: 2026-11-09
- Tarefa: [TASK-0042](../tasks/TASK-0042-avisos-por-email.md)
- Relacionadas: ADR-0010 (revisão humana), ADR-0012 (representante verificado, D7 risco e D12 marcos de 7 e 15 dias), TASK-0023 (SMTP do Gmail), TASK-0007 (base legal e retenção), parecer de plataforma (seção 2 e R4.2, fora do Git)

## Contexto
- Hoje só o Supabase Auth envia e-mail (confirmação de cadastro), pelo SMTP do Gmail. A aplicação não envia nenhum aviso. O trabalhador só descobre que a manifestação mudou de situação se entrar na plataforma, e a empresa só descobre que há caso aguardando resposta se abrir o portal.
- O responsável decidiu (2026-11-08) manter o Gmail e não contratar provedor. A meta do MVP é 30/11 e o custo precisa ser zero.
- A documentação das Edge Functions diz que conexões de saída para as portas 25 e 587 não são permitidas. A porta 465 (SMTP com TLS direto), que o Gmail aceita, não é citada. **Ela precisa ser testada no projeto antes de qualquer implementação.**
- O Gmail pessoal tem limite de 500 envios por dia; ao estourar, a conta fica bloqueada para envio de 1 a 24 horas. Se o Auth usar a mesma conta, o limite é compartilhado.
- A ADR-0012 ainda é proposta: não existem `risk_level` (D7) nem representante verificado (D2 a D6). O AGENTS.md proíbe contato externo automático em caso de alto risco.

## Decisões propostas

**D1. Conta Gmail dedicada da plataforma.** Criada pelo responsável, com verificação em duas etapas e senha de app só para SMTP. Não usar a conta pessoal: a senha de app dá acesso SMTP à caixa inteira. A senha fica nos Secrets da Edge Function, definida pelo responsável no painel, e nunca no Git, no Vault ou em log. Recomendação: o SMTP do Auth passa para a mesma conta, que vira o único remetente da plataforma.

**D2. Teste da porta 465 antes de tudo.** Uma Edge Function descartável abre TLS em `smtp.gmail.com:465`, lê a saudação `220` e encerra, sem autenticar nem enviar. É publicada e apagada pelo responsável, ou com a autorização dele. Resultado:
- 465 aberta: segue o desenho abaixo;
- 465 fechada: a alternativa sem custo é a API do Gmail por HTTPS (porta 443) com OAuth e token de atualização da conta dedicada. É mais trabalho e a credencial é mais poderosa, então volta para decisão. Até lá, envio manual pela Operação (D9).

**D3. Fila no banco (outbox), sem dado pessoal copiado.** Tabela `private.notification_outbox`, com RLS ligado, sem política e sem grant para `anon` e `authenticated`:
`id`, `kind` (`worker_update`, `company_reminder_7`, `company_reminder_15`), `worker_id` ou `company_id`, `dedupe_key` única, `status` (`pending`, `sending`, `sent`, `failed`, `suppressed`), `attempts`, `next_attempt_at`, `last_error_code` (código curto, sem texto do servidor), `sent_at`, `created_at`.
Não guarda e-mail, nome, corpo, protocolo nem conteúdo do caso. O e-mail é resolvido no momento do envio, a partir do `user_id`.

**D4. Aviso ao trabalhador, sem a situação no e-mail.** Um gatilho em `complaint_events` grava uma linha `worker_update` quando o evento não foi gerado pelo próprio trabalhador (`actor <> 'worker'`), com `dedupe_key = 'worker_update:' || event_id`. No envio, todas as linhas pendentes do mesmo trabalhador viram **um único e-mail**. O texto é fixo e não diz a situação nem a empresa (ver D7). Motivo: o e-mail pode cair numa caixa compartilhada, e "liberada para a empresa" ou "retida" já revela que existe uma manifestação.

**D5. Lembretes de 7 e 15 dias à empresa (ADR-0012 D12).** Um job diário do `pg_cron`, às 9h de Brasília, roda só SQL:
1. Acha manifestações em `shared` sem `company_responses`, contando os dias a partir do primeiro evento `shared`. Tema e categoria não entram no critério.
2. Grava cada marco uma única vez por manifestação em `private.complaint_reminder_marks (complaint_id, level)`, com chave única.
3. Agrupa os marcos novos por empresa e cria **uma linha por empresa e nível**, com `dedupe_key = kind || ':' || company_id || ':' || data`.

Destinatário e risco:
- **O lembrete automático só liga quando existirem o representante verificado e o `risk_level` da ADR-0012**. Antes disso, a linha nasce `suppressed` e aparece na Operação como tarefa manual (D9).
- Caso com risco `high` nunca gera envio automático: nasce `suppressed`, como manda a D7.
- A alternativa interina, enviar à conta dona da empresa (`company_users.role = 'owner'`), é **decisão do responsável**. O texto é genérico, mas a dona não é verificada e não há como suprimir o alto risco.

**D6. Envio pela Edge Function `send-notifications`.**
- O `pg_cron` a chama via `pg_net` a cada 5 minutos, com um segredo próprio do agendador guardado no Vault. Nunca a chave de serviço, porque o valor descriptografado fica em `net.http_request_queue` até o envio.
- Ela reserva um lote pequeno com `for update skip locked`, marca `sending`, envia e marca `sent`.
- Em caso de falha, faz nova tentativa com espera crescente (5 min, 30 min, 2 h, 6 h, 24 h). Na quinta falha, a linha fica `failed` e aparece na Operação.
- Erro de autenticação no SMTP interrompe o lote sem gastar tentativas e gera alerta, porque é a senha revogada ou a conta bloqueada.
- **Teto diário de 300 avisos**, contados pelos `sent` do dia, deixando folga para o Auth dentro dos 500 do Gmail. O excedente fica para o dia seguinte.
- SMTP não tem chave de idempotência. Uma queda entre o envio e a marcação pode gerar uma duplicata rara. É aceitável, porque o texto é genérico.

**D7. Textos fixos, sem conteúdo do relato.** Nenhum e-mail leva relato, título, categoria, protocolo, nome da empresa, situação, datas ou quantidade de casos. O link aponta só para a página de login, sem token e sem identificador.
- Trabalhador. Assunto: "Há uma atualização na sua conta Escuta Aí Brasil". Corpo: "Olá. Há uma atualização na sua conta. Para ver, entre na plataforma: [Entrar]. Você recebe este aviso porque tem uma conta de trabalhador na Escuta Aí Brasil. Para não receber mais, desligue os avisos em Meu perfil."
- Empresa, 7 dias. Assunto: "Há manifestações aguardando resposta no portal da sua organização". Corpo genérico, com link para o portal.
- Empresa, 15 dias. Assunto: "Lembrete: manifestações aguardam resposta há mais de 15 dias". Mesmo corpo, sem tom de ameaça.

Os textos finais passam por produto e jurídico.

**D8. Opt-out do trabalhador.** Uma preferência `workers.email_updates` (padrão ligado), alterada em Meu perfil pela RPC `update_worker_profile`. Desligada, a linha nasce `suppressed`. A base legal e o padrão (ligado ou desligado) são decisão do responsável, ligada à TASK-0007.

**D9. Envio manual pela Operação, que já funciona no primeiro dia.** Uma RPC de leitura `ops_notifications_due`, só para `platform_admins`, lista as linhas `suppressed` e `failed` com o destinatário resolvido. A equipe envia o texto fixo a partir da conta da plataforma e marca `sent_manual`, com autor e data. Cobre o período até a porta 465 ser testada e até a ADR-0012 ficar pronta.

**D10. Observabilidade e retenção.**
- Os logs da função trazem só o `id` da linha, o `kind` e o resultado, sem e-mail nem conteúdo.
- A Operação mostra, por status, o total de pendentes, enviados no dia e falhas.
- Linhas `sent` e `suppressed` são apagadas 90 dias depois por um job do `pg_cron`. O prazo é proposta, a definir na TASK-0007.

## Alternativas consideradas
- **Provedor transacional (Resend, SES):** tem domínio próprio e idempotência, mas foi descartado pela decisão de custo e pela transferência internacional. Fica na Revisão 3 do parecer como evolução.
- **Gatilho com `pg_net` chamando o SMTP ou a API direto:** rejeitado. A fila do `pg_net` é *unlogged*, se perde numa queda e não tem nova tentativa, e a credencial ficaria no banco.
- **Front chama a função depois da decisão:** rejeitado. Se a aba fechar, o aviso se perde, e a decisão e o aviso não ficam na mesma transação.
- **`pgmq`:** viável, mas para dezenas de envios por dia uma tabela é mais simples de auditar.

## Consequências
- O trabalhador fica sabendo que há novidade sem que o e-mail exponha a manifestação.
- A empresa recebe lembretes por tempo, nunca por tema. Só com representante verificado e fora do alto risco.
- Custo zero: Gmail gratuito, mais `pg_cron`, `pg_net` e Edge Functions dentro do plano atual. O consumo de invocações (cerca de 9 mil por mês, a cada 5 minutos) precisa ser conferido na cota do plano.
- Riscos:
  - Bloqueio da conta Gmail por volume ou denúncia de spam. Mitigado pelo teto diário e pelos textos genéricos.
  - A senha de app é uma credencial forte. Mitigada pela conta dedicada e pela troca da senha em incidente.

## Pendências de decisão humana
1. Criar a conta Gmail dedicada, com verificação em duas etapas, e definir quem guarda o acesso.
2. Autorizar o teste da porta 465 (D2), que publica e apaga uma função em produção.
3. Passar o SMTP do Auth para a conta dedicada (recomendado).
4. Destinatário dos lembretes até a ADR-0012 (D5): esperar o representante verificado (recomendado) ou usar a conta dona da empresa.
5. Opt-out do trabalhador e a base legal (D8).
6. Textos finais (D7), com produto e jurídico.
7. Retenção da outbox (D10).

## Testes necessários
- **SQL de fumaça** (rodando e desfazendo tudo):
  - evento da equipe ou da empresa gera `worker_update`, e evento do trabalhador não gera;
  - o marco de 7 e o de 15 dias são criados uma vez só por manifestação;
  - os lembretes são agrupados por empresa;
  - a resposta da empresa cancela marcos futuros;
  - risco `high` e destinatário não verificado geram `suppressed`;
  - opt-out gera `suppressed`;
  - `anon` e `authenticated` não leem a outbox.
- **Edge Function**, no local contra o servidor de e-mail do Supabase local (Inbucket): lote com `skip locked`, nova tentativa com espera crescente, `failed` na quinta falha, teto diário e logs sem e-mail.
- **Teste da porta 465** no projeto (D2) e um envio real para uma caixa da equipe, conferindo assunto, corpo e remetente.

## Rollback
`cron.unschedule` dos jobs de envio e de lembretes. A outbox continua acumulando, e a Operação assume pelo envio manual (D9). Para remover de vez: apagar a função, a outbox e o gatilho numa migration nova. Nenhum dado de negócio depende dos avisos.
