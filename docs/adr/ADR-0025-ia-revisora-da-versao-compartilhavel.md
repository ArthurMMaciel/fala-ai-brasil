# ADR-0025 — IA revisora da versão que será enviada à empresa

- **Estado:** Proposta. Nada foi implementado no banco nem no servidor. Hoje o Front faz só uma simulação local, sem serviço externo e sem envio de texto a terceiros.
- **Data:** 2026-11-23
- **Origem:** pedido do responsável, repassado pelo Gestor: "SEMPRE passará por uma IA orientada a ser uma revisora de casos psicossociais das empresas, que deve ser de forma totalmente anônima, que não cite nomes de pessoas e nem deixe a frase de forma agressiva".
- **Relacionadas:**
  - ADR-0010 (revisão humana antes do compartilhamento);
  - ADR-0012 (D7 e R3: alto risco sem contato externo automático);
  - ADR-0017 (primeiro serviço externo chamado por Edge Function);
  - TASK-0007 (base legal e retenção);
  - runbook `docs/runbooks/AI_ERROR.md`;
  - ROADMAP, Fase 5 (IA).
- **Por que exige ADR (AGENTS.md):** introduz IA, envia texto de relato a um terceiro e cria um serviço externo novo.

## Contexto

- **Duas versões do relato.** O trabalhador escreve o relato original e, separada, a "versão que será enviada à empresa" (`complaint_shared_versions`). A equipe revisa essa versão antes de liberá-la (ADR-0010). O original nunca sai para a empresa.
- **O que a memória do projeto já registra (`docs/PROJECT_MEMORY.md`):**
  - IA autônoma está rejeitada para decisões sensíveis;
  - a IA deve começar assistiva;
  - nenhum dado sensível vai a IA ou a terceiros sem avaliação aprovada.
- **ROADMAP, Fase 5:** dataset e avaliação, experimento assistivo com revisão humana, auditoria de modelo e prompt, custo, fallback e segurança.
- **ClickUp:** não consultado. Esta sessão não tem acesso ao ClickUp, e a busca por tarefas de "IA" e "AI" fica para o Gestor. No repositório, a única tarefa com "IA" no título é a TASK-0025 ("Refinar o front para parecer menos gerado por IA", ClickUp 17tu7rp7qbx), que não trata deste assunto.

## Problema

1. **O texto pode identificar pessoas.** A versão compartilhável costuma citar colegas, chefias e situações. Numa empresa pequena, isso identifica o trabalhador ou terceiros. A revisão humana pega muito, mas não tudo, e não em escala.
2. **O texto pode ser agressivo.** Isso piora a recepção pela empresa e expõe o trabalhador.
3. **Enviar o texto a uma IA externa é tratamento de dado sensível por terceiro.** Relato psicossocial pode envolver saúde (LGPD, art. 11). Os nomes citados são dados de terceiros que não consentiram. Se o provedor estiver fora do Brasil, há transferência internacional (LGPD, art. 33).

## Decisões propostas

**D1. A IA sugere; quem decide são pessoas.**
- A IA devolve uma versão reescrita, sem nomes de pessoas e com tom não agressivo, e uma lista curta do que mudou (por exemplo, "nome removido" e "frase suavizada").
- O trabalhador vê a sugestão e decide: aceita, edita ou mantém o próprio texto.
- A equipe continua revisando a versão escolhida antes de liberar (ADR-0010).
- A IA não decide nada: não libera, não retém, não classifica risco, não contata ninguém e não bloqueia o envio.

**D2. "Sempre passa pela IA" quer dizer que toda versão compartilhável recebe a sugestão antes de ir para revisão.**
- Se a IA estiver fora do ar, o fluxo segue com aviso ao trabalhador, e a revisão humana continua sendo a barreira.
- A alternativa, travar o envio até a IA voltar, é decisão do responsável (item 3 abaixo). Ela faz a disponibilidade de um terceiro sem SLA bloquear o relato.

