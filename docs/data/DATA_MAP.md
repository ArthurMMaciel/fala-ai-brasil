# Mapa inicial de dados

| Entidade | Origem/destino | Sensibilidade | Acesso | Retenção | IA | Proteção |
|---|---|---|---|---|---|---|
| Conta e identidade | Usuário → identidade | Alta | Próprio/suporte restrito | A definir | Não | Separação e criptografia |
| Vínculo/contexto laboral | Usuário → perfil privado | Alta | Próprio/revisão mínima | A definir | Somente aprovado | Minimização/pseudonimização |
| Relato original | Usuário → cofre privado | Muito alta | Próprio/reviewer autorizado | A definir | Bloqueado por padrão | Chave/acesso/auditoria separados |
| Versão protegida | Revisão → empresa | Alta | Usuário, operação e tenant alvo | Conforme caso | Possível com avaliação | Redação e aprovação |
| Meio de comunicação | Usuário/base verificada → comunicação | Média/alta | Operação restrita | Até validação/caso | Não | Verificação e masking |
| Resposta da empresa | Empresa → caso | Alta | Usuário, tenant e operação | Conforme caso | Não por padrão | Autoria e auditoria |
| Eventos de auditoria | Sistema → auditoria | Alta | Segurança/auditoria | Maior que dado operacional, a definir | Não | Append-only, sem conteúdo |
| Métricas agregadas | Operacional → analytics | Média | Perfis autorizados | Por snapshot | Possível após agregação | Limites de grupo/anti-reidentificação |

Campos e prazos são propostas até validação jurídica/LGPD. Nenhum dado real deve ser coletado antes dessa definição.
