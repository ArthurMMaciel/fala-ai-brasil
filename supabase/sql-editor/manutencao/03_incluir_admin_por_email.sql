-- MANUTENÇÃO 03 (CAMINHO RECOMENDADO): incluir uma conta na equipe (private.platform_admins) só pelo e-mail.
-- Antes, crie a conta no painel: Authentication > Users > Add user > Create new user, com o e-mail, uma senha forte e
-- "Auto Confirm User" marcado. Assim a senha não passa pelo SQL Editor nem fica no histórico dele.
-- Depois, troque SEU_EMAIL_AQUI abaixo e rode o arquivo INTEIRO uma vez. Idempotente: rodar de novo não duplica.
-- A conta de equipe não precisa de perfil (trabalhador/empresa/parceiro): o acesso à Operação vem só desta tabela.
-- Não salve este arquivo com o e-mail preenchido. Erro = nada foi feito.
do $admin$
declare
  v_email text := 'SEU_EMAIL_AQUI';
  v_uid uuid;
begin
  if btrim(v_email) = 'SEU_EMAIL_AQUI' or position('@' in v_email) = 0 then
    raise exception 'Preencha o e-mail antes de rodar. Nada foi feito.';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(btrim(v_email));
  if v_uid is null then
    raise exception 'Nenhuma conta com esse e-mail. Crie antes em Authentication > Users > Add user. Nada foi feito.';
  end if;
  if not exists (select 1 from auth.users where id = v_uid and email_confirmed_at is not null) then
    raise exception 'A conta existe mas o e-mail não está confirmado. Confirme no painel (ou crie com Auto Confirm). Nada foi feito.';
  end if;
  insert into private.platform_admins (user_id) values (v_uid) on conflict do nothing;
end $admin$;

-- Conferência (sem e-mail nem id): total da equipe.
select count(*) as equipe from private.platform_admins;
