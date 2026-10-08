# TASK-0015 — Visões comerciais, planos e suporte

- Status: concluída
- ClickUp: [TASK-0015](https://app.clickup.com/t/86aktn73p)
- Conclusão: 2026-10-05
- Área: Produto/Frontend/Monetização
- Prioridade: P2
- Estimativa: pequena
- Impacto: torna demonstráveis as personas de receita e separa suporte da operação sensível

## Problema

A POC apresenta apenas trabalhador e empresa/admin. O plano de monetização prevê Hub, Intelligence, estudos e patrocínio, mas essas personas não tinham uma visão de produto. Suporte também não estava representado nem separado da operação humana.

## Contexto

Os modelos e valores vêm do `PLANO_MONETIZACAO_ESCUTA_AI.html` e são hipóteses para entrevistas. A plataforma continua sendo uma POC local sem autenticação, cobrança, contratos, backend ou persistência reais.

## Objetivo

Demonstrar o valor, a visão e exemplos de contratação de cada persona comercial, além de uma visão interna de suporte com limites explícitos de acesso.

## Escopo

- Página navegável “Soluções e planos”.
- Visões de Empresa, Parceiro do Hub, Intelligence, Estudos e Patrocínio.
- Três exemplos de contratação por persona, com preços marcados como hipóteses.
- Indicação de acesso gratuito para pessoa trabalhadora.
- Visão interna de suporte, separada conceitualmente da operação humana.
- Atualização do plano de monetização e da memória do projeto.

## Fora de escopo

Checkout, cobrança, CRM, contratos, cadastro real de parceiros, autenticação/RBAC, persistência de chamados, benchmarks reais, publicidade ativa e integrações externas.

## Critérios de aceite

- Cada motor de receita possui uma visão demonstrativa e uma proposta de contratação.
- Preços e funcionalidades futuras são identificados como hipóteses, não capacidades atuais.
- Pessoa trabalhadora aparece como acesso gratuito, sem prioridade por pagamento.
- Suporte tem visão própria e não acessa conteúdo original ou identidade por padrão.
- Navegação funciona por teclado e em telas estreitas.
- Build TypeScript/Vite aprovado.

## Riscos

- Confundir protótipo comercial com oferta disponível.
- Antecipar acesso a dados agregados sem densidade e controles anti-reidentificação.
- Misturar suporte técnico, operação humana e portal da empresa.
- Fixar preços antes de validar disposição a pagar e custo de revisão humana.

## Dependências

Validação comercial com empresas e parceiros. Cobrança real depende da fundação segura do MVP e de decisões humanas sobre provedores e contratos.

## Segurança

Nenhuma autorização real é adicionada. As telas usam somente dados sintéticos e registram os limites de mínimo privilégio. Implementação futura de perfis exige ADR de autenticação, autorização e tenancy.

## Dados envolvidos

Somente textos e números fictícios em memória. Não há coleta ou envio de interesse comercial.

## Observabilidade

Fora de escopo na POC. Uma implementação real deve medir funil sem registrar relato, identidade ou conteúdo sensível.

## Rollback

Remover a rota `solutions`, os componentes comerciais e a rota `admin-support`; reverter as seções correspondentes de CSS e documentação.

## Testes necessários

- `npm.cmd run build` aprovado em 2026-10-05.
- Servidor Vite local respondeu `HTTP 200` em `http://127.0.0.1:5173/`.
- Revisão estática confirmou rotas, troca de personas, avisos de hipótese e ausência de persistência nos botões demonstrativos.
- Inspeção visual automatizada ficou pendente porque nenhum navegador estava conectado à sessão; estilos responsivos e foco visível foram revisados estaticamente.

## Definição de pronto

Código, plano, backlog e memória alinhados; build aprovado; riscos e estado demonstrativo explícitos.
