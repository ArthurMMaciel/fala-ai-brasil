# TASK-0042 — Avisos por e-mail: atualização ao trabalhador e lembretes de 7 e 15 dias à empresa

- Status: proposta
- ClickUp: (a criar pelo Gestor)
- Área: Backend / DevOps
- Prioridade: P1
- Estimativa: 3 a 4 dias, depois das decisões (manual pela Operação: 0,5 dia)
- Impacto: o trabalhador sabe que há novidade e a empresa é lembrada dos casos parados, sem expor o relato.
- Decisão: [ADR-0020](../adr/ADR-0020-avisos-por-email-pelo-gmail-da-plataforma.md), proposta

## Problema
A aplicação não envia nenhum aviso. Quem manifestou só vê a mudança de situação se entrar na plataforma. A empresa só vê o caso aguardando resposta se abrir o portal. Os marcos de 7 e 15 dias da ADR-0012 (D12) não têm mecanismo de envio.

## Escopo
1. Teste da porta 465 do Gmail a partir de uma Edge Function no projeto (ADR-0020 D2).
2. Migration: `private.notification_outbox`, `private.complaint_reminder_marks`, gatilho em `complaint_events`, preferência de opt-out e RPC `ops_notifications_due`.
3. Jobs do `pg_cron`: lembretes diários às 9h de Brasília, envio a cada 5 minutos e limpeza da outbox.
4. Edge Function `send-notifications`, com SMTP 465, teto diário, novas tentativas e logs sem dado pessoal.
5. Tela de envio manual na Operação e o opt-out em Meu perfil.

## Fora de escopo
Convite à empresa não cadastrada (ADR-0012 D5), representante verificado (TASK-0011), domínio próprio e provedor transacional.

## Critérios de aceite
- Nenhum e-mail contém relato, título, categoria, protocolo, nome da empresa, situação ou data.
- Cada manifestação gera no máximo um lembrete de 7 dias e um de 15, agrupados por empresa.
- Alto risco, destinatário não verificado e opt-out nunca geram envio automático.
- Os logs da função não têm e-mail nem conteúdo.
- O teto diário é respeitado.
- O envio manual funciona antes do automático.

## Dependências
- Conta Gmail dedicada criada pelo responsável.
- Teste da porta 465.
- ADR-0012 (representante verificado e `risk_level`), para o lembrete automático à empresa.
- TASK-0007, para base legal e retenção.

## Segurança
A senha de app fica só nos Secrets da Edge Function, definida pelo responsável. O segredo do agendador fica no Vault; a chave de serviço não é usada nele. A outbox fica sem grant para os papéis do cliente.

## Dados envolvidos
E-mail de login do trabalhador e do representante, resolvidos só no momento do envio e nunca copiados para a outbox.

## Observabilidade
Contagem por status na Operação. Linhas `failed` visíveis para a equipe. O alerta de falha de autenticação no SMTP vai para o DevOps.

## Rollback
`cron.unschedule` dos jobs. A Operação assume o envio manual.

## Testes necessários
Ver ADR-0020, seção "Testes necessários".

## Definição de pronto
Envio manual em uso, porta 465 testada e envio automático ao trabalhador em produção. O lembrete automático à empresa só liga depois da ADR-0012.
