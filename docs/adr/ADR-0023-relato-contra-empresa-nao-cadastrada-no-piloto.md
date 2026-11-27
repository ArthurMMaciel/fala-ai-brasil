# ADR-0023 — Relato contra empresa não cadastrada no piloto, com aviso à empresa sem conteúdo

- Estado: **Aceita**, pelo responsável em 2026-11-17 (repassado pelo Gestor): "Aprovo a ADR-0023 com as recomendações, menos com a parte da busca de CNPJ, basta aceitarmos somente CNPJs nesse primeiro momento e bater numa API que busca as empresas pelo CNPJ (caso esse CNPJ não seja encontrado no nosso banco), ai trazemos os dados pra dentro de casa...Se virar manifestação é show porque a empresa recebe o email que existe uma manifestação, ve mais e vira cliente, aí quando buscar o CNPJ novamente ele já existe no nosso banco." Decisões: ver "Decisões do responsável (2026-11-17)". Implementação: `20261118120000`, `20261118130000`, `20261118140000` e `20261118150000`, aplicadas em produção em 2026-11-19 (lote 2 do SQL Editor; conferidas pelo responsável e, em leitura, pelo Back: versões, hash das instruções e objetos). Edge Function `cnpj-lookup` escrita e testada com fixtures, ainda não publicada (DevOps).
- Data: 2026-11-17
- Origem: decisão do responsável, repassada pelo Gestor em 2026-11-17: o trabalhador encontra qualquer empresa e relata contra ela; se a empresa não estiver cadastrada, ela recebe um aviso, sem conteúdo, de que existe um relato, no e-mail que o trabalhador informou. Vale para o piloto, não para depois.
- Relacionadas: ADR-0012 (D4, D5, D7, D9 a D11, C1 a C3), ADR-0017 (busca de CNPJ), ADR-0020 (e-mail pelo Gmail), ADR-0010 (revisão humana), TASK-0007 (base legal e retenção)

## O que muda em relação às decisões anteriores

1. **A ADR-0012 D5 proíbe que o texto do convite cite a manifestação.** O pedido do responsável ("informar a empresa que existe um relato") muda essa regra. A mudança precisa ser registrada como decisão dele, porque é o ponto de maior risco deste plano (ver Riscos).
2. **A ADR-0012 tirou D4 e D9 a D11 do recorte do piloto** (revisão de 2026-11-17). Este plano traz de volta uma parte mínima deles.
3. **A troca do gate (20261117130000) passa a ser pré-requisito.** A empresa avisada vai se cadastrar. Sem o gate, a primeira conta que cadastrar aquele CNPJ vê os casos liberados, sem verificação. Esse é exatamente o risco que a ADR-0012 fecha.

## 1. Recorte mínimo

O fluxo do trabalhador:
1. Digita o CNPJ. Se a empresa existe, o fluxo é o de hoje.
2. Se não existe, cria a empresa pré-cadastrada (ADR-0012 D9, D10).
3. Informa, se quiser, **um** e-mail da empresa para o aviso e responde se essa pessoa pode estar envolvida (D4).
4. Concorda explicitamente com o texto: "A empresa receberá um aviso de que existe um relato na plataforma, sem o conteúdo, sem o seu nome e sem a data."

Na Operação, a equipe:
1. revisa a manifestação, como hoje (ADR-0010);
2. confere a empresa (`pending_check`) e o contato;
3. aprova ou recusa o aviso;
4. envia o aviso.

Quando a empresa se cadastra com aquele CNPJ, a conta é ligada à empresa existente com vínculo `pending` (D11). O acesso aos casos depende da verificação (V1, já aprovada).

**Busca de CNPJ (decisão do responsável, que substitui a recomendação de pré-cadastro só manual):**
1. A busca é só por CNPJ, primeiro em `companies` e no cache próprio.
2. Se o CNPJ não estiver lá, a Edge Function `cnpj-lookup` da ADR-0017 consulta o provedor.
3. Os dados da lista branca ficam guardados (ADR-0017, "Aceitação de 2026-11-17").
4. O pré-cadastro manual (`pending_check`) é o plano B, para API fora do ar, CNPJ não encontrado ou CNPJ de pessoa física.

### O que fica de fora do recorte

- token de convite (D5, D6);
- nome, telefone e cargo do contato (só e-mail);
- lembretes de 7 e 15 dias (D12);
- `risk_level` (fica R3: risco alto vira `held` e não gera aviso);
- opt-out por link (no piloto, o pedido de não receber é atendido pela equipe e entra na lista);
- botão de envio (ver variante a2).

## 2. Variantes de envio

