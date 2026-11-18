# Deploy e rollback de Edge Function (primeira função: `cnpj-lookup`, ADR-0017)

- Estado: **preparado em 2026-11-18, nunca executado.** Não há nenhuma Edge Function no projeto.
- Quem executa: **o responsável, na máquina dele.** O deploy é um deploy em produção.
- O token desta máquina de desenvolvimento é de outra conta. Nenhum token nem segredo vai para a CI.
- Relacionadas: ADR-0017, TASK-0038, [ENVIRONMENTS](../devops/ENVIRONMENTS.md), [PILOT_SUSPENSION](PILOT_SUSPENSION.md).

## Fatos da plataforma (plano Free, conferidos em 2026-11-18)

Fontes: [limites](https://supabase.com/docs/guides/functions/limits) e [preço](https://supabase.com/docs/guides/functions/pricing).

| Item | Valor |
|---|---|
| Invocações | 500 mil por mês, incluídas no Free |
| Memória | 256 MB |
| Tempo total | 150 s |
| CPU | 2 s por requisição, sem contar espera de rede. Uma [página de ajuda](https://supabase.com/docs/guides/troubleshooting/edge-function-cpu-limits) cita 200 ms: "a confirmar" |
| Portas de saída | 25 e 587 bloqueadas |
| Logs | 1 dia de retenção ([TASK-0009](../tasks/TASK-0009-auditoria-e-observabilidade.md)) |
| Empacotamento sem Docker | `functions deploy --use-api`, com limite de 5 MB por função |

## Antes do deploy (todos obrigatórios)

1. **ADR-0017 aceita** pelo responsável, incluindo a decisão sobre usar provedores sem termos de uso.
2. **Banco pronto.** As migrations de `private.cnpj_cache`, `private.cnpj_lookup_quota` e `preregister_company*` estão aplicadas e conferidas no SQL Editor. A ordem é sempre banco, depois função, depois front.
3. **Front tolerante já em produção.** Qualquer resposta diferente de 200 da função, inclusive 404, cai no preenchimento manual (ADR-0017, D7 e D8).
4. **Código revisado pelo DevOps** (checklist abaixo). A CI precisa estar verde no commit, incluindo o job `functions-test`.
5. **A cópia local do repositório é o commit revisado:**
   - `git status` limpo;
   - `git log -1` igual ao SHA aprovado.

## Passo a passo (PowerShell, na máquina do responsável)

1. Conferir se a CLI tem o empacotamento sem Docker. A ajuda precisa listar `--use-api`:

   ```bash
   npx supabase functions deploy --help
   ```

2. Remover o token de ambiente deste terminal, para não usar a conta errada:

   ```powershell
   Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
   ```

3. Entrar. O navegador abre, e o token fica só nesta máquina. Ninguém cola token em chat ou arquivo:

   ```bash
   npx supabase login
   ```

4. Conferir que o acesso é à conta certa, só lendo. Na primeira vez, a lista deve vir vazia:

   ```bash
   npx supabase functions list --project-ref <ref-de-producao>
   ```

   O `<ref-de-producao>` é o `SUPABASE_PROJECT_REF` do `.env`, um valor público.

5. Deploy, com a opção de JWT definida na revisão:

   ```bash
   npx supabase functions deploy cnpj-lookup --project-ref <ref-de-producao> --use-api
   ```

   - Se a revisão decidir que a função confere o JWT sozinha, acrescentar `--no-verify-jwt`. Isso é provável com as chaves `sb_publishable_` que o front usa.
   - A opção fica escrita no comando para não depender do que o `config.toml` diz.

6. **Secrets: nenhum.** A ADR-0017 não usa chave de provedor. `SUPABASE_URL` e as chaves do projeto já são injetadas pela plataforma. Não rodar `secrets set`.

7. Conferir sem login. Esperado: `401`:

   ```powershell
   curl.exe -s -o NUL -w "%{http_code}" -X POST https://<ref-de-producao>.supabase.co/functions/v1/cnpj-lookup -H "content-type: application/json" -d "{}"
   ```

8. Conferir com login:
   - No site, com uma conta de teste, buscar um CNPJ público de grande empresa. O resultado deve trazer só os campos da lista branca (D4).
   - Em Edge Functions > `cnpj-lookup` > Logs, conferir que as linhas trazem só o resultado, o provedor e o tempo, sem CNPJ, conta nem IP (D10).

9. Registrar na TASK-0038:
   - a data;
   - a versão que o `functions list` mostra;
   - o SHA do commit;
   - o resultado dos passos 7 e 8.

10. Sair, para não deixar o token de acesso na máquina:

    ```bash
    npx supabase logout
    ```

11. Num push liberado, trocar `CNPJ_LOOKUP_REQUIRED` para `"true"` em `.github/workflows/ci.yml`. A partir daí, o `production-smoke` exige o 401.

## Rollback

O Instant Rollback da Vercel **não** volta a função. O banco também não volta, e o cache e a cota seguem como estão.

- **Contenção (mais rápida):** apagar a função. O front recebe 404 e cai no preenchimento manual:

  ```bash
  npx supabase functions delete cnpj-lookup --project-ref <ref-de-producao>
  ```

  Depois, num push liberado, voltar `CNPJ_LOOKUP_REQUIRED` para `"false"`. Sem isso, o próximo `production-smoke` falha com 404.
- **Voltar uma versão:** fazer checkout do commit anterior aprovado (`git switch --detach <sha>`), repetir os passos 2 a 7 e voltar à `main`. Se existe um botão no painel para voltar versão de função é "a confirmar". Este roteiro não depende dele.
- Registrar no incidente quem fez, quando e por quê.

## Checklist de revisão do código (DevOps, antes do passo 4 de "Antes do deploy")

- **Autenticação (D3):** recusa sem usuário. A conta precisa ter `sub` e `role = authenticated`. Só a chave pública não basta, e a validação é feita dentro da função, sem depender só do `verify_jwt`. O desenho segue o que a documentação atual diz sobre chaves novas e JWT, "a confirmar" na revisão.
- **CNPJ:** vai só no corpo do POST (D2). Os dígitos são validados antes de qualquer chamada externa, com a mesma regra de `private.valid_cnpj`.
- **Cota (D9):** é conferida antes da chamada externa, e a tabela não guarda o CNPJ.
- **Provedores (D7):** Minha Receita, depois BrasilAPI, depois `manual`. Timeout de 4 s por provedor com `AbortController`, e no máximo uma reserva.
- **Lista branca (D4) e pessoa física (D5):** o resto da resposta é descartado em memória. Natureza jurídica de empresário individual ou MEI não devolve nem guarda nome.
- **Logs (D10):** nenhum `console.*` com CNPJ, conta, IP, corpo da requisição ou da resposta. O teste confere o texto dos logs.
- **Erros:** a resposta não ecoa a entrada nem a mensagem do provedor.
- **CORS:** só a origem de produção na Vercel, mais `localhost` se for necessário em desenvolvimento.
- **Chave de serviço:** usada só para gravar o cache e a cota, e nunca devolvida nem registrada em log.
- **Dependências:** imports `npm:` ou `jsr:` com versão exata e `deno.lock` no Git. Nada de URL remota sem versão.
- **Testes:** `fetch` simulado. Os testes rodam sem permissão de rede, e o job da CI não concede `--allow-net`.
