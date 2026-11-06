# TASK-0030 — Fechar escopo e fluxos operacionais do piloto Trabalhador–Empresa

- Status: em-andamento
- ClickUp: [TASK-0030](https://app.clickup.com/t/17tu7rpb56v)
- Área: Produto/Operação/Privacidade
- Prioridade: P0
- Alvo de revisão: 2026-11-09
- Relacionadas: TASK-0026, TASK-0029, TASK-0007, TASK-0011, TASK-0031, TASK-0032

## Objetivo do piloto

Validar se uma pessoa consegue registrar uma manifestação com proteção, se a empresa legítima consegue conhecê-la e responder sem cobrança e se a equipe consegue oferecer orientação especializada opcional. O piloto é fechado e assistido; número de empresas, casos por dia e responsáveis devem ser aprovados antes de dados reais.

## Recorte

- Trabalhador: entrada, cadastro, seleção da empresa, relato, revisão da versão compartilhável, protocolo, acompanhamento, feedback e encerramento.
- Operação: triagem, verificação de destinatário e representante, liberação, acompanhamento e tratamento de exceções.
- Empresa: convite mínimo, cadastro/verificação, acesso gratuito à versão autorizada, resposta e pedido opcional de orientação.
- Hub, Patrocinador, pesquisa de ambiente e ranking público não integram a operação do piloto.

## Fluxo do trabalhador — alvo, ainda não implementado por completo

1. Entra na página do trabalhador e entende finalidade, limites de proteção de identidade, gratuidade e como obter ajuda.
2. Cria ou acessa a conta. Cadastro identificado não deve ser chamado de anônimo. Avaliar minimização dos campos exigidos.
3. Seleciona empresa cadastrada; ausência de empresa tem caminho de suporte, sem inventar destinatário. Indicar uma pessoa de contato é opcional e nunca comprova que ela é destinatária segura.
4. Preenche contexto e relato original. Risco imediato exige orientação e encaminhamento humano conforme protocolo aprovado; não gera contato externo automático.
5. Prepara separadamente a versão que poderá ser compartilhada. O texto compartilhável começa vazio; o trabalhador revê nomes, datas, locais e detalhes de reidentificação.
6. Escolhe guardar sem solicitar compartilhamento ou solicitar revisão para compartilhamento. Recebe protocolo e estado claro. A solicitação ainda não equivale a envio à empresa.
7. Acompanha: guardada, em revisão, aguardando ajuste, autorizada para a empresa, respondida ou encerrada. Recebe retorno apropriado em cada transição.
8. Pode responder ao pedido de ajuste, avaliar a resposta da empresa e encerrar; cancelamento e retirada antes da liberação precisam de regra definida.

## Fluxo da operação — alvo

1. Recebe caso pendente em fila restrita; registra responsável e horário sem conteúdo sensível em logs.
2. Avalia risco e a versão compartilhável. Acesso ao original só se necessário, excepcional e auditado.
3. Verifica empresa, representante e contato por fonte independente. Contato sugerido pelo trabalhador é apenas candidato.
4. Retém casos de alto risco ou com destinatário inseguro para decisão humana documentada; solicita ajuste quando necessário.
5. Autoriza a liberação da versão compartilhável e registra ator, decisão e motivo. Envia convite mínimo somente ao destinatário verificado, pelo canal aprovado.
6. Monitora entrega, acesso, resposta, prazo e exceções. Reenvio não duplica caso nem revela dados por URL.
7. Se a empresa pedir orientação, encaminha para atendimento comercial/técnico separado da tratativa gratuita.

## Fluxo da empresa — alvo

1. Recebe convite sem identidade, relato, tema ou detalhes do caso no primeiro contato.
2. Acessa entrada da empresa, cria conta ou entra e comprova representação da organização. Cadastro sozinho não concede acesso.
3. Vê somente manifestações autorizadas da própria organização e apenas a versão compartilhável; leitura e resposta não dependem de pagamento.
4. Registra resposta institucional e providências dentro de escopo definido; trabalhador acompanha o retorno.
5. Opcionalmente pede orientação humana com escopo, preço e contratação próprios. Pedido não altera acesso, prioridade nem ranking.

## Exceções obrigatórias

- Alto risco, ameaça imediata ou suspeita de retaliação: segurar contato externo automático e escalar à pessoa responsável.
- Contato inválido, representante não verificado ou empresa ausente: não revelar caso; operação busca alternativa segura.
- Texto compartilhável com identificadores: devolver para ajuste ou reter; não publicar original.
- Link repassado, tentativa de outro CNPJ, sessão revogada: negar acesso e auditar tentativa.
- Empresa não responde, resposta inadequada, falha de entrega, duplicidade ou trabalhador retira solicitação: procedimento e estados explícitos.

## Decisões para produto, operação e jurídico

1. Quais categorias entram no piloto e qual é o limite diário de casos?
2. Quem revisa risco e texto, quem autoriza envio e quem atende incidentes fora do expediente?
3. Qual base legal, aviso de privacidade, retenção e regra de exclusão se aplicam a cada dado? Quem é controlador/operador em cada etapa?
4. Como comprovar representação empresarial e qual canal é aprovado para o convite?
5. O que constitui a orientação paga, quem a entrega, qual preço, SLA e forma de faturamento?
6. Qual nome e promessa pública serão usados? Não prometer anonimato absoluto, conformidade automática ou proteção que os controles ainda não sustentam.

## Critérios de aceite

- Fluxos e exceções revisados por produto, operação, técnico e jurídico.
- Cada transição tem ator, dado exposto, condição de acesso, resultado e tratamento de erro.
- Acesso ao caso e resposta gratuitos; oferta paga independente.
- Nenhum caso real entra antes do gate da TASK-0033.

## Progresso em 2026-11-05

Primeira versão das jornadas e exceções registrada para revisão. A indicação de contato empresarial deixou de ser obrigatória no assistente, pois o dado ainda é apenas demonstrativo e não comprova destinatário seguro. `npm test` passou (38 testes) e `npm run build` passou. Produto, operação e jurídico ainda precisam validar as decisões listadas acima.

## Riscos e rollback

Segurança e privacidade: vazamento, reidentificação, retaliação e acesso por empresa errada. Operação: fila humana sem capacidade e atraso. Custo: tempo de triagem e suporte por caso. Se o fluxo não for seguro, manter apenas demonstração sintética e suspender novas entradas reais.
