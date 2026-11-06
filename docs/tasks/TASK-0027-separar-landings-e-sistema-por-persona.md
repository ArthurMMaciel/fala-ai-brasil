# TASK-0027 — Separar landings do sistema por persona

- Status: proposta
- ClickUp: [TASK-0027](https://app.clickup.com/t/17tu7rp9zgc)
- Área: Produto/Frontend/Arquitetura
- Prioridade: P2; após os gates do piloto fechado
- Impacto: entrada pública clara e acesso autenticado coerente
- Relacionadas: TASK-0020, TASK-0022, TASK-0025, TASK-0026

## Problema
Hoje a landing pública, o cadastro e a navegação da aplicação estão acoplados no mesmo fluxo, dificultando o entendimento de onde termina a apresentação e começa a área de cada persona.

## Objetivo
Definir e implementar rotas públicas por persona e uma transição explícita para cadastro, login e portal correspondente, preservando os fluxos já existentes.

## Escopo
- Produzir tese visual, plano de conteúdo, tese de interação, auditoria e plano de melhorias antes de implementar.
- Especificar URLs e navegação para Trabalhador, Empresa, Parceiro, Patrocinador e oferta Intelligence; validar a estrutura com a TASK-0026.
- Separar layout e navegação de páginas públicas dos portais autenticados, com retorno e redirecionamento pós-login previsíveis.
- Definir CTA primário e alternativa “Saiba mais / Entrar em contato” em cada landing; o formulário é da TASK-0028.
- Registrar ADR antes de mudar fronteiras de rotas, autenticação ou arquitetura.

## Fora de escopo
Novo provedor, deploy ou domínio; reescrever os portais; alterar regras de planos e pagamentos.

## Critérios de aceite
- Cada persona tem entrada pública identificável e link direto que abre a seção certa; cadastro/login conduzem ao portal autorizado.
- Usuário não autenticado não vê dados de portal; troca de persona não concede outro papel nem perde o contexto necessário para cadastro.
- Navegação por teclado, foco, retorno, estados de erro e telas de 320/390 px são revisados.
- Links existentes e fluxos de demonstração têm migração ou redirecionamento documentado; build e testes de navegação passam.

## Riscos e dependências
Segurança: regressão de autorização e exposição entre organizações. Privacidade: dados de sessão em rotas públicas. Dados: preservar contexto sem incluir relato em URL. Operação: links existentes e rollback por reversão de rotas. Custo: sem serviço novo. Depende da TASK-0026 e das regras de autenticação/tenancy vigentes.

## Testes e pronto
Roteiro por persona cobrindo link direto, CTA, cadastro, login, retorno e acesso indevido, além de build e revisão mobile/acessibilidade. Pronto com ADR, evidências visuais e navegação funcional.
