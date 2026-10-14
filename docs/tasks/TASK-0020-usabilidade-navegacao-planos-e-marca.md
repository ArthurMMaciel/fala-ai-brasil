# TASK-0020 — Usabilidade, navegação contextual e marca oficial

- Status: em-andamento
- Prioridade: P1
- ClickUp: [TASK-0020](https://app.clickup.com/t/17tu7rp3wa5)
- Área: Frontend/UX

## Pedido e contexto
Corrigir botões sem resposta, integrar soluções e planos à landing conforme a persona escolhida no topbar e substituir o monograma genérico pela logo oficial fornecida em `logo/Proposta Logo Escuta ai Brasil (1).pdf`. A marca deve sempre retornar à landing. CI/CD fica fora deste pedido; Vercel mantém o deploy existente.

## Consulta ao ClickUp
Lista oficial consultada em 2026-10-14: não há tarefa duplicada para esta correção. TASK-0015/0016 concluídas registram as visões comerciais; TASK-0019 continua responsável pelas regras demonstrativas de cadastro e assinatura.

## Auditoria inicial
- React monta a landing no mesmo elemento que as outras rotas sobrescrevem via `innerHTML`, sem desmontagem: retorno à landing pode quebrar eventos e renderização.
- Soluções usam persona comercial separada da seleção da landing.
- Marca genérica `EA` aparece no cabeçalho; o PDF oficial contém aplicação horizontal vetorial.
- Há botões de avaliação, acompanhamento e operação sem handler; ações não implementadas não devem parecer disponíveis.
- Após recuperar a codificação, três rótulos de cadastro voltaram a conter a nomenclatura antiga; revisar também os textos renderizados.

## Tese visual
Cabeçalho calmo com a marca oficial, seleção de persona e acesso; hierarquia clara, conteúdo útil, espaçamento consistente e planos comparáveis sem decoração excessiva.

## Plano de conteúdo
Apresentação da persona; benefícios/solução; planos pertinentes ou acesso gratuito; ação para cadastro com plano preservado. Preços e capacidades comerciais continuam demonstrativos.

## Tese de interação
Seleção de persona atualiza apresentação e planos juntos; ações para planos levam à seção da mesma página; transições curtas de foco/seleção e entrada respeitam redução de movimento. Marca retorna à landing com eventos funcionais após qualquer rota.

## Aceite e validação
- Planos acompanham cada persona do topo; trabalhador mantém acesso gratuito.
- Escolha de plano abre cadastro do perfil correto com plano selecionado.
- Marca oficial aparece nos dois cabeçalhos, é acessível e retorna à landing repetidamente.
- Botões têm resposta verificável ou estado indisponível com explicação.
- Validar teclado/mobile e caminhos landing → cadastro/login → marca → troca de persona → plano.
- Testes proporcionais, build e verificação de codificação aprovados.

## Riscos e limites
Sem novas dependências, integrações, persistência, controles de autenticação/autorização ou custo. O principal risco é regressão na transição React/HTML e divergência de persona/plano. Dados permanecem fictícios em memória. Comandos operacionais não enviam contatos externos.

## Rollback
Reverter o commit desta correção; manter as correções de nomenclatura/codificação da PR #1.

## Entrega e limites de validação
- Cabeçalhos usam a aplicação horizontal vetorial oficial; símbolo extraído do mesmo PDF substitui a arte genérica. Logo é um botão acessível de retorno à landing.
- Soluções e planos estão na mesma página e acompanham a persona do topo. Trabalhador recebe bloco gratuito; oferta comercial mantém avisos de hipótese. Catálogo compartilhado com cadastro elimina divergência de IDs, incluindo projeto sob proposta em Intelligence.
- Corrigida desmontagem/remontagem React antes de substituição por HTML. Rotas legadas de soluções retornam à landing contextual. Sessão demonstrativa reconhecida com Minha área/Sair.
- Avaliação e finalização do caso registram resposta em memória, com feedback visível e finalização idempotente. Operações reais ausentes têm estado desabilitado e explicação; editar texto demonstrativo move o foco para o campo.
- Navegador integrado indisponível (`iab` sem conexão). Testes executam o renderer legado em ambiente simulado e renderizam o componente React para HTML; não substituem revisão visual, teclado e mobile em navegador.
- A revisão de responsividade é estática; foco visível, destino de skip-link, alvos de toque e redução de movimento incluídos. Aceite visual será feito no preview da PR.
- `npm.cmd test`: 21 testes aprovados, incluindo retorno repetido à landing, todos os planos no cadastro correto, conteúdo das cinco personas, finalização idempotente e sessão/upgrade preservados.
- `npm.cmd run build`: aprovado. `git diff --cached --check`: sem erros de whitespace. Sem novas dependências.
