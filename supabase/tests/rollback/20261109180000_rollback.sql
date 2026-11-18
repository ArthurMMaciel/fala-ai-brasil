-- Rollback R4 da 20261109180000 (resposta da empresa passa pela revisão da equipe, ADR-0013). SQL Editor de produção,
-- arquivo INTEIRO, uma vez. Independe dos outros rollbacks.
-- Antes: a Operação libera ou devolve TODAS as respostas em revisão. Com alguma em revisão, este script recusa, porque a
-- política antiga mostraria ao trabalhador resposta não revisada.
-- Efeito: resposta da empresa volta a chegar direto ao trabalhador; a versão sai de schema_migrations. Se a 120000 ou
-- posteriores continuarem registradas, um db push futuro vai pedir --include-all para reaplicar a 180000.
-- Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261109180000') then
    raise exception 'A 20261109180000 não está registrada. Nada foi feito.';
  end if;
  if exists (select 1 from public.company_responses where review_status = 'in_review')
     or exists (select 1 from public.complaints where status = 'answer_in_review') then
    raise exception 'Há resposta em revisão. A Operação libera ou devolve antes. Nada foi feito.';
  end if;
end $trava$;

alter table public.company_responses alter column review_status set default 'released';

-- respond_complaint de 20261109170000, literal.
create or replace function public.respond_complaint(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_status public.complaint_status;
begin
  select company_id, status into v_company, v_status from public.complaints where id = p_id for update;
  if v_company is null or not public.is_company_user(v_company) or v_status not in ('shared', 'answered') then
    raise exception 'Manifestação não disponível para resposta.' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_content, ''))) < 10 then raise exception 'Escreva uma resposta com pelo menos 10 caracteres.' using errcode = 'P0001'; end if;
  insert into public.company_responses (complaint_id, company_id, author_user_id, content, review_status, released_at)
  values (p_id, v_company, auth.uid(), btrim(p_content), 'released', now());
  update public.complaints set status = 'answered' where id = p_id;
  insert into public.complaint_events (complaint_id, status, actor, note) values (p_id, 'answered', 'company', 'Empresa enviou uma resposta institucional.');
end;
$$;

-- Política de 20261027024534, literal.
drop policy responses_read_worker on public.company_responses;
create policy responses_read_worker on public.company_responses for select to authenticated using (public.owns_complaint(complaint_id));
delete from supabase_migrations.schema_migrations where version = '20261109180000';

commit;
-- Conferir: select (select column_default from information_schema.columns where table_schema = 'public'
--   and table_name = 'company_responses' and column_name = 'review_status') as default_atual,  -- esperado 'released'::text
--   (select qual from pg_policies where policyname = 'responses_read_worker') as politica;     -- esperado owns_complaint(complaint_id)
