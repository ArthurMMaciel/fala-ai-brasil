# TASK-0024 — Levar ao banco o que ainda é simulado

- Status: proposta
- ClickUp: [TASK-0024](https://app.clickup.com/t/17tu7rp7qbw)
- Área: Fullstack/Dados
- Prioridade: P1
- Estimativa: 2–3 dias
- Impacto: demonstração sem telas com dados inventados no código
- Relacionada: [TASK-0022](TASK-0022-mvp-supabase-cadastro-e-confirmacao.md), [ADR-0009](../adr/ADR-0009-supabase-auth-e-banco-inicial-mvp.md)

## Problema
Contas, perfis, manifestações, respostas, ranking, Hub e campanhas já estão no Supabase (modelo v3). Ainda há partes simuladas no código ou sem exemplos no banco.
## Contexto
Seed atual: `scripts/seed-demo-data.mjs` (24 contas fictícias). Testes de fumaça em `supabase/tests/`.
## Objetivo
Toda tela acessível por conta real mostra dados do banco, com exemplos suficientes para a apresentação.
## Escopo (cada item novo de banco passa por aprovação do modelo antes da migration)
- Fotos de exemplo para os parceiros do seed (bucket `partner-media`) e logo de patrocinador no banco, em vez de arquivo local por nome.
- "Conteúdos" do parceiro: publicar e listar conteúdos (removido do portal real até existir tabela).
- Revisão de campanhas: perfil de revisor da plataforma e tela de aprovar/recusar com motivo.
- Percursos editoriais anônimos (relatar/acompanhar por protocolo e chave) e botão "Acompanhamento" da landing: ligar ao banco ou retirar do MVP.
- Tela para adicionar um segundo perfil à conta (`add_profile()` já existe) e convite de outros usuários de RH (`company_users`).
- Alteração de plano e pagamento persistidos (hoje simulados; Stripe na TASK-0018).
- Limpeza do legado sem uso: `src/worker-portal.tsx`, `src/mockData.ts`, `src/main.ts` desatualizado e rotas de Operação/IA ocultas.
## Fora de escopo
IA, pagamento real e operação humana de casos.
## Critérios de aceite
- Nenhuma tela de conta real lê `mockData.ts`.
- Seed idempotente cobre todos os perfis com exemplos coerentes.
- Testes de fumaça cobrem as novas tabelas/funções.
## Riscos
Escopo grande para o prazo de sexta: priorizar fotos do seed, revisão de campanhas e retirada dos percursos anônimos.
## Dependências
Aprovação de modelo para conteúdos, revisor e logos.
## Segurança
RLS em toda tabela nova; revisor com acesso mínimo e auditável.
## Dados envolvidos
Somente dados fictícios.
## Observabilidade
Sem mudança.
## Rollback
Migrations de reversão e remoção do seed.
## Testes necessários
Testes de fumaça SQL, testes de regras e roteiro no navegador por perfil.
## Definição de pronto
Critérios atendidos, ADR e memória atualizadas.
