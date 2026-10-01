# TASK-0011 — Verificar contatos empresariais antes de enviar relatos

- Status: proposta
- Área: Produto/Integrações/Segurança
- Prioridade: P1
- Estimativa: 3–5 dias
- Impacto: evita envio a terceiro incorreto ou malicioso

## Problema
Formato válido de e-mail/telefone não comprova que o destino pertence à empresa.
## Contexto
O novo fluxo permite ao manifestante sugerir múltiplos contatos.
## Objetivo
Separar candidato de contato verificado e exigir aprovação antes de comunicação.
## Escopo
Normalização, deduplicação, origem, verificação de domínio/representante, estado e revisão humana.
## Fora de escopo
Automação de contato em massa.
## Critérios de aceite
Nenhum relato é enviado a contato apenas sintaticamente válido; histórico de verificação existe; erros são claros.
## Riscos
Phishing, retaliação, entrega a pessoa envolvida e enumeração.
## Dependências
TASK-0007/0008/0009 e decisão de canal.
## Segurança
Rate limit, masking, verificação independente e conteúdo mínimo no primeiro contato.
## Dados envolvidos
E-mails/telefones corporativos e evidências de verificação.
## Observabilidade
Taxa de validação, rejeição, entrega e denúncia de contato incorreto.
## Rollback
Suspender envios e retornar fluxo à revisão manual.
## Testes necessários
Formato, duplicidade, domínio falso, takeover, retries e opt-out.
## Definição de pronto
Política aprovada, implementação testada e runbook de envio incorreto.
