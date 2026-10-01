# Runbook — Banco indisponível

**Detectar:** readiness falha, pool esgotado, conexão/latência/replicação anormal. **Severidade:** SEV-1 se escrita/leitura crítica indisponível.

1. Declarar incidente e impedir migrações/deploys.
2. Confirmar provedor, rede, storage, conexões e mudança recente.
3. Reduzir carga não essencial; não executar restart/failover destrutivo sem evidência.
4. Aplicar failover documentado ou restaurar serviço do provedor.
5. Validar integridade, migrações e transações pendentes; reconciliar jobs idempotentes.
6. Comunicar indisponibilidade sem expor esquema/dados.
7. Preservar métricas/logs e revisar capacidade, timeout e alertas.

**Fechar:** consistência verificada, backup atual confirmado e filas normalizadas.
