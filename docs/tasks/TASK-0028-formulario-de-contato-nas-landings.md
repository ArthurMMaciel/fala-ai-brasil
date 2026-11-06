# TASK-0028 — Oferecer contato em todas as landings

- Status: em-andamento
- ClickUp: [TASK-0028](https://app.clickup.com/t/17tu7rp9zgd)
- Área: Produto/Frontend/Backend/Privacidade
- Prioridade: P1 para apresentação e gestão inicial de contatos; ativação real sujeita ao gate de privacidade
- Impacto: receber dúvidas de quem ainda não quer criar conta
- Relacionadas: TASK-0026, TASK-0027, [ADR-0011](../adr/ADR-0011-solicitacoes-de-contato-e-acesso-da-equipe.md)

## Problema
As pessoas interessadas não têm um caminho único para conversar com a equipe antes de criar conta.

## Objetivo
Disponibilizar “Saiba mais / Entrar em contato” em todas as landings, com formulário simples e retorno claro.

## Escopo
- Campos: nome, telefone, e-mail e organização opcional; identificar a persona/origem da landing sem coletar dados da manifestação. Mensagem livre retirada por risco de receber relato sensível no canal comercial.
- Validar campos, informar finalidade e tratamento de dados, oferecer confirmação de envio e estados de erro/tentativa novamente.
- Persistir em `contact_solicitations`, com status `waiting_contact`/`contacted`, marcação de data e pessoa da equipe; não encaminhar a caixa externa nesta etapa.
- Criar aba “Solicitações contato” no menu da equipe da plataforma, com filtros de perfil (Trabalhador, Empresa, Parceiro, Patrocinador) e status; Intelligence entra como perfil Empresa com origem própria.
- Definir responsável, prazo interno de resposta, proteção contra abuso e retenção/exclusão antes de ativar dados reais.
- Registrar ADR e avaliação de privacidade antes de introduzir persistência, serviço de envio ou compartilhar dados com provedor.

## Fora de escopo
CRM, disparos de marketing, automação de resposta personalizada e envio de relatos/identidades ao ClickUp ou à caixa comercial.

## Critérios de aceite
- As cinco entradas públicas atuais (Trabalhador, Empresa, Parceiro, Intelligence e Patrocinador) mostram CTA de contato; o formulário mantém contexto da persona.
- Nome, telefone e e-mail são obrigatórios e validados; mensagem é opcional. O formulário orienta a não incluir relatos ou dados sensíveis.
- Sucesso mostra “Recebemos seu contato. Retornaremos assim que possível.”; falha não exibe sucesso nem perde os dados digitados.
- A equipe autorizada vê os dados mínimos na aba, sem logs de conteúdo ou credenciais; abuso e duplicidade recebem tratamento.
- Conta empresarial comum não consegue listar nem alterar solicitações; a equipe é provisionada fora do navegador.
- Formulário e mensagens são acessíveis por teclado e leitor de tela e funcionam em mobile.

## Riscos e dependências
Segurança: spam e abuso na RPC pública. Privacidade/dados: nome, telefone, e-mail e organização exigem finalidade, acesso restrito, base legal e retenção definidos; mesmo sem campo livre, nomes de organizações podem identificar pessoas. Operação: capacidade e prazo de resposta. Custo: armazenamento e atendimento manual; nenhum novo provedor de e-mail ou CRM nesta etapa.

## Implementação local em 2026-11-05

- As cinco landings mostram “Saiba mais” com formulário de nome, e-mail, telefone e organização opcional, validação e estados de erro/sucesso.
- Migration `20261105170000_contact_solicitations.sql`: tabela, RPC pública de envio com deduplicação de 15 minutos, RPCs de listagem/mudança de status limitadas à equipe e sem acesso direto à tabela.
- Aba administrativa com filtros e ação para marcar/desmarcar contato. O papel empresarial `admin` não autoriza esta aba.
- `npm test` (40 testes) e `npm run build` passaram. A migration ainda precisa de teste de autorização no banco e aplicação no ambiente aprovado.
- Pendente: base legal, aviso aprovado, prazo de retenção/exclusão, responsável operacional e provisionamento da primeira conta da equipe. Sem esses itens, não ativar coleta real.

## Testes e pronto
Validar sucesso, falha, campos inválidos, duplicidade/abuso, teclado e mobile; confirmar entrega sem dados sensíveis de teste. Pronto com fluxo end-to-end, política aprovada e instrução operacional de resposta.
