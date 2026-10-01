# Runbook — Aumento de erros ou latência

**Detectar:** burn rate/SLO, P95/P99 ou taxa de erro acima do limite.

1. Declarar severidade pelo impacto e congelar mudanças relacionadas.
2. Segmentar por rota, versão, tenant, dependência e recurso, sem payload sensível.
3. Verificar deploy, saturação, pool, query, fila e integração.
4. Reverter, limitar carga ou degradar função não essencial conforme evidência.
5. Validar jornada sintética e observar recuperação por pelo menos 30 minutos.
6. Registrar causa, capacidade e ação preventiva.

**Escalar:** SEV-1 se fluxo principal indisponível ou risco de perda/inconsistência.
