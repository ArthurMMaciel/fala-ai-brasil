# Deploy e ambientes

## Estado atual

Não há pipeline, hosting, infraestrutura ou ambientes configurados. O único artefato reproduzível validado é o build estático do Vite.

## Direção

- Desenvolvimento local com configuração documentada.
- Homologação isolada com dados sintéticos.
- Produção isolada, aprovação explícita e rollback.
- Infraestrutura declarativa apenas quando o provedor for escolhido.
- Migrações versionadas, backup antes de mudança destrutiva e restore testado.

Nenhum deploy público deve ocorrer antes das tarefas de segurança, privacidade, auth e tenancy essenciais.
