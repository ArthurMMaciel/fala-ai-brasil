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

**Pré-requisito:** as migrations `20261109180000` (resposta revisada ativa) e `20261117120000` (representante verificado) aplicadas em produção pelo Back. Antes disso, o ensaio testa o fluxo antigo, sem revisão da resposta nem verificação; uma rodada antes desses db push vale só como checagem de sintaxe.

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

## Ensaio pelo navegador: três fluxos (meta 20/11)

O SQL acima prova regras e permissões e não deixa nada gravado. Já os três fluxos abaixo usam o site de produção, como uma pessoa usaria. **Eles gravam dados de verdade em produção:** contas, empresa, manifestação, aviso, conexão e contato. Por isso:
- cada fluxo só roda com **liberação escrita do responsável**, e é ele, ou quem ele indicar, que usa as contas;
- todos os dados são fictícios e marcados "TESTE";
- os e-mails são `@example.com`, domínio reservado que não recebe mensagens;
- **nenhuma senha vai neste documento.** Cada conta tem a senha que a pessoa escolher no cadastro, guardada fora do repositório;
- no fim, a limpeza dos dados de teste é pedida ao Back (ver "Depois do ensaio").

### Pré-requisitos

1. **Banco.** O Back aplicou, com liberação:
   - a troca do gate (`20261117130000`);
   - as migrations da empresa pré-cadastrada e do aviso (`20261118120000`, `20261118130000`, `20261118140000`);
   - a da aba "Contratados" (`20261118150000`).
2. **Edge Function.** O DevOps publicou a `cnpj-lookup`. Sem ela, a tela usa o preenchimento manual, e o fluxo 1 continua possível.
3. **Front.** O front com a busca por CNPJ, as filas da Operação, a aba "Contratados" e a landing nova está em produção (push liberado).
4. **Contas confirmadas.** O cadastro exige confirmar o e-mail, e `@example.com` não recebe o link. Depois de cada cadastro, o responsável marca a conta como confirmada no painel do Supabase (Authentication → Users → a conta → Confirm user). Isso é uma escrita em produção e entra na mesma liberação.
5. **Conta da equipe.** O responsável usa a própria conta, que já tem acesso à Operação.

| Papel | E-mail | Observação |
|---|---|---|
| Trabalhador | `ensaio-trabalhador@example.com` | nome "TESTE Trabalhador Ensaio" e CPF fictício válido (gerador de teste) |
| Empresa | `ensaio-empresa@example.com` | CNPJ `98.765.010/0001-12` (fictício, dígitos válidos), razão social "TESTE Empresa Ensaio Ltda" |
| Parceiro | `ensaio-parceiro@example.com` | nome "TESTE Parceiro Ensaio" |
| Contato do aviso | `ensaio-aviso@example.com` | só digitado no relato; nunca vira conta |
| Contato pela landing | `ensaio-contato@example.com` | só no formulário da landing |

Se `98.765.010/0001-12` já tiver sido usado num ensaio anterior, use `98.765.020/0001-58`. Os dois foram montados só com dígitos verificadores válidos; não foram consultados nos provedores.

### Fluxo 1: relato → aviso → empresa → resposta → linha do tempo

1. **Trabalhador, cadastro.** Na landing, clique em "Criar conta gratuita". O cadastro do app abre.
   - Preencha os dados do trabalhador e escolha uma senha.
   - Depois do cadastro, o responsável confirma a conta no painel.
   - Entre com o e-mail e a senha.
2. **Trabalhador, nova manifestação.**
   - Em "Qual é o CNPJ da empresa?", digite `98.765.010/0001-12` e clique em "Buscar empresa".
   - Esperado: a empresa não está entre as cadastradas. Com a função publicada, aparecem os dados da Receita ou o preenchimento manual. Sem ela, só o manual.
   - No manual, preencha "TESTE Empresa Ensaio Ltda", município e UF.
   - Responda o contexto, o tema e o relato, todos fictícios.
   - Na etapa "Aviso à empresa":
     - e-mail `ensaio-aviso@example.com`;
     - "A pessoa que lê esse e-mail pode estar envolvida…?" → **Não**;
     - marque o consentimento.
   - Na revisão, escreva a versão compartilhável e clique em "Solicitar revisão".
   - Esperado: mensagem de manifestação registrada, com o protocolo na lista.
