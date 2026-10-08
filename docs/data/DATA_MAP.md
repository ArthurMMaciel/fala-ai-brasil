# Mapa inicial de dados

| Entidade | Origem/destino | Sensibilidade | Acesso | Retenção | IA | Proteção |
|---|---|---|---|---|---|---|
| Conta e identidade | Usuário → identidade | Alta | Próprio/suporte restrito | A definir | Não | Separação e criptografia |
| Endereço de cadastro (CEP, Rua/Avenida, número e complemento opcional) | Titular → conta privada; consulta externa somente CEP após provedor aprovado | Alta | Próprio; nunca empresa relacionada ao relato | A definir; POC sem persistência | Não | Minimização, consulta sem identidade/número/complemento e preenchimento manual em falha; conexão direta expõe IP ao provedor |
| Assinatura, pedido e pagamento comercial | Organização → cobrança / Stripe | Média/alta | Própria organização e financeiro autorizado; nunca outra empresa | A definir antes de produção; POC volátil | Não | Estados separados de identidade/relato, confirmação no servidor, auditoria, IDs técnicos e catálogo aprovado |
| Vínculo/contexto laboral | Usuário → perfil privado | Alta | Próprio/revisão mínima | A definir | Somente aprovado | Minimização/pseudonimização |
| Relato original | Usuário → cofre privado | Muito alta | Próprio/reviewer autorizado | A definir | Bloqueado por padrão | Chave/acesso/auditoria separados |
| Versão protegida | Revisão → empresa | Alta | Usuário, operação e tenant alvo | Conforme caso | Possível com avaliação | Redação e aprovação |
| Contato empresarial sugerido (nome, e-mail, telefone, cargo) | Manifestante → operação restrita | Média/alta | Operação restrita; empresa somente após validação | Até validação/caso; prazo definitivo pendente | Não | Finalidade explícita, validação, masking e revisão humana para proprietário/sócio |
| Contexto laboral da manifestação | Manifestante → manifestação | Alta | Operação restrita; apenas agregados governados em analytics | Vinculado ao ciclo do caso; prazo definitivo pendente | Não | Separação da identidade e supressão de grupos pequenos |
| Resposta da empresa | Empresa → caso | Alta | Usuário, tenant e operação | Conforme caso | Não por padrão | Autoria e auditoria |
| Eventos de auditoria | Sistema → auditoria | Alta | Segurança/auditoria | Maior que dado operacional, a definir | Não | Append-only, sem conteúdo |
| Métricas agregadas | Operacional → analytics | Média | Perfis autorizados | Por snapshot | Possível após agregação | Limites de grupo/anti-reidentificação |

Campos e prazos são propostas até validação jurídica/LGPD. Nenhum dado real deve ser coletado antes dessa definição.
