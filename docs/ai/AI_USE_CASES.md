# Casos de uso de IA

Nenhum caso está aprovado para produção.

| Caso | Classe | Entrada | Saída | Risco | Revisão humana | Métrica |
|---|---|---|---|---|---|---|
| Sugerir categoria | Assistiva | Versão minimizada do relato | Categoria/confiança | Médio | Sim no início | F1 por categoria |
| Detectar identificadores | Recomendação | Relato privado controlado | Trechos/rótulos | Alto | Sempre antes de envio | Recall e vazamento residual |
| Propor versão protegida | Recomendação | Relato + política | Texto sugerido | Alto | Sempre | Reidentificação e fidelidade |
| Sugerir risco | Recomendação | Conteúdo/contexto permitido | Nível + razões | Muito alto | Obrigatória; nunca decisão clínica | Falso negativo por classe |
| Resumir resposta | Assistiva | Resposta institucional | Resumo | Médio | Usuário vê original | Fidelidade |

## Gate para experimento

Definir dataset sintético/anotado, critérios de aceitação, provedor/modelo, região, contrato, retenção, custo por caso, fallback, versionamento e processo de incidente. Não usar relatos reais para experimentação informal.
