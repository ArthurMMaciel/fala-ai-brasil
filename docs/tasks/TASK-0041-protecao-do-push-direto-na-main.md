# TASK-0041 — Proteção do push direto na main

- Status: em-andamento
- ClickUp: https://app.clickup.com/t/17tu7rpcgfb
- Área: DevOps
- Prioridade: P0
- Estimativa: 0,5 dia
- Impacto: cada push na `main` vira deploy de Production na Vercel. Sem esta proteção, um teste quebrado chega aos usuários.

## Problema
Em 2026-11-09 o responsável decidiu que Front e Back passam a trabalhar direto na `main`, sem branch e sem PR, para cumprir a meta do MVP em 30/11. A Vercel publica cada push em produção. Até agora, a revisão de PR e os testes rodados à mão eram a única barreira.

## Objetivo
Barreiras baratas e sem custo:
1. Bloquear no próprio computador o push que quebra os testes ou o build.
2. Alarmar quando um push na `main` quebrar os testes no ambiente limpo, ou quando o deploy de Production servir algo inesperado.

## Escopo
- `.githooks/pre-push`: em push para `main`, roda `npm test` e `npm run build` e bloqueia se algum falhar. Bloqueia também quando o commit enviado não é o HEAD da pasta, porque nesse caso os testes rodariam em outro código. Push para outras branches e deleções passam direto.
- `.github/workflows/ci.yml`, sem secrets e sem custo, porque o repositório é público:
  - `test-build`: em push na `main` e em PR, roda `npm ci`, `npm test`, `npm run build` e confere que o `dist/index.html` não tem script inline (CSP).
  - `production-smoke`: no `deployment_status` de Production com sucesso, enviado pela Vercel, confere a landing (200), o bundle principal (200) e o cabeçalho de CSP servido, que precisa ser igual ao `vercel.json` do commit.
- Ativação do hook, uma vez por clone: `git config core.hooksPath .githooks`.

## Fora de escopo
- Proteção de branch no GitHub com checagem obrigatória: ela impediria o push direto, que é o modelo decidido.
- Testes dos smoke SQL no CI: exigem Supabase em Docker no runner. Fica como melhoria.
- Teste de console da landing no CI: exige navegador. O DevOps confere o console a cada deploy (item 2 da fila).

## Opção mais forte, para decisão do responsável
Trocar o comando de build da Vercel para `npm test && npm run build`, por `buildCommand` no `vercel.json`. Um push com teste quebrado faria o build falhar, e a produção ficaria no deploy anterior. Não depende de hook local nem de `--no-verify`. O custo é de cerca de 6 s por build. É mudança de configuração de produção, então depende de autorização.

## Critérios de aceite
- O hook bloqueia o push para `main` com teste ou build quebrado e libera com tudo verde. Testado com um `npm` falso que falha no teste e no build.
- O workflow passa na `main` atual, e o `production-smoke` passa contra a produção atual. Script rodado à mão contra fala-ai-brasil.vercel.app em 2026-11-09.

## Riscos
- O hook roda na pasta como está. Alterações não commitadas de outra sessão na mesma pasta podem mascarar o resultado. O hook avisa, e o CI roda no commit limpo.
- `git push --no-verify` pula o hook. Uso só em emergência, avisando o DevOps.
- O `production-smoke` usa a URL pública de produção. Se o domínio mudar, atualizar `SITE` no workflow.

## Segurança
Nenhum secret. Permissão `contents: read`. As actions oficiais (`checkout`, `setup-node`) ficam na versão v4.

## Rollback
Apagar `.github/workflows/ci.yml`. Para o hook: `git config --unset core.hooksPath`.

## Testes necessários
Hook com entradas simuladas (push para main, outra branch, commit diferente do HEAD, deleção, teste falhando, build falhando). Script do smoke contra a produção atual. Primeiro push na `main` com o workflow ativo, conferindo o resultado em Actions.

## Definição de pronto
Hook ativo na pasta de trabalho de Front e Back, workflow verde na `main` e primeiro `production-smoke` verde depois de um deploy.
