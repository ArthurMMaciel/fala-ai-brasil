# Runbook — Plataforma indisponível

**Detectar:** health check, erro 5xx ou jornada crítica falhando. **Severidade:** SEV-1 se todos os usuários; SEV-2 se parcial.

1. Declarar incidente, responsável e horário; congelar deploys.
2. Confirmar escopo por região/serviço sem usar dados de usuário.
3. Verificar último deploy, capacidade, DNS/TLS, API e banco.
4. Reverter o último deploy/config se houver correlação segura; ativar página de status.
5. Validar login e criação/consulta sintética após recuperação.
6. Comunicar impacto e próximos horários, sem especular causa.
7. Preservar logs, timeline e mudanças; abrir pós-incidente e tarefas.

**Escalar:** segurança/privacidade se houver sinal de ataque ou exposição. **Fechar:** SLO estável por 30 minutos e backlog de recuperação processado.
