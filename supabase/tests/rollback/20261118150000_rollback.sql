-- Rollback do lote 2, passo 05 (20261118150000, aba Contratados). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Efeito: some list_my_contracted_partners; company_request_partner volta a aceitar vínculo não verificado. Conexões
-- gravadas ficam. A versão sai de schema_migrations. Erro = nada foi feito; rode `rollback;` sozinho.
begin;
set local lock_timeout = '5s';

do $trava$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118150000') then
    raise exception 'A 20261118150000 não está registrada. Nada foi feito.';
  end if;
end $trava$;

drop function public.list_my_contracted_partners();
-- company_request_partner de 20261027024534, literal.
create or replace function public.company_request_partner(p_partner uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company uuid;
begin
  select company_id into v_company from public.company_users where user_id = auth.uid() order by created_at limit 1;
  if v_company is null then raise exception 'Somente empresas podem sinalizar interesse.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.partners where id = p_partner) then raise exception 'Parceiro não encontrado.' using errcode = 'P0001'; end if;
  insert into public.partner_connections (partner_id, company_id, stage) values (p_partner, v_company, 'company_interest')
  on conflict (partner_id, company_id) do nothing;
end;
$$;

delete from supabase_migrations.schema_migrations where version = '20261118150000';

commit;
