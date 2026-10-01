# Plano de observabilidade

## Sinais mínimos

- Logs estruturados: timestamp, nível, serviço, ambiente, request_id, actor_id pseudônimo, ação e resultado.
- Métricas: tráfego, erros, latência, saturação, login, autorização negada, jobs, entregas e fila de revisão.
- Traces: API → banco → job → integração, com sampling e sem payload sensível.
- Auditoria: trilha separada para acesso/alteração de recursos sensíveis.

## Alertas iniciais

- API indisponível ou erro 5xx sustentado.
- Falha de login/anomalia de autorização acima do baseline.
- Fila de revisão/job parada ou crescendo.
- Falha de entrega a empresas.
- Backup/restore check falhou.
- Acesso excepcional a relato original.
- Custo ou volume fora do limite.

## SLOs propostos para piloto

- Disponibilidade mensal: 99,5%.
- P95 de operações comuns: abaixo de 500 ms, excluindo integrações.
- Jobs críticos: 99% processados em até 15 minutos.
- RPO: 24 h; RTO: 4 h inicialmente, a validar com produto.

Não registrar texto de relato, senha, token, cookies, prompt bruto ou resposta sensível em telemetria.
