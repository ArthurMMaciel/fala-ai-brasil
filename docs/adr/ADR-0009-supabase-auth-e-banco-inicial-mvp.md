# ADR-0009 — Supabase Auth e PostgreSQL gerenciado como fundação do MVP

- Estado: Aceita para o MVP de demonstração
- Data: 2026-10-26
- Tarefa: [TASK-0022](../tasks/TASK-0022-mvp-supabase-cadastro-e-confirmacao.md)
- Relacionadas: TASK-0005, TASK-0006, TASK-0007, TASK-0008; ADR-0002, ADR-0005

## Contexto

O responsável técnico definiu um MVP para apresentação em 2026-10-30 com cadastro real das personas Trabalhador, Empresa, Parceiro e Patrocinador, confirmação de senha e confirmação de conta por e-mail, sem backend próprio e com custo mínimo (planos gratuitos). Intelligence/Estudos ficam fora do cadastro nesta etapa.

## Problema

Persistir contas e organizações com autenticação real sem construir e operar uma API agora, mantendo isolamento por usuário/organização e sem expor dados pessoais a outros usuários.

## Opções

1. API própria (monólito modular, ADR-0002) + PostgreSQL: maior controle, inviável no prazo.
2. Supabase (Auth + PostgreSQL + RLS) acessado direto pelo front com chave pública: rápido, gratuito, segurança concentrada em RLS e triggers.
3. Firebase/Auth0 + outro banco: duas plataformas, sem PostgreSQL relacional.

## Decisão

Opção 2, em projeto Supabase na região `sa-east-1` (São Paulo):

- Supabase Auth com e-mail/senha, confirmação de e-mail obrigatória e SMTP próprio via Resend configurado no painel.
- Esquema versionado em `supabase/migrations/`, aplicado com a CLI (`supabase db push`).
- RLS habilitado em todas as tabelas expostas; nenhum insert direto do cliente em perfis, organizações, vínculos ou assinaturas.
- Criação de perfil, organização, vínculo e assinatura inicial feita por trigger `security definer` em `auth.users`, numa única transação, validando persona, plano e modalidade.
- CPF e endereço são removidos de `raw_user_meta_data` após a cópia para `profiles`, para não circularem no JWT.
- Cliente usa somente a publishable/anon key. `service_role` e senha do banco nunca entram no repositório nem no front.
- Contas demo `@escutaai.demo` continuam locais para preservar a demonstração dos portais com dados fictícios.

## Revisão v2 (2026-10-27, aprovada pelo responsável)

O modelo inicial com tabela única `profiles` e coluna `persona` foi substituído pela migration `20261027002812_mvp_entidades_por_tipo.sql`, antes de haver dados reais:

- Entidades por tipo: `workers`, `companies` + `company_users` (vários usuários de RH por empresa; quem cadastra é owner), `partners` (nome profissional, CPF ou CNPJ, especialidade em texto livre, descrição, foto) e `sponsors` (nome e CNPJ).
- `addresses` como entidade própria (zip_code, street_type, street_name, number, complement, neighborhood, city, state), referenciada por `address_id` em cada entidade.
- Uma conta pode ter vários perfis; `current_profiles()` lista os perfis e o front mostra seletor quando há mais de um. Perfis adicionais entram por `add_profile()` (RPC autenticada); a tela para isso fica para depois do MVP.
- Criação centralizada em `private.create_profile()` (schema não exposto), chamada pelo trigger de cadastro e por `add_profile()`.
- `media`: imagens no bucket público `partner-media` (até 5 MB, JPG/PNG/WebP, escrita só na pasta do próprio parceiro); vídeos apenas por link externo, para não estourar o Storage gratuito.
- `subscriptions` liga a exatamente uma entre empresa, parceiro e patrocinador.
- `list_partner_directory()` entrega às empresas nome, especialidade, descrição, foto e cidade/UF, sem documento nem endereço completo.
- CNPJ de empresa é único: um segundo RH da mesma empresa recebe orientação para pedir acesso (convite ainda não implementado). Sem verificação de titularidade (TASK-0011).
- Teste de fumaça de trigger e RLS em `supabase/tests/rls_smoke.sql` (executa e desfaz).

## Motivo

Atende ao prazo e ao custo, entrega autenticação e isolamento reais em PostgreSQL e preserva o caminho para uma API própria: o esquema e as políticas podem migrar para uma API que use o mesmo banco.

## Consequências

- Toda regra de acesso precisa estar em RLS/grants; uma tabela sem RLS fica pública via API REST.
- Assinatura e pagamento continuam simulados; a assinatura persistida é somente leitura para o cliente.
- Projeto gratuito pausa após 7 dias sem uso e não tem backup point-in-time.
- Dependência nova: `@supabase/supabase-js` (mantida pelo fornecedor, MIT, sem custo).

## Riscos

- Cadastro aberto permite contas automatizadas: sem CAPTCHA nem rate limit próprio nesta etapa.
- CPF/CNPJ sem unicidade nem verificação de titularidade (TASK-0011 continua pendente).
- Sem trilha de auditoria de acesso (TASK-0009) nem base legal/retenção formalizadas (TASK-0007).
- Fotos de parceiros são públicas por URL (perfil público do Hub).
- Endereço órfão permanece se a conta for excluída (exclusão/retenção ainda pendentes).

## Limites

Não autoriza relatos reais, piloto com dados reais ou promessa pública de anonimato. O gate do `docs/ROADMAP.md` continua válido. Manifestações seguem voláteis no front.

## Rollback

Desativar as chamadas Supabase no front (contas demo continuam funcionando) e, se necessário, aplicar migration de reversão `drop` das tabelas `public.*`, funções, schema `private`, políticas do bucket `partner-media` e do trigger em `auth.users`.

## Alternativas rejeitadas

API própria agora (prazo); Firebase (modelo não relacional, divergente da direção PostgreSQL).
