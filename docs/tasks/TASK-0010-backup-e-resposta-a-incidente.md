# TASK-0010 — Backup, restore e resposta a incidente

- Status: proposta
- Área: DevOps/SRE/Segurança
- Prioridade: P1
- Estimativa: 3–5 dias
- Impacto: reduz perda de dados e tempo de recuperação

## Problema
Não há backup nem runbooks executáveis.
## Contexto
Dados sensíveis exigem recuperação e contenção comprováveis.
## Objetivo
Definir RPO/RTO, backup criptografado, restore testado e runbooks prioritários.
## Escopo
Backup DB/config relevante, exercício de restore e oito cenários do índice.
## Fora de escopo
DR multi-região antes de necessidade.
## Critérios de aceite
Restore em ambiente isolado cumpre RPO/RTO; responsáveis e contatos definidos; evidências registradas.
## Riscos
Backup ilegível, permissões excessivas e retenção conflitante.
## Dependências
Infra/provedor e TASK-0008/0009.
## Segurança
Criptografia, acesso restrito, rotação e exclusão coerente.
## Dados envolvidos
Banco e metadados operacionais.
## Observabilidade
Sucesso, idade e tamanho do backup; falha de restore drill.
## Rollback
Manter geração anterior até validar nova política.
## Testes necessários
Restore completo, corrupção simulada e tabletop de incidente.
## Definição de pronto
Restore comprovado e runbooks aprovados/testados.
