# TASK-0002 — Eliminar XSS na POC

- Status: em-andamento (correções e testes em PR na branch `fix/xss-poc`; CSP e revisão de segurança pendentes)
- ClickUp: [TASK-0002](https://app.clickup.com/t/86aktn715)
- Área: Segurança/Frontend
- Prioridade: P0
- Estimativa: 1–2 dias
- Impacto: remove execução de conteúdo inserido pelo usuário

## Problema
Valores de nome, relato, resposta e contato entram em templates de `innerHTML`.
## Contexto
O fluxo já aceita texto livre; payloads HTML podem executar no navegador.
## Objetivo
Garantir encoding seguro e reduzir superfícies HTML dinâmicas.
## Escopo
Inventariar sinks/sources, criar renderização segura, CSP compatível e testes de payloads.
## Fora de escopo
Migração total para framework.
## Critérios de aceite
Payloads comuns de XSS aparecem como texto; nenhum dado não confiável chega cru ao HTML; build e fluxos passam.
## Riscos
Quebrar destaques/redações intencionais.
## Dependências
Baseline de testes da interface pode ser feito em conjunto com TASK-0004.
## Segurança
Cobrir stored/reflected/DOM XSS conceitualmente, inclusive atributos.
## Dados envolvidos
Relato e dados de perfil sintéticos.
## Observabilidade
No backend futuro, métricas de violações CSP sem registrar payload sensível.
## Rollback
Reverter patch; não desativar encoding para recuperar formatação.
## Testes necessários
Unitários do encoder e E2E com `<img onerror>`, tags, aspas e Unicode.
## Definição de pronto
Revisão de segurança concluída e testes automatizados verdes.

## Execução (2026-11-06)

Branch `fix/xss-poc`, a partir de `fix/restaura-assistente-manifestacao`. Nenhuma dependência nova (DOMPurify não foi necessário), nenhuma mudança em `supabase/`, regra de negócio ou visual.

### Inventário de sinks

| Sink | Local | Dados que chegavam ao HTML | Situação |
|---|---|---|---|
| `innerHTML` do renderer `y()` | `src/app/main.js` (template único da aplicação legada) | Ver tabela de fontes abaixo | Fontes não confiáveis agora passam por `h()`/`acctEsc()`, que delegam a `escapeHtml` |
| `innerHTML` do botão de senha | `src/app/main.js` (`acctTogglePassword`) | SVG constante | Sem dado do usuário; mantido |
| `innerHTML` da barra de etapas | `src/app/auth-steps.ts` | Classes calculadas pelo índice da etapa | Sem dado do usuário; mantido |
| `dangerouslySetInnerHTML`, `insertAdjacentHTML`, `outerHTML`, `document.write` | `src/` | — | Nenhuma ocorrência |
| `href`/`src` em JSX | `src/portals/portal-live.tsx` | URL externa de conteúdo do parceiro, foto do parceiro | Só `http(s)` via `safeHttpUrl`; fora disso, sem link/imagem |
| `href` `mailto:`/`tel:` em JSX | `contact-solicitations-admin.tsx`, `portal-live.tsx` | E-mail/telefone | Esquema fixo e texto escapado pelo React; sem risco de `javascript:` |

Fontes no renderer legado (`main.js`) corrigidas: nome do usuário na saudação; e-mail pré-preenchido no login; busca de empresa (XSS refletido em `value`); título, relato original, período e recorrência do rascunho; relato original na revisão e na aba Relato da equipe (escapa antes de aplicar a marcação de redação); título, versão compartilhável e resposta da empresa no acompanhamento e nas listas; mensagens de erro do assistente; tipo de perfil vindo do banco sem rótulo conhecido; foto do parceiro e link de campanha (só `http`/`https`; link inválido aparece como texto). Já estavam escapados: contatos indicados, nome/ID dos perfis, campos de campanha (exceto o esquema da URL). Textos de catálogo, mocks e rótulos fixos do próprio código não foram alterados.

### Implementação

- `src/domain/html-safety.ts`: `escapeHtml` (`& < > " ' \``, aceita `null`/número) e `safeHttpUrl` (URL absoluta `http`/`https`; rejeita `javascript:`, `data:`, `vbscript:`, relativas, `//host`, espaços e caracteres de controle).
- `src/app/main.js`: 22 substituições pontuais por script Node que preserva CRLF; `h()` e `acctEsc()` passam a delegar a `escapeHtml`.
- `src/portals/portal-live.tsx`: galeria de conteúdos, avatar do diretório e foto do perfil usam `safeHttpUrl`.

### Evidências

- `npm test`: 48 testes passando (42 antes + 6 novos). Novos: `scripts/test-html-safety.mjs` (encoder, filtro de URL e trava de inventário de sinks) e três cenários em `scripts/test-navigation.mjs` que renderizam o `main.js` real com `<img onerror>`, `<script>`, `'><svg onload>` e `javascript:`.
- Teste de mutação: removendo o escape da busca e do relato original, os dois cenários correspondentes falham.
- `npx tsc --noEmit -p .` e `npx vite build` sem erros.
- Navegador (prévia local `tmp/xss-preview.html`, que executa o `main.js` real com DOM real e `alert` instrumentado, e `tmp/portal-preview.html`): em busca, rascunho (etapas 6 e 9), acompanhamento, aba Relato da equipe, campanhas, seleção de perfil, foto do parceiro e conteúdos do parceiro, zero `alert` disparado, zero `img[onerror]`, zero `script` injetado, zero `href`/`src` com `javascript:`; payload visível como texto; redação de "Carlos" preservada; link `https` mantido. Conferido em 375 px sem rolagem horizontal e a landing em desktop sem erro de JavaScript novo.

### Pendente

- CSP compatível (o renderer legado usa atributos `style` inline nos templates; exige avaliação própria).
- Revisão de segurança independente e E2E no fluxo autenticado real (a verificação usou prévias com dados simulados).
- Portais React dependem do escape automático do React para texto; qualquer `dangerouslySetInnerHTML` futuro deve passar por esta tarefa.
