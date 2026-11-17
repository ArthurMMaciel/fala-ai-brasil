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

## Lacuna registrada

**Não há revogação do compartilhamento depois da liberação.** Conferido no código em 2026-11-17:
- `close_complaint` (versão vigente em `20261106130100`) só retira (`canceled`) antes da liberação; depois dela, encerra (`closed`).
- `list_company_complaints` (versão vigente em `20261109170000`) devolve à empresa casos `closed`, com a versão compartilhável e o histórico.
- Não existe RPC nem botão de revogação.

O passo 9d documenta o comportamento atual (a empresa continua vendo). Revogar depois da liberação exige tarefa, desenho do Back e decisão do responsável.

## Como rodar

O ensaio é um SQL gerado por `scripts/ensaio-piloto.mjs`. Ele:
- cria quatro contas fictícias (trabalhador, empresa A, empresa B e equipe) pelo mesmo gatilho de cadastro de produção, com e-mails em `example.invalid` e CPF/CNPJ gerados a cada execução;
- assume o papel de cada pessoa como o PostgREST faz (`role authenticated` e `request.jwt.claims`), passando pelas mesmas RPCs e políticas de RLS que o front usa;
- desfaz tudo no fim (subtransação revertida) e devolve uma tabela `passo | esperado | obtido | ok`.

Não usa senha, chave de serviço nem dado real. Não deixa dados no banco compartilhado.

Banco de dev (nunca produção; a trava fica no `scripts/dev-db.mjs`, ver `docs/devops/ENVIRONMENTS.md`):

```bash
node scripts/ensaio-piloto.mjs > <pasta-temporaria>/ensaio.sql
node scripts/dev-db.mjs query <pasta-temporaria>/ensaio.sql
```

Banco local com Docker:

```bash
npx supabase db query --local < <pasta-temporaria>/ensaio.sql
```

Critério: todas as linhas com `ok = true`. Uma linha "FALHA INESPERADA" indica que o ensaio parou no passo anterior; o resto não rodou.

## Conferência no navegador

O SQL prova regras e permissões. A conferência visual (portal do trabalhador, da empresa e da Operação em desktop e 375 px) usa contas fictícias de dev com sessão por link mágico, sem senha. Ela depende do projeto Supabase de dev e fica registrada na TASK-0033 com data e resultado.
