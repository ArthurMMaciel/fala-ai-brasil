-- Contagem dos dados de demonstração em produção (TASK-0010)
-- Só leitura: um único SELECT, sem escrita, sem função que altere estado.
-- Devolve apenas nomes de métrica e números. Nenhum e-mail, nome, CPF ou CNPJ sai na tela.
-- Quem roda: o responsável, no SQL Editor do Supabase de produção.
-- Marcador do seed (scripts/seed-demo-data.mjs e contas *.teste): e-mail em auth.users terminando em @example.com.
-- Esperado se o seed rodou inteiro: 20 contas do seed mais as contas *.teste, 19 relatos, 10 respostas,
-- 9 conexões e 6 campanhas aprovadas (ver TASK-0010, "Dados de demonstração em produção").
-- Valores 0 em tudo indicam que o seed nunca rodou em produção.

with demo_users as (
  select id from auth.users where lower(email) like '%@example.com'
),
demo_companies as (
  select distinct cu.company_id as id from public.company_users cu join demo_users d on d.id = cu.user_id
),
demo_workers as (
  select w.id from public.workers w join demo_users d on d.id = w.user_id
),
demo_partners as (
  select p.id from public.partners p join demo_users d on d.id = p.user_id
),
demo_sponsors as (
  select s.id from public.sponsors s join demo_users d on d.id = s.user_id
)
select metrica, total from (values
  (1,  'contas_total',                      (select count(*) from auth.users)),
  (2,  'contas_demo_example_com',           (select count(*) from demo_users)),
  (3,  'contas_fora_do_demo',               (select count(*) from auth.users where lower(email) not like '%@example.com' or email is null)),
  (4,  'empresas_demo',                     (select count(*) from demo_companies)),
  (5,  'trabalhadores_demo',                (select count(*) from demo_workers)),
  (6,  'parceiros_demo',                    (select count(*) from demo_partners)),
  (7,  'patrocinadores_demo',               (select count(*) from demo_sponsors)),
  (8,  'relatos_total',                     (select count(*) from public.complaints)),
  (9,  'relatos_demo_trab_e_empresa_demo',  (select count(*) from public.complaints c where c.worker_id in (select id from demo_workers) and c.company_id in (select id from demo_companies))),
  (10, 'relatos_trab_real_empresa_demo',    (select count(*) from public.complaints c where c.worker_id not in (select id from demo_workers) and c.company_id in (select id from demo_companies))),
  (11, 'relatos_trab_demo_empresa_real',    (select count(*) from public.complaints c where c.worker_id in (select id from demo_workers) and c.company_id not in (select id from demo_companies))),
  (12, 'respostas_em_relato_demo',          (select count(*) from public.company_responses r join public.complaints c on c.id = r.complaint_id where c.worker_id in (select id from demo_workers))),
  (13, 'conexoes_parceiro_demo',            (select count(*) from public.partner_connections pc where pc.partner_id in (select id from demo_partners))),
  (14, 'conexoes_parceiro_demo_empresa_real', (select count(*) from public.partner_connections pc where pc.partner_id in (select id from demo_partners) and pc.company_id not in (select id from demo_companies))),
  (15, 'campanhas_de_patrocinador_demo',    (select count(*) from public.campaigns c where c.sponsor_id in (select id from demo_sponsors))),
  (16, 'patrocinadores_na_landing_total',   (select count(*) from public.list_public_sponsors())),
  (17, 'patrocinadores_demo_na_landing',    (select count(*) from public.list_public_sponsors() l where l.id in (select id from demo_sponsors)))
) as t(ordem, metrica, total)
order by ordem;
