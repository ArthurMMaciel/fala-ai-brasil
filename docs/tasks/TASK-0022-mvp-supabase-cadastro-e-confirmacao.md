# TASK-0022 — MVP: Supabase, cadastro persistido e confirmação por e-mail

- Status: em-andamento
- ClickUp: [TASK-0022](https://app.clickup.com/t/17tu7rp7pjw)
- Área: Fullstack/Dados/Segurança
- Prioridade: P1
- Estimativa: 2–3 dias
- Impacto: primeira persistência real; base da demonstração de 2026-10-30
- Decisão: [ADR-0009](../adr/ADR-0009-supabase-auth-e-banco-inicial-mvp.md)

## Problema
Cadastros e logins são simulados em memória; a demonstração precisa de contas reais.
## Contexto
Sem backend próprio; Supabase gratuito em `sa-east-1`; SMTP Resend; Intelligence/Estudos fora do cadastro.
## Objetivo
Cadastrar Trabalhador, Empresa, Parceiro e Patrocinador no Supabase, com confirmação de senha e de e-mail, login, sessão persistente e logout.
## Escopo
- Migration v2 com entidades por tipo (`workers`, `companies`/`company_users`, `partners`, `sponsors`), `addresses`, `media` + bucket `partner-media`, `plans`, `subscriptions`, RLS, `current_profiles()`, `add_profile()` e `list_partner_directory()`.
- Seletor de perfil para contas com mais de um tipo; foto de perfil do parceiro na conta.
- Conta do patrocinador com abas Planos e Campanhas (`campaigns`, `create_campaign()`, `submit_campaign()`); empresa real abre o portal da empresa com seus dados e o diretório real de parceiros.
- Toasts de sucesso/erro, exibir senha, reenvio contextual, patrocinadores fixos na landing e usuários de teste por entidade.
- Integração `@supabase/supabase-js` no cadastro/login existentes.
- Confirmação de senha, tela "verifique seu e-mail", reenvio e tratamento de e-mail não confirmado.
- Modelo de templates de e-mail em PT-BR.
- Diagramas de banco e arquitetura em `arquiteturas/`.
## Fora de escopo
Manifestações persistidas, pagamento real, verificação de CNPJ/contato, auditoria, recuperação de senha, convite de membros, tela para adicionar segundo perfil, upload de vídeo.
## Critérios de aceite
- Cadastro dos quatro tipos cria usuário, entidade, endereço e (comercial) assinatura em uma transação; empresa também cria vínculo owner.
- Teste `supabase/tests/rls_smoke.sql` passa (12 verificações).
- Login só após confirmação de e-mail; mensagem clara caso contrário.
- Usuário lê apenas os próprios perfis, endereços e empresas das quais é membro; empresas veem diretório de parceiros sem documento.
- CPF e endereço não permanecem em `user_metadata`.
- Contas demo continuam funcionando.
- `npm test` e `npm run build` passam.
## Riscos
Ver ADR-0009 (RLS, cadastro aberto, pausa do projeto gratuito, sem verificação de CNPJ).
## Dependências
Projeto Supabase vinculado; SMTP Resend configurado; URLs de redirecionamento no painel.
## Segurança
Somente chave pública no front; RLS em todas as tabelas; nenhum segredo versionado; sem dados pessoais em logs.
## Dados envolvidos
Nome, e-mail, CPF (Trabalhador), CNPJ (Empresa), endereço, plano/modalidade. Somente dados fictícios na demonstração.
## Observabilidade
Logs do painel Supabase (Auth); nenhuma telemetria adicionada.
## Rollback
Ver ADR-0009.
## Testes necessários
Validação de formulário (unitário), RLS com dois usuários, cadastro ponta a ponta com e-mail real de teste.
## Definição de pronto
Critérios atendidos, documentação e memória atualizadas, tarefa sincronizada no ClickUp.