### (a) A equipe aprova na Operação e envia — recomendada

- **(a1) Manual:** a equipe copia o texto fixo, envia pela conta da plataforma e marca como enviado (quem e quando). Não precisa de infraestrutura nova. Funciona no primeiro dia.
- **(a2) Botão:** a aprovação grava o aviso numa fila, e uma Edge Function envia pelo SMTP do Gmail. Depende da ADR-0020: o teste da porta 465 ainda não foi feito, a conta dedicada não existe e a ADR é só proposta. Fica para depois do piloto, salvo se o DevOps fechar a ADR-0020 a tempo.

Travas no banco, nas duas formas:
- Não há aviso enquanto a manifestação não tiver passado pela revisão da equipe.
- Não há aviso se o contato foi marcado como possivelmente envolvido.
- Não há aviso se o e-mail estiver na lista de opt-out.
- Não há aviso se a manifestação estiver `held`, o que inclui o risco alto pela R3.
- Não há aviso se a empresa ainda estiver `pending_check`.
- No máximo um aviso por empresa num intervalo (proposta: 30 dias), mesmo com várias manifestações.

### (b) Envio automático ao e-mail indicado pelo trabalhador — não recomendada

O que fere:
- **ADR-0012 D4:** o contato indicado é candidato, nunca destino verificado. O envio automático usa como destino um e-mail que ninguém conferiu.
- **ADR-0012 D4 (segunda regra):** o contato possivelmente envolvido não pode receber. O trabalhador pode não saber quem está envolvido, e só a equipe consegue conferir que o e-mail é de um canal institucional e não de uma pessoa.
- **ADR-0012 D7:** caso de risco alto não gera contato automático. No envio automático, o aviso sai antes de qualquer pessoa avaliar o risco.
- **ADR-0012 C3:** o convite automático foi excluído do piloto expressamente, por contrariar a regra de não haver contato externo sem revisão, e porque depende da ADR-0020, que não está pronta.
- **ADR-0012 D5:** o texto não pode citar a manifestação. Isso vale também para a variante (a) e precisa da decisão do item 1 de "O que muda".
- **AGENTS.md:**
  - "Casos de alto risco não geram contato externo automático": no momento do envio automático, o risco é desconhecido.
  - "Não introduzir serviços externos... sem tarefa e decisão registradas": o envio pela aplicação é serviço novo (ADR-0020, só proposta).
  - "Nunca enviar... dados psicossociais a terceiros sem avaliação de privacidade, base legal e controles documentados": "existe um relato contra você" é informação sobre o caso, enviada a um endereço que ninguém conferiu.
- **Abuso:** qualquer conta autenticada faria a plataforma mandar e-mail para qualquer endereço. Serviria para assédio, para spam e para derrubar a conta do Gmail, que é a mesma do Auth: a confirmação de cadastro pararia.

### Remetente no piloto (responsável, 2026-11-17)

"Por hora vai ser da minha conta, mas vamos abrir uma para a empresa": no piloto, o aviso sai da conta pessoal de e-mail do responsável. Ainda falta ele escolher entre envio manual (a1) e automático (a2 ou b). Efeito em cada variante:

- **(a1) manual:** funciona sem mudança. Ele envia da própria caixa, com o texto fixo, e marca como enviado na Operação. Nenhuma credencial vai para a plataforma.
- **(a2) e (b), automáticas:** a Edge Function precisaria da senha de app SMTP da conta pessoal nos Secrets. A ADR-0020 D1 desaconselha isso: a senha de app dá acesso SMTP à caixa inteira, e um vazamento da função expõe o e-mail pessoal do responsável. Se a escolha for automática, o caminho é abrir antes a conta da empresa e só então ligar o envio.
- **Em qualquer variante:**
  - O destinatário vê o nome e o e-mail pessoal do responsável, e as respostas da empresa caem na caixa pessoal dele, possivelmente com dado do caso ou de terceiros. Essas mensagens precisam de tratamento e retenção definidos (TASK-0007).
  - **Decisão do responsável (2026-11-18): "mesma caixa, mesma conta".** O aviso manual sai da mesma conta Gmail do SMTP do Auth. **Risco aceito:**
    - o limite de 500 envios por dia é compartilhado;
    - se denúncias de spam ou o bloqueio por excesso derrubarem a conta, a confirmação de cadastro e a recuperação de senha param junto com os avisos;
    - as respostas das empresas e as mensagens do Auth ficam na mesma caixa.

    Mitigações:
    - volume baixo e manual;
    - no máximo 1 aviso por empresa a cada 30 dias;
    - texto sem link clicável.

    O DevOps registra a decisão também na ADR-0009.
  - Quando a conta da empresa existir, os avisos passam a sair dela. O texto não muda.

