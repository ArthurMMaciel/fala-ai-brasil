-- MANUTENÇÃO 05: registrar um pedido de "não quero mais receber avisos" (opt-out) da Escuta Aí Brasil.
-- Uso: quem recebeu o aviso à empresa não cadastrada respondeu o e-mail pedindo a exclusão (ADR-0023, revisão de
-- 2026-11-26, aceita em 2026-11-27; quem atende é o responsável).
--
-- Preencha os campos no topo e rode o arquivo INTEIRO uma vez no SQL Editor de produção:
--   - v_email: o e-mail que pediu a exclusão (o remetente da resposta); OU
--   - v_cnpj: o CNPJ da empresa, quando o pedido vier de outro endereço. Exclui o e-mail da Receita desse CNPJ e os
--     e-mails dos contatos que já foram destino de aviso dessa empresa;
--   - v_quem: o e-mail da SUA conta de equipe (fica registrado como autor do opt-out).
-- Pode preencher só o e-mail, só o CNPJ ou os dois. Idempotente: rodar de novo não duplica.
--
-- Efeito: grava só o hash do e-mail em private.notice_opt_outs (o mesmo que ops_add_opt_out faz na Operação). A partir
-- daí, ops_decide_notice recusa aviso a esse e-mail, e um aviso já aprovado e ainda não enviado não sai: a fila confere o
-- opt-out na hora do envio.
-- Não salve este arquivo com os campos preenchidos. Erro = nada foi feito.
begin;

create temp table _opt_in on commit drop as select
  'EMAIL_AQUI'::text               as email,
  'CNPJ_AQUI'::text                as cnpj,
  'SEU_EMAIL_DE_EQUIPE_AQUI'::text as quem;

create temp table _opt_out (fonte text, h text, ja_existia boolean, gravado_agora boolean) on commit drop;  -- h: hash, não exibido

do $optout$
declare
  i record;
  v_email text; v_cnpj text; v_uid uuid; v_hash text; v_existed boolean; v_n int := 0;
  r record;
begin
  select * into i from _opt_in;
  v_email := lower(btrim(coalesce(i.email, '')));
  v_cnpj := regexp_replace(upper(coalesce(i.cnpj, '')), '[^0-9A-Z]', '', 'g');
  if v_email = 'email_aqui' then v_email := ''; end if;
  if v_cnpj = 'CNPJAQUI' then v_cnpj := ''; end if;

  if v_email = '' and v_cnpj = '' then
    raise exception 'Preencha o e-mail ou o CNPJ antes de rodar. Nada foi feito.';
  end if;
  if v_email <> '' and (char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'E-mail inválido. Nada foi feito.';
  end if;
  if v_cnpj <> '' and v_cnpj !~ '^[0-9A-Z]{12}[0-9]{2}$' then
    raise exception 'CNPJ inválido (14 caracteres, sem pontuação ou com). Nada foi feito.';
  end if;
  select a.user_id into v_uid from private.platform_admins a join auth.users u on u.id = a.user_id
  where lower(u.email) = lower(btrim(i.quem));
  if v_uid is null then
    raise exception 'Preencha v_quem com o e-mail de uma conta da equipe (private.platform_admins). Nada foi feito.';
  end if;

  for r in
    select 'e-mail informado' as fonte, v_email as email where v_email <> ''
    union all
    select 'e-mail da Receita do CNPJ', cc.email from private.cnpj_cache cc
    where v_cnpj <> '' and cc.cnpj = v_cnpj and not cc.natural_person and cc.email is not null
    union all
    select 'contato já avisado da empresa', k.email
    from public.companies co
    join public.company_notices n on n.company_id = co.id and n.destination_source = 'worker'
    join public.complaint_contacts k on k.id = n.contact_id
    where v_cnpj <> '' and co.cnpj = v_cnpj and k.email is not null
  loop
    v_n := v_n + 1;
    v_hash := private.email_hash(r.email);
    v_existed := exists (select 1 from private.notice_opt_outs where email_hash = v_hash);
    insert into private.notice_opt_outs (email_hash, added_by) values (v_hash, v_uid) on conflict (email_hash) do nothing;
    insert into _opt_out values (r.fonte, v_hash, v_existed, not v_existed);
  end loop;

  if v_n = 0 then
    raise exception 'O CNPJ não tem e-mail da Receita nem contato já avisado. Peça o e-mail que deve sair da lista. Nada foi feito.';
  end if;
end $optout$;

-- Conferência: uma linha por e-mail tratado, sem mostrar e-mail algum. gravado_na_lista deve ser true em todas.
select o.fonte, o.ja_existia, o.gravado_agora,
       exists (select 1 from private.notice_opt_outs x where x.email_hash = o.h) as gravado_na_lista
from _opt_out o
order by o.fonte;

commit;
