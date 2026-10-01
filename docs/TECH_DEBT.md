# Dívida técnica

| ID | Item | Prioridade | Consequência | Estratégia |
|---|---|---|---|---|
| TD-001 | `src/main.ts` concentra UI, estado e regras | P2 | Alto acoplamento e testes difíceis | Extrair por feature após baseline de testes |
| TD-002 | Renderização por `innerHTML` com dados não confiáveis | P0 antes de piloto | XSS e exposição de dados | Escape central + APIs DOM ou framework avaliado |
| TD-003 | Estado apenas em memória | P1 | Perda de dados e POC não operacional | API e PostgreSQL |
| TD-004 | Auth e senha demo no bundle | P1 | Sem segurança real | Sessão server-side e hash de senha |
| TD-005 | Admin e empresa usam o mesmo papel/portal | P1 | Escalada de privilégio e domínio confuso | Modelo explícito de papéis e organização |
| TD-006 | Sem testes | P1 | Regressões e refatoração arriscada | Unitários + integração + E2E crítico |
| TD-007 | Sem lint/format/check de acessibilidade | P2 | Qualidade inconsistente | Ferramentas mínimas no CI |
| TD-008 | Documentos legados misturam alvo e realidade | P2 | Decisões com premissas erradas | Governança nova e links de status |
| TD-009 | Identidade visual/nome inconsistente | P2 | Confusão e retrabalho | ADR de naming antes de migração |
| TD-010 | Sem `.env.example`, ambientes ou deploy | P1 | Setup e operação não reproduzíveis | Definir contratos de configuração e pipeline |
| TD-011 | Datas e dados demo codificados | P3 | Demonstração envelhece | Fixtures isoladas e relógio injetável quando houver testes |
| TD-012 | Validações de domínio vivem na UI | P1 | Bypass no futuro backend | Replicar regra autoritativa no servidor |

Regra: dívida crítica de segurança não entra como “melhoria futura”; bloqueia piloto com dados reais.