## 3. Modelo (aprovado em 2026-11-17)

```mermaid
erDiagram
  companies ||--o{ complaints : "manifestações"
  complaints ||--o| complaint_contacts : "e-mail indicado (0 ou 1)"
  complaint_contacts ||--o{ company_notices : "destino"
  companies ||--o{ company_notices : "empresa"

  companies {
    text registration_status "NOVO: registered|pre_registered|pending_check; existentes = registered"
    text data_source "NOVO: signup|manual (cnpj_api se a ADR-0017 entrar)"
    uuid address_id "passa a aceitar nulo fora de registered (check)"
    uuid created_by "já aceita nulo"
  }
  complaint_contacts {
    uuid id PK
    uuid complaint_id FK "único"
    text email "normalizado, minúsculo"
    boolean possibly_involved "marcado pelo trabalhador"
    boolean worker_consented "concordou com o texto do aviso"
    text status "candidate|verified|rejected"
    uuid reviewed_by
    timestamptz reviewed_at
    timestamptz created_at
  }
  company_notices {
    uuid id PK
    uuid company_id FK
    uuid complaint_id FK
    uuid contact_id FK
    text status "approved|sent|rejected|bounced"
    text reason "na recusa, 10 a 300, sem conteúdo do relato"
    uuid decided_by
    timestamptz decided_at
    uuid sent_by
    timestamptz sent_at
  }
  notice_opt_outs {
    text email_hash PK "sha256 do e-mail normalizado"
    uuid added_by
    timestamptz created_at
  }
```

- **Quem lê:** a empresa nunca lê `complaint_contacts`, `company_notices` nem `notice_opt_outs`. O trabalhador lê só o próprio contato e o estado do aviso (enviado ou não, sem data exata). A equipe lê pelas funções `ops_*`. Tudo fica com RLS ligada, `revoke all` e acesso só por função.
- **Implementação (2026-11-18), diferenças em relação ao ERD acima:**
  - Os dados de origem da pré-cadastrada (município, UF, situação, CNAE, natureza, provedor, conferência da equipe) ficam em `private.company_preregistrations`, e não em `companies`.
  - `companies.created_by` fica nulo, porque gravar o trabalhador ligaria a conta ao empregador.
  - O diretório, o ranking, a responsividade, a lista dos parceiros e `ops_list_companies` já excluem a pré-cadastrada pelo join interno com `addresses`, então não são redefinidos. O teste tx confere.
  - Migrations em `supabase/pending/20261118120000_*` e `20261118130000_*`; teste em `supabase/tests/tx/empresa_checks.sql`.
- **Trilha:** `company_notices` é só inserção, com mudança de estado registrada. `private.block_trail_change` vale para linhas `sent` e `rejected`.

### Migrations previstas (nenhuma escrita)

| Ordem | Migration | Conteúdo | Muda acesso? |
|---|---|---|---|
| 0 | `20261117130000` (já pronta) | troca do gate | sim (já aprovada; pré-requisito) |
| 1 | `..._empresa_pre_cadastrada_estrutura` | colunas de `companies` + checks; `private.cnpj_cache` e `private.cnpj_lookup_quota` (ADR-0017); `complaint_contacts`; `company_notices`; `notice_opt_outs` | não |
| 2 | `..._empresa_pre_cadastrada_funcoes` | funções abaixo; filtros de listagem | sim (listagens e criação de empresa) |
| 3 | `..._reivindicacao_cnpj` | `private.create_profile` com a D11 | sim (cadastro: autenticação) |

A 3 fica separada porque mexe no cadastro de todas as contas de empresa e tem rollback próprio.

### Funções

- `find_company_by_cnpj(p_cnpj) → (id, name, city, state)`: devolve a empresa existente sem dizer se ela é pré-cadastrada nem se tem manifestação.
- `preregister_company(p_cnpj) → uuid` (ADR-0017 D8): cria `pre_registered` a partir do cache, nunca de dados do cliente.
- `preregister_company_manual(p_cnpj, p_name, p_city, p_state) → uuid` (plano B): valida os dígitos (`private.valid_cnpj`), cria `pending_check` e devolve a existente se o CNPJ já estiver na base. Limite proposto: 3 por conta por dia.
- `create_complaint(p, p_share)`: aceita `p.notice_contact {email, possibly_involved, consent}`. Recusa e-mail inválido e contato sem consentimento.
- `ops_list_pending_companies()` e `ops_review_company(p_company, p_decision, p_reason)`: `pending_check` → `pre_registered` ou recusa.
- `ops_list_notices(p_status)`, `ops_decide_notice(p_complaint, p_decision, p_reason)` (com as travas da variante a), `ops_mark_notice_sent(p_notice)` e `ops_add_opt_out(p_email)`.
- `my_notice_status(p_complaint)`: para o trabalhador.
- Filtro `registration_status = 'registered'` em `list_company_directory`, `company_responsiveness`, `company_ranking` e `list_partner_companies`. Conferir, na implementação, toda função que lê `companies`.
- `private.create_profile`: CNPJ pré-cadastrado no cadastro de empresa liga a conta como membro `pending` e passa a empresa a `registered`. Uma segunda conta entra como membro `pending`, nunca como dono.

