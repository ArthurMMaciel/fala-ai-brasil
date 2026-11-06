# TASK-0034 — Content Security Policy (CSP) no front da Vercel

- Status: em-andamento
- ClickUp: (preencher após a criação)
- Área: Segurança/DevOps
- Prioridade: P0, item do gate do piloto ([TASK-0033](TASK-0033-gate-tecnico-piloto-fechado.md))
- Estimativa: 0,5 a 1 dia por fase
- Impacto: segunda barreira contra XSS. Se um escape falhar, o navegador continua bloqueando script de fora e script inline.
- Relacionadas: [TASK-0002](TASK-0002-eliminar-xss-na-poc.md) (escapes, PR #13), parecer em `docs/devops/PARECER-PLATAFORMA-PILOTO-2026-11.md`

## Problema
O renderer legado (`src/app/main.js`) monta HTML como texto e grava com `innerHTML`. Hoje a única defesa contra XSS são os escapes da TASK-0002. Sem CSP, qualquer escape esquecido no futuro vira execução de script com a sessão Supabase da pessoa. Para o trabalhador, isso significa acesso ao relato original. A produção só envia `Strict-Transport-Security`; nenhum cabeçalho CSP é enviado.

## Contexto
Aprovado pelo responsável em 2026-11-06, por meio da sessão Gestor, em duas fases. O front é estático (Vite) na Vercel, e os cabeçalhos ficam em `vercel.json`, sem custo no plano atual. O build gera um único `<script type="module" src>` externo, sem script inline. O bundle não usa `eval` nem `new Function`. O HTML gerado por `main.js` tem cerca de 30 atributos `style=""`.

## Objetivo
Fase 1: publicar a política em modo `Content-Security-Policy-Report-Only`, verificar todos os fluxos no Preview e ajustar a política até não haver violação.
Fase 2: trocar para `Content-Security-Policy`, que bloqueia de fato.

## Política (fase 1)

```
default-src 'self';
script-src 'self';
style-src 'self' 'unsafe-inline';
img-src 'self' https: data: blob:;
font-src 'self';
media-src 'self';
connect-src 'self' https://nkxfhctqfqroyfmihsns.supabase.co wss://nkxfhctqfqroyfmihsns.supabase.co https://viacep.com.br;
object-src 'none';
base-uri 'self';
form-action 'self'
```

- O host do Supabase é a URL pública que já aparece no bundle de produção. Não é segredo, e nenhuma chave vai no `vercel.json`.
- `style-src 'unsafe-inline'` é aceito no piloto por causa dos `style=""` do renderer legado. O risco residual é injeção de CSS, não de script. Migrar esses estilos para classes é melhoria posterior.
- `img-src https:` cobre fotos do Storage e links externos de imagem. Restringir ao host do Supabase pode vir depois, na revisão de conteúdos do parceiro.
- `frame-ancestors 'none'` fica para a fase 2: os navegadores ignoram essa diretiva em política Report-Only e geram aviso no console.

## Escopo
- Fase 1: `vercel.json` com o cabeçalho Report-Only, validação do build e roteiro no Preview: landing, login, cadastro até o CEP, portais de trabalhador, empresa, parceiro e Operação, Storage e links do YouTube. Registro das violações e ajuste da política.
- Fase 2: trocar o nome do cabeçalho, acrescentar `frame-ancestors 'none'` e repetir o roteiro. Só depois do merge da fase 1 e de nova autorização do responsável.

## Fora de escopo
Endpoint de relatório (`report-to`), porque não há backend para receber os relatos de violação. Nonces e hashes. Remoção dos estilos inline. Outros cabeçalhos (`X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`), que podem entrar como tarefa própria.

## Critérios de aceite
- O build não tem script inline nem atributo `on*` no `index.html` gerado.
- O Preview envia o cabeçalho Report-Only, e o console fica sem violação nos fluxos do escopo. Se houver violação, ela fica listada com a mudança feita na política.
- O PR da fase 1 é aberto contra `main`, sem merge, com a lista de violações.

## Riscos
- Na fase 2, uma origem esquecida em `connect-src` quebra login ou cadastro. A fase 1 existe para pegar isso.
- O Preview pode apontar para o Supabase de produção. Nesse caso a verificação se limita a login e leitura, sem criar nem alterar dados.

## Dependências
Deploy de Preview da Vercel ligado ao repositório. Variáveis `VITE_` do escopo Preview.

## Segurança
Nenhum segredo no `vercel.json`. As contas de teste não têm senha impressa nem registrada; o login no Preview é feito pela pessoa responsável quando o Preview usa o banco de produção.

## Dados envolvidos
Nenhum dado novo. O navegador só registra violações localmente, no console.

## Observabilidade
Console do navegador na fase 1. Endpoint de relatório só quando houver backend próprio, sem payload sensível (TASK-0002).

## Rollback
Remover o cabeçalho, ou o `vercel.json`, e fazer novo deploy. Na fase 2, voltar para `-Report-Only` resolve um bloqueio inesperado sem perder o monitoramento.

## Testes necessários
`npx vite build`, inspeção do `dist/index.html`, roteiro no Preview com o console aberto e checagem do cabeçalho por `curl -I`.

## Resultado da fase 1
(preencher com as violações encontradas ou "nenhuma")

## Definição de pronto
Fase 2 em produção, com console limpo nos fluxos do escopo e evidência registrada no gate da TASK-0033.