**D3. O que sai para o provedor:**
- só o texto da versão compartilhável, mais as instruções fixas do sistema;
- nunca o relato original, o nome ou e-mail do trabalhador, a empresa, o CNPJ, o protocolo, a categoria, as datas ou os identificadores internos;
- nenhuma informação que ligue o texto à conta.

O texto ainda pode conter nomes e detalhes. É exatamente o que a IA deve tirar, e é o risco residual que a avaliação de privacidade precisa aceitar ou mitigar. Por exemplo, uma remoção local de padrões óbvios antes do envio, como e-mails, telefones, CPFs e nomes da lista de pessoas da empresa, quando existir.

**D4. A chamada roda numa Edge Function, nunca no navegador**, no mesmo padrão da ADR-0017:
- só conta autenticada, com cota por conta;
- texto no corpo do POST;
- timeout curto;
- chave do provedor nos Secrets, definida pelo responsável e nunca no Git;
- logs sem conteúdo.

**D5. Logs e registro sem conteúdo.**
- **Logs:** a função registra só resultado (`ok`, `timeout`, `erro`, `cota`), provedor, versão do modelo, versão do prompt e tempo. Nunca o texto de entrada nem o de saída.
- **Banco:** grava só que houve sugestão e qual versão do prompt e do modelo foi usada, para auditoria. A sugestão em si não é guardada; o que fica é a versão final que o trabalhador escolheu, que já é gravada hoje.

**D6. Alto risco.**
- A IA não identifica nem classifica risco. Relatos que indiquem risco à vida, violência ou crime seguem a regra atual: revisão humana, decisão `held` e nenhum contato externo automático (ADR-0012, R3).
- O prompt instrui a IA a não minimizar nem apagar a gravidade do fato ao suavizar o tom. Ela tira a agressividade da forma, nunca o conteúdo.
- Usar a IA para sinalizar possível risco à equipe é uma decisão à parte (item 6 abaixo). Na primeira versão, não sinaliza.

**D7. Instruções do sistema fixas e versionadas no repositório**, revisadas por produto, jurídico e psicologia antes do uso. O texto do trabalhador entra como conteúdo a revisar, nunca como instrução: a função ignora pedidos contidos no texto (proteção contra injeção de instruções). Como a saída volta só para o próprio trabalhador e a equipe ainda revisa, o dano de uma injeção é limitado.

**D8. Avaliação antes de ligar** (ROADMAP, Fase 5):
- um conjunto de casos fictícios, nunca relatos reais, com nomes, apelidos, cargos únicos e frases agressivas;
- métricas mínimas: nomes removidos, sentido preservado e gravidade não reduzida, conferidas por pessoa da equipe;
- os limites e quem aprova ficam definidos antes de ligar em produção.

**D9. Rollback.** A chave liga ou desliga a IA (feature flag no banco, lida pela Edge Function e pelo Front). Desligada, o fluxo é o de hoje. O runbook `AI_ERROR.md` vale para vazamento, sugestão perigosa ou queda de qualidade.

## Opções de provedor, modelo e hospedagem

| Opção | Como | A favor | Contra | A conferir antes de decidir |
|---|---|---|---|---|
| **A. API de modelo comercial** (por exemplo, Anthropic, OpenAI ou Google) | Edge Function chama a API do fornecedor | Melhor qualidade de reescrita; sem infraestrutura; custo por uso | Transferência internacional; dado sensível sai do país; depende de contrato | Retenção de dados (há opção de retenção zero e em que plano), uso para treino (desligado por contrato?), região de processamento, DPA, termos para dado de saúde |
| **B. Modelo comercial via nuvem com região** (por exemplo, Vertex AI ou Bedrock) | Edge Function chama a nuvem, numa região escolhida | Pode manter o processamento no Brasil, se o modelo estiver disponível na região; contrato de nuvem com DPA | Exige conta de nuvem e faturamento; mais configuração | Quais modelos existem na região do Brasil; retenção; custo; quem administra a conta |
| **C. Modelo aberto hospedado pela plataforma** | Servidor próprio ou GPU alugada | O texto não sai para um provedor de IA | Custo fixo e operação; qualidade menor em português para este uso; fora do Free | Custo mensal; quem opera; latência |
| **D. Só regras locais** (sem IA) | Remoção de padrões e lista de termos agressivos, no Front ou no banco | Nenhum terceiro, custo zero | Não reescreve tom; erra muito com nomes | Serve como camada prévia de qualquer opção |