### Testes

- Smoke próprio de cada migration.
- `isolation_smoke.sql` com empresa pré-cadastrada (as tabelas novas entram sozinhas pelo catálogo).
- Teste tx em produção, rodada por rodada, com liberação escrita.

## 4. Estimativa (refeita em 2026-11-17, com a Edge Function)

Escrita no fim de 17/11. A meta é tudo aplicado até 24/11; o go/no-go é em 25/11.

O trabalho do Back, com a função:

| Dia | Back | Responsável / DevOps / Front |
|---|---|---|
| 18/11 | migration 1 (estrutura) e 2 (funções), smokes | o responsável roda o lote atual (00 a 04) e verifica as 3 empresas reais na fila |
| 19/11 | Edge Function `cnpj-lookup` com testes de provedor simulado (fixture); migration 3 (D11) | DevOps prepara o deploy da função |
| 20/11 | testes tx (130000, 1, 2, 3) e scripts do SQL Editor | o responsável libera as rodadas tx e aplica a 130000, depois a 1, a 2 e a 3; o DevOps publica a função |
| 21 a 23/11 | correções do ensaio | o Front integra a busca, o contato e o consentimento, a fila de avisos e a conferência de empresa; ensaio ponta a ponta |
| 24/11 | folga | termos versão 1 (ADR-0022) |

**Avaliação honesta:** cabe sem folga real. Basta um dia perdido (uma rodada tx que falha, a liberação de um passo que demora ou o teste da função em produção que revela formato diferente do provedor) para passar de 24/11.

O que torna isso seguro é que o **plano B já está aprovado**: o pré-cadastro manual não depende da função. Por isso, o go/no-go não precisa esperar a função.

**O que sai, nesta ordem, se atrasar (sem perder o go/no-go). Revisto em 2026-11-18 pelo Gestor: a reivindicação (D11) não pode ser cortada, porque a empresa avisada precisa conseguir se cadastrar:**

1. **(a2) botão de envio:** já está fora; o envio é manual.
2. **Provedor reserva (BrasilAPI):** fica só a Minha Receita e, se falhar, o manual.
3. **Situação do aviso para o trabalhador (`my_notice_status`):** já ficou fora da migration 2.
4. **A própria Edge Function:** o piloto abre com o plano B (pré-cadastro manual com conferência da equipe na Receita), e a função entra depois, sem migration nova.

**Não sai:** a migration 3 (reivindicação no cadastro, `20261118140000`).

**Nada sai das travas do aviso (variante a)** nem da troca do gate (130000).

## Revisão do DevOps (2026-11-18) e contrato para o Front

Correções feitas antes de qualquer aplicação, seguindo "grava quando relatar" e "aviso sem revelar":

1. **`find_company_by_cnpj` devolve só empresa `registered`**, a mesma do diretório. A pré-cadastrada só existe porque alguém relatou. Se a busca a devolvesse, quem trabalha na empresa descobriria que há relato, o que numa empresa pequena aponta o trabalhador. Para quem busca, "nunca relatada" e "já relatada" dão a mesma resposta (nenhuma linha), e o front segue pela Edge Function.
2. **A empresa nasce dentro de `create_complaint`**, na mesma transação do relato; as RPCs `preregister_company*` não existem para clientes.
   - Validações, cota (3 relatos por CNPJ por dia por conta) e exigência de dados manuais (sempre que o cache não tem a empresa) não dependem de a empresa existir.
   - Se o CNPJ já existe como pré-cadastrado, o relato entra nela e o contato é aceito. Isso resolve o "segundo trabalhador" apontado pelo Front.
   - Empresa `registered`, por id ou por CNPJ: o relato é aceito, e o contato é validado igual e descartado em silêncio.
3. **`service_role` sem acesso a nenhuma tabela nova** (`revoke all`): a chave da Edge Function não lê os e-mails indicados nem os avisos; só executa as três RPCs do cache e da cota.

