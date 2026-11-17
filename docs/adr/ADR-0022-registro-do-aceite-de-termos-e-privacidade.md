# ADR-0022 — Registro do aceite dos termos de uso e do aviso de privacidade

- Estado: **Aceita**, pelo responsável em 2026-11-17 (aceite pós-login, versão e re-aceite). Com o advogado: retenção após a exclusão da conta e a lacuna dos dados gravados antes do aceite. Versão 1 = texto do advogado (24/11); até lá o gate fica desligado. Implementação: `20261117140000`, ainda não aplicada.
- Origem: pedido do Front (o cadastro já exige as caixas "termos" e "privacidade" em `src/app/main.js`, mas nada é gravado) e do Gestor (sem aceite gravado o go/no-go de 25/11 não fecha).
- Relacionadas: ADR-0009 (cadastro), TASK-0007 (base legal e retenção), TASK-0009 (auditoria)

## Restrições recebidas

1. O aceite guarda a versão do documento.
2. Texto novo exige novo aceite. O texto do advogado chega até 24/11 e pode mudar depois.
3. Não usar o `user_metadata` do signUp. Esse campo é controlado pelo cliente e pode ser editado pelo próprio usuário depois.

## Consequência das restrições

No signUp com confirmação de e-mail não há sessão. Sem `user_metadata`, o banco não tem como saber, no momento do cadastro, que caixas foram marcadas. O registro só pode ser feito com a pessoa autenticada. Por isso, o aceite que vale é o feito **após o login**, na tela de aceite; as caixas do cadastro continuam como aviso, sem valor de registro.

Isso também resolve o re-aceite: a mesma tela aparece sempre que existir versão vigente não aceita.

Lacuna assumida: entre a confirmação do e-mail e o primeiro aceite, a conta já existe com os dados do cadastro (CPF, endereço, CNPJ), gravados pelo gatilho a partir do metadata do cadastro (ADR-0009). O aceite registrado vem logo depois, no primeiro login. Se o responsável ou o advogado exigirem registro anterior a qualquer gravação, o caminho é outro: cadastro por função de servidor (Edge Function), que fica fora do piloto.

## Decisão proposta

D1. **Documentos e versões no servidor.** A tabela `private.legal_documents` lista, por documento (`terms`, `privacy`), as versões publicadas, com a data e o hash do texto. Só uma versão por documento é a vigente. A versão é um texto curto (por exemplo, `2026-11-24`), validado contra essa tabela. Nada de texto livre vindo do cliente.

D2. **Aceite só de inserção.** A tabela `public.legal_acceptances` guarda uma linha por pessoa, documento e versão, com `accepted_at = now()` do servidor. Não há update nem delete pelo cliente. Uma chamada repetida não duplica a linha (`unique (user_id, document, version)`).

D3. **Gate no banco.** `private.assert_legal_current()` recusa, com mensagem fixa, quem não aceitou a versão vigente dos dois documentos. Ela entra nas funções de ação: `create_complaint`, `share_complaint`, `respond_complaint`, `rate_response` e `add_profile`. Ficam fora a leitura dos próprios dados, o encerramento (`close_complaint`) e o próprio aceite: a pessoa precisa conseguir ler e sair mesmo sem aceitar o texto novo.

D4. **Publicação de versão nova pela equipe.** `ops_publish_legal_version(p_document, p_version, p_content_hash)` marca a nova versão como vigente e registra quem publicou. A partir daí, todos voltam a ter aceite pendente.

D5. **Sem dados extras.** Não gravar IP, user agent nem geolocalização. Se o advogado pedir, isso é uma decisão nova, com retenção própria.

## Modelo previsto

| Objeto | Colunas | Quem lê | Quem escreve |
|---|---|---|---|
| `private.legal_documents` | `document` (`terms`/`privacy`), `version`, `content_hash`, `published_at`, `published_by`, `is_current`; `unique (document, version)`; um `is_current` por documento | funções `security definer` | `ops_publish_legal_version` |
| `public.legal_acceptances` | `id`, `user_id`, `document`, `version`, `accepted_at`; FK `(document, version)` para `legal_documents`; `unique (user_id, document, version)` | dono via `my_legal_status()`; equipe via `ops_*`; empresa **nunca** | só `record_legal_acceptance`. RLS ligada, sem policy de escrita, `revoke all` de anon e authenticated |

## Contrato para o Front (sujeito a aprovação)

- `my_legal_status() → table(document text, current_version text, accepted_version text, needs_acceptance boolean)`. Para authenticated. Chamada logo após o login; se alguma linha tiver `needs_acceptance`, o front mostra a tela de aceite antes do portal.
- `record_legal_acceptance(p_document text, p_version text) → void`. Para authenticated. Recusa documento desconhecido e versão que não é a vigente, com a mesma mensagem nos dois casos. É idempotente.
- Erro fixo do gate (D3), para o front reconhecer e levar à tela de aceite: "Aceite a versão atual dos termos e do aviso de privacidade para continuar."
- `ops_legal_acceptance_stats() → table(document, version, accepted_count, pending_count)`, só para a equipe, sem lista de pessoas.

## Riscos

- **Exclusão de conta:** com FK `on delete cascade` para `auth.users`, apagar a conta apaga a prova do aceite. Com `on delete set null`, a prova perde o vínculo. Se a base legal for consentimento, a LGPD (art. 8º, § 2º) põe no controlador o ônus de provar que ele foi obtido. A escolha depende da retenção (TASK-0007) e do advogado. Proposta inicial: `on delete set null`, mantendo documento, versão e data.
- **Gate em funções existentes:** acrescentar `assert_legal_current` muda `create_complaint`, `respond_complaint` e outras. Contas existentes, inclusive de teste e demonstração, ficam bloqueadas até aceitar. O front precisa da tela de aceite **antes** do db push do gate. Ordem prevista: (1) tabelas e RPCs sem gate; (2) front com a tela; (3) gate em migration separada.
- **Texto do advogado depois de 24/11:** a primeira versão publicada pode ser provisória. Cada troca gera re-aceite de todos, o que é o comportamento esperado, mas cria atrito no piloto.
- **Hash do texto:** só serve se o texto publicado no site for exatamente o que gerou o hash. O responsável por publicar o texto precisa seguir esse passo.

## Testes de fumaça previstos

- conta sem aceite é barrada em `create_complaint` e `respond_complaint`, mas lê os próprios dados e encerra caso;
- aceite da versão vigente libera; aceite de versão antiga ou desconhecida é recusado com a mesma mensagem;
- chamada repetida não duplica;
- publicar versão nova volta `needs_acceptance` para todos;
- a pessoa lê só os próprios aceites; a empresa não lê nada; anon não executa;
- update e delete diretos são recusados;
- o `isolation_smoke.sql` da TASK-0006 inclui as tabelas novas automaticamente.

## Rollback

Antes do gate: remover funções e tabelas, sem dado dependente fora delas (exportar os aceites antes). Depois do gate: retirar `assert_legal_current` das funções por migration. Os aceites gravados são preservados.

## Decisões que dependem do responsável

1. Aceitar a lacuna entre o cadastro e o primeiro aceite, ou exigir cadastro por função de servidor (fora do piloto).
2. Quais ações exigem aceite vigente (D3).
3. Retenção do aceite após a exclusão da conta (`set null`, manter por prazo ou apagar).
4. Versão inicial a publicar antes do texto do advogado, ou esperar o texto de 24/11.
5. Se o advogado pedir IP ou user agent no registro.
