-- Destaques no diretório de parceiros: planos Profissional e Nacional com assinatura vigente.
-- Só muda o retorno da função; nenhuma tabela nova e nenhum dado pessoal adicional.
drop function public.list_partner_directory();
create function public.list_partner_directory()
returns table (id uuid, display_name text, specialty text, description text, avatar_path text, city text, state text, requested boolean, featured boolean)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name, p.specialty, p.description, m.storage_path, a.city, a.state,
         exists (select 1 from public.partner_connections pc join public.company_users cu on cu.company_id = pc.company_id
                 where pc.partner_id = p.id and cu.user_id = auth.uid()),
         exists (select 1 from public.subscriptions s
                 where s.partner_id = p.id and s.plan_id in ('partner-professional', 'partner-national')
                   and s.status in ('trialing', 'pending', 'active'))
  from public.partners p
  join public.addresses a on a.id = p.address_id
  left join public.media m on m.id = p.avatar_media_id
  where exists (select 1 from public.company_users cu where cu.user_id = auth.uid())
  order by p.display_name;
$$;
revoke execute on function public.list_partner_directory() from public, anon;
grant execute on function public.list_partner_directory() to authenticated;
