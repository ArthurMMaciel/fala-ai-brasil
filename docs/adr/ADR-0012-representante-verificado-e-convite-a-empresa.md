# ADR-0012 — Representante verificado e convite seguro à empresa

- Estado: **Proposta**, aguardando aprovação do responsável. Nenhuma migration foi criada.
- Data: 2026-11-06
- Tarefas: [TASK-0011](../tasks/TASK-0011-verificacao-de-contatos-empresariais.md) · [TASK-0029](../tasks/TASK-0029-convite-seguro-a-empresa-apos-manifestacao.md) · TASK-0031
- Relacionadas: ADR-0009, ADR-0010, ADR-0011

## Contexto (estado atual do código)

- Qualquer pessoa que cadastra um CNPJ ainda não usado vira `owner` da empresa em `company_users`. Não há prova de que representa a empresa (`companies.cnpj` é único, sem verificação).
- `public.is_company_user(company_id)` só confere o vínculo em `company_users`. É ela que libera `list_company_complaints`, `get_company_complaint_timeline` e `respond_complaint`.
- Depois da ADR-0010, a equipe libera a versão compartilhável (`shared`). Nada impede que a conta que a recebe seja da pessoa envolvida no relato, se ela cadastrou o CNPJ primeiro.
- O trabalhador só pode manifestar contra empresa já cadastrada (`create_complaint` exige `company_id`). Os contatos empresariais indicados no assistente (nome, e-mail, telefone, cargo, aviso sobre sócio/proprietário) ficam só na sessão do navegador; não são gravados.
- Não há registro de risco por manifestação, nem convite, nem envio de e-mail pela aplicação.

## Problema

1. **Representante (TASK-0011):** a liberação da ADR-0010 entrega o texto a quem tiver o vínculo, sem verificação. É o risco aberto do piloto.
2. **Convite (TASK-0029):** não há forma segura de trazer a empresa para a plataforma depois da manifestação, sem revelar o caso a destinatário errado ou à pessoa envolvida.

## Decisões propostas

D1. **Verificação por vínculo, não por empresa.** Cada linha de `company_users` ganha estado de verificação. Só o vínculo `verified` acessa manifestações. Portal, diretório de parceiros e perfil continuam acessíveis ao vínculo não verificado, que vê o aviso "aguardando verificação" e nenhum número de manifestações.

D2. **Gate no banco.** É criada `public.is_verified_company_user(company_id)`, que passa a substituir `is_company_user` nas três funções de manifestação e em `company_ranking.is_mine`. As demais funções (parceiros, conteúdos, contato) continuam com `is_company_user`.

D3. **Verificação feita pela equipe (manual no piloto).** Métodos aceitos:
- `corporate_domain`: e-mail de login confirmado pelo Supabase num domínio já verificado para a empresa;
- `document_review`: documento de representação conferido fora da plataforma, sem guardar o arquivo; registra-se só o tipo e a referência;
- `callback`: ligação ao telefone público da empresa.
Domínios de e-mail gratuitos (gmail, hotmail etc.) nunca contam como `corporate_domain`.

D4. **Contato indicado pelo trabalhador é candidato, nunca destino verificado.** Os contatos são gravados por manifestação, ficam visíveis só para o próprio trabalhador e para a equipe, e a empresa nunca os vê. A equipe marca cada contato como `verified` ou `rejected`. Um contato que o trabalhador marcou como possivelmente envolvido não pode receber convite.

D5. **Convite manual assistido no piloto.** A equipe gera o convite na Operação. O banco guarda só o hash do token, que é de uso único e expira em 7 dias. A pessoa da equipe envia o e-mail por fora, com texto mínimo aprovado, e marca como enviado. O texto não cita manifestação, protocolo, tema nem trabalhador; diz apenas que a empresa tem um canal de escuta à disposição na plataforma. Envio automático por provedor fica para outra ADR, com o DevOps.

D6. **O aceite do convite não dá acesso a manifestações.** O aceite liga a conta à empresa com vínculo `pending`. O acesso só vem com a verificação da D3. O link não carrega nem permite descobrir o ID da manifestação ou da empresa.

