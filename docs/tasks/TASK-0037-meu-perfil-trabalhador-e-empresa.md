# TASK-0037 — "Meu perfil" do trabalhador e da empresa

- Status: em-andamento (modelo aceito em 2026-11-08; banco pronto na branch `feat/meu-perfil`, aguardando o front para PR conjunto)
- ClickUp: [TASK-0037](https://app.clickup.com/t/17tu7rpc384)
- Área: Backend/Frontend/Privacidade
- Prioridade: P2
- Estimativa: 2 a 3 dias após a aprovação
- Impacto: trabalhador e empresa corrigem os próprios dados com as mesmas validações do cadastro e trilha mínima; documento e razão social ficam travados
- Decisão estrutural proposta: [ADR-0014](../adr/ADR-0014-meu-perfil-trabalhador-e-empresa.md)

## Problema
A edição já existe por `update` direto nas tabelas, sem validação de dígitos, sem trilha, com a razão social editável e com membros da empresa (não só o dono) podendo alterar o endereço. Não há tela de perfil do trabalhador.

## Objetivo
Substituir a edição direta por RPCs validadas, travar CPF, CNPJ e razão social (troca só pela equipe), usar o fluxo do Supabase Auth para e-mail e registrar as alterações sem guardar valores.

## Escopo
`update_worker_profile`, `update_company_profile`, `ops_change_document`, `ops_profile_changes`, `private.valid_cpf`/`valid_cnpj`, tabela `profile_change_log`, `revoke` dos `update` diretos e telas "Meu perfil" nos dois portais.

## Fora de escopo
Perfil do parceiro e do patrocinador, exclusão de conta e portabilidade de dados.

## Critérios de aceite
Ver "Testes de fumaça previstos" na ADR-0014.

## Riscos
Compatibilidade do `revoke` com o front em produção e troca de e-mail sem dupla confirmação no remoto (ver ADR-0014).

## Progresso em 2026-11-08

- Decisões: razão social travada (C1), membro só lê (C2), trilha sem valores (C3), troca de CPF/CNPJ/razão social só pelo responsável com documento (C4, privilégio `private.document_officers` e `evidence_ref`). C5: conferir a dupla confirmação de e-mail no remoto.
- Migration `20261108120000_meu_perfil.sql` e teste `profile_smoke.sql` (33/33). Banco local recriado do zero com as 13 migrations; os 6 testes de fumaça passaram (95 verificações).
- Pendente: conceder `private.document_officers` à conta do responsável no remoto, após a aplicação (script manual).
- Pendente: telas "Meu perfil" (Front, a partir desta branch), PR único banco + tela e aplicação no remoto com autorização.

## Front (2026-11-08, branch `feat/meu-perfil-ui` a partir de `feat/meu-perfil`)

- Telas "Meu perfil" no portal do trabalhador (item no menu lateral) e no da empresa (item "Meu perfil"). Editáveis: trabalhador nome, telefone e endereço; dono da empresa nome fantasia, contato e endereço. CPF, CNPJ e razão social aparecem só para leitura com "Para alterar, fale com a equipe." Membro da empresa vê tudo só para leitura, inclusive o contato do Dashboard.
- Envio parcial (só os campos alterados) para `update_worker_profile` e `update_company_profile`; validação no navegador com as mesmas mensagens, erros do banco (P0001) no toast. `updateCompanyContact` passou a usar a RPC.
- E-mail de acesso: exibido; a troca por `supabase.auth.updateUser` está implementada atrás de `emailChangeEnabled = false` (`src/domain/profile.ts`) até a conferência da dupla confirmação no remoto (C5).
- Cadastro com CPF/CNPJ inválido: no banco local o Auth devolve 500 "Database error saving new user", sem a mensagem do gatilho; o front mantém a mensagem genérica (a validação do navegador já barra dígito inválido).
- Testes: `scripts/test-profile.mjs` (7) e suíte 57/57; conferido no banco local com contas fictícias (trabalhador, dona e membro), desktop e 375 px.
- Pendente: consulta de CEP (ViaCEP) no formulário do perfil, tela de troca de documento na Operação e navegação pelo menu lateral real do trabalhador logado (conferida só na prévia).

## Rollback
Reconceder os `update` por coluna e recriar as políticas antigas.

## Texto para o ClickUp
Título: TASK-0037 — "Meu perfil" do trabalhador e da empresa
Descrição: RPCs de atualização de perfil com as validações do cadastro, CPF/CNPJ/razão social travados (troca só pela equipe, com justificativa), e-mail pelo Supabase Auth com dupla confirmação e trilha sem valores. Corrige a edição de endereço da empresa por membros não donos. Prioridade P2. Documentos: docs/tasks/TASK-0037-meu-perfil-trabalhador-e-empresa.md e docs/adr/ADR-0014-meu-perfil-trabalhador-e-empresa.md. Status: proposta, aguardando aprovação do responsável.
