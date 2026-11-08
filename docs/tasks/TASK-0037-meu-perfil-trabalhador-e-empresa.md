# TASK-0037 — "Meu perfil" do trabalhador e da empresa

- Status: proposta (modelo aguardando aprovação do responsável; sem migration)
- ClickUp: (preencher após a criação; texto pronto no fim deste documento)
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

## Rollback
Reconceder os `update` por coluna e recriar as políticas antigas.

## Texto para o ClickUp
Título: TASK-0037 — "Meu perfil" do trabalhador e da empresa
Descrição: RPCs de atualização de perfil com as validações do cadastro, CPF/CNPJ/razão social travados (troca só pela equipe, com justificativa), e-mail pelo Supabase Auth com dupla confirmação e trilha sem valores. Corrige a edição de endereço da empresa por membros não donos. Prioridade P2. Documentos: docs/tasks/TASK-0037-meu-perfil-trabalhador-e-empresa.md e docs/adr/ADR-0014-meu-perfil-trabalhador-e-empresa.md. Status: proposta, aguardando aprovação do responsável.
