# Manutenção: zerar o banco e incluir contas de equipe

Scripts para o SQL Editor de produção, pedidos pelo responsável em 2026-11-24. Rodar **depois** dos testes das notificações e **antes** das empresas reais.

> **IRREVERSÍVEL. NÃO HÁ BACKUP.** O `02_zerar_banco.sql` apaga todas as contas que não são da equipe e todos os dados de aplicação. Depois do commit, não há como desfazer.

## Zerar o banco

| Passo | Arquivo | O que faz |
|---|---|---|
| 1 | `01_previa_zerar_banco.sql` | **Só leitura.** Mostra, por tabela, o que seria apagado e o que fica. Confira os números antes do passo 2 |
| 2 | `02_zerar_banco.sql` | Troque `v_confirmo := 'NAO'` por `'APAGAR TUDO'` e rode o arquivo inteiro uma vez. A última consulta mostra zero em tudo, o número da equipe e se algum gatilho de trilha ficou desligado (deve ser 0) |

**O que é apagado:**
- contas fora de `private.platform_admins`, com sessões e identidades;
- manifestações, originais, versões, eventos, revisões e respostas;
- avaliações, contatos, consentimentos, avisos e opt-outs;
- fila de notificações, cache e cota de CNPJ, pré-cadastros;
- empresas, vínculos e verificações;
- parceiros, conexões e mídia;
- patrocinadores, campanhas e assinaturas;
- contatos da landing, aceites de termos, trilha da pausa, trilha de mudanças de perfil e endereços.

**O que fica:**
- as contas da equipe e os perfis delas, se houver (trabalhador, empresa, parceiro ou patrocinador, com endereço, assinatura e mídia);
- `private.document_officers` da equipe;
- `public.plans`, `private.legal_documents`, `private.platform_settings` (estado do piloto) e `supabase_migrations.schema_migrations`.

**Detalhes:**
- Os gatilhos de trilha imutável (`company_notices_guard`, `legal_acceptances_immutable`, `pilot_state_log_immutable` e `representative_verifications_immutable`) são desligados **só dentro da transação** e religados antes do commit.
- A sequência dos protocolos (EAB-…) **não** é reiniciada, para não repetir números que empresas já viram.
- O script recusa rodar se não houver nenhuma conta de equipe com e-mail.

**Storage, que o SQL não apaga:**
- o único bucket do projeto é `partner-media` (foto e conteúdo dos parceiros);
- o `01` mostra quantos arquivos há em `storage.objects`;
- se houver, apague pelo painel em Storage > `partner-media`, exceto os arquivos de parceiros da equipe, se existirem.

**Testado no banco local em 2026-11-24, numa transação desfeita, sem gravar nada:**
- zerou tudo e manteve a conta de equipe e o perfil de trabalhador dela;
- religou os gatilhos;
- a equipe é reconhecida (`is_platform_admin`) e as funções da Operação respondem;
- cadastro novo de trabalhador e de empresa cria os perfis, e o fluxo relato → liberação roda;
- sem a confirmação, o script recusa e não apaga nada.

O login real (Auth) da conta mantida não foi testado depois do zerar, porque o teste não grava. O zerar não mexe nas linhas da conta da equipe em `auth.users` nem em `auth.identities`.

## Incluir uma conta na equipe

**Caminho recomendado:**
1. No painel, em Authentication > Users > Add user > Create new user, informe o e-mail e uma senha forte e marque **Auto Confirm User**.
2. Rode `03_incluir_admin_por_email.sql`, trocando só `SEU_EMAIL_AQUI`.

A senha não passa pelo SQL Editor. O script recusa conta inexistente ou com e-mail não confirmado e é idempotente.

**Alternativa:** `04_criar_admin_com_senha.sql`, trocando `EMAIL_AQUI` e `SENHA_AQUI` (12 ou mais caracteres).
- **A senha fica no histórico do SQL Editor.** Peça à pessoa que troque a senha no primeiro acesso.
- Cria a conta já confirmada, com senha em bcrypt e identidade de e-mail, e inclui na equipe.
- Se o e-mail já existir, não mexe na senha; só inclui na equipe.

**Perfil:** a conta de equipe **não precisa** de perfil de trabalhador, empresa ou parceiro. O acesso à Operação vem só de `private.platform_admins`. Sem `signup_type`, o gatilho `handle_new_user` não cria perfil.

**Testado no banco local em 2026-11-24:**
- `04`: a conta criada entrou pelo Auth local com a senha, `is_platform_admin` respondeu `true` e `ops_list_complaints` respondeu 200. A conta de teste foi apagada em seguida.
- `03`: incluiu a conta confirmada sem diferenciar maiúsculas e recusou a não confirmada, numa transação desfeita.
- Os dois recusam rodar com os valores de exemplo.

Não salve nenhum destes arquivos com e-mail ou senha preenchidos.