D7. **Risco registrado na decisão da equipe.** `complaint_reviews` ganha `risk_level` (`low`, `medium`, `high`), obrigatório na decisão. Com risco `high`, não é possível criar convite para aquela empresa enquanto o caso estiver aberto, e a liberação exige uma segunda pessoa da equipe.

D8. **Opt-out.** Uma lista de e-mails que pediram para não receber convites, guardada só como hash do e-mail normalizado. Antes de gerar o convite, o hash é conferido nessa lista.

## Modelo (ERD)

```mermaid
erDiagram
  companies ||--o{ company_users : "vínculos"
  companies ||--o{ company_domains : "domínios verificados"
  company_users ||--o{ representative_verifications : "histórico"
  complaints ||--o{ complaint_contacts : "contatos indicados"
  complaints ||--o{ company_invitations : "convites"
  complaint_contacts ||--o{ company_invitations : "destino"
  companies ||--o{ company_invitations : "empresa"
  complaints ||--o{ complaint_reviews : "decisões (+risk_level)"

  company_users {
    uuid company_id PK
    uuid user_id PK
    member_role role
    text verification_status "NOVO: pending|verified|rejected|revoked"
    timestamptz verified_at "NOVO"
  }
  company_domains {
    uuid id PK
    uuid company_id FK
    text domain "único, minúsculo, sem domínio gratuito"
    uuid verified_by FK "equipe"
    timestamptz verified_at
  }
  representative_verifications {
    uuid id PK
    uuid company_id FK
    uuid user_id FK
    text decision "verified|rejected|revoked"
    text method "corporate_domain|document_review|callback"
    text evidence_ref "até 200 caracteres, sem documento"
    text reason
    uuid reviewer_id FK
    timestamptz created_at
  }
  complaint_contacts {
    uuid id PK
    uuid complaint_id FK
    text name
    text email
    text phone
    text role_title
    boolean possibly_involved "marcado pelo trabalhador"
    text status "candidate|verified|rejected"
    uuid reviewed_by FK
    timestamptz reviewed_at
  }
  company_invitations {
    uuid id PK
    uuid company_id FK
    uuid complaint_id FK
    uuid contact_id FK
    text token_hash "sha256, único"
    text status "created|sent|accepted|expired|revoked|bounced"
    uuid created_by FK
    timestamptz sent_at
    timestamptz expires_at
    uuid accepted_by FK
    timestamptz accepted_at
  }
  contact_opt_outs {
    text email_hash PK
    timestamptz created_at
  }
  complaint_reviews {
    text risk_level "NOVO: low|medium|high"
    uuid second_reviewer_id "NOVO: obrigatório em high"
  }
```

## Quem lê e quem escreve

| Tabela | Trabalhador | Empresa | Equipe (`platform_admins`) | Anônimo |
|---|---|---|---|---|
| `company_users.verification_status` | — | lê o próprio status via `current_profiles()` | altera via `ops_verify_representative` | — |
| `company_domains` | — | — | lê e escreve via `ops_*` | — |
| `representative_verifications` | — | — | lê e escreve via `ops_*` (só inserção) | — |
| `complaint_contacts` | escreve na criação e lê os próprios | **nunca** | lê e decide via `ops_*` | — |
| `company_invitations` | — | — | cria, marca enviado e revoga via `ops_*` | aceita só via `accept_company_invitation(token)` autenticado |
| `contact_opt_outs` | — | — | conferência interna | inserção via `opt_out_invitations(token)` |
| `complaint_reviews.risk_level` | — | — | grava em `ops_decide_complaint` | — |

RLS ligada em todas as tabelas novas. Nenhum `grant` direto a `anon` ou `authenticated`: o acesso é só por funções `security definer` com `search_path = ''`, no padrão das ADR-0010 e ADR-0011.

## Funções novas ou alteradas (assinaturas previstas)

