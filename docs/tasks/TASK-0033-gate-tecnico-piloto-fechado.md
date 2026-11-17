# TASK-0033 — Validar gate técnico e operar piloto fechado de novembro

- Status: proposta
- ClickUp: [TASK-0033](https://app.clickup.com/t/17tu7rpb56y)
- Área: QA/Segurança/DevOps/Operação
- Prioridade: P0
- Alvo de avaliação: 2026-11-25; abertura condicionada a evidências
- Relacionadas: TASK-0002, TASK-0004, TASK-0005, TASK-0006, TASK-0007, TASK-0009, TASK-0010, TASK-0011, TASK-0029, TASK-0031

## Objetivo

Liberar um piloto por convite, com poucas empresas verificadas e capacidade operacional definida, somente após prova dos controles. Esta tarefa não autoriza deploy público nem uso de dados reais sozinha.

## Gate de entrada de casos reais

- Escopo, base legal, aviso, retenção e responsáveis aprovados.
- XSS e fluxos de autenticação revistos; sessão e acesso entre duas empresas testados.
- Relato original isolado; versão compartilhável só liberada após triagem e verificação.
- Convite mínimo e manual/assistido aprovado; alto risco sem contato automático.
- Auditoria de decisões e acessos sem conteúdo sensível em logs.
- Backup e restauração em ambiente isolado testados; runbook de incidente e suspensão disponível.
- Fluxo ponta a ponta ensaiado com dados fictícios: trabalhador, operação, empresa, resposta, pedido opcional de orientação, erros e revogação.
- Responsáveis de plantão, limite de casos por dia e critério de pausa definidos.

## Evidências do Front (2026-11-17)

- Sessão entre abas (ClickUp 17tu7rpc7ru): commit `9171d4d`. A tela escuta `onAuthStateChange`; saída em outra aba ou token sem renovação volta à landing com aviso; outra conta no mesmo navegador recarrega a tela. Testes unitários verdes. **Pendente:** teste manual de duas abas pelo responsável no site de produção, sem gravar nada (passo a passo no roteiro do ensaio).
- Termos e aviso de privacidade: commit `6030adb`. Páginas públicas `/#termos` e `/#privacidade` com texto vindo de `src/content/legal/*.md`, marcador visível "Texto em revisão jurídica" e links no rodapé e nas caixas obrigatórias do cadastro. Sem texto jurídico. Conferido no navegador em desktop e 375 px, sem rolagem horizontal. **Pendente:** registro do aceite em tabela própria, a desenhar pelo Back e aprovar pelo responsável; até lá as caixas seguem obrigatórias e sem registro.
- Ensaio ponta a ponta: roteiro em `docs/runbooks/ENSAIO-PILOTO-PONTA-A-PONTA.md`, gerador em `scripts/ensaio-piloto.mjs`: uma instrução `DO` que termina sempre em exceção, no formato do `isolation_smoke`, para rodar em produção (banco único). **Ainda não rodado:** cada execução exige liberação escrita do responsável. O resultado entra aqui com data.
- Lacuna conhecida, decisão do responsável em 17/11: não há revogação do compartilhamento depois da liberação; o encerramento mantém a empresa vendo o caso (passo 9d do ensaio). Fica para depois do piloto.

## Decisão go/no-go

Registrar evidências, pendências, riscos residuais e aprovadores técnico, produto, operação e jurídico. Qualquer bloqueio mantém demonstração com dados sintéticos. Abertura de remoto, deploy público e credenciais exigem decisão humana conforme AGENTS.md.

## Riscos e rollback

Segurança/privacidade: exposição de dados sensíveis. Operação: triagem sem capacidade. Custo: backup, e-mail, suporte e horas humanas. Rollback: suspender novas entradas e convites, preservar casos existentes e trilhas, comunicar envolvidos conforme runbook aprovado.