Pontos não bloqueantes:
- **`closed_at` em relato cancelado:** é gravado. `close_complaint` (20261106130100) grava `closed_at = now()` no mesmo update que muda o estado para `closed` ou `canceled`. A retenção de 90 dias vale para os dois.
- **Cota contada duas vezes:** resolvido; a busca no banco não tem cota.
- **"Aviso exige a 130000":** já está em `ops_decide_notice`, que recusa aprovar se a troca do gate não estiver aplicada. Não depende da migration 3.

Padrões passados pelo Gestor ao Front:
- "Não sei" na pergunta de envolvimento vira `possibly_involved = true`.
- A retenção (`ops_purge_expired_contacts`) roda por botão na Operação.

### Contrato para o Front

| Chamada | Quem | Uso |
|---|---|---|
| `find_company_by_cnpj(p_cnpj) → (id, name, city, state)` | authenticated | Só cadastradas. Nenhuma linha: chamar a Edge Function. `CNPJ inválido.` para dígito errado |
| `POST /functions/v1/cnpj-lookup {"cnpj"}` | conta logada | `found` com `company {legal_name, trade_name, cadastral_situation, city, state}`, ou `manual` com `reason` (`natural_person`, `unavailable`, `not_found`, `rate_limited`), ou 400 `invalid` |
| `create_complaint(p, p_share)` | trabalhador | Empresa: `p.company_id` (cadastrada) **ou** `p.company_cnpj`. Com `company_cnpj`, mandar `p.company_manual {name, city, state}` sempre que a Edge Function não respondeu `found`. Contato opcional: `p.notice_contact {email, possibly_involved: bool, consent: true}`, só com `p_share = true`; pode ser oferecido para qualquer empresa achada pelo CNPJ, porque na cadastrada é descartado em silêncio |
| `ops_list_pending_companies()`, `ops_review_company(p_company, 'confirmed' or 'blocked', p_reason, p_natural_person)` | equipe | Conferência das pré-cadastradas |
| `ops_list_notice_candidates()`, `ops_decide_notice(p_complaint, 'approved' or 'rejected', p_reason)`, `ops_mark_notice_sent(p_notice, 'sent' or 'bounced')`, `ops_add_opt_out(p_email)`, `ops_purge_expired_contacts()` | equipe | Fila e envio manual do aviso, opt-out e retenção |

Texto do consentimento, válido para os dois casos: "Se a empresa ainda não estiver na plataforma, ela receberá um aviso de que existe um relato, sem o conteúdo, sem o seu nome e sem a data." Assim, o trabalhador não é enganado quando a empresa já é cadastrada. A versão final passa pelo advogado.

## Revisão de 2026-11-19: contato da manifestação para qualquer empresa e e-mail da Receita

Decisão do responsável: "Esses contatos são apenas para ter um segundo meio de comunicação além do email e numero da empresa, as vezes o manifestante deseja fazer para o rh diretamente e tem o email [...] Ai salva na manifestação, não precisa salvar como responsável ou algo do tipo. Cada manifestação deve ter o seu, ai caso o manifestante não coloque nenhum, mandamos para o email que pegamos no get de CNPJ." Confirmado com "Isso, confirmo" (repassado pelo Gestor).

Ela substitui, nas migrations 20261118120000 e 20261118130000, ainda não aplicadas, o que diverge abaixo; o restante desta ADR continua valendo.

1. **Contato da manifestação** (`complaint_contacts`):
   - **Escopo:** vale para qualquer empresa, cadastrada ou não. Um por manifestação, com e-mail e/ou telefone (10 ou 11 dígitos).
   - **Campos obrigatórios:** `possibly_involved` e o consentimento, sempre que houver contato.
   - **Natureza:** não é representante nem vínculo. É dado da manifestação.
   - **Quem lê:** a empresa nunca lê. Leem o trabalhador dono (`my_complaint_contact`) e a equipe (`ops_complaint_contact`).
   - **Retenção:** 90 dias, como antes.
2. **Aviso para empresa não cadastrada:**
   - O destino é o e-mail do contato do trabalhador. Sem ele, a fila mostra o e-mail da Receita (do cache), marcado com `destination_source = 'receita'`.
   - A equipe aprova ou recusa manualmente; nada é automático.
   - Continuam todas as travas: liberada (`shared`), troca do gate, `possibly_involved`, opt-out, `pending_check`, bloqueada, pessoa física e 30 dias por empresa.
   - O contato marcado como possivelmente envolvido não recebe. A equipe pode escolher a Receita como destino (`p_destination = 'receita'`).
