# Runbook — Suspeita de acesso indevido

**Detectar:** alerta de autorização, usuário/tenant incompatível ou relato de pessoa afetada. **Severidade:** SEV-1 para conteúdo sensível.

1. Declarar incidente de segurança/privacidade e restringir a equipe por necessidade.
2. Preservar logs/auditoria; não contatar suspeito antes da estratégia de contenção.
3. Revogar sessões, bloquear conta/rota afetada e interromper exportações.
4. Determinar recursos, tenants, atores, intervalo e dados acessados/alterados.
5. Corrigir política/consulta e testar IDOR/escalada antes de reabrir.
6. Avaliar notificações legais e comunicação às pessoas afetadas com responsáveis.
7. Monitorar recorrência e realizar pós-incidente.

**Fechar:** vetor contido, escopo documentado, acesso corrigido e decisões de comunicação registradas.
