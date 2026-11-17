# TASK-0010 — Backup, restore e resposta a incidente

- Status: proposta
- ClickUp: [TASK-0010](https://app.clickup.com/t/86aktn72g)
- Área: DevOps/SRE/Segurança
- Prioridade: P1
- Estimativa: 3–5 dias
- Impacto: reduz perda de dados e tempo de recuperação

## Problema
Não há backup nem runbooks executáveis.
## Contexto
Dados sensíveis exigem recuperação e contenção comprováveis.
## Objetivo
Definir RPO/RTO, backup criptografado, restore testado e runbooks prioritários.
## Escopo
Backup DB/config relevante, exercício de restore e oito cenários do índice.
## Fora de escopo
DR multi-região antes de necessidade.
## Critérios de aceite
Restore em ambiente isolado cumpre RPO/RTO; responsáveis e contatos definidos; evidências registradas.
## Riscos
Backup ilegível, permissões excessivas e retenção conflitante.
## Dependências
Infra/provedor e TASK-0008/0009.
## Segurança
Criptografia, acesso restrito, rotação e exclusão coerente.
## Dados envolvidos
Banco e metadados operacionais.
## Observabilidade
Sucesso, idade e tamanho do backup; falha de restore drill.
## Rollback
Manter geração anterior até validar nova política.
## Testes necessários
Restore completo, corrupção simulada e tabletop de incidente.
## Definição de pronto
Restore comprovado e runbooks aprovados/testados.

## Levantamento para o piloto (2026-11-17)

Contexto: piloto fechado com relato real a partir de 30/11; go/no-go em 25/11. Fonte: documentação oficial do Supabase, lida em 2026-11-17. O que a documentação não diz está marcado "a confirmar".

### O que cada plano oferece

| Item | Free | Pro | Team | Fonte |
|---|---|---|---|---|
| Backup diário automático | Não incluído | 7 dias | 14 dias | [backups](https://supabase.com/docs/guides/platform/backups), [pricing](https://supabase.com/pricing) |
| PITR (add-on) | Não incluído | Opcional | Opcional | [backups](https://supabase.com/docs/guides/platform/backups) |
| Pausa por inatividade | Após 1 semana | Nunca | Nunca | [pricing](https://supabase.com/pricing) |

- Enterprise: até 30 dias de backup diário, pela página de backups. O pricing diz apenas "Custom".
- Free: a documentação recomenda exportar os dados regularmente com `supabase db dump`. Não diz se o Free baixa backup pelo painel ("a confirmar").
- PITR:
  - Preço: 7 dias custam cerca de US$ 100/mês, 14 dias US$ 200/mês e 28 dias US$ 400/mês. A cobrança é por hora e fica fora do Spend Cap.
  - Disponível em todos os tamanhos de compute.
  - RPO de 2 minutos no pior caso, porque o WAL é copiado a cada 2 minutos.
  - Com PITR ligado, o backup diário deixa de ser feito.
- O que o backup não cobre:
  - Arquivos do Storage: o backup só leva os metadados.
  - Senhas de roles customizadas.
  - A documentação de backups não diz se o schema `auth` entra no backup diário ("a confirmar"). O `db dump` padrão exclui `auth`, `storage` e os schemas de extensões.
- Restauração pelo painel:
  - Substitui o banco atual, e o projeto fica fora do ar durante o processo.
  - A documentação não informa a duração nem se a restauração pode ser desfeita ("a confirmar").
  - Para preservar o estado atual, a documentação recomenda restaurar primeiro num projeto novo.
- Excluir o projeto apaga também os backups, de forma irreversível.

### Leitura para o piloto

- **Se o projeto estiver no Free, não há backup automático nem PITR.** Para receber relato real seria a única camada de dados sem cópia, e a pausa após uma semana de inatividade também se aplica. Nesse caso recomendo **Pro antes de 30/11**, como condição de go. O custo exato do plano e do compute é "a confirmar" no painel.
- No Pro, o backup diário dá RPO de até 24 h e retenção de 7 dias. O PITR baixa o RPO para 2 minutos, mas custa cerca de US$ 100/mês a mais. Para um piloto fechado com poucas empresas, o diário mais um `db dump` cifrado antes de cada migration de risco parece proporcional. A decisão de custo é do responsável.
- O Storage não tem backup em nenhum plano. É preciso confirmar com o Back se o piloto guarda arquivo no Storage (anexo, áudio). Se guardar, isso é lacuna.

### Checklist para o responsável conferir no painel (sem copiar segredos)

1. Organization > Billing: nome do plano (Free, Pro ou Team), add-ons ativos (PITR, IPv4, compute) e Spend Cap ligado ou desligado.
2. Project ouvira-brasil > Database > Backups:
   - se aparece a lista de backups diários, e a data do mais recente;
   - se a aba PITR existe e está ativa.
3. Project > Settings > Infrastructure (ou General): versão do Postgres. Projetos a partir da 15.8.1.079 usam backup físico.
4. Project > Settings > Compute and Disk: tamanho do compute e uso do disco, para estimar o tempo de dump e de restore.
5. Storage: quantos buckets existem e se algum recebe arquivo de usuário.
6. Project > Settings > General: se aparece aviso de pausa por inatividade.

Basta anotar as respostas em texto. Nenhuma tela traz chave nem senha que precise ser copiada.
