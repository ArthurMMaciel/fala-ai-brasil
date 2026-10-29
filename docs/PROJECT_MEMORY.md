# Memória permanente do projeto

Atualizado em: 2026-10-26

## Visão

Permitir que uma pessoa relate situações psicossociais do trabalho, preserve sua identidade perante a empresa, acompanhe o tratamento e receba retorno; permitir que empresas respondam com rastreabilidade e evoluam sua responsividade.

## Arquitetura atual

Aplicação Vite + TypeScript com landing e percursos editoriais em React, integrados ao renderer HTML legado. Todo estado é volátil e os dados são simulados. Os exemplos editoriais e os mocks legados têm estado separado. Não existe servidor de aplicação próprio. Desde 2026-10-26 (ADR-0009), contas, perfis, organizações e assinatura inicial persistem no Supabase (Auth + PostgreSQL com RLS, `sa-east-1`), acessado pelo front com chave pública; manifestações e demais fluxos seguem voláteis.

## Direção técnica vigente

- Evoluir incrementalmente para uma aplicação web + API + PostgreSQL.
- Manter a POC utilizável enquanto se cria a fundação.
- Começar com monólito modular; separar serviços apenas por necessidade comprovada.
- Preferir jobs em PostgreSQL antes de adotar broker dedicado.
- Separar fisicamente/logicamente identidade, relato original e versão compartilhável.
- Exigir revisão humana para risco médio/alto; bloquear automação externa em risco alto.

## Decisões pendentes

- Identidade oficial definida: Escuta Aí Brasil. Os nomes anteriores foram descontinuados em 2026-10-01.
- Estratégia de autenticação (sessão server-side é preferência inicial, ainda não decidida).
- Provedor de infraestrutura e regiões de dados.
- Base legal, consentimentos, retenção e atendimento a direitos do titular.
- Canal de comunicação com empresas e comprovação de domínio/representação.
- Uso, modelo, provedor e fronteiras de IA.

## Tecnologias atuais

- TypeScript 5.9.3, Vite 5.4.21, HTML e CSS.
- Sem runtime de produção definido.
- Proposta legada não ratificada: Go, chi, pgx, PostgreSQL, goose e OpenTelemetry.

## Tecnologias rejeitadas ou adiadas

- Microserviços: adiados; aumentam operação sem benefício atual.
- Kubernetes: adiado; inadequado ao tamanho da equipe e estágio.
- Broker dedicado: adiado; avaliar após demanda real.
- IA autônoma: rejeitada para decisões sensíveis; IA deve começar assistiva.

## Riscos conhecidos

- POC pode executar HTML inserido pelo usuário por uso de `innerHTML`.
- Credenciais demo e autorização existem apenas no cliente.
- Não há isolamento entre organizações nem separação real de dados sensíveis.
- A promessa de proteção de identidade ainda não é sustentada por controles técnicos.
- Há testes locais de regras, navegação, codificação e roteiro de navegador; não há logs operacionais, backups ou resposta a incidentes implementados. A validação da POC não substitui controles de produção.

## Regras permanentes

- Nunca expor texto original à empresa.
- Evitar promessa de anonimato absoluto; comunicar proteção de identidade e limites.
- Não usar relatos reais na POC.
- Não enviar dados sensíveis a IA/terceiros sem avaliação aprovada.
- Alterações estruturais exigem ADR; trabalho relevante exige tarefa.

## Alterações recentes

- Em 2026-10-29 o responsável aprovou "Meus conteúdos" do parceiro (fotos e vídeos por link, planos Profissional/Nacional) e o contato da empresa visível ao parceiro com interesse ou cliente (migration 20261029050000, ADR-0009). Parceira Teste passa ao plano Nacional no seed.

- Em 2026-10-29, regressões do portal com dados reais (commits de 2026-10-26/27, sem pedido do responsável) corrigidas: aba Empresas do trabalhador volta como diretório com "Fazer manifestação" e ranking; aba Destaques volta em Parceiros (planos Profissional e Nacional, migration 20261029040000); empresa logada aparece no Ranking mesmo abaixo de 3 manifestações; parceiro edita perfil e foto em "Meu perfil". "Meus conteúdos" e contato com clientes aguardam aprovação do modelo.

- Em 2026-10-29 o cadastro em produção passou a enviar e-mail pelo Gmail (TASK-0023 concluída). Após cadastrar, a pessoa vê "confirme seu e-mail"; o link leva ao login. Senha com regras e checklist; máscara de CPF/CNPJ; aba Empresas do trabalhador volta com o ranking real (oculta desde 2026-10-22 por usar dados simulados).

