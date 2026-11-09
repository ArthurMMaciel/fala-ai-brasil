# Ambientes

| Ambiente | Dados | Acesso | Finalidade |
|---|---|---|---|
| Desenvolvimento | Sintéticos | Desenvolvedor | Implementação local |
| Homologação | Sintéticos/anonimizados aprovados | Restrito | Integração e aceite |
| Produção | Reais | Menor privilégio | Operação |

Configuração deve vir de variáveis/secret manager, com `.env.example` sem valores secretos. Bancos, chaves, domínios e integrações devem ser distintos entre ambientes. Promoção exige build imutável, migração versionada e rollback.

## Push direto na main (desde 2026-11-09)

Cada push na `main` vira deploy de Production na Vercel ([TASK-0041](../tasks/TASK-0041-protecao-do-push-direto-na-main.md)).

- Ative o hook uma vez por clone: `git config core.hooksPath .githooks`. Ele roda `npm test` e `npm run build` e bloqueia o push para `main` se algum falhar.
- `git push --no-verify` só em emergência, avisando o DevOps.
- O GitHub Actions (`ci`) repete testes e build em cada push e confere a produção depois de cada deploy. Uma falha chega por e-mail do GitHub.
- Se a produção quebrar: Instant Rollback na Vercel para o último deploy bom, feito pelo responsável, e correção na `main` em seguida.
