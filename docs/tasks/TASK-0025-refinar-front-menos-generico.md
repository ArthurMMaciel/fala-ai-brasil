# TASK-0025 — Refinar o front para parecer menos gerado por IA

- Status: em-andamento
- ClickUp: [TASK-0025](https://app.clickup.com/t/17tu7rp7qbx)
- Área: Frontend/UX
- Prioridade: P2; após os gates do piloto fechado
- Estimativa: 1–2 dias
- Impacto: percepção de produto real na apresentação a clientes
- Relacionada: [TASK-0021](TASK-0021-figma-direcao-editorial.md), [TASK-0022](TASK-0022-mvp-supabase-cadastro-e-confirmacao.md)

## Problema
Partes da interface têm padrões genéricos de layout e texto gerado (cards iguais, títulos explicativos demais, avisos repetidos, ícones e badges padrão), o que reduz a credibilidade do produto.
## Contexto
A direção editorial do Figma (TASK-0021) é a referência aprovada pela equipe. Telas criadas no MVP (cadastro, toasts, campanhas, portais com dados reais, patrocinadores) seguiram o padrão existente sem passada de design.

## Referências candidatas registradas em 2026-11-05

- Preferência explícita do responsável: componentes mais arredondados, mantendo linguagem sóbria e adequada a fluxos psicossociais.
- Imagem local `refero.design 0eab7b47-0939-4bed-bc79-22b6723ca32f.jpg`: referência da landing da Vectary para ritmo vertical, áreas amplas, imagens em destaque e agrupamentos com cantos suaves. Avaliar adaptação ao conteúdo e à identidade da Escuta Aí Brasil antes de implementar.
- [Emerald24 no Behance](https://www.behance.net/gallery/256834293/Neobank-web-mobile-app-UXUI-design-Emerald24) e [case da equipe criadora](https://goodface.agency/case/emerald-24-digital-bank-product-design-and-web-development/): referência para linguagem de produto, componentes arredondados, hierarquia operacional e consistência web/mobile.
- As referências ainda não constituem aprovação de redesign. Primeiro apresentar auditoria do estado atual e uma tese visual para Trabalhador e Empresa; preservar a direção editorial existente até decisão do responsável.
## Direção aprovada em 2026-11-05

O responsável aprovou a aplicação das duas referências e pediu componentes mais arredondados. A primeira passada cobre landing e áreas de Trabalhador/Empresa; as outras personas ainda exigem revisão visual própria.

- Tese visual: ambiente claro e sereno, verde profundo como eixo de navegação e superfícies suaves; ritmo amplo inspirado na referência Vectary e linguagem operacional arredondada inspirada no case Emerald24. Preservar a marca e evitar cores competitivas em um tema sensível.
- Plano de conteúdo: hero com promessa e ação principal; painel de três passos como apoio; jornada; detalhes de escuta/resposta; chamada final; planos demonstrativos identificados como hipótese.
- Tese de interação: seleção de persona em navegação de leitura rápida, movimento breve apenas no CTA/entrada do hero, foco visível e respeito a movimento reduzido.
- Auditoria do código anterior: botões com raio de 4 px, painéis e filtros quadrados, landing com pouco respiro e hierarquia de navegação fraca. O painel do trabalhador substituiu uma fotografia por decisão anterior e permanece.
- Riscos: visual não altera autorização nem separação de dados; texto sobre acesso empresarial precisa continuar condicionado à liberação segura. Sem serviços, dependências ou dados novos. Rollback pela reversão das alterações de `landing-react.tsx` e `editorial.css` desta passada.
- ClickUp: tarefa existente consultada; atualização remota pendente após limite da API encontrado nesta sessão. Manter este documento vinculado ao [TASK-0025](https://app.clickup.com/t/17tu7rp7qbx).
- Verificação desta passada: `npm test -- --run` (38/38), `npm run build` e `git diff --check` passaram. Servidor local respondeu HTTP 200 em `http://127.0.0.1:5173/`. Capturas e revisão visual manual ainda pendentes: o navegador via Computer Use ficou indisponível e o roteiro `test:editorial:browser` não executa porque Playwright não está instalado neste ambiente.

## Objetivo
Interface consistente com a direção editorial, com textos curtos e específicos e hierarquia visual clara.
## Escopo
- Auditoria visual das telas por perfil (landing, cadastro/login, trabalhador, empresa, parceiro, patrocinador) com capturas antes/depois.
- Tese visual, plano de conteúdo e tese de interação registrados antes de implementar (diretriz de frontend do AGENTS.md).
- Revisão de microcopy: cortar explicações redundantes, avisos repetidos e frases genéricas.
- Em cada seção das landings, manter um resumo curto e um próximo passo útil; CTA primário por persona e alternativa de contato conforme TASK-0026/TASK-0028, sem multiplicar botões redundantes.
- Hierarquia: menos cards idênticos, mais tipografia e espaço; estados vazios e de carregamento com cara do produto.
- Consistência de botões, espaçamentos, tabelas e cores com o `editorial.css`.
- Checagem de acessibilidade básica e mobile (320/390 px).
## Fora de escopo
Nova identidade visual ou redesign completo.
## Critérios de aceite
- Direção aprovada pelo responsável para a primeira passada visual; demais perfis serão avaliados em outra passada.
- Capturas antes/depois de cada perfil.
- Nenhuma regressão nos testes; contraste e foco visíveis.
- Conteúdo e CTAs conferidos nas cinco entradas públicas, com promessa compatível com o que está implementado.
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