- Em 2026-10-28, a pedido do responsável, a fotografia do hero do trabalhador saiu da landing. No lugar entrou o painel "Você no controle" (original protegido, versão autorizada sem identidade, retorno na área do trabalhador). O aviso "nada é enviado à empresa" era da POC e passou a pedir dados fictícios. Produção na Vercel ainda sem variáveis do Supabase.

- Em 2026-10-27 o repositório foi reorganizado a pedido do responsável: `src/` em pastas (`app`, `portals`, `landing`, `editorial`, `services`, `domain`, `styles`); legado sem uso removido (`main.ts`, `worker-portal.tsx`, `commercial-portal.tsx`, `mockData.ts`, `models.ts`); diagramas em `docs/arquitetura/diagramas/{poc,mvp}`; `ENGENHARIA.md` e apresentações HTML movidos para `docs/`. Portais de empresa e parceiro só montam com conta real.

- Em 2026-10-27 o responsável aprovou o modelo v3 e pediu tudo em banco: manifestações (original separado da versão compartilhável revisada pelo trabalhador), respostas, ranking calculado, conexões do Hub e patrocinadores da landing vindos do banco. Migration `20261027024534_mvp_manifestacoes_e_conexoes.sql`; seed `scripts/seed-demo-data.mjs` (24 contas fictícias, mesma senha em `supabase/test-users.local.md`). Contas `@escutaai.demo` removidas; Operação/IA ocultas. Novo portal do trabalhador `src/worker-portal-live.tsx` e portais de empresa/parceiro `src/portal-live.tsx`; `src/worker-portal.tsx`, `mockData.ts` e os percursos editoriais anônimos seguem no código, sem uso pelas contas reais.

- Em 2026-10-27 o responsável aprovou campanhas de patrocinador: um tipo por plano, revisão antes de publicar e uma campanha ativa por vez. Migrations `20261027012723_mvp_campanhas_patrocinador.sql` e `20261027013216_campanhas_fuso_sao_paulo.sql` (datas pelo fuso de São Paulo, pois `current_date` é UTC). Conta do patrocinador ganhou abas Planos/Campanhas; conta real de empresa abre o portal da empresa (evento `escuta:open-portal`). Na mesma data, o portal da empresa passou a usar dados reais quando a conta é real: nome, razão social, CNPJ e cidade da empresa logada, indicadores zerados (manifestações ainda não persistidas) e diretório real de parceiros via `list_partner_directory()`. "Entrar em contato" com parceiro ainda não registra interesse (exige nova entidade e aprovação). Contas `@escutaai.demo` seguem com a demonstração Aurora Tecnologia.

- Em 2026-10-27 (TASK-0022): mensagens de login/cadastro e alert() viraram toasts acessíveis (`src/app/toast.ts`, sucesso verde, erro vermelho); botão de exibir senha; reenvio de confirmação só após cadastro ou e-mail não confirmado; aviso "A POC…" removido da tela de acesso; seção fixa "Nossos patrocinadores" na landing com marcas fictícias (`public/sponsors/`). Quatro usuários de teste confirmados (trabalhador, empresa, parceiro, patrocinador) criados direto no banco com e-mails `@example.com`; credenciais só em `supabase/test-users.local.md` (ignorado pelo Git). Diagnóstico: cadastro real falhava com `Error sending confirmation email` — SMTP do Resend recusando o remetente/destinatário; exige domínio verificado no Resend ou remetente `onboarding@resend.dev` enviando só ao e-mail do dono da conta Resend.

- Em 2026-10-27 o responsável rejeitou o modelo com coluna `persona` e aprovou o modelo v2 (ADR-0009, revisão v2): entidades por tipo (`workers`, `companies` + `company_users`, `partners`, `sponsors`), `addresses` separado, `media` com fotos no bucket `partner-media` e vídeos só por link, vários perfis por conta (`current_profiles()`, `add_profile()`), especialidade do parceiro em texto livre e nomes de banco em inglês. Migration `20261027002812_mvp_entidades_por_tipo.sql` aplicada; `supabase/tests/rls_smoke.sql` passou nas 12 verificações. Lição: mudanças de modelo de dados devem ser apresentadas ao responsável antes de aplicar.

