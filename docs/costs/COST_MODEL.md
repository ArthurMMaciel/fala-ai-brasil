# Modelo de custos

Estimativas são ordens de grandeza mensais, sem provedor definido, e excluem mão de obra/impostos.

| Componente | MVP | 1 mil usuários | 10 mil | 100 mil | Driver |
|---|---:|---:|---:|---:|---|
| Web/API/worker | R$ 150–600 | R$ 300–1.200 | R$ 1–4 mil | R$ 5–20 mil | requests/CPU |
| PostgreSQL + backup | R$ 150–700 | R$ 300–1.000 | R$ 1–5 mil | R$ 5–25 mil | storage/IO/HA |
| E-mail/mensagens | R$ 0–300 | R$ 100–800 | R$ 800–6 mil | R$ 6–50 mil | mensagens/canal |
| Logs/monitoramento | R$ 0–400 | R$ 100–800 | R$ 800–5 mil | R$ 5–30 mil | ingestão/retenção |
| IA | R$ 0 no início | R$ 0–1 mil | R$ 1–10 mil | R$ 10–100 mil+ | tokens/modelo/revisões |
| Domínio/serviços | R$ 20–200 | R$ 20–300 | R$ 100–1 mil | R$ 500–5 mil | fornecedores |

## Controles

- Budget e alertas desde homologação.
- Limites de retenção, sampling e quotas.
- Medir custo por manifestação e por organização.
- IA fica zerada até experimento aprovado.
- Reestimar após escolher região, SLA, canais e política de backup.