3. **Empresa cadastrada:** o contato aparece para a equipe no detalhe da manifestação, como segundo canal. Não gera aviso, e `ops_decide_notice` recusa.
4. **Descarte em silêncio:** o descarte na cadastrada (revisão do DevOps) deixa de existir: o contato agora é gravado em qualquer caso. A resposta de `create_complaint` continua igual para cadastrada e não cadastrada, então o estado da empresa segue sem ser revelado.
5. **Contrato novo:**
   - `p.notice_contact = {email?, phone?, possibly_involved: bool, consent: true}`, só com `p_share`.
   - `ops_list_notice_candidates()` devolve `contact_email`, `contact_phone`, `receita_email`, `destination_email` e `destination_source`.
   - `ops_decide_notice(p_complaint, p_decision, p_reason, p_destination)`.
   - `ops_complaint_contact(p_complaint)` e `my_complaint_contact(p_complaint)`.
6. **Risco novo:** o e-mail da Receita pode ser de contador ou de escritório, e não da empresa, ou estar desatualizado. A equipe confere antes de aprovar. O texto do aviso, que não traz conteúdo, continua passando pelo advogado.

### Revisão do DevOps sobre o e0f43bd (2026-11-19): consentimento ao aviso é do relato

Problema bloqueante corrigido antes da aplicação: o consentimento só era exigido quando havia contato, e, sem contato, o aviso podia sair pela Receita sem o trabalhador ter concordado.

- **Consentimento do relato:** `create_complaint` aceita `p.notice_consent` (boolean), com ou sem contato, e o grava em `private.complaint_notice_consents`, uma linha por relato.
  - É aceito e guardado para qualquer empresa, para não revelar se ela é cadastrada. Só é usado na não cadastrada.
  - `true` só com `p_share`.
- **Aprovação do aviso:** `ops_decide_notice` só aprova, por qualquer destino, com o consentimento `true`. Sem ele, só recusa.
  - A fila (`ops_list_notice_candidates`) mostra `notice_consented`.
- **Receita igual ao contato envolvido:** com destino Receita, o aviso é recusado se o e-mail da Receita for o do contato marcado como possivelmente envolvido.
- **Ordem das travas:** a dos 30 dias por empresa passou para o fim, depois da escolha do destino.
- **O que não muda:** o `consent` do contato continua significando o uso do contato pela equipe, como segundo canal.

## Revisão de 2026-11-26: até 3 contatos por manifestação

**Decisão do responsável**, repassada pelo Gestor: o trabalhador pode indicar **até 3** contatos da empresa por manifestação; antes era 1. Ele pediu "inúmeros"; o Gestor recomendou e ele escolheu "Até 3", como a D4 original da ADR-0012.

**Implementação**, em `20261126120000`, ainda não aplicada (lote 5 do SQL Editor):
- **Os contatos:**
  - `complaint_contacts` perde o unique por manifestação, e um gatilho recusa o 4º contato;
  - cada contato tem e-mail e/ou telefone, `possibly_involved` e `status` próprios e o mesmo consentimento de uso;
  - a retenção de 90 dias e `ops_purge_expired_contacts` valem para cada contato.
- **`create_complaint`** aceita `p.notice_contacts` (lista de 1 a 3, sem e-mail repetido) e continua aceitando `p.notice_contact` (um objeto), para o front em produção não quebrar.
- **Aviso:** continua 1 por manifestação e 1 por empresa a cada 30 dias.
  - `ops_decide_notice` ganha `p_contact_id`: a equipe escolhe um contato com e-mail e não envolvido, ou a Receita.
  - Sem escolha, vale o primeiro contato elegível e, sem nenhum, a Receita.
  - A Receita é recusada se o e-mail dela for o de **qualquer** contato envolvido.
  - Na recusa, todos os contatos ainda candidatos viram `rejected`.
  - As demais travas (consentimento do relato, opt-out, `pending_check`, bloqueada, pessoa física, troca do gate) não mudam.
- **Leitura:**
  - funções novas `ops_complaint_contacts_list(p_complaint)` (equipe, com `eligible_for_notice` e `opted_out`) e `my_complaint_contacts_list(p_complaint)` (trabalhador);
  - `ops_list_notice_candidates`, `ops_complaint_contact` e `my_complaint_contact` mantêm a assinatura e devolvem uma linha, com o **contato padrão**: o primeiro com e-mail e não envolvido, ou, sem ele, o primeiro indicado;
  - a empresa continua sem ler contato algum.
