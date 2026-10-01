# Runbook — Vazamento de credencial

**Detectar:** secret em Git/log, alerta de provedor ou uso anômalo. Tratar como SEV-1 quando acesso a produção/dados for possível.

1. Não copiar o segredo para tickets/chat. Registrar apenas identificador e escopo.
2. Revogar/rotacionar imediatamente; invalidar sessões/tokens derivados.
3. Conter permissões e bloquear origem suspeita sem destruir evidências.
4. Investigar uso desde a criação/última rotação e recursos alcançáveis.
5. Se houve acesso a dados, acionar fluxo de privacidade/jurídico e preservar timeline.
6. Remover a credencial do histórico quando necessário, sem tratar isso como revogação.
7. Corrigir origem, adicionar detecção e revisar privilégios.

**Fechar:** credencial antiga inválida, nova armazenada corretamente e impacto determinado.
