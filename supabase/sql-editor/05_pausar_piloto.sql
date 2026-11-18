-- Pausar o piloto (ADR-0021; uso: SEV-1 do runbook PILOT_SUSPENSION). SQL Editor de produção, arquivo INTEIRO, uma vez.
-- Só depois do passo 04 (20261117150000) e do passo 00 (você na equipe).
-- No SQL Editor auth.uid() é nulo; por isso o script assume, só dentro desta transação, a identidade da sua conta de equipe
-- e chama a mesma função que uma tela chamaria (ops_set_pilot_state). Ela confere is_platform_admin(), troca o estado e
-- grava a trilha em pilot_state_log com você como autor.
-- Troque SEU_EMAIL_AQUI e o motivo (10 a 500 caracteres; sem dado de trabalhador, empresa ou relato).
-- Não salve este arquivo preenchido. Erro = nada foi feito.
do $pausa$
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
  perform public.ops_set_pilot_state('paused', v_motivo);
end $pausa$;

-- Conferência: esperado estado_atual = paused e a última linha da trilha com new_state = paused.
select public.pilot_state() as estado_atual,
       (select new_state from public.pilot_state_log order by created_at desc limit 1) as ultima_mudanca,
       (select created_at from public.pilot_state_log order by created_at desc limit 1) as quando;
