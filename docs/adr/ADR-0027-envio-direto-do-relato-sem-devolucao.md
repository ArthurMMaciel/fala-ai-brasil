# ADR-0027 — Envio direto do relato à empresa, sem versão separada e sem devolução

- Estado: **Aceita** pelo responsável em 2026-11-27, nesta sessão ("Sim, sem reter"), para a apresentação de 2026-12-01. Nada foi implementado ainda.
- Data: 2026-11-27
- Substitui em parte: ADR-0010 (revisão humana antes do compartilhamento: saem "pedir ajuste" e "reter"; a versão compartilhável escrita à parte deixa de existir na tela)
- Altera: regra do `AGENTS.md` "Não misturar relato original com versão compartilhável" — passa a valer só no banco (as duas colunas continuam), não na experiência
- Relacionadas: ADR-0013 (resposta revisada, **não alterada** por esta ADR), ADR-0025 (IA revisora, segue proposta), ADR-0026

## Decisão

D1. **A empresa lê o texto que o trabalhador escreveu.** O assistente deixa de pedir uma versão separada. Na etapa final, o trabalhador vê o relato em modo leitura, pode clicar em "Alterar relato" para editar e salvar, e envia com o botão "Enviar manifestação". Saem "Guardar sem compartilhar", o campo "Versão que será enviada à empresa" e "Sugerir versão revisada".

D2. **A equipe só libera.** Na Operação, a decisão tem um único botão: "Liberar para a empresa". Saem "Pedir ajuste ao trabalhador", "Reter para análise" e o campo de motivo. A equipe nunca devolve nada ao trabalhador.

D3. **Sem mudança de banco.** A tela envia o texto do relato também como versão compartilhável (`share_complaint` com o mesmo texto). Original e compartilhável continuam em colunas separadas, o que permite voltar atrás sem migration. `ops_decide_complaint` continua aceitando os três valores; só a interface deixa de oferecer dois deles.

D4. **Aviso obrigatório antes do envio**, fixo na etapa final: "A empresa vai ler exatamente este texto, sem o seu nome. Antes de enviar, tire nomes, datas, setores e qualquer detalhe que identifique você ou outras pessoas." Texto final com o responsável.

D5. **Textos públicos deixam de prometer o que saiu.** Retirar ou reescrever, na landing e nos portais: "Fica protegido: o relato original", "Você escolhe o que compartilhar", "Escolha o que pode ser compartilhado", "versão compartilhável liberada pelo trabalhador" e equivalentes.

## Riscos aceitos pelo responsável

| Risco | Consequência | O que ainda protege |
|---|---|---|
| O texto identifica quem relatou ou terceiros (nomes, datas, setor) | Exposição do trabalhador e possível retaliação, sobretudo em empresa pequena | Aviso D4; a equipe pode simplesmente não clicar em "Liberar" enquanto conversa com o responsável |
| Caso de alto risco (ameaça, risco de vida) sem forma registrada de segurar | Contraria a regra "casos de alto risco não geram contato externo automático" se a liberação um dia for automática | Liberação continua manual; os canais de emergência seguem no assistente. **Qualquer envio automático (IA) exige reintroduzir uma retenção antes** |
| Texto ofensivo ou difamatório chega à empresa sem edição | Risco jurídico (ver `docs/product-intelligence/MARKET_ANALYSIS.md` §5) | Liberação manual |
| Casos antigos em "aguardando ajuste" ou "retido" | Ficam parados sem botão para mexer | A equipe libera esses casos pela tela de detalhe (o botão "Liberar" continua) ou o Back lista e trata por SQL |

## Fora desta ADR

- IA para classificar o nível e enviar ou receber automaticamente: próximo passo, depende da ADR-0025, de avaliação de privacidade e de uma retenção para alto risco.
- Revisão da resposta da empresa (ADR-0013): **continua** — decisão do responsável em 2026-11-27 ("Continua revisando"). A equipe segue revisando a resposta antes de ela chegar ao trabalhador, inclusive podendo devolvê-la à empresa.

## Especificação para o Front

1. `src/portals/complaint-wizard.tsx`, etapa final ("Revisão protegida", ~linha 234):
   - título "Revise seu relato"; texto do relato em modo leitura e botão "Alterar relato", que volta à etapa do relato (ou edita no lugar) e salva;
   - remover o painel "Versão que será enviada à empresa" e o "Sugerir versão revisada";
   - remover "Guardar sem compartilhar" e "Quero ajustar meu relato" (substituído por "Alterar relato");
   - botão principal "Enviar manifestação", chamando o envio com `shared = original`;
   - aviso D4 acima do botão.
2. `src/portals/ops-portal-live.tsx`: decisão só com "Liberar para a empresa" (linha 39 e bloco da decisão); remover campo de motivo e contador de 469 caracteres; texto da fila (linha 232) sem "pedir ajuste" e "reter".
3. Portal do trabalhador: estados "aguardando ajuste" deixam de ser alcançáveis; manter a exibição para casos antigos.
4. Landing e textos públicos conforme D5 (`src/landing-site/pages/inicio.tsx` linhas 14, 64 e 84; `empresa.tsx` seção "O que a sua empresa vê").
5. "Vamos conversar": tirar o formulário da página do Trabalhador (`inicio.tsx:112`) e a escolha de perfil do formulário (`site-parts.tsx:158`), usando o `perfil` da página.
6. Testes afetados: ajustar os que conferem os rótulos de decisão e a etapa final; `npm test` e build verdes antes do push.

## Rollback

Voltar os arquivos do front pelo Git. Banco intacto (D3).
