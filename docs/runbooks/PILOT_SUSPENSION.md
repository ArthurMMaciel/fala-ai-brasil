# Runbook — Incidente e suspensão do piloto

Vale para o piloto fechado a partir de 30/11. Usa só o que existe em 2026-11-17. O que falta está marcado **Lacuna**.

## Parâmetros do piloto (definidos pelo responsável, comunicados pelo Gestor em 2026-11-17)

- Referência: 3 empresas e até 5 casos novos por dia. São números de referência, não limites. O piloto se ajusta com a experiência, e não há gatilho automático nem critério operacional de pausa.
- Operador único: o próprio responsável. **Lacuna aceita:** não há substituto do operador.
- A pausa do piloto ([ADR-0021](../adr/ADR-0021-pausa-do-piloto.md)) fica reservada a incidente de segurança ou privacidade (SEV-1 abaixo). Em 2026-11-17, a ADR consta como "Proposta" no repositório e não está implementada. Até a migration chegar à produção, vale o que está em "Pausar novas entradas" abaixo.

## Quem faz o quê

| Papel | Quem | Pode |
|---|---|---|
| Aciona e decide | Responsável técnico | Única pessoa com acesso de escrita à Vercel e ao Supabase de produção. Decide suspender, reabrir e comunicar. |
| Conduz o registro | Gestor | Abre o registro do incidente, mantém a linha do tempo e redige as comunicações para o responsável aprovar. |
| Apoio técnico | DevOps, Back, Front | Diagnosticam e preparam comandos. Não executam nada em produção sem liberação escrita do responsável. |

Qualquer pessoa que perceber um problema avisa o responsável e o Gestor. O aviso não inclui conteúdo de relato, dado pessoal nem segredo, só o identificador (protocolo, id da empresa, nome da chave).

**Lacuna:** não há plantão nem contato fora do horário. Definir antes de 30/11 o canal (telefone ou grupo) e quem substitui o responsável na ausência dele.

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
- **Lacuna (Back):** não há como pausar o envio de novos relatos por quem já tem conta. Hoje, a única forma de impedir é tirar o site do ar, o que derruba também a leitura. O Back está cuidando do mecanismo de pausa.
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
| Chave secret / service_role do Supabase | Nenhum código do repositório a usa hoje: não há Edge Function nem backend próprio | Supabase > Settings > API Keys: revogar e gerar outra. Sem impacto no app, que não a usa. |
| Senha do banco (Postgres) | CLI (`db push`, `db dump`) na máquina do responsável | Supabase > Settings > Database > reset da senha. |
| SMTP do Auth (senha de app do Gmail do responsável, ADR-0009 e TASK-0023) | Supabase > Authentication > SMTP | Revogar a senha de app na conta Google, gerar outra e colar no painel do Supabase. Enquanto isso, os e-mails de confirmação param. |
| Token da Vercel e token do GitHub | Contas pessoais do responsável | Revogar no painel de cada serviço. |

Nunca colar um segredo em chat, task ou commit. No registro do incidente entra só o nome da chave e a hora da troca.

**Lacuna (antes do piloto):** o ADR-0009 aceita o Gmail do responsável no SMTP "só para a demonstração" e pede domínio próprio e provedor transacional antes do piloto. A proposta do ADR-0020 também usa Gmail. A decisão é do responsável.

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
