# TASK-0023 — Trocar o SMTP do Supabase para Gmail na demonstração

- Status: pronta
- ClickUp: [TASK-0023](https://app.clickup.com/t/17tu7rp7qbv)
- Área: Operação/Auth
- Prioridade: P0
- Prazo: 2026-10-30 (apresentação)
- Estimativa: 1 hora
- Impacto: sem isso, nenhum cadastro novo recebe e-mail de confirmação
- Relacionada: [TASK-0022](TASK-0022-mvp-supabase-cadastro-e-confirmacao.md), [ADR-0009](../adr/ADR-0009-supabase-auth-e-banco-inicial-mvp.md)

## Problema
O cadastro real falha com `Error sending confirmation email`: o Resend sem domínio verificado só entrega para o e-mail do dono da conta.
## Contexto
Não há domínio próprio do produto até sexta. O Gmail do responsável, com senha de app, autentica o envio pelo próprio Google (SPF/DKIM válidos), sem custo e com limite diário suficiente para a demonstração.
## Objetivo
Cadastros novos recebem o e-mail de confirmação na caixa de entrada.
## Escopo
- Ativar verificação em duas etapas e gerar senha de app na conta Google (feito pelo responsável).
- Supabase → Authentication → SMTP: `smtp.gmail.com`, porta 465, usuário e remetente = Gmail, senha = senha de app, nome do remetente "Escuta Aí Brasil".
- Conferir Site URL/Redirect URLs (`http://127.0.0.1:5173/**`, `http://localhost:5173/**` e a URL da Vercel).
- Colar o modelo `supabase/templates/confirmacao-cadastro.html` em "Confirm signup".
- Cadastro de teste ponta a ponta e registro do resultado.
## Fora de escopo
Domínio próprio e retorno ao Resend (pendência antes do piloto).
## Critérios de aceite
- Cadastro novo recebe e-mail em até 1 minuto, fora do spam, e o link confirma e loga.
- Reenvio de confirmação funciona.
- Nenhuma senha de app no repositório, no chat ou em logs.
## Riscos
Remetente pessoal visível para clientes; cadastro aberto sem CAPTCHA pode gerar abuso e bloqueio temporário da conta Google.
## Dependências
Acesso do responsável à conta Google e ao painel do Supabase.
## Segurança
Senha de app revogável, guardada só no painel do Supabase.
## Dados envolvidos
E-mail de quem se cadastra (fictício na demonstração).
## Observabilidade
Logs de Auth do Supabase.
## Rollback
Revogar a senha de app e voltar ao SMTP anterior no painel.
## Testes necessários
Cadastro ponta a ponta com e-mail real de teste; reenvio; link expirado.
## Definição de pronto
Critérios atendidos e ADR-0009 atualizada com a pendência de domínio próprio antes do piloto.
