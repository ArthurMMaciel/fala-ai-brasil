# ADR-0008 — Percurso editorial demonstrativo do Figma

- Estado: aceito somente para a POC; autenticação de produção permanece pendente.
- Data: 2026-10-20
- Tarefa: [TASK-0021](../tasks/TASK-0021-figma-direcao-editorial.md)

## Contexto
O responsável autorizou reproduzir o Figma, que apresenta um percurso de quatro etapas e consulta por protocolo/chave, além da área empresarial com revisão antes de publicar. A POC anterior reúne contas e operação em um renderer legado, com dados fictícios. Não existe servidor ou controle de acesso real.

## Decisão delimitada
- Implementar as telas editoriais em componentes React, aproveitando a raiz já existente; desmontar a raiz antes de renderizar telas HTML legadas.
- Oferecer o percurso do Figma sem exigir cadastro, exclusivamente como demonstração volátil nesta aba. Protocolos/chaves têm prefixo público `DEMO` e **não são autenticação**. Não persistir em localStorage, cookies ou banco, nem enviar pela rede.
- Manter as contas, assinaturas e o percurso anterior disponíveis como demonstrações complementares. Os exemplos editoriais têm estado de sessão próprio; não alegar sincronização com os mocks legados.
- Registrar a escolha de compartilhamento no exemplo. Um novo registro, mesmo autorizado, não entra na lista empresarial porque nenhuma revisão humana foi executada. A lista usa apenas projeções fictícias compartilháveis e nunca recebe original, chave ou identidade.
- Separar rascunho empresarial do retorno publicado. Guardar mantém apenas o rascunho; confirmar revisão altera a fila demonstrativa, sem publicar ou modificar o retorno anterior.
- Renderizar entradas como texto pelo React, sem HTML fornecido pelo usuário.
- Complementos exigem prévia, possibilidade de edição e confirmação antes de entrar no histórico local; não alteram a autorização inicial nem são encaminhados à empresa. O original continua consultável somente no percurso do trabalhador.
- A ação explícita “Guardar dados de acesso” copia somente protocolo/chave fictícios e limites da sessão para a área de transferência do navegador. Não copia o relato, não transmite dados e não implementa recuperação ou persistência. Falha de permissão oferece cópia manual. Continua vedado usar dados reais nesta POC.

## Consequências
O trabalho é uma demonstração navegável do design. Não decide autenticação real, RBAC, tenancy, base legal, retenção, exclusão ou promessas públicas de proteção. Esses gates e tarefas continuam pendentes. A implantação de um MVP deve substituir os mocks por contratos e controles aprovados, sem tratar esta consulta como autorização.

## Alternativas
Modificar todo o renderer legado aumentaria o alcance da mudança e o risco nos fluxos comerciais. Reescrever a aplicação ou adicionar framework de estilos seria desproporcional; as telas usam React já instalado e CSS local.

## Reversão
Reverter o commit da TASK-0021. Não há migração, credencial ou infraestrutura nova.