- Em 2026-10-26 o responsável redirecionou o projeto de POC para MVP de demonstração (2026-10-30) com custo mínimo (Vercel, Supabase e Resend gratuitos), sem backend próprio. ADR-0009 e TASK-0022 registram: Supabase Auth com confirmação de e-mail via SMTP Resend; migration `supabase/migrations/20261026235534_mvp_cadastro_inicial.sql` aplicada (profiles, organizations, organization_members, plans, subscriptions, RLS, grants mínimos e trigger de cadastro que remove CPF/CNPJ/endereço do user_metadata); cadastro real de Trabalhador, Empresa, Parceiro e Patrocinador com confirmação de senha (mínimo 8) e validação de CPF/CNPJ; Intelligence/Estudos fora do cadastro por decisão do responsável. Contas `@escutaai.demo` continuam locais. Figma deixado de lado; conectores Figma/Supabase indisponíveis na conta corporativa, migrations aplicadas via CLI com login pessoal. Diagramas `arquiteturas/06-banco-de-dados-mvp.drawio` e `07-arquitetura-mvp.drawio`. A variável de ambiente `SUPABASE_ACCESS_TOKEN` do Windows pertence a outra conta e precisa ser ignorada nos comandos da CLI. O app em execução é `src/main.js` (JS minificado mantido manualmente), não `src/main.ts`.

- Em 2026-10-21 foram concluídos os cinco pontos da retomada da TASK-0021: confirmação/acompanhamento ajustados ao Figma; cópia explícita de dados fictícios com recuperação manual; complemento com revisão/edição/confirmação; pendências empresariais separadas por responsável, com lista própria e atualização após envio à revisão; validação em navegador e organização da entrega em commit local. Os 25 testes passam. Navegação com teclado, erros, ausência de execução de HTML digitado, preservação de escolhas, filtros/estados vazios e mobile em 320/390 px foram verificados. Assets/fontes locais foram carregados e as capturas revisadas. Nenhum serviço, dependência, publicação de resposta, merge ou deploy novo. O protótipo continua exclusivo para dados fictícios.

- Em 2026-10-21 foi retomada e auditada a TASK-0021 na branch local `feat/figma-escuta-editorial`. A implementação editorial permanece sem commit e a branch não está publicada. Os 24 testes e o build passaram; roteiro de navegador executou manifestação, acompanhamento e revisão empresarial sem erros de JavaScript, com inicial/assunto sem overflow em 390 px. Contexto Figma de confirmação/acompanhamento voltou a ficar disponível: há diferenças de composição e ausência de revisão do complemento a resolver. Auditoria e demais pendências registradas na TASK-0021. A base versionada da branch tem conteúdo idêntico a `origin/main` após PR #2, com históricos distintos. Nenhum merge, push ou deploy realizado nesta retomada.

- Em 2026-10-14 a TASK-0020 integra soluções e planos à landing conforme a persona escolhida no topo, usa a logo oficial extraída do PDF fornecido e corrige a transição entre React e as telas HTML. Catálogo de planos compartilhado com o cadastro, seleção preservada e sessão demonstrativa reconhecida na landing. Avaliação/finalização do caso respondem em memória; ações operacionais ainda ausentes aparecem indisponíveis. Nenhum envio externo ou controle real de acesso adicionado. Testes de navegação/renderização sem navegador cobrem regressões; revisão visual/mobile em navegador permanece pendente por indisponibilidade da ferramenta na sessão. Vercel mantém o deploy existente; CI adiado pelo responsável.

