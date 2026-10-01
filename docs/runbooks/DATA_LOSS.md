# Runbook — Perda ou corrupção de dados

**Detectar:** contagem/integridade divergente, relato ausente, corrupção ou exclusão indevida. **Severidade:** SEV-1.

1. Interromper escritas afetadas e preservar banco, logs e backups; não restaurar sobre a única cópia.
2. Determinar intervalo, tabelas/tenants e causa provável.
3. Criar ambiente isolado e validar backup/checksum antes do restore.
4. Escolher recuperação point-in-time conforme RPO e reconciliar transações posteriores.
5. Validar constraints, amostras autorizadas e contagens; documentar dados irrecuperáveis.
6. Acionar segurança/privacidade/jurídico quando aplicável e comunicar com precisão.
7. Corrigir causa e executar novo restore drill.

**Fechar:** integridade verificada, impacto registrado e prevenção atribuída.
