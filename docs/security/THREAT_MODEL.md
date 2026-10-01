# Modelo inicial de ameaças

## Ativos

Identidade, vínculos de trabalho, respostas psicossociais, relato original, versão protegida, contatos de empresa, credenciais, sessões, decisões humanas/IA, auditoria e métricas.

## Atores e fronteiras

- Pessoa manifestante, usuário de empresa e operador interno.
- Navegador, API, banco, worker, IA e integrações externas.
- Cada organização é uma fronteira de isolamento.
- Administração interna não implica acesso irrestrito ao conteúdo original.

## Ameaças prioritárias

| Ameaça/vetor | Impacto | Mitigação necessária |
|---|---|---|
| XSS em relato, nome ou resposta | Roubo de sessão/exposição de dados | Encoding, CSP, componentes seguros, testes |
| IDOR entre casos/empresas | Vazamento grave | Autorização server-side por recurso e tenant |
| Credencial/sessão comprometida | Acesso indevido | MFA admin, sessões revogáveis, rate limit e detecção |
| Reidentificação pelo texto/contexto | Retaliação/dano | Minimização, revisão e métricas de reidentificação |
| Operador abusivo | Exfiltração | Menor privilégio, just-in-time, auditoria e alertas |
| Contato empresarial falso | Relato enviado ao destino errado | Verificação de domínio/representante e aprovação |
| Injection em API/banco | Comprometimento | Queries parametrizadas, validação e privilégios mínimos |
| CSRF | Ação não autorizada | SameSite, token/origin checks conforme sessão |
| SSRF em integrações | Acesso à rede interna | Allowlist, egress control e validação de URLs |
| Prompt injection/data leakage | Saída insegura ou exfiltração | Dados mínimos, isolamento, filtros e revisão humana |
| Upload malicioso (futuro) | Malware/DoS | Não implementar sem quarentena, limites e scanning |
| Logs/backups expostos | Vazamento em massa | Redação, criptografia, acesso e retenção |
| Negação de serviço/brute force | Indisponibilidade | Rate limit, quotas, timeouts e alertas |
| Dependência comprometida | Supply chain | Lockfile, audit, pinning e CI restrito |

## Controles por momento

- Antes de piloto: XSS, auth, tenancy, segregação de dados, consentimento, auditoria e backups.
- Antes de integrações: egress, secrets, idempotência, verificação de destino e contratos.
- Antes de IA: avaliação de fornecedor, dados permitidos, red teaming e revisão humana.

Revisar quando houver novo fluxo, fornecedor, tipo de dado ou mudança de fronteira.
