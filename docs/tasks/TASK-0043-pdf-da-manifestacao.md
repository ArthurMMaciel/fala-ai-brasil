# TASK-0043 — PDF da manifestação (fase 1: impressão do navegador)

- Status: em-andamento (código na main em `7860eef` desde 2026-11-10; aguarda conferência humana do PDF)
- ClickUp: [TASK-0043](https://app.clickup.com/t/17tu7rpcpde)
- Área: Frontend/Privacidade
- Prioridade: P2
- Estimativa: 1 dia
- Impacto: trabalhador e empresa guardam um registro da manifestação sem expor identidade nem, por padrão, o relato original

## Problema
Não havia como guardar ou imprimir uma manifestação. O trabalhador não tinha comprovante e a empresa copiava o texto à mão.

## Contexto
Proposta aprovada pelo responsável em 2026-11-09: só a fase 1 (impressão do navegador, sem dependência nova), relato original fora por padrão e rodapés como propostos. O registro da geração pela empresa (auditoria) fica para depois do MVP.

## Objetivo
"Baixar PDF" no detalhe da manifestação do trabalhador e da empresa, gerado no navegador pelo "Salvar como PDF", com as regras de privacidade de cada versão.

## Escopo
- Trabalhador: botão no cabeçalho do detalhe; diálogo com "Só a versão compartilhável e o acompanhamento" (padrão) ou "Incluir meu relato original", com aviso quando o original é incluído.
- Empresa: botão no cabeçalho do detalhe, que gera direto.
- Documento em texto real, montado só no clique, fora do `#app`, impresso por `window.print()`; o título da aba vira `manifestacao-<protocolo>` (nome sugerido do arquivo) e volta ao normal no `afterprint`.
- CSS `@media print` que mostra só o documento, com margens de página e quebras controladas.

## Fora de escopo
- Fase 2 (arquivo baixado direto, com biblioteca como jsPDF).
- Registro em auditoria da geração pela empresa (depois do MVP; exige evento novo no banco).
- PDF na Operação e nas listas.

## Critérios de aceite
- Trabalhador: protocolo, situação, empresa, assunto, período, recorrência, datas, versão compartilhável (liberada ou em revisão), o que espera, acompanhamento e avaliação; o original só com a opção marcada.
- Empresa: protocolo, situação, assunto, datas, versão compartilhada, histórico e avaliação; nunca o original.
- Nenhuma versão traz nome, CPF, telefone, e-mail ou endereço.
- Rodapés: trabalhador "Documento pessoal com informações do seu relato. Guarde com cuidado." mais a linha de emergência (CVV 188, SAMU 192, PM 190); empresa "Versão compartilhável revisada pela equipe Escuta Aí Brasil. Não contém a identidade de quem relatou. Não tente identificar a pessoa. Gerado por <empresa> em <data e hora>."
- Em 375 px o botão ocupa a largura toda abaixo do título.

## Riscos
- Privacidade: o arquivo sai da plataforma e pode ser encaminhado. Mitigação: original fora por padrão, aviso ao incluir e nenhum dado de identidade.
- O layout impresso varia um pouco por navegador.

## Dependências
Nenhuma dependência nova. Usa os dados que o detalhe já carrega, pelas mesmas regras de acesso (RLS).

## Segurança
Nenhum componente novo processa o relato; a CSP (`script-src 'self'`) não muda. O teste trava, no código-fonte, que a chamada da empresa não recebe o original.

## Dados envolvidos
Dados da própria manifestação já visíveis a cada perfil; o relato original só na versão do trabalhador e por escolha dele.

## Observabilidade
Nenhuma. A geração não é registrada nesta fase.

## Rollback
Reverter o commit `feat: PDF da manifestação pela impressão do navegador (TASK-0043, fase 1)`. Não há dado nem migration envolvidos.

## Testes necessários
- `scripts/test-print-document.mjs`: original fora por padrão e só com a opção; empresa sem original (inclusive no código-fonte do portal); rodapés; nome do arquivo saneado; texto real sem `input` nem `canvas`.
- Navegador com dados do banco local: trabalhador com e sem original, empresa só com a compartilhada, limpeza depois do `afterprint`, layout de impressão e botão em 375 px.

## Definição de pronto
Commit na main, testes e build verdes e a conferência humana abaixo feita.

## Progresso em 2026-11-10
- Implementado em `src/domain/print-document.ts`, `src/portals/print-document.tsx`, nos detalhes de `worker-portal-live.tsx` e `portal-live.tsx` e em `src/styles/system.css`. `npm test` 78/78, `tsc` e build OK.
- `window.print()` é chamado por `setTimeout` depois da renderização: com `requestAnimationFrame` o diálogo não abria com a aba em segundo plano.
- Pendente: conferência humana do diálogo de impressão e do arquivo final em Chrome (desktop), Safari (macOS ou iOS) e no celular (Chrome no Android). A verificação automática substituiu `window.print()` por um registro e não abriu o diálogo nativo.
- Na main em `7860eef` (push de 2026-11-10, liberado por escrito pelo responsável).