- **Teste:** `supabase/tests/tx/contatos3_checks.sql`, que passou no banco local em transação desfeita. O rollback também foi testado no local.

## Revisão de 2026-11-26: envio automático do aviso depois da aprovação (proposta, aguarda o responsável)

**Pedido do Gestor** em 2026-11-26: o aviso à empresa não cadastrada sai sozinho depois que a equipe aprova. Hoje a equipe aprova e envia à mão.

**O que muda:** só o envio. A variante (a) da seção 2 passa a ter o envio pela fila da ADR-0020, e a variante (b) continua descartada.
- **A decisão continua humana**, em `ops_decide_notice`, que não muda e mantém todas as travas:
  - a manifestação precisa ter sido liberada, com consentimento do relato e troca do gate;
  - a empresa não pode estar em `pending_check`, bloqueada ou ser pessoa física;
  - o destino precisa ser contato com e-mail e não envolvido, ou a Receita diferente de contato envolvido;
  - o e-mail não pode ter opt-out;
  - vale 1 aviso por manifestação e 1 por empresa a cada 30 dias.
- Antes de aprovar, a equipe avalia a manifestação. O caso de risco alto fica sem aprovação, e nada sai.
- **A recusa** não gera envio.

**Implementação**, em `20261126130000`, não aplicada (lote 5, passo 02):
- **Fila:**
  - um gatilho em `company_notices` põe a aprovação na fila da ADR-0020, como `kind = 'company_notice'`, com `notice_id`;
  - a fila não guarda o e-mail.
- **Envio:**
  - o banco resolve o destino na hora do envio (`private.company_notice_destination`) e confere de novo: aviso ainda `approved`, empresa ainda não cadastrada nem bloqueada, manifestação existente, opt-out, e Receita diferente de contato envolvido;
  - se a conferência falhar, a linha vira `suppressed` e o aviso fica `approved`, para a equipe decidir.
- **Resultado:**
  - enviado, o aviso vira `sent` automaticamente (`sent_by` nulo);
  - na 6ª falha, vira `bounced`;
  - `ops_mark_notice_sent` (manual) tira da fila o envio ainda pendente e recusa enquanto ele estiver em curso.
- **Teto:** conta nos 300 e-mails por dia da ADR-0020.
- **Texto:** fixo, enviado pela send-notifications.
  - Assunto: "Existe uma manifestação sobre a sua empresa na Escuta Aí Brasil".
  - Corpo: o que é a plataforma, que existe uma manifestação, o link https://fala-ai-brasil.vercel.app/empresa, "Por segurança, este e-mail não traz detalhes." e o pedido de exclusão por resposta ao e-mail.
  - Nada de protocolo, categoria, conteúdo ou nome do trabalhador.
- **Teste:** `supabase/tests/tx/avisos2_checks.sql`, que passou no banco local, assim como o rollback e a regressão de `contatos3` e `avisos`.

**Pendências antes de aplicar:**
1. **Aprovação do responsável.** A mudança contraria a revisão de 2026-11-23 da ADR-0020 ("o contato e a Receita não recebem nada automático"), que ele aprovou.
2. **Caixa de respostas:** alguém da equipe precisa ler as respostas na conta do remetente e registrar a exclusão com `ops_add_opt_out`. Sem isso, o pedido de exclusão escrito no e-mail não é atendido.
3. **Base legal e texto:** o e-mail a terceiro (contato indicado ou e-mail da Receita) continua na pendência jurídica da TASK-0007. O texto passa pelo jurídico.

## Ordem de aplicação

Formato igual ao do lote atual: scripts `aplicar` e `conferir` para o SQL Editor, rollback por passo e teste tx antes de cada um, com liberação escrita.

1. **Lote atual** (já na main): passo 00 (equipe) e passos 01 a 04 (180000, 120000, 140000, 150000).
2. **O responsável verifica os representantes** das 3 empresas reais na fila da Operação.
3. **20261117130000**, troca do gate: sai de `supabase/pending` para `supabase/migrations`, com o script do SQL Editor gerado pelo mesmo `build.mjs`. Pré-requisito do aviso: sem ela, a empresa avisada que se cadastrar vê os casos.
4. **Migration 1, estrutura** (só aditiva):
   - `companies.registration_status`, `data_source` e `address_id` nulo fora de `registered`;
   - `private.cnpj_cache` e `private.cnpj_lookup_quota`;
   - `complaint_contacts`, `company_notices` e `notice_opt_outs`.
