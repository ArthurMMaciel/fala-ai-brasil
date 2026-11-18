-- Retomar o piloto (ADR-0021). SQL Editor de produção, arquivo INTEIRO, uma vez. Mesmo mecanismo do 05_pausar_piloto.sql.
-- Troque SEU_EMAIL_AQUI e o motivo (10 a 500 caracteres; sem dado de trabalhador, empresa ou relato).
-- Não salve este arquivo preenchido. Erro = nada foi feito.
do $retoma$
declare
  v_email text := 'SEU_EMAIL_AQUI';
  v_motivo text := 'ESCREVA_O_MOTIVO_AQUI';
  v_uid uuid;
begin
  if v_email like '%AQUI%' or v_motivo like '%AQUI%' then
    raise exception 'Preencha e-mail e motivo antes de rodar. Nada foi feito.';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(btrim(v_email));
  if v_uid is null then raise exception 'Nenhuma conta com esse e-mail. Nada foi feito.'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform public.ops_set_pilot_state('open', v_motivo);
end $retoma$;

-- Conferência: esperado estado_atual = open e a última linha da trilha com new_state = open.
select public.pilot_state() as estado_atual,
       (select new_state from public.pilot_state_log order by created_at desc limit 1) as ultima_mudanca,
       (select created_at from public.pilot_state_log order by created_at desc limit 1) as quando;
