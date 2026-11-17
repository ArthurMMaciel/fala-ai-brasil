# Rotina de backup gratuito (proposta, TASK-0010)

- Estado: **proposta** em 2026-11-17. Nada foi executado.
- Contexto: plano Free, sem backup automático e sem PITR ([backups](https://supabase.com/docs/guides/platform/backups)). Esta rotina é a única cópia do banco do piloto.

## Limite técnico: a CLI precisa de Docker

O `supabase db dump` roda o `pg_dump` num container ([db dump](https://supabase.com/docs/reference/cli/supabase-db-dump)). Sem Docker, não há dump pela CLI. Há duas saídas, e o responsável escolhe uma:

- **A (recomendada): ligar o Docker Desktop só durante o dump e desligar depois.** O Docker já está instalado (cliente 28.5.1). Não entra dependência nova e o comando é o documentado pelo Supabase. O Docker não precisa ficar ligado no dia a dia.
- **B: instalar o cliente do PostgreSQL 17 (`pg_dump`) no Windows.** Funciona sem Docker, mas é uma dependência nova a manter, e a versão do `pg_dump` precisa ser igual ou maior que a do servidor (17). A conexão usaria a connection string do painel, com a senha em `PGPASSWORD` definida pelo responsável no terminal, nunca na linha de comando.

## Quem executa

O responsável. A senha do banco e a frase da cifragem são dele, e um agente não pode digitá-las. Por isso, uma liberação permanente para agente não faz sentido nesta rotina. O DevOps pode escrever o script (`scripts/backup-prod.ps1`, a fazer depois de aprovada a proposta), revisar os resultados registrados e avisar quando um backup atrasar.

## Frequência proposta

- **Uma vez antes de 30/11:** é a linha de base, ainda sem relato real.
- **No piloto, um por dia útil**, ao fim do expediente. Com até 5 casos novos por dia, a perda máxima é de um dia útil (até 3 dias corridos num fim de semana).
- **Obrigatório antes de cada `db push`**, já que a migration não tem volta automática no Free.

## Passos (cada execução)

1. Docker Desktop ligado (opção A). A senha do banco é digitada quando a CLI pedir.
2. Pasta fora de qualquer repositório: `%USERPROFILE%\escuta-backups\AAAAMMDD-HHMM\`.
3. Dump, com os comandos da [documentação oficial](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore):

   ```bash
   npx supabase db dump --linked -f roles.sql --role-only
   ```

   ```bash
   npx supabase db dump --linked -f schema.sql
   ```

   ```bash
   npx supabase db dump --linked -f data.sql --use-copy --data-only
   ```

   ```bash
   npx supabase db dump --linked -f auth.sql --data-only --schema auth
   ```

   - O dump padrão exclui o schema `auth`. Sem ele, um restore perde as contas de login e o vínculo entre usuário e perfil. O quarto comando cobre isso. **A confirmar no primeiro uso:** se `--schema auth` com `--data-only` traz `auth.users` e `auth.identities`.
   - `auth.sql` tem e-mail e hash de senha, e `data.sql` tem relato e CPF. Os dois só existem em texto claro até o passo 5.
4. **Verificação mínima, sem restaurar.** Ela não prova que o restore funciona.
   - **O arquivo abre:**
     - os quatro arquivos existem e não estão vazios;
     - `schema.sql` e `data.sql` terminam com a linha `-- PostgreSQL database dump complete`, que o `pg_dump` grava ao concluir.
   - **Schema esperado:** cada tabela criada em `supabase/migrations` (`create table public.*`) aparece como `CREATE TABLE` em `schema.sql`. Tabelas apagadas por migrations posteriores ficam fora da lista.
   - **Tabelas com dados:** cada tabela de `public` tem um bloco `COPY public.<tabela>` em `data.sql`. O número de linhas de cada bloco, entre o `COPY` e o `\.`, fica registrado.
   - **Tamanho coerente:** o tamanho de `data.sql` e o total de linhas são comparados com a execução anterior. Uma queda maior que 20% ou um arquivo menor que o da linha de base interrompe a rotina e gera aviso ao DevOps.
   - Opcional, com a mesma liberação: o SELECT read-only de contagem por tabela do [RESTORE_DRILL](RESTORE_DRILL.md), rodado logo antes do dump e comparado com as contagens dos blocos `COPY`. A diferença esperada é só o que entrou no intervalo.
5. **Cifrar e apagar o texto claro.** O GnuPG já vem com o Git for Windows (2.4.8):
   - empacotar os quatro arquivos com `tar`;
   - `gpg --symmetric --cipher-algo AES256`, com a frase guardada no gerenciador de senhas do responsável. A cifragem simétrica não depende do par de chaves pendente (R4.3);
   - testar a leitura: decifrar para a saída padrão e listar o pacote (`gpg -d ... | tar -t`), sem gravar texto claro;
   - apagar os `.sql` e o `.tar` e conferir que só sobrou o `.gpg`.
6. **Rotação:**
   - manter os 7 backups mais recentes e a linha de base pré-piloto;
   - apagar os mais antigos e conferir a exclusão.

   Com 7 dias de retenção, um pedido de exclusão de dados pela LGPD sai dos backups em até uma semana. O prazo final de retenção é decisão do responsável e entra na política do piloto.
7. **Cópia fora da máquina:** recomendada, porque com uma única cópia no mesmo computador, perder o computador leva o backup junto.
   - Opções: disco externo, ou a pasta de nuvem pessoal do responsável, só com o `.gpg`.
   - Mandar o arquivo cifrado a um terceiro é decisão do responsável.
8. **Registro na TASK-0010**, sem dados:
   - data e hora;
   - tamanho do `.gpg`;
   - linhas por tabela;
   - resultado da verificação;
   - confirmação de que o texto claro foi apagado.

## Riscos residuais

- **A restauração não está ensaiada** (ver [RESTORE_DRILL](RESTORE_DRILL.md)). A verificação mínima mostra que o arquivo está completo e coerente. Ela não prova que ele carrega num banco.
- Os arquivos do Storage (bucket `partner-media`) não entram no dump.
- O backup depende da disciplina diária de uma pessoa, que é também o operador único do piloto. Um backup esquecido não gera alarme automático.
- Perder a frase da cifragem torna os backups ilegíveis.

## Rollback

A rotina não altera produção: o dump só lê. Para parar, basta não executar mais. Os `.gpg` existentes são apagados conforme a rotação.
