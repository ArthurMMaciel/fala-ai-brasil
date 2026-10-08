# ADR-0006 — Consulta de CEP por ViaCEP no cadastro

- Estado: aceita como escolha técnica no escopo autorizado
- Data: 2026-10-08
- Tarefa: [TASK-0019](../tasks/TASK-0019-cadastro-planos-e-endereco.md)

## Contexto e autorização
O responsável pediu explicitamente consulta a API de CEP no blur, preenchendo Rua/Avenida nos cadastros de todas as personas. Escolha de provedor CEP não faz parte dos bloqueios humanos específicos de nuvem, identidade, comunicação ou IA do AGENTS.md. Escolher ViaCEP é decisão técnica dentro desse pedido; não autoriza cadastro real nem piloto com dados pessoais.

## Decisão
Consultar ViaCEP diretamente pelo navegador, uma vez por CEP válido ao sair do campo. HTTPS, CEP com oito dígitos, sem cookies ou Referer, timeout de oito segundos e cancelamento de consulta antiga. Nenhuma dependência adicionada. Falhas, CEP inexistente ou sem logradouro permitem recuperação por preenchimento manual. Resposta entra pela propriedade `value`, sem HTML. Número e complemento nunca são enviados nem sobrescritos. Edição manual durante a consulta é preservada.

## Dados e privacidade
Provedor recebe somente CEP na requisição de aplicação, além do IP e metadados inevitáveis de conexão direta. Não recebe nome, CPF/CNPJ, e-mail, número, complemento, relatos ou dados psicossociais. Endereço é dado pessoal, portanto permanece sem persistência nesta POC. Antes de produção, avaliar minimização, transparência, retenção e adequação da chamada direta; eventual proxy exige novo refinamento na fundação da API.

## Operação e custo
Serviço gratuito sem credencial; sem infraestrutura contratada ou promessa de SLA. Uso limitado à consulta pontual, não a validação massiva. Não bloquear cadastro por indisponibilidade externa; CEP deve ter formato válido e Rua/Avenida/número continuam obrigatórios.

## Referência verificada
[Documentação oficial ViaCEP](https://viacep.com.br/), consultada em 2026-10-08: formato de oito dígitos, JSON, campo logradouro, erro para CEP inexistente e restrição a consultas massivas.

## Rollback
Definir `postalCodeProvider` como `pending` para suspender chamadas externas e manter preenchimento manual. Nenhum dado persistido precisa de migração.
