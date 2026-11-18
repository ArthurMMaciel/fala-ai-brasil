-- GERADO por supabase/sql-editor/build.mjs a partir de supabase/migrations/20261109180000_resposta_revisada_ativa.sql. Não editar à mão.
-- Passo 01 de 04. SQL Editor de produção: colar o arquivo INTEIRO e rodar UMA vez.
-- Tudo ou nada (begin ... commit). Se aparecer erro, nada foi gravado: rode `rollback;` sozinho e avise o Back.
-- Depois de rodar: 01_conferir_20261109180000.sql (todas as linhas com ok = true).
-- AVISO: a partir deste passo, toda resposta de empresa espera a revisão do operador antes de chegar ao trabalhador.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261109180000') then
    raise exception 'A migration 20261109180000 já está registrada. Nada foi feito; não rode de novo.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261109170000') then
    raise exception 'Falta a 20261109170000 (passo anterior). Nada foi feito.';
  end if;
  if not exists (select 1 from private.platform_admins) then
    raise exception 'Ninguém na equipe (private.platform_admins). Rode o passo 00 antes: sem equipe, as respostas ficariam presas em revisão. Nada foi feito.';
  end if;
end $trava$;

-- ======== início da migration 20261109180000_resposta_revisada_ativa.sql (4 instruções) ========
-- TASK-0035 / ADR-0013, passo (d): a resposta da empresa passa pela equipe antes de chegar ao trabalhador.
-- Só aplicar DEPOIS do front tolerante (passo c) estar em produção: ele precisa conhecer 'answer_in_review'
-- e ler review_status/worker_summary.
-- Rollback: liberar ou devolver pela Operação todas as respostas em revisão ANTES de reverter (nunca expor ao trabalhador
-- resposta não revisada); depois reaplicar respond_complaint de 20261109170000, a política responses_read_worker de
-- 20261027024534 e o default 'released'.

alter table public.company_responses alter column review_status set default 'in_review';

-- Empresa responde: a resposta fica em revisão; com uma em revisão, não envia outra.
create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_company_user(v_company) or v_status not in ('shared', 'answer_in_review', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if v_status = 'answer_in_review' or exists (select 1 from public.company_responses where complaint_id = p_id and review_status = 'in_review') then
    raise exception 'Já existe uma resposta em revisão pela equipe.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'in_review');
  update public.complaints set status = 'answer_in_review' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, 'answer_in_review', 'company', 'A empresa respondeu. A equipe revisa a resposta antes de você receber.');
end;
$$;

-- Trabalhador só lê respostas liberadas (conteúdo revisado e descrição da equipe).
drop policy responses_read_worker on public.company_responses;
create policy responses_read_worker on public.company_responses for select to authenticated
  using (review_status = 'released' and public.owns_complaint(complaint_id));
-- ======== fim da migration ========

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261109180000', 'resposta_revisada_ativa', array[
$s0$-- TASK-0035 / ADR-0013, passo (d): a resposta da empresa passa pela equipe antes de chegar ao trabalhador.
-- Só aplicar DEPOIS do front tolerante (passo c) estar em produção: ele precisa conhecer 'answer_in_review'
-- e ler review_status/worker_summary.
-- Rollback: liberar ou devolver pela Operação todas as respostas em revisão ANTES de reverter (nunca expor ao trabalhador
-- resposta não revisada); depois reaplicar respond_complaint de 20261109170000, a política responses_read_worker de
-- 20261027024534 e o default 'released'.

alter table public.company_responses alter column review_status set default 'in_review'$s0$,
$s0$-- Empresa responde: a resposta fica em revisão; com uma em revisão, não envia outra.
create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_company_user(v_company) or v_status not in ('shared', 'answer_in_review', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if v_status = 'answer_in_review' or exists (select 1 from public.company_responses where complaint_id = p_id and review_status = 'in_review') then
    raise exception 'Já existe uma resposta em revisão pela equipe.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'in_review');
  update public.complaints set status = 'answer_in_review' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note)
  values (p_id, 'answer_in_review', 'company', 'A empresa respondeu. A equipe revisa a resposta antes de você receber.');
end;
$$$s0$,
$s0$-- Trabalhador só lê respostas liberadas (conteúdo revisado e descrição da equipe).
drop policy responses_read_worker on public.company_responses$s0$,
$s0$create policy responses_read_worker on public.company_responses for select to authenticated
  using (review_status = 'released' and public.owns_complaint(complaint_id))$s0$
]::text[]);

commit;
