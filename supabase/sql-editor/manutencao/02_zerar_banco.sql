-- #####################################################################################################################
-- ##  MANUTENÇÃO 02: ZERAR O BANCO.  IRREVERSÍVEL.  NÃO HÁ BACKUP.                                                      ##
-- ##  Apaga TODAS as contas que não são da equipe e TODOS os dados de aplicação: relatos, empresas, parceiros,        ##
-- ##  patrocinadores, respostas, avisos, contatos, campanhas, assinaturas, endereços, contatos da landing, aceites... ##
-- ##  Depois do commit não há como desfazer. Rode antes o 01_previa_zerar_banco.sql e confira os números.             ##
-- #####################################################################################################################
--
-- Fica: as contas em private.platform_admins (e os perfis delas, se houver: trabalhador, empresa, parceiro,
-- patrocinador, com endereço, assinatura e mídia), private.document_officers da equipe, public.plans,
-- private.legal_documents, private.platform_settings (estado do piloto) e supabase_migrations.schema_migrations.
-- A sequência dos protocolos (EAB-…) NÃO é reiniciada: números já vistos por empresas não voltam a ser usados.
-- Arquivos do Storage NÃO são apagados por SQL: ver LEIA-ME (limpar pelo painel, se houver).
-- Os gatilhos de trilha imutável são desligados SÓ dentro desta transação e religados antes do commit.
--
-- Como rodar: troque 'NAO' por 'APAGAR TUDO' na linha de v_confirmo, cole o arquivo INTEIRO no SQL Editor de produção
-- e rode UMA vez. Erro = nada foi apagado; rode `rollback;` sozinho. A última consulta mostra zero em tudo e a equipe.
begin;
set local lock_timeout = '10s';

do $zerar$
declare
  v_confirmo text := 'NAO';  -- <<< troque por 'APAGAR TUDO' para confirmar
  v_admins integer;
  v_t text;
  v_imutaveis text[][] := array[
    ['public.company_notices', 'company_notices_guard'],
    ['public.legal_acceptances', 'legal_acceptances_immutable'],
    ['public.pilot_state_log', 'pilot_state_log_immutable'],
    ['public.representative_verifications', 'representative_verifications_immutable']];
  i integer;
begin
  if v_confirmo is distinct from 'APAGAR TUDO' then
    raise exception 'Confirmação ausente: troque NAO por APAGAR TUDO em v_confirmo. Nada foi apagado.';
  end if;
  select count(*) into v_admins from private.platform_admins a join auth.users u on u.id = a.user_id where u.email is not null;
  if v_admins = 0 then
    raise exception 'Nenhuma conta de equipe com e-mail em private.platform_admins: o banco ficaria sem acesso. Nada foi apagado.';
  end if;

  -- Conjuntos que ficam (perfis da equipe).
  create temp table z_keep_companies on commit drop as
    select distinct cu.company_id as id from public.company_users cu join private.platform_admins a on a.user_id = cu.user_id;
  create temp table z_keep_partners on commit drop as
    select p.id from public.partners p join private.platform_admins a on a.user_id = p.user_id;
  create temp table z_keep_sponsors on commit drop as
    select s.id from public.sponsors s join private.platform_admins a on a.user_id = s.user_id;
  create temp table z_keep_addresses on commit drop as
    select w.address_id as id from public.workers w join private.platform_admins a on a.user_id = w.user_id
    union select address_id from public.companies where id in (select id from z_keep_companies)
    union select address_id from public.partners where id in (select id from z_keep_partners)
    union select address_id from public.sponsors where id in (select id from z_keep_sponsors);

  -- Trilhas imutáveis: desligadas só nesta transação.
  for i in 1 .. array_length(v_imutaveis, 1) loop
    if to_regclass(v_imutaveis[i][1]) is not null
       and exists (select 1 from pg_trigger where tgrelid = to_regclass(v_imutaveis[i][1]) and tgname = v_imutaveis[i][2]) then
      execute format('alter table %s disable trigger %I', v_imutaveis[i][1], v_imutaveis[i][2]);
    end if;
  end loop;

  -- Dados de aplicação (dos filhos para os pais).
  if to_regclass('private.notification_outbox') is not null then execute 'delete from private.notification_outbox'; end if;
  delete from public.company_notices;
  delete from public.complaint_contacts;
  delete from private.complaint_notice_consents;
  delete from public.original_access_log;
  delete from public.response_ratings;
  delete from public.company_response_reviews;
  delete from public.company_responses;
  delete from public.complaint_reviews;
  delete from public.complaint_events;
  delete from public.complaint_shared_versions;
  delete from public.complaint_originals;
  delete from public.complaints;
  delete from private.notice_opt_outs;
  delete from private.cnpj_cache;
  delete from private.cnpj_lookup_quota;
  delete from public.representative_verifications;
  delete from public.partner_connections;
  delete from public.campaigns;
  delete from public.contact_solicitations;
  delete from public.legal_acceptances;
  delete from public.pilot_state_log;
  delete from public.profile_change_log;

  -- Perfis que não são da equipe.
  delete from public.subscriptions
  where not (company_id in (select id from z_keep_companies) or partner_id in (select id from z_keep_partners)
             or sponsor_id in (select id from z_keep_sponsors));
  delete from public.media where partner_id not in (select id from z_keep_partners);
  delete from public.company_users where user_id not in (select user_id from private.platform_admins);
  delete from private.company_preregistrations where company_id not in (select id from z_keep_companies);
  delete from public.companies where id not in (select id from z_keep_companies);
  delete from public.partners where id not in (select id from z_keep_partners);
  delete from public.sponsors where id not in (select id from z_keep_sponsors);
  delete from public.workers where user_id not in (select user_id from private.platform_admins);
  delete from public.addresses where id not in (select id from z_keep_addresses where id is not null);
  delete from private.document_officers where user_id not in (select user_id from private.platform_admins);

  -- Contas que não são da equipe (sessões, identidades e fatores saem em cascata no esquema auth).
  delete from auth.users where id not in (select user_id from private.platform_admins);

  -- Religa as trilhas imutáveis.
  for i in 1 .. array_length(v_imutaveis, 1) loop
    if to_regclass(v_imutaveis[i][1]) is not null
       and exists (select 1 from pg_trigger where tgrelid = to_regclass(v_imutaveis[i][1]) and tgname = v_imutaveis[i][2]) then
      execute format('alter table %s enable trigger %I', v_imutaveis[i][1], v_imutaveis[i][2]);
    end if;
  end loop;
end $zerar$;

commit;

-- Conferência: tudo zero, menos o que fica.
select 'manifestações' as item, count(*) as total from public.complaints
union all select 'empresas que não são da equipe', count(*) from public.companies c
  where not exists (select 1 from public.company_users cu join private.platform_admins a on a.user_id = cu.user_id where cu.company_id = c.id)
union all select 'contas que não são da equipe', count(*) from auth.users where id not in (select user_id from private.platform_admins)
union all select 'avisos, contatos e consentimentos', (select count(*) from public.company_notices) + (select count(*) from public.complaint_contacts)
  + (select count(*) from private.complaint_notice_consents)
union all select 'contatos da landing', count(*) from public.contact_solicitations
union all select 'gatilhos de trilha desligados (deve ser 0)', count(*) from pg_trigger
  where tgname in ('company_notices_guard', 'legal_acceptances_immutable', 'pilot_state_log_immutable', 'representative_verifications_immutable')
    and tgenabled = 'D'
union all select 'EQUIPE (platform_admins)', count(*) from private.platform_admins;
