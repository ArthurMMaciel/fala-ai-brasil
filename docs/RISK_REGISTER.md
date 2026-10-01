# Registro de riscos

Escala: probabilidade (P) e impacto (I) de 1 a 5; exposição = P × I.

| ID | Risco | P | I | Exposição | Tratamento | Dono | Estado |
|---|---|---:|---:|---:|---|---|---|
| R-001 | XSS por conteúdo interpolado em `innerHTML` | 4 | 5 | 20 | Escapar conteúdo, evitar HTML dinâmico e adicionar testes | Tecnologia | Aberto |
| R-002 | Autenticação e autorização apenas simuladas no cliente | 5 | 5 | 25 | Não usar dados reais; implementar auth server-side e RBAC | Tecnologia | Aberto |
| R-003 | Empresa/admin sem fronteiras e sem isolamento por organização | 5 | 5 | 25 | Modelo de tenancy e testes de autorização/IDOR | Tecnologia | Aberto |
| R-004 | Reidentificação por relato/contexto | 4 | 5 | 20 | Separação de dados, revisão humana e critérios de anonimização | Produto/Privacidade | Aberto |
| R-005 | Ausência de Git no diretório atual | 4 | 4 | 16 | Repositório inicializado e baseline publicada | Tecnologia | Mitigado |
| R-006 | Perda de dados por ausência de persistência/backups | 5 | 4 | 20 | Não usar em produção; definir banco, backup e restore testado | Tecnologia | Aberto |
| R-007 | Promessas públicas maiores que controles reais | 4 | 5 | 20 | Revisar linguagem, threat model e evidências antes de piloto | Produto/Jurídico | Aberto |
| R-008 | Dados sensíveis enviados a IA/terceiros | 3 | 5 | 15 | Bloqueio por política até DPIA/avaliação e contrato | Tecnologia/Privacidade | Aberto |
| R-009 | Sem rastreabilidade confiável de ações | 5 | 4 | 20 | Auditoria append-only e identidade de ator | Tecnologia | Aberto |
| R-010 | Sem testes automatizados ou CI | 5 | 4 | 20 | Testes de fluxo/segurança e pipeline mínimo | Tecnologia | Aberto |
| R-011 | Ausência de observabilidade e resposta a incidente | 4 | 4 | 16 | Baseline de logs/métricas/alertas/runbooks | Tecnologia | Aberto |
| R-012 | Dependências sem rotina de atualização/verificação | 3 | 3 | 9 | Dependabot/Renovate, lockfile e audit no CI | Tecnologia | Aberto |
| R-013 | Identidade de marca inconsistente | 4 | 2 | 8 | Decidir nome e executar migração controlada | Produto | Aberto |
| R-014 | Sobrecarga operacional de uma única pessoa | 5 | 4 | 20 | Automação simples, runbooks e limitar serviços | Tecnologia | Aberto |
| R-015 | Contatos de empresa informados por usuário podem estar incorretos/maliciosos | 4 | 4 | 16 | Verificação de domínio/empresa e aprovação antes de envio | Produto/Segurança | Aberto |
| R-016 | Vite 5.4.21 está em faixas afetadas por advisories de dev server de 2026 | 3 | 4 | 12 | Não expor dev server; atualizar para linha corrigida e automatizar audit | Tecnologia | Aberto |

Revisar mensalmente e após mudança de arquitetura, incidente ou início de piloto.
