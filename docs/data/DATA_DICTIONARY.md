# Dicionário inicial de dados

| Entidade | Campos mínimos propostos | Observações |
|---|---|---|
| User | id, email normalizado, status, created_at | Nome/apelido opcional e separado quando possível |
| Organization | id, CNPJ, nome, status_verificação | CNPJ validado e histórico de verificação |
| Membership | user_id, organization_id, role, status | Base do isolamento multi-tenant |
| Complaint | id, owner_id, organization_id, status, category, risk, timestamps | Sem texto original na tabela principal |
| ComplaintPrivateContent | complaint_id, encrypted_original, context | Acesso excepcional e auditado |
| ComplaintSharedContent | complaint_id, version, content, approved_by, approved_at | Imutabilidade de versão enviada |
| ContactCandidate | complaint_id, type, normalized_value, source, verification_status | Não enviar antes de verificar destino |
| ReviewDecision | complaint_id, reviewer_id, action, reason, timestamp | Humano responsável explícito |
| CompanyResponse | id, complaint_id, author_membership_id, content, created_at | Somente tenant do caso |
| AuditEvent | id, actor, action, resource, result, timestamp, request_id | Não armazenar conteúdo sensível |

Tipos, constraints e retenção serão definidos junto ao esquema inicial e ADR de dados.
