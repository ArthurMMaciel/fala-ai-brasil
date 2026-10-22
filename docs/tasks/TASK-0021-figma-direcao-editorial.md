# TASK-0021 — Direção editorial do Figma

- Status: concluída
- Prioridade: P1
- ClickUp: [TASK-0021](https://app.clickup.com/t/17tu7rp6397)
- Branch: `feat/figma-escuta-editorial`, criada de `origin/main` em 2026-10-20.
- Referência: [Figma](https://www.figma.com/design/v3InRnIyVZ36wF8Vavv6oI/Untitled?node-id=0-1).

## Escopo autorizado
Reproduzir a direção visual e os percursos do Figma na POC. Consulta à API oficial do ClickUp em 2026-10-20 não encontrou duplicidade; TASK-0020 trata correções anteriores de navegação/marca, incorporadas como pré-requisito nesta branch. Em 2026-10-21 o responsável autorizou concluir os cinco pontos da auditoria e criar commit local. Nenhum merge, push ou deploy incluído.

## Direção
- Tese visual: papel claro, verde profundo, títulos Lora e controles Inter; composição editorial, sem sombras decorativas.
- Conteúdo: inicial A com a fotografia original, explicação da jornada, limites e convite; página de empresas; quatro etapas da manifestação; consulta e acompanhamento; lista, detalhe e revisão da empresa.
- Interação: foco visível e deslocado ao novo título/erro, seleção explícita, revisão antes da confirmação; transições curtas com redução de movimento. Layout responsivo derivado das pranchas desktop.
- Cadastros, planos, assinaturas e telas complementares da POC permanecem acessíveis, com o mesmo sistema visual.

## Riscos e limites
Segurança/privacidade: formulários apenas demonstrativos e dados voláteis; nenhum relato real, envio externo, autenticação real ou persistência. Protocolo/chave exemplificam a consulta na mesma sessão, sem constituir controle de acesso de produção. Empresa recebe apenas a projeção demonstrativa compartilhável; rascunho empresarial não deve publicar retorno. Operação/custo: sem nova dependência de produção, serviço ou infraestrutura. Fontes e assets servidos localmente.

## Aceite
- Inicial A e empresas reproduzem composição, cores, fontes, imagem e conteúdo obtidos pelo plugin.
- Assunto, descrição, compartilhamento, revisão, confirmação e consulta têm navegação funcional em memória, validação e recuperação.
- Lista/detalhe/revisão empresarial usam conteúdo compartilhável e não publicam rascunho automaticamente.
- Preservar fluxos comerciais, retorno à inicial e ações demo anteriores.
- Validar desktop/mobile, teclado, ausência de overflow, build, testes e codificação.

## Referência disponível
Plugin retornou contexto detalhado e imagens para inicial A, empresas, assunto, descrição, validação, compartilhamento, revisão final, consulta, lista, detalhe e revisão empresarial. O bloqueio Starter inicial de confirmação/acompanhamento foi superado em 2026-10-21: ambas as referências foram obtidas e usadas no ajuste de composição. Textos e comportamentos foram adaptados à POC navegável, mantendo explícitos os limites da demonstração.

## Rollback
Reverter os commits desta tarefa e restaurar a versão anterior. Não há migração ou operação externa no produto.

## Retomada e auditoria — 2026-10-21

- Branch local confirmada e ativa: `feat/figma-escuta-editorial`. Não existe branch homônima no remoto consultado. A implementação editorial está no diretório de trabalho, sem commit, incluindo componentes, estilos, assets, testes e este documento.
- Após `git fetch origin`, `origin/main` está em `885e395` (merge do PR #2). O HEAD local `ddfe69f` e `origin/main` têm árvores idênticas (`git diff --stat HEAD origin/main` vazio), apesar de dois commits exclusivos locais e três remotos. Não foi feito merge, reset, push ou deploy.
- Consulta somente leitura à API oficial do ClickUp confirmou TASK-0021 `17tu7rp6397`, ainda em `to do`; o documento local indica trabalho em andamento. Alinhar esse status na continuidade.
- `npm.cmd test`: 24 testes aprovados. `npm.cmd run build`: TypeScript e Vite aprovados.
- Execução de `.codex-tmp-browser.mjs`: inicial, manifestação com validação/recusa de compartilhamento, confirmação, acompanhamento, lista/detalhe/revisão empresarial e retorno à inicial navegaram sem erros de JavaScript. Inicial e assunto em 390 px sem overflow horizontal. Capturas em `artifacts/figma/`. Isso não representa cobertura completa de teclado ou mobile das demais telas.
- O plugin voltou a fornecer contexto detalhado e screenshots de `3:15894` (confirmação) e `3:15987` (acompanhamento). O bloqueio Starter registrado acima é histórico, não o estado desta consulta.

### Pendências verificadas na auditoria inicial (resolvidas abaixo)

1. Confirmação (`Confirmation`, `src/editorial-experience.tsx`): o Figma coloca confirmação e credenciais à esquerda, continuidade/orientação à direita. A implementação reaproveita a lateral do formulário e coloca credenciais à direita. Falta a ação de guardar dados de acesso apresentada na referência; definir comportamento demonstrativo coerente.
2. Acompanhamento (`WorkerCase`, mesmo arquivo): o Figma prioriza histórico à esquerda e retorno/complemento à direita, com título próprio e aviso destacado sobre ação prevista. A implementação inverte a distribuição, acrescenta o original como destaque e não tem revisão do complemento antes de registrá-lo. A referência apresenta “Revisar complemento”; hoje o botão registra diretamente na sessão.
3. Lista empresarial (`CompanyList`, mesmo arquivo): filtro “Ação da empresa” usa `!item.queued`, incluindo o exemplo `EAB-2026-0031`, cuja pendência é aguardar informação revisada. Separar pendências por responsável antes de considerar o filtro concluído. “Pendências” no cabeçalho abre o primeiro caso fora da fila de revisão, sem mostrar uma lista filtrada.
4. Completar verificação visual das demais telas e validação de teclado, mobile empresarial, estados vazios e recuperação. O roteiro atual não cobre todo esse aceite.
5. Comparação com a versão anterior: as novas telas substituem a landing na branch; não há seletor lado a lado. Cadastros e operação legada continuam no renderer anterior, e seus mocks são separados dos exemplos editoriais (ADR-0008).
6. Antes de concluir: registrar a evolução na memória, alinhar tarefa, selecionar arquivos entregáveis (separando scripts temporários/capturas de produto) e criar commit local. Publicação remota e deploy continuam fora do escopo registrado.

## Conclusão — 2026-10-21

- Confirmação: composição 650/400 px com credenciais à esquerda e continuidade à direita; ação de cópia de dados fictícios com mensagem de sucesso e alternativa manual quando negada.
- Acompanhamento: histórico à esquerda, retorno/complemento à direita, destaque da ação prevista e título da referência. Registro original e autorização continuam disponíveis em seção recolhida do trabalhador. Registros novos não exibem revisão/encaminhamento fictícios como realizados.
- Complemento: edição, prévia focada, retorno para edição sem perda de texto e confirmação explícita. Somente a confirmação acrescenta um registro à sessão; não publica ou envia à empresa.
- Empresa: “Pendências” abre uma lista filtrada por ação da empresa; espera por informação revisada fica separada. Envio à revisão retira o caso dessa lista e atualiza o estado operacional, preservando o retorno público anterior. Filtros combinados e recuperação de lista vazia validados.
- Verificação: 25 testes automatizados aprovados; TypeScript/Vite aprovados. Roteiro Chromium verifica navegação com teclado, foco no erro/prévia, chave incorreta e recuperação, recusa/autorização, edição do complemento, conteúdo digitado renderizado como texto, cópia e falha de permissão, rascunho sem publicação, filas, filtros/estado vazio e fluxos em 320/390 px sem overflow da página. A tabela possui rolagem no próprio contêiner.
- Revisão visual: capturas desktop e mobile em `artifacts/figma/`; foto, indicador de seleção, fontes e marca local carregados sem falha. Não é uma auditoria WCAG completa nem validação multibrowser.
- Entrega: código, assets locais com licenças, testes, ADR e documentação. Capturas, contextos baixados, scripts temporários e original local da marca em `logo/` preservados e ignorados pelo Git.
- ClickUp: tarefa `17tu7rp6397` sincronizada como `complete` pela API oficial em 2026-10-21, com referência ao documento local.
- Comparação: a branch contém a proposta nova; a versão anterior permanece na `main`. Nenhum seletor de versões foi adicionado ao produto.

## Ajuste de integração com a jornada oficial — 2026-10-22

- A entrada do trabalhador na landing editorial voltou a abrir cadastro ou login antes de qualquer manifestação.
- Após o acesso, a área do trabalhador permanece responsável por listar relatos e iniciar o percurso oficial: contexto, categoria, relato, formas de comunicação, expectativa e revisão protegida antes da aprovação.
- O layout editorial continua sendo usado na landing; a jornada oficial legada permanece com a mesma fundação visual da branch.
- No painel administrativo, o seletor de persona e o identificador da equipe foram removidos visualmente do navbar; os controles permanecem alinhados à direita e o menu lateral usa verde escuro para manter contraste.
- Validação: `npm.cmd test` (25 testes) e `npm.cmd run build` aprovados. Nenhuma autenticação, persistência ou IA real foi adicionada.

## Ações da manifestação — 2026-10-22

- A área do trabalhador agora exibe `Cancelar manifestação`, `Excluir manifestação` e `Finalizar` na tela de detalhes.
- Cancelar e excluir ficam bloqueados após o encaminhamento; excluir remove o registro local e prepara a operação `DELETE` com `id` e status `canceled`.
- Finalizar fica disponível após resposta/ mediação e abre confirmação de satisfação; a alternativa cria uma nova manifestação ligada ao protocolo de origem no fluxo local.
- A implementação permanece demonstrativa e sem persistência externa nesta POC.

## Ajuste do Hub de parceiros — 2026-10-22

- `Empresas` passou a representar o diretório de organizações cadastradas na plataforma.
- `Possíveis clientes` representa somente empresas que sinalizaram interesse pelo botão de contato da vitrine.
- `Clientes` representa a carteira manual do parceiro; o vínculo é criado por `Marcar como cliente` no diretório.
- Botões de criação foram removidos dessas três listas. Ações de edição permanecem apenas em `Meu perfil` e `Conteúdos`.

### Reproduzir as verificações

1. Executar `npm.cmd test` e `npm.cmd run build`.
2. Iniciar `npm.cmd run dev`.
3. Executar `npm.cmd run test:editorial:browser` em um ambiente com Playwright/Chromium já disponíveis. Sem instalação no projeto, `PLAYWRIGHT_MODULE` pode apontar para a URL `file:///.../playwright/index.mjs` da instalação externa e `CHROMIUM_EXECUTABLE` para o executável. `EDITORIAL_URL` permite alterar a URL local; `EDITORIAL_ARTIFACTS` altera o diretório das capturas.
