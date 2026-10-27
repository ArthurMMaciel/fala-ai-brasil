# TASK-0025 — Refinar o front para parecer menos gerado por IA

- Status: proposta
- ClickUp: [TASK-0025](https://app.clickup.com/t/17tu7rp7qbx)
- Área: Frontend/UX
- Prioridade: P1
- Estimativa: 1–2 dias
- Impacto: percepção de produto real na apresentação a clientes
- Relacionada: [TASK-0021](TASK-0021-figma-direcao-editorial.md), [TASK-0022](TASK-0022-mvp-supabase-cadastro-e-confirmacao.md)

## Problema
Partes da interface têm padrões genéricos de layout e texto gerado (cards iguais, títulos explicativos demais, avisos repetidos, ícones e badges padrão), o que reduz a credibilidade do produto.
## Contexto
A direção editorial do Figma (TASK-0021) é a referência aprovada pela equipe. Telas criadas no MVP (cadastro, toasts, campanhas, portais com dados reais, patrocinadores) seguiram o padrão existente sem passada de design.
## Objetivo
Interface consistente com a direção editorial, com textos curtos e específicos e hierarquia visual clara.
## Escopo
- Auditoria visual das telas por perfil (landing, cadastro/login, trabalhador, empresa, parceiro, patrocinador) com capturas antes/depois.
- Tese visual, plano de conteúdo e tese de interação registrados antes de implementar (diretriz de frontend do AGENTS.md).
- Revisão de microcopy: cortar explicações redundantes, avisos repetidos e frases genéricas.
- Hierarquia: menos cards idênticos, mais tipografia e espaço; estados vazios e de carregamento com cara do produto.
- Consistência de botões, espaçamentos, tabelas e cores com o `editorial.css`.
- Checagem de acessibilidade básica e mobile (320/390 px).
## Fora de escopo
Nova identidade visual ou redesign completo.
## Critérios de aceite
- Auditoria e plano aprovados pelo responsável antes da implementação.
- Capturas antes/depois de cada perfil.
- Nenhuma regressão nos testes; contraste e foco visíveis.
## Riscos
Mudar demais perto da apresentação; fazer em passadas pequenas e revisáveis.
## Dependências
Disponibilidade do responsável para aprovar a direção.
## Segurança
Não se aplica.
## Dados envolvidos
Nenhum novo.
## Observabilidade
Não se aplica.
## Rollback
Reverter commits de estilo e texto.
## Testes necessários
Testes existentes, roteiro de navegador e revisão visual em desktop e mobile.
## Definição de pronto
Critérios atendidos e capturas anexadas à tarefa.
