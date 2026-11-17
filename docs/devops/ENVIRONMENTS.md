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
- A Vercel roda `npm test && npm run build` (`buildCommand` no `vercel.json`): teste quebrado não publica, e a produção fica no deploy anterior.
- O GitHub Actions (`ci`) repete testes e build em cada push e confere a produção depois de cada deploy. Uma falha chega por e-mail do GitHub.
- Se a produção quebrar: Instant Rollback na Vercel para o último deploy bom, feito pelo responsável, e correção na `main` em seguida.

## Banco único (decisão do responsável em 2026-11-17, comunicada pelo Gestor)

O projeto fica no plano Free, com um único banco: o de produção (`ouvira-brasil`, ref `nkxfhctqfqroyfmihsns`). Não há projeto de desenvolvimento nem Docker local. Os testes de banco rodam em produção, em transação com `ROLLBACK`, e o ensaio do Front usa só contas fictícias, com limpeza confirmada. As regras de cada teste ficam no próprio script (por exemplo, `supabase/tests/isolation_smoke.sql`).

- **Cada execução contra produção** (teste, `db query`, `db dump`, `db push`) depende de liberação escrita do responsável. As exceções estão registradas na [rotina de backup](../runbooks/BACKUP_FREE.md).
- **Nenhum `supabase link` para outro projeto** e nenhum `--project-ref` apontando para outro ref na pasta principal. O link de `supabase/.temp` é o que o `db push` liberado usa.
- **CLI v4:** `--remote` sem valor mira o projeto linkado, que é a produção. `--db-url`, `--linked` e `--local` foram removidos na v4 ([db query](https://supabase.com/docs/reference/cli/supabase-db-query)). Se a CLI subir de versão, revisar os comandos documentados antes de rodá-los.
- **Credenciais:**
  - A senha do banco fica no gerenciador de senhas do responsável. Ela é digitada quando a CLI pede ou definida por ele na variável `SUPABASE_DB_PASSWORD`, só no terminal da sessão.
  - Nunca vai para arquivo versionado nem para a linha de comando, porque a linha aparece em histórico e em transcript.
  - Ninguém cola ou imprime URL com senha, chave secret ou senha de conta de teste em chat, task, commit ou log.
- **Sem Docker:** `db dump` depende de Docker, porque a CLI roda o `pg_dump` num container ([db dump](https://supabase.com/docs/reference/cli/supabase-db-dump)). Também deixam de funcionar `supabase start` e `db query --local`. Ver a [rotina de backup](../runbooks/BACKUP_FREE.md).
