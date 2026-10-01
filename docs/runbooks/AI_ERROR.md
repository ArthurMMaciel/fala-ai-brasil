# Runbook — Erro de IA ou anonimização

**Detectar:** dado identificável residual, classificação perigosa, alucinação ou mudança de qualidade. Tratar vazamento/ação externa como SEV-1.

1. Desativar a função/modelo/prompt afetado por feature flag.
2. Bloquear envios externos ainda não aprovados e encaminhar casos para revisão humana.
3. Preservar versão do modelo/prompt e metadados mínimos; restringir acesso a entradas/saídas.
4. Identificar casos potencialmente afetados sem ampliar exposição.
5. Corrigir, reavaliar dataset e exigir aprovação antes de reativar.
6. Avaliar incidente de fornecedor/dados e obrigações de comunicação.

**Fechar:** avaliação atende thresholds, casos afetados foram revisados e fallback está funcional.
