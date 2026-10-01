# Ambientes

| Ambiente | Dados | Acesso | Finalidade |
|---|---|---|---|
| Desenvolvimento | Sintéticos | Desenvolvedor | Implementação local |
| Homologação | Sintéticos/anonimizados aprovados | Restrito | Integração e aceite |
| Produção | Reais | Menor privilégio | Operação |

Configuração deve vir de variáveis/secret manager, com `.env.example` sem valores secretos. Bancos, chaves, domínios e integrações devem ser distintos entre ambientes. Promoção exige build imutável, migração versionada e rollback.
