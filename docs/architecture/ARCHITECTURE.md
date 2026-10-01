# Arquitetura atual e alvo

## Atual

```text
Navegador
  └─ Vite/TypeScript
      ├─ main.ts: rotas, estado, renderização e eventos
      ├─ mockData.ts: usuários, empresas, casos e métricas fictícios
      ├─ models.ts: tipos de domínio
      └─ styles.css: design responsivo
```

Não existem componentes de backend, banco, autenticação, mensageria, cache, storage ou integração. A navegação usa estado em memória; atualizar a página reinicia tudo.

## Fluxo implementado

```text
Landing → login/cadastro demo → onboarding → busca empresa
→ criação de manifestação → “revisão IA” simulada → acompanhamento

Portal administrativo demo → casos → comparação original/protegido
→ supervisão simulada → resposta simulada → métricas/ranking mock
```

## Alvo incremental do MVP

```text
Web
  → API (monólito modular)
      ├─ Identidade e acesso
      ├─ Organizações
      ├─ Manifestações
      ├─ Revisão e auditoria
      ├─ Comunicação
      └─ Métricas
  → PostgreSQL
  → Worker de jobs
  → Provedores externos aprovados
```

## Fronteiras de domínio

- Identidade: usuário, credenciais, sessão, consentimentos.
- Organização: empresa, usuários vinculados, verificação e escopo.
- Manifestação privada: identidade/contexto e texto original, acesso restrito.
- Manifestação compartilhável: versão protegida, categoria, status e resposta.
- Operação: revisão humana, decisão, justificativa e filas.
- Comunicação: destinos verificados, mensagens e entrega.
- Analytics: eventos e agregados com limite de reidentificação.

## Regras estruturais

- IDs opacos e autorização em todo acesso a recurso.
- Empresa recebe somente conteúdo compartilhável autorizado.
- Eventos de auditoria são append-only e separados de logs técnicos.
- Transações protegem mudanças de status e seus eventos.
- Jobs externos devem ser idempotentes e retentáveis.

## Evolução sem reescrita

Primeiro modularizar limites no código; depois extrair processos apenas por necessidade de escala, isolamento ou disponibilidade. O banco pode começar único com schemas/tabelas e permissões bem definidas.