- `is_verified_company_user(uuid) → boolean` (nova). Passa a ser usada em `list_company_complaints`, `get_company_complaint_timeline`, `respond_complaint` e `company_ranking`.
- `create_complaint(p jsonb, p_share boolean)`: aceita `p.contacts[]`, com até 3 contatos, e valida e-mail e telefone.
- `ops_decide_complaint(p_id, p_decision, p_reason, p_risk_level)` (nova versão): exige `p_risk_level`. Com risco `high`, a liberação exige uma segunda pessoa da equipe, diferente da primeira.
- `ops_list_representatives(p_status)`, `ops_verify_representative(p_company, p_user, p_decision, p_method, p_evidence_ref, p_reason)`, `ops_add_company_domain(p_company, p_domain)`.
- `ops_review_contact(p_contact, p_decision)`, `ops_create_invitation(p_contact) → text`. O token é devolvido uma única vez à equipe e só o hash fica no banco. Mais `ops_mark_invitation_sent(p_id)` e `ops_revoke_invitation(p_id)`.
- `accept_company_invitation(p_token text) → uuid` (autenticada): cria o vínculo `pending`. Qualquer token inválido, expirado ou revogado devolve a mesma mensagem de erro, para não permitir enumeração.
- `opt_out_invitations(p_token text)` (anônima): registra o hash do e-mail do destino.

## Migração de dados

- Vínculos existentes em `company_users` passam a `pending`. As contas de demonstração (seed `@example.com`) recebem `verified` com método `document_review` e referência `seed-demo`, por script separado, nunca automático em produção.
- Valores novos de enum ou check ficam em migration separada, conforme o padrão do projeto.
- Ordem: (1) colunas e tabelas sem mudar acesso; (2) funções novas; (3) troca do gate (D2) por último, com teste de fumaça antes e depois.

## Riscos

- **Operação:** a verificação manual cria fila e atraso. A empresa liberada sem representante verificado fica com o caso pendente até a verificação.
- **Tenancy:** a troca do gate (D2) afeta todas as contas de empresa. Um erro pode esconder casos de quem tinha acesso ou mostrar a quem não tinha. Mitigação: teste de fumaça com dois tenants, vínculo `pending`, `revoked` e conta fora da empresa.
- **Dados pessoais novos:** `complaint_contacts` grava nome, e-mail, telefone e cargo de terceiros, indicados pelo trabalhador. Exige base legal e prazo de retenção (TASK-0007); proposta inicial: apagar os contatos 90 dias após o encerramento.
- **Convite:** mesmo sem detalhes, um convite logo após um conflito pode sugerir à pessoa envolvida que houve manifestação. Mitigações: D4, D7, intervalo mínimo e texto genérico. O risco residual exige decisão humana.
- **Token:** o link pode ser encaminhado. Como o aceite só cria vínculo `pending` (D6), encaminhar não dá acesso a manifestações.

## Decisões que dependem do responsável

1. Aprovar D1–D8, especialmente: vínculo não verificado sem acesso a manifestações (D1), segunda pessoa da equipe para risco alto (D7) e convite manual no piloto (D5).
2. Métodos de verificação aceitos (D3) e quem na equipe pode verificar.
3. Texto do convite e da página de destino. Não deve conter promessa de anonimato.
4. Base legal e retenção de `complaint_contacts` e `contact_opt_outs` (TASK-0007).
5. Se manifestação contra empresa **não cadastrada** entra no piloto. Esta proposta não cobre esse caso: hoje é preciso que a empresa já exista. Incluí-lo exigiria um cadastro de empresa feito pela equipe, numa decisão à parte.

## Testes de fumaça previstos

Dois tenants; vínculo `pending` não vê caso liberado; `verified` vê; `revoked` deixa de ver; contato de outra manifestação não é visível; convite com token reutilizado, expirado ou revogado é recusado com a mesma mensagem; aceite cria só vínculo `pending`; risco alto bloqueia convite e exige segunda pessoa da equipe; opt-out bloqueia novo convite; empresa nunca lê `complaint_contacts`.

## Rollback

- Antes da troca do gate: remover as tabelas e colunas novas; não há dado dependente.
- Depois da troca: reaplicar `is_company_user` nas funções de manifestação apenas se a verificação travar a operação, e com decisão registrada, porque isso reabre o risco do representante não verificado. Convites pendentes são revogados (`revoked`); nada é apagado da trilha.