- Em 2026-10-14 foi corrigida corrupção de codificação no JavaScript executado pela POC e nos textos dos testes. A varredura de textos versionados e o teste da mensagem da Empresa passam a integrar `npm.cmd test`, prevenindo regressão de acentos/travessão em PT-BR (TASK-0019, PR #1).

- Em 2026-10-14 o responsável definiu Trabalhador como nomenclatura da persona gratuita. Interface, rótulos acessíveis, materiais comerciais e documentação foram padronizados; identificador interno `worker`, gratuidade e regras comerciais preservados (TASK-0019).

- Em 2026-10-08 o responsável determinou usar somente a API oficial do ClickUp com `CLICKUP_API_TOKEN` no `.env`; não utilizar o plugin/conector ClickUp. Preferência persistente para consultas e alterações de tarefas. Sem imprimir chave ou enviar dados pessoais.
- Regras comerciais atualizadas pelo responsável: trabalhador gratuito; demais personas escolhem primeiro plano no cadastro e gerenciam upgrade na conta. Modalidades: um mês de calendário grátis e mensal a partir do segundo, mensal imediato ou anual com 5% de desconto sobre doze mensalidades (ADR-0005/TASK-0019). Substitui a recomendação anterior de piloto pago e gratuidade de 30 dias exclusiva do Hub. Preços finais permanecem pendentes.
- Regra comercial corrigida pelo responsável em 2026-10-08: um mês de calendário grátis e mensalidade a partir do segundo; mensal imediato ou anual com 5% de desconto. A regra de três meses foi substituída em código, apresentação e documentos.
- Boleto foi incluído no estudo de cobrança. Documentação Stripe consultada indica suporte no Brasil/BRL, geração de voucher/PDF, confirmação até 1 dia útil, liquidação até T+2, recorrência, Checkout/Billing/Invoicing/Subscriptions/Customer Portal, limite de R$ 5 a R$ 49.999,99 e ausência de reembolso padrão. Transferência bancária genérica não aparece na matriz oficial para BRL/conta brasileira; não prometer sem validação da conta (ADR-0007).
- POC demonstra cadastro das cinco personas comerciais, área própria de assinatura, estado pendente/trial/pagante e confirmação simulada. Novas personas não empresariais usam papel demonstrativo `commercial`, sem herdar painel de administrador. Pagamentos, autenticação, autorização e persistência reais continuam ausentes.
- Interface usa trabalhador no lugar de empregado. Todos os cadastros exibem CEP, Rua/Avenida e número obrigatórios, complemento opcional. Pedido explícito de API CEP autoriza integração pontual: ViaCEP escolhido como decisão técnica (ADR-0006), com timeout, recuperação manual e proteção contra resposta obsoleta. Somente CEP enviado na aplicação; conexão direta expõe IP ao provedor. Relação de assinaturas com estudos/patrocínios avulsos permanece pendente.

- Stripe escolhida pelo responsável para pagamentos dos clientes em 2026-10-07 (ADR-0004). TASK-0018 criada no ClickUp com 7 subtarefas e levantamento de cartão, Pix avulso, recorrência, webhooks, ciclo comercial e conciliação. Integração ainda não implementada; conta, preços finais e políticas comerciais pendentes. Pix Automático não disponível para contas brasileiras segundo documentação consultada; habilitação de Pix e limites exigem validação da conta antes de lançamento.
- Gestão técnica pelo ClickUp autorizada pelo responsável: lista Escuta Aí Brasil (`901329218347`) no Arthur Workspace e TASK-0001 a TASK-0017 registradas em 2026-10-07, com links em cada documento local. São 11 pendentes (`to do`) e 6 concluídas (`complete`), preservando prioridades e histórico documentado. Consultar duplicatas antes de criar tarefas e manter vínculos locais. A rotina de manutenção da TASK-0017 ainda é proposta.
- API oficial do ClickUp validada para gestão local de tarefas com token em `.env` ignorado pelo Git. Compartilhar somente metadados técnicos; nunca relatos, identidades ou credenciais. Isso não implementa integração no produto.
- As visões comerciais passaram de catálogo de funcionalidades para argumento de compra: comprador, gatilho, problema, promessa, resultados do piloto, lógica econômica, scorecard, jornada e diferenciação de planos por persona.
- Histórico (substituído em 2026-10-08): entrada recomendada de piloto pago de 90 dias e 30 dias sem mensalidade apenas no Hub.
- POC ganhou a página “Soluções e planos” com visões demonstrativas para Empresa, Parceiro do Hub, Intelligence, Estudos e Patrocínio; valores são hipóteses comerciais, sem cobrança real.
- Pessoa trabalhadora permanece como acesso gratuito e monetização não pode definir prioridade de atendimento.
- Suporte da plataforma passou a ter visão interna demonstrativa, separada da operação humana e sem acesso a relato original ou identidade por padrão.
- Cadastro pessoal simplificado para nome, CPF, endereço, e-mail e senha; confirmação de senha adiada.
- Contexto laboral passou a ser coletado por manifestação, sem a opção de candidato em processo seletivo.
- Formas de comunicação agora registram nome, e-mail, telefone e cargo do contato empresarial, com cautela explícita para proprietário/sócio.
- Landing segmentada entre empregado e empresa.
- Passo de formas de comunicação na manifestação, com contato empresarial estruturado e validação de e-mail/telefone.
- Baseline publicada na branch `main` do repositório `ArthurMMaciel/fala-ai-brasil` em 2026-09-30.

## Aprendizados e incidentes

- Nenhum incidente de produção: não há produção.
- Documentos antigos misturam arquitetura desejada e estado implementado; a governança nova separa explicitamente os dois.
