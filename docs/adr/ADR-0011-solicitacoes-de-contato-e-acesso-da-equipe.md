# ADR-0011 — Solicitações de contato e acesso da equipe

- Status: aceita para implementação local; ativação com dados reais condicionada a decisões de privacidade e provisionamento da equipe
- Data: 2026-11-05
- Tarefa: [TASK-0028](../tasks/TASK-0028-formulario-de-contato-nas-landings.md) · [ClickUp](https://app.clickup.com/t/17tu7rp9zgd)

## Contexto

O responsável solicitou uma seção “Saiba mais” em cada landing, persistência em `contact_solicitations` e uma aba administrativa para acompanhar pedidos por perfil e status. O papel `admin` existente representa também o painel de uma empresa; usá-lo como autorização global exporia contatos de outras personas.

## Decisão técnica

1. Coletar apenas nome, e-mail, telefone com DDD, organização opcional, perfil e origem da landing. Não oferecer texto livre para reduzir a entrada de relatos e dados psicossociais no canal comercial.
2. O perfil de Intelligence é `company` com origem `intelligence`, pois o filtro de perfil solicitado contém trabalhador, empresa, parceiro e patrocinador.
3. Gravar em `public.contact_solicitations` com status `waiting_contact` ou `contacted`, data de criação e, quando contatado, data e identidade da pessoa da equipe que mudou o status.
4. Bloquear acesso direto à tabela por `anon` e `authenticated`. Inserção pública apenas por RPC com validação no banco, honeypot e deduplicação por e-mail em 15 minutos. Leitura e atualização apenas por RPC que exige vínculo em `private.platform_admins`. A conta empresarial não ganha esse vínculo automaticamente.
5. Integrantes da equipe são provisionados por operação controlada, usando o ID da conta Supabase Auth em `private.platform_admins`. Não há cadastro público de administrador. O navegador usa somente a chave pública existente; nenhuma chave de serviço entra no frontend.
6. Nenhum e-mail automático, CRM ou fornecedor novo recebe os dados nesta etapa. O contato é feito manualmente pela equipe e marcado na aba.

## Privacidade e riscos

- Finalidade declarada no formulário: responder ao pedido de contato. O canal não recebe relatos; a interface orienta a usar o fluxo próprio de manifestação.
- Dados: nome, e-mail, telefone e organização são dados pessoais e ficam no Supabase já adotado pelo projeto. Só a equipe autorizada deve vê-los. Não registrar payload ou credenciais em logs.
- A RPC pública ainda pode sofrer abuso com e-mails diferentes; a proteção atual é adequada apenas para piloto de baixo volume e exige monitoramento. Se houver abuso, revogar `EXECUTE` de `submit_contact_solicitation` para `anon` e `authenticated` e desativar o formulário.
- Base legal, texto completo do aviso, prazo de retenção/exclusão, atendimento a direitos do titular e responsável operacional dependem de decisão humana. **Não ativar coleta de dados reais nem promover a migration para produção antes dessas definições.**

## Alternativas consideradas

- Reutilizar o papel empresarial `admin`: rejeitado por permitir leitura global a empresas.
- Enviar diretamente por e-mail/CRM: adiado por adicionar destinatário, custo e superfície de exposição.
- Campo de mensagem livre: adiado por risco de receber conteúdo sensível fora do fluxo de manifestação.

## Verificação e rollback

- Testar validação, envio, duplicidade, filtragem, troca de status e negação de leitura/alteração por contas comuns e anônimas no ambiente de teste.
- Se a função pública precisar ser desligada, revogar sua execução. A reversão estrutural da migration só é segura antes de haver registros; após isso, exportar/reter/excluir conforme decisão aprovada antes de remover a tabela.
