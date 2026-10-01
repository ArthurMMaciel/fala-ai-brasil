# Controle de acesso

## Papéis propostos

- `worker`: cria e acompanha somente suas manifestações.
- `company_member`: acessa conteúdo compartilhável de casos da própria organização.
- `company_admin`: gerencia membros e configurações da própria organização.
- `reviewer`: revisa casos atribuídos conforme política.
- `platform_admin`: administra plataforma; acesso a conteúdo sensível não é automático.
- `auditor`: consulta eventos autorizados, preferencialmente sem conteúdo.

## Matriz inicial

| Recurso/ação | Worker | Company member | Reviewer | Platform admin |
|---|---|---|---|---|
| Criar manifestação | Própria | Não | Não | Não |
| Ver relato original | Próprio | Nunca | Atribuído e justificado | Excepcional e auditado |
| Ver versão protegida | Própria | Tenant próprio | Atribuído | Conforme função |
| Responder caso | Não | Tenant próprio | Não | Simular/mediar conforme política |
| Alterar risco/status | Não | Limitado | Atribuído | Conforme função |
| Gerenciar usuários empresa | Não | Admin do tenant | Não | Suporte auditado |
| Ver auditoria | Próprios eventos limitados | Tenant limitado | Casos atribuídos | Conforme função |

## Restrições

- Autorização sempre no servidor e por recurso; esconder botão não autoriza.
- Negação por padrão; nenhum wildcard de tenant.
- Acesso excepcional requer motivo, prazo e evento de auditoria.
- Testes devem cobrir enumeração de IDs, troca de tenant e escalada horizontal/vertical.
