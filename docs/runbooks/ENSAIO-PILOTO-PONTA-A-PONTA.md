# Ensaio ponta a ponta do piloto (TASK-0033)

Roteiro reproduzível, com dados fictícios, do fluxo que o piloto fechado vai operar. Evidência para o gate da TASK-0033.

## O que o ensaio cobre

| Etapa | Quem | O que se confere |
|---|---|---|
| 1 | Trabalhador | Manifesta com versão compartilhável e pedido de revisão; erro sem versão compartilhável. |
| 2 | Empresa A | Antes da liberação não vê o caso, não responde e não decide como Operação. |
| 3 | Operação | Erro ao reter sem motivo; libera a versão compartilhável. |
| 4 | Empresas A e B | A vê só a versão autorizada; o original não chega nem pela lista, nem pelo histórico, nem pela tabela. B não vê, não responde e não lê o histórico do caso de A. |
| 5 | Empresa A | Responde; a resposta fica com a equipe; segunda resposta recusada; trabalhador ainda não vê. |
| 6 | Operação | Devolve com motivo (a empresa vê o motivo), libera a nova resposta com descrição e corrige a descrição; erros de tamanho. |
| 7 | Trabalhador | Vê só a resposta liberada, com a descrição corrigida; avalia uma vez; não avalia a resposta devolvida. Empresa nunca recebe a descrição; satisfação "sem dado" abaixo de 3 avaliações; empresa B não avalia. |
| 8 | Operação | Leitura do original exige justificativa e fica registrada na trilha. |
| 9 | Trabalhador | Retirada antes da liberação: a empresa nunca vê. Encerramento depois da liberação: ver lacuna abaixo. |

## Lacuna conhecida (decisão do responsável em 17/11)

**Não há revogação do compartilhamento depois da liberação.** O responsável decidiu, em 2026-11-17, deixar a revogação para depois do piloto. Conferido no código na mesma data:
- `close_complaint` (versão vigente em `20261106130100`) só retira (`canceled`) antes da liberação; depois dela, encerra (`closed`).
- `list_company_complaints` (versão vigente em `20261109170000`) devolve à empresa casos `closed`, com a versão compartilhável e o histórico.
- Não existe RPC nem botão de revogação.

O passo 9d documenta o comportamento atual (a empresa continua vendo). O ensaio cobre só a retirada antes da liberação e o encerramento depois dela.

## Como rodar

Banco único (produção), por decisão do responsável. **Cada execução exige liberação escrita do responsável**, com o script mostrado antes e o resultado registrado depois.

O ensaio é uma única instrução `DO` gerada por `scripts/ensaio-piloto.mjs`, no mesmo formato do `supabase/tests/isolation_smoke.sql`. Ela:
- cria quatro contas fictícias (trabalhador, empresa A, empresa B e equipe) pelo mesmo gatilho de cadastro de produção, com e-mails `ensaio-*-<execução>@example.com`, nomes marcados "TESTE" e CPF/CNPJ gerados a cada execução;
- com a ADR-0012 aplicada, verifica o representante da empresa A pela mesma RPC da fila da Operação;
- assume o papel de cada pessoa como o PostgREST faz (`set local role authenticated` e `request.jwt.claims`), passando pelas mesmas RPCs e políticas de RLS que o front usa;
- roda o corpo numa subtransação (bloco com tratador de exceção), onde COMMIT e ROLLBACK são proibidos pelo Postgres, e termina **sempre** em exceção: nada fica gravado, inclusive em `auth.users`;
- devolve o resultado na mensagem da exceção: `RESULTADOS aprovado=true|false (n de m ok)` e uma linha por passo (`[ok]` ou `[FALHA]`, esperado, obtido).

```bash
node scripts/ensaio-piloto.mjs > <pasta-temporaria>/ensaio.sql
npx supabase db query --linked < <pasta-temporaria>/ensaio.sql
```

Critério: `aprovado=true`. Uma linha "FALHA INESPERADA" indica que o ensaio parou naquele ponto; os passos seguintes não rodaram.

O que o ensaio cria e desfaz na mesma instrução: 4 usuários em `auth.users` e seus perfis (1 trabalhador, 2 empresas com assinatura de teste, 1 integrante da equipe), 2 manifestações com originais, versões e eventos, 2 respostas da empresa, decisões de revisão, 1 avaliação, 1 registro de acesso ao original e, com a ADR-0012, 1 verificação de representante.

Efeitos que o rollback não desfaz:
- a sequência `complaint_protocol_seq` avança 2 números (protocolos pulados);
- durante a execução (segundos), as linhas novas ficam bloqueadas para outras transações, mas não visíveis a ninguém: outras sessões nunca leem dados não confirmados. Por isso a empresa de teste **não aparece** no diretório nem no ranking público;
- nenhuma migration do repositório chama serviço externo a partir de gatilho (sem `pg_net`, `http` ou webhooks). Webhooks configurados só no painel do Supabase não aparecem no repositório e não foram conferidos.

Não há limpeza a fazer depois: não sobra nada para apagar.

Teste de duas abas (sessão encerrada em outra aba): feito manualmente pelo responsável, com a própria conta, no site de produção, sem gravar nada: abrir a área logada em duas abas, sair em uma e conferir que a outra volta à página inicial com o aviso "Sua sessão terminou".

## Conferência no navegador

O SQL prova regras e permissões. A conferência visual (portal do trabalhador, da empresa e da Operação em desktop e 375 px) usa contas fictícias de dev com sessão por link mágico, sem senha. Ela depende do projeto Supabase de dev e fica registrada na TASK-0033 com data e resultado.