Nenhuma afirmação sobre retenção, região ou termos dos fornecedores foi conferida nesta ADR. Isso fica com o DevOps e o advogado, nas páginas e nos contratos atuais de cada um.

**Recomendação técnica, sujeita à avaliação de privacidade:** D + A ou D + B.
- **D + A:** regras locais primeiro e, depois, um modelo comercial com retenção zero e treino desligado em contrato.
- **D + B:** o mesmo, com processamento no Brasil, se a região tiver o modelo.

A opção C só se a avaliação jurídica proibir o envio a terceiros.

## Avaliação de privacidade (a completar com o advogado)

| Item | Situação |
|---|---|
| Finalidade | Proteger o trabalhador e terceiros, tirando nomes e agressividade da versão que vai à empresa |
| Dados enviados | Só o texto da versão compartilhável, que pode conter nomes de terceiros e fatos de saúde ou do trabalho |
| Base legal | Em aberto. Candidatas: consentimento específico do trabalhador para o processamento por IA, ou outra hipótese que o advogado indicar. Dado sensível tem regras próprias (art. 11) |
| Transferência internacional | Se o provedor processar fora do Brasil: exige base do art. 33 (cláusulas contratuais, por exemplo) |
| Operador | O provedor é operador. Exige DPA com retenção, finalidade, proibição de treino, subcontratados, incidente e exclusão |
| Retenção | Na plataforma, nada do texto em logs; sugestão não guardada. No provedor, retenção zero, se o contrato permitir |
| Transparência | O aviso de privacidade (ADR-0022) e a tela precisam dizer que a versão compartilhável passa por uma IA, quem é o provedor e o que é enviado |
| Direitos do titular | Terceiros citados não sabem do tratamento. O advogado avalia se a remoção de nomes, que é a própria finalidade, basta |

## Custo

- Por chamada, o custo é proporcional ao tamanho do texto, de entrada e de saída. A versão compartilhável tem limite de tamanho no banco, então cada chamada é curta.
- O custo mensal = número de relatos com versão compartilhável × chamadas por relato (1, ou mais se o trabalhador pedir nova sugestão) × preço por chamada do modelo escolhido. O número fica para o DevOps, com o preço vigente do fornecedor.
- No piloto (3 empresas), o volume é baixo.
- Edge Function: as invocações entram no limite do plano Free (ver ADR-0017).
- Cota por conta, para evitar uso como serviço gratuito de reescrita.

## Rollback

- A feature flag desliga a IA, e o fluxo volta ao de hoje: o trabalhador escreve e a equipe revisa.
- A chave do provedor é revogada no painel do fornecedor.
- Como nada da sugestão é guardado, não há dado a apagar na plataforma. No provedor, vale o que o DPA definir.

## Fora do escopo

- IA no relato original, na triagem, na classificação de risco, na resposta da empresa ou na decisão da equipe.
- Envio automático de qualquer coisa à empresa.

## Decisões que dependem do responsável

1. Provedor e hospedagem: A, B, C ou D, combinadas como na recomendação. Depende da avaliação do advogado.
2. Base legal e consentimento: se o trabalhador consente especificamente o processamento por IA (caixa própria) ou outra base. E se quem não consentir pode seguir só com a revisão humana.
3. "Sempre": se a IA fora do ar bloqueia o envio ou se o fluxo segue com revisão humana (recomendado).
4. Se o trabalhador pode recusar a sugestão e manter o próprio texto (recomendado: pode; a equipe revisa de qualquer forma).
5. Limites de qualidade da avaliação (D8) e quem aprova ligar em produção.
6. Se a IA pode, no futuro, sinalizar possível risco à equipe, sem decidir nada. Fica fora da primeira versão.
7. Prazo: a simulação local do Front segue como está, sem serviço externo, até esta ADR ser aceita, o DPA estar assinado e a avaliação aprovada.
