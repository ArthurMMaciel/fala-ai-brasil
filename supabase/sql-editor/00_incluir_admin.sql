-- Passo 00: o responsável se inclui como equipe (private.platform_admins). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Troque SEU_EMAIL_AQUI pelo e-mail com que você entra na plataforma. Não salve este arquivo com o e-mail preenchido.
-- Idempotente: rodar de novo não duplica. Erro = nada foi feito.
do $admin$
declare
  v_email text := 'SEU_EMAIL_AQUI';
  v_uid uuid;
begin
  if v_email like '%AQUI%' or position('@' in v_email) = 0 then
    raise exception 'Preencha o e-mail antes de rodar. Nada foi feito.';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(btrim(v_email));
  if v_uid is null then
    raise exception 'Nenhuma conta com esse e-mail em produção. Cadastre-se no site e confirme o e-mail antes. Nada foi feito.';
  end if;
  insert into private.platform_admins (user_id) values (v_uid) on conflict do nothing;
end $admin$;

-- Conferência (esperado: equipe >= 1). Não mostra e-mail nem id.
select count(*) as equipe from private.platform_admins;
