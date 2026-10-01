# Baseline de segurança

## Obrigatório antes de qualquer piloto com dados reais

- HTTPS, headers seguros e política de conteúdo.
- Autenticação server-side, sessões revogáveis e MFA para administração.
- RBAC com escopo de organização, negação por padrão e testes contra IDOR.
- Hash de senha forte; rate limit e proteção contra abuso.
- Secrets fora do código, com rotação e ambientes segregados.
- Validação server-side e encoding de saída; nenhuma interpolação insegura em HTML.
- Criptografia em trânsito e em repouso; backups protegidos.
- Separação de identidade, relato original e versão compartilhável.
- Logs sem relato, PII, token ou segredo; auditoria de acesso a conteúdo privado.
- Dependências e imagens verificadas no CI.
- Processo de vulnerabilidade e resposta a incidente.

## Estado atual

Nenhum desses controles existe como controle de produção. A POC deve usar apenas dados fictícios. Threat model e matriz de acesso estão em `docs/security/`.
