-- #####################################################################################################################
-- ##  MANUTENÇÃO 04 (ALTERNATIVA): criar conta de equipe com e-mail E SENHA.                                         ##
-- ##  ATENÇÃO: a senha digitada aqui FICA NO HISTÓRICO DO SQL EDITOR do painel. Prefira o 03 (conta criada no painel ##
-- ##  e incluída só pelo e-mail). Se usar este, peça à pessoa que troque a senha no primeiro acesso.                  ##
-- #####################################################################################################################
-- Cria a conta já confirmada (senha em bcrypt, como o Auth grava), a identidade de e-mail e inclui na equipe.
-- Sem signup_type: o gatilho handle_new_user não cria perfil, e a conta de equipe não precisa de perfil.
-- Se o e-mail já existir, NÃO mexe na senha: só inclui na equipe (use o 03 nesse caso).
-- Troque os dois valores, rode o arquivo INTEIRO uma vez e NÃO salve o arquivo preenchido. Erro = nada foi feito.
do $admin$
declare
  v_email text := 'EMAIL_AQUI';
  v_senha text := 'SENHA_AQUI';  -- 12 ou mais caracteres
  v_uid uuid;
begin
  if btrim(v_email) = 'EMAIL_AQUI' then raise exception 'Preencha o e-mail. Nada foi feito.'; end if;
  v_email := lower(btrim(v_email));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Preencha um e-mail válido. Nada foi feito.';
  end if;
  if v_senha = 'SENHA_AQUI' or char_length(v_senha) < 12 then
    raise exception 'Preencha uma senha com 12 ou mais caracteres. Nada foi feito.';
  end if;

  select id into v_uid from auth.users where lower(email) = v_email;
  if v_uid is null then
    v_uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data,
                            raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new,
                            email_change, email_change_token_current, reauthentication_token, phone_change, phone_change_token)
    values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email,
            extensions.crypt(v_senha, extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
            '{}', now(), now(), '', '', '', '', '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (v_uid::text, v_uid, jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
  else
    raise notice 'A conta já existia: a senha não foi alterada; só a inclusão na equipe.';
  end if;
  insert into private.platform_admins (user_id) values (v_uid) on conflict do nothing;
end $admin$;

-- Conferência (sem e-mail nem id): total da equipe.
select count(*) as equipe from private.platform_admins;