5. **Edge Function `cnpj-lookup`**: publicada pelo DevOps depois da migration 1, porque grava no cache. Pode ser publicada antes do Front, porque ninguém a chama até lá.
6. **Migration 2, funções:**
   - `find_company_by_cnpj`, `preregister_company`, `preregister_company_manual`;
   - `create_complaint` com o contato;
   - `ops_*` de empresa e de aviso;
   - filtros de diretório, ranking e responsividade.
7. **Migration 3, cadastro com a D11** (`private.create_profile`), separada, com rollback próprio. Sai se o prazo apertar (item 4 acima).
8. **Front** (a busca, o contato, o consentimento e a fila da Operação) depois da 2 e da função.

## 5. Riscos

- **E-mail errado ou da pessoa envolvida.**
  - O aviso "existe um relato" que chega à pessoa envolvida, sobretudo em empresa pequena, pode identificar o trabalhador pelo momento e expô-lo a retaliação. Esse é o maior risco do plano, e só o envio aprovado pela equipe o reduz.
  - A equipe confere se o e-mail é um canal institucional (RH, ouvidoria, contato do site) e recusa e-mail pessoal ou de pessoa nomeada.
  - O aviso não sai logo após o relato: é enviado só depois da revisão, sem data.
  - Mesmo assim, o risco residual existe e precisa de aceite do responsável.
- **Abuso (envio a qualquer endereço).** Na variante (a), nenhum envio sai sem a equipe. A trava é ainda:
  - um contato por manifestação;
  - um aviso por empresa a cada 30 dias;
  - limite de pré-cadastro por conta;
  - lista de opt-out.

  Na variante (b), não há trava efetiva.
- **MEI ou pessoa física.**
  - O CNPJ de MEI ou de empresário individual identifica uma pessoa (ADR-0012 D9, ADR-0017 D5). Uma empregada doméstica, por exemplo, relataria contra uma pessoa física.
  - No pré-cadastro manual, o banco não detecta isso; a equipe confere na Receita em `pending_check`.
  - Proposta: a manifestação é aceita, mas o aviso é recusado quando a empresa é pessoa física. A decisão é do responsável.
- **Dado de terceiro.**
  - O e-mail do contato é dado pessoal de terceiro, que não consentiu. O nome digitado no pré-cadastro manual também pode ser de pessoa física.
  - Base legal e retenção ficam com o advogado (TASK-0007). Proposta: apagar o contato 90 dias depois do encerramento da manifestação ou da recusa do aviso.
- **Gmail.**
  - Um e-mail "existe um relato contra a sua empresa", vindo de um Gmail, parece golpe: vai para spam ou é denunciado.
  - Denúncias e o limite de 500 por dia podem bloquear a conta. Se for a mesma do Auth, a confirmação de cadastro para.
  - Mitigações: conta dedicada (ADR-0020 D1), volume baixo e manual, e um texto que oriente a empresa a entrar pelo endereço oficial digitado, sem link clicável. O canal e o custo ficam com o DevOps.
- **Existência como sinal.** Uma empresa pré-cadastrada indica que alguém relatou contra ela. Por isso, `find_company_by_cnpj` não informa o estado, e a empresa pré-cadastrada não aparece em diretório, ranking nem responsividade.
- **Sem projeto de desenvolvimento.** Toda a validação roda em produção, em transação desfeita, com liberação escrita por rodada. Isso alonga o calendário da seção 4.

## Decisões do responsável (2026-11-17)

1. Texto citando que existe um relato: **aceito**, com o texto final revisado pelo advogado. Muda a ADR-0012 D5 só para este aviso.
2. **(a1) envio manual no piloto**; (a2) depois.
3. **Busca só por CNPJ:** base própria, depois a API (ADR-0017, Edge Function), com os dados gravados; o pré-cadastro manual é o plano B.
4. **Pessoa física ou MEI:** o relato é aceito e o aviso é recusado.
5. **30 dias** entre avisos à mesma empresa; **90 dias** de retenção do contato.
6. **Risco residual aceito** (o aviso pode chegar à pessoa envolvida).
7. **Remetente (2026-11-18): "mesma caixa, mesma conta".** O aviso manual sai da conta Gmail do SMTP do Auth. Risco aceito: limite e bloqueio compartilhados com o cadastro (ver "Remetente no piloto").

8. **Provedores e gravação (2026-11-18): "Aceito as duas, e grava quando relatar."** Minha Receita, com a BrasilAPI de reserva, fica aceita sem termos de uso. A empresa entra em `companies` só quando o trabalhador a escolhe para relatar (`preregister_company`), e não a cada busca; a busca grava só no cache.

Em aberto: a finalidade comercial do aviso ("vira cliente"), que o advogado precisa cobrir na base legal e no texto.