3. **Operação, fila de revisão.** Abra a manifestação e libere a versão compartilhável.
4. **Operação, Empresas a conferir.**
   - Abra "TESTE Empresa Ensaio Ltda".
   - Escolha "Dados conferem" e **não** marque pessoa física.
   - Registre.
5. **Operação, Avisos à empresa.**
   - Na aba "A decidir", abra o protocolo.
   - Esperado: nenhuma trava listada.
   - Aprove o aviso.
   - Na aba "Aprovados para enviar", clique em "Copiar texto". **Não envie de fato**: o endereço é `@example.com`. Clique em "Marquei como enviado".
   - Esperado: o aviso aparece em "Enviados".
6. **Empresa, cadastro pelo CNPJ.**
   - Na landing, em "Criar conta da empresa", cadastre com `ensaio-empresa@example.com` e o mesmo CNPJ. O responsável confirma a conta.
   - Esperado: a conta entra como integrante pendente e a área mostra "Aguardando verificação", sem casos nem números.
7. **Operação, Representantes a verificar.** Abra o representante e verifique com um método e uma referência fictícia (ex.: "ensaio 20/11, conferência simulada").
8. **Empresa, manifestações.**
   - Esperado: o caso liberado aparece só com a versão compartilhável.
   - Responda.
9. **Operação, Respostas em revisão.** Libere a resposta com a descrição para o trabalhador.
10. **Trabalhador, linha do tempo.**
    - Esperado: a resposta liberada aparece com a descrição. A versão compartilhável e o relato original continuam visíveis só para ele.
    - Avalie a resposta.

### Fluxo 2: empresa pede contato a parceiro → parceiro marca cliente → aba Contratados

1. **Parceiro, cadastro.** Na landing de parceiros, clique em "Cadastrar". O responsável confirma a conta.
   - Complete o perfil (nome, especialidade, cidade).
2. **Empresa, contato público.** Use a empresa verificada no fluxo 1.
   - Em Meu perfil, preencha "E-mail de contato" (`ensaio-empresa@example.com`) e um telefone fictício. Sem isso, o parceiro não vê como falar com a empresa.
3. **Empresa, parceiros.** Na aba Parceiros, em "Geral", abra "TESTE Parceiro Ensaio" e peça contato.
   - Esperado: o aviso "Interesse enviado". Uma conta ainda não verificada recebe "Seu vínculo com a empresa ainda não foi verificado pela equipe."
4. **Parceiro, Possíveis clientes.**
   - Esperado: a empresa aparece com os botões "Entrar em contato" (e-mail) e "WhatsApp" (telefone).
   - Não clique em "Entrar em contato": o endereço é `@example.com`.
   - Clique em "Marcar como cliente".
   - Esperado: a empresa passa para "Clientes".
   - O botão "Entrar em contato" que só registra "contato iniciado" aparece apenas quando a empresa não tem contato público.
5. **Empresa, Contratados.**
   - Esperado: "TESTE Parceiro Ensaio" aparece com "Cliente desde …".
   - Sem a `20261118150000`, a aba avisa que ainda não está ativa.

### Fluxo 3: contato pela landing → fila da Operação

1. **Visitante, sem conta.** Em `/empresa.html`, seção "Vamos conversar?", preencha:
   - perfil Empresa;
   - nome "TESTE Contato Ensaio";
   - e-mail `ensaio-contato@example.com`;
   - telefone fictício com DDD;
   - organização "TESTE Empresa Ensaio".

   Clique em "Solicitar contato".
   - Esperado: "Solicitação recebida."
   - Um segundo envio com o mesmo e-mail em 15 minutos não cria outra linha.
2. **Operação, Solicitações de contato.**
   - Esperado: o pedido aparece como "aguardando contato", com perfil Empresa e origem empresa.
   - Marque como contatado.

### Depois do ensaio

- Registre data, quem executou, o resultado de cada passo (ok ou falha) e prints em desktop e 375 px na TASK-0033.
- **Limpeza.** Peça ao Back um script de remoção dos dados de teste, com as contas `ensaio-*@example.com`, o CNPJ usado, a manifestação, o aviso, a conexão e o contato. O script roda com liberação escrita, como qualquer escrita em produção.
- A sequência de protocolos não volta atrás. O protocolo usado fica pulado.
