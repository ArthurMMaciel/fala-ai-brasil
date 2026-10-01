# Runbook — Integração externa indisponível

**Detectar:** timeout, erro, webhook parado ou fila crescendo. Severidade depende da jornada; comunicação atrasada normalmente SEV-2.

1. Identificar provedor/operação e suspender retries agressivos.
2. Confirmar status do fornecedor e mudanças de credencial/config.
3. Manter jobs em fila idempotente; ativar circuit breaker/fallback aprovado.
4. Comunicar atraso sem afirmar entrega; não duplicar mensagem manualmente sem reconciliação.
5. Retomar gradualmente, respeitando rate limit, e reconciliar por idempotency key.
6. Medir backlog, duplicidades e falhas permanentes.

**Fechar:** backlog zerado/reconciliado e fornecedor estável; revisar SLA e fallback.
