import { useEffect, useState } from 'react';
import { showToast } from '../app/toast';
import { confirmAction } from '../app/confirm-dialog';
import { EmptyState } from './ui';
import { maskCnpj } from '../domain/account-rules';
import { dataSourceLabels, automaticNoticeSendEnabled, noticeSendStateText, noticeStatusLabels, noticeTab, noticeTexts, noticeTextsInReview, registrationLabels, validateOpsReason, type NoticeTab } from '../domain/company-notice';
import { addNoticeOptOut, decideNotice, listNoticeCandidates, listPendingCompanies, loadComplaintContacts, markNoticeSent, noticeDestination, purgeExpiredContacts, reviewPendingCompany, type NoticeCandidate, type NoticeDestinationChoice, type PendingCompany , type ComplaintContactItem } from '../services/notices';

const registryEmailBadge = 'E-mail da Receita: confira antes (pode ser do contador ou pessoal)';

// ADR-0023 na Operação: conferência das empresas fora do cadastro e aviso sem conteúdo, aprovado e enviado à mão (a1).
// Sem as migrations 20261118120000/130000 as telas avisam e não quebram.
const dateLabel = (value: string | null) => value ? new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value)) : '—';
const notActive = (what: string) => <section className="commercial-panel"><p>{what} ainda não está ativa no banco. A tela passa a funcionar assim que a atualização for aplicada.</p></section>;
const heading = (title: string, text: string) => <div className="commercial-page-head"><div><h1>{title}</h1><p>{text}</p></div></div>;

function useRows<T>(load: () => Promise<{ missing: true } | { missing: false; rows: T[] }>, version: number) {
 const [rows, setRows] = useState<T[] | null>(null);
 const [missing, setMissing] = useState(false);
 const [failure, setFailure] = useState('');
 useEffect(() => { let active = true; setRows(null); load().then(result => { if (!active) return; setFailure(''); setMissing(result.missing); setRows(result.missing ? [] : result.rows); }).catch(error => { if (active) setFailure(error instanceof Error ? error.message : 'Não foi possível carregar.'); }); return () => { active = false; }; }, [version]);
 return { rows, missing, failure };
}

function CompanyReview({ item, onBack, onChanged }: { item: PendingCompany; onBack: () => void; onChanged: () => void }) {
 const [decision, setDecision] = useState<'confirmed' | 'blocked'>('confirmed');
 const [naturalPerson, setNaturalPerson] = useState(Boolean(item.naturalPerson));
 const [reason, setReason] = useState('');
 const [busy, setBusy] = useState(false);
 async function submit(event: React.FormEvent) {
  event.preventDefault();
  if (decision === 'blocked') { const problem = validateOpsReason(reason); if (problem) return showToast('error', problem, 'Confira os dados'); }
  const ok = await confirmAction(decision === 'confirmed'
   ? { title: 'Confirmar os dados da empresa?', text: `Os dados de ${item.name} ficam confirmados conforme a Receita Federal.`, confirmLabel: 'Confirmar dados' }
   : { title: 'Bloquear esta empresa?', text: `Nenhum aviso sai para ${item.name}.`, confirmLabel: 'Bloquear', danger: true });
  if (!ok) return;
  setBusy(true); const result = await reviewPendingCompany(item.companyId, decision, decision === 'blocked' ? reason : '', naturalPerson); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', decision === 'confirmed' ? 'Empresa conferida.' : 'Empresa bloqueada para aviso.'); onChanged();
 }
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar</button>
  <div className="worker-detail-heading"><div><span className="editorial-eyebrow">Empresa · {registrationLabels[item.registrationStatus] ?? item.registrationStatus}</span><h2>{item.name}</h2><p className="muted">CNPJ {maskCnpj(item.cnpj)} · {item.city}/{item.state} · {dataSourceLabels[item.dataSource] ?? item.dataSource} · desde {dateLabel(item.createdAt)}</p></div></div>
  <div className="worker-detail-grid"><div>
   <form className="worker-detail-section ops-decision" onSubmit={submit} noValidate><h3>Conferência na Receita Federal</h3>
    <p className="muted small">Consulte o CNPJ no site da Receita Federal, fora da plataforma, e compare nome, município e situação cadastral.</p>
    <fieldset className="response-rating"><legend>Resultado</legend>
     <label className="check-row"><input type="radio" name="company-decision" checked={decision === 'confirmed'} onChange={() => setDecision('confirmed')} /> <span>Dados conferem</span></label>
     <label className="check-row"><input type="radio" name="company-decision" checked={decision === 'blocked'} onChange={() => setDecision('blocked')} /> <span>Dados não conferem (bloquear aviso)</span></label></fieldset>
    <label className="check-row"><input type="checkbox" checked={naturalPerson} onChange={event => setNaturalPerson(event.target.checked)} /> <span>Pessoa física, MEI ou empresário individual (o relato segue; o aviso é recusado)</span></label>
    {decision === 'blocked' && <label className="field">Motivo<textarea rows={3} maxLength={300} value={reason} onChange={event => setReason(event.target.value)} placeholder="Ex.: CNPJ baixado na Receita; nome informado não confere." /><small className="muted">{reason.trim().length}/300 caracteres. Sem conteúdo de relato.</small></label>}
    <div className="ops-decision-actions"><button className="btn primary" type="submit" disabled={busy}>{busy ? 'Registrando…' : 'Registrar conferência'}</button></div>
   </form>
  </div><aside className="worker-detail-aside"><section className="worker-detail-section"><h3>Resumo</h3><ul className="ops-notice-facts">
   <li><span className="muted small">Situação cadastral</span><strong>{item.cadastralSituation ?? 'Não informada'}</strong></li>
   <li><span className="muted small">Manifestações</span><strong>{item.complaints}</strong></li>
   <li><span className="muted small">Último aviso</span><strong>{dateLabel(item.lastNoticeAt)}</strong></li>
   <li><span className="muted small">Conferência anterior</span><strong>{item.reviewDecision === 'confirmed' ? 'Confere' : item.reviewDecision === 'blocked' ? `Bloqueada: ${item.reviewReason ?? ''}` : 'Ainda não conferida'}</strong></li>
  </ul></section></aside></div></>;
}

export function OpsPendingCompanies() {
 const [version, setVersion] = useState(0);
 const [openId, setOpenId] = useState<string | null>(null);
 const { rows, missing, failure } = useRows(listPendingCompanies, version);
 const opened = rows?.find(row => row.companyId === openId);
 if (opened) return <CompanyReview key={opened.companyId + opened.registrationStatus + (opened.reviewDecision ?? '')} item={opened} onBack={() => setOpenId(null)} onChanged={() => { setOpenId(null); setVersion(value => value + 1); }} />;
 return <>{heading('Empresas a conferir', 'Empresas que entraram por uma manifestação e ainda não têm conta. Confira na Receita Federal antes de qualquer aviso. Elas não aparecem no diretório nem no ranking.')}
  {missing ? notActive('A conferência de empresas') : failure ? <section className="commercial-panel"><p>{failure}</p></section> : rows === null ? <p className="muted">Carregando…</p> : !rows.length ? <EmptyState icon="building" text="Nenhuma empresa fora do cadastro." hint="Empresas informadas pelo CNPJ numa manifestação, ainda sem conta, aparecem aqui para conferência." /> :
  <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Empresa</th><th>Município</th><th>Origem</th><th>Situação</th><th>Manifestações</th></tr></thead>
   <tbody>{rows.map(row => <tr key={row.companyId} tabIndex={0} onClick={() => setOpenId(row.companyId)} onKeyDown={event => event.key === 'Enter' && setOpenId(row.companyId)}><td>{row.name}<small>CNPJ {maskCnpj(row.cnpj)}</small></td><td>{row.city}/{row.state}</td><td>{dataSourceLabels[row.dataSource] ?? row.dataSource}</td><td>{row.reviewDecision === 'blocked' ? 'Bloqueada' : registrationLabels[row.registrationStatus] ?? row.registrationStatus}{row.naturalPerson ? ' · pessoa física' : ''}</td><td>{row.complaints}</td></tr>)}</tbody></table></div>}</>;
}

// Motivos que o banco usa para travar o aviso, mostrados antes da decisão.
function blockers(row: NoticeCandidate): string[] {
 const list: string[] = [];
 if (row.complaintStatus === 'in_review' || row.complaintStatus === 'held' || row.complaintStatus === 'received') list.push('A manifestação ainda não foi liberada pela equipe.');
 if (row.workerConsent === false) list.push('Trabalhador não autorizou o aviso.');
 if (row.possiblyInvolved) list.push('O trabalhador marcou o contato como possivelmente envolvido (ou respondeu "Não sei").');
 if (row.optedOut) list.push('Este e-mail pediu para não receber avisos.');
 if (row.registrationStatus === 'pending_check') list.push('A empresa ainda não foi conferida.');
 if (row.registrationStatus === 'registered') list.push('A empresa já é cadastrada.');
 if (row.naturalPerson || row.reviewDecision === 'blocked') list.push('Empresa bloqueada para aviso ou pessoa física/MEI.');
 if (row.lastCompanyNoticeAt && Date.now() - new Date(row.lastCompanyNoticeAt).getTime() < 30 * 86400000) list.push(`A empresa recebeu aviso em ${dateLabel(row.lastCompanyNoticeAt)} (intervalo de 30 dias).`);
 return list;
}

function NoticeDetail({ item, onBack, onChanged }: { item: NoticeCandidate; onBack: () => void; onChanged: () => void }) {
 const tab = noticeTab(item);
 // Sem o aceite do trabalhador (workerConsent === false), só "Recusar" (revisão do DevOps, 2026-11-19).
 const noConsent = item.workerConsent === false;
 const [decision, setDecision] = useState<'approved' | 'rejected'>(noConsent ? 'rejected' : 'approved');
 const [reason, setReason] = useState('');
 const [busy, setBusy] = useState(false);
 const locks = blockers(item);
 // Sem contato do trabalhador, o destino é o e-mail da Receita (pode ser do contador ou pessoal): a equipe confere.
 // Com os dois e-mails (do trabalhador e da Receita), a equipe escolhe o destino na aprovação (p_destination).
  const bothDestinations = Boolean(item.email && item.registryEmail);
  const [choice, setChoice] = useState<NoticeDestinationChoice | null>(bothDestinations ? (item.destinationSource === 'receita' ? 'receita' : 'worker') : null);
  // Até 3 contatos (contrato 03847ae): com a lista, a equipe escolhe entre os contatos elegíveis com e-mail (não envolvidos,
  // sem pedido de não receber) ou a Receita; o contato vai em p_contact_id. Sem a lista, vale a escolha acima.
  const [contactList, setContactList] = useState<ComplaintContactItem[] | null>(null);
  const [pickedContact, setPickedContact] = useState<string | null>(null);
  useEffect(() => { let active = true; loadComplaintContacts(item.complaintId, 'ops').then(result => { if (!active || result.missing || !result.list) return; const eligible = result.contacts.filter(contact => contact.email && contact.contactId && contact.eligibleForNotice !== false && !contact.possiblyInvolved && !contact.optedOut); setContactList(eligible); setPickedContact(eligible[0]?.contactId ?? null); if (!eligible.length && item.registryEmail) setChoice('receita'); }).catch(() => undefined); return () => { active = false; }; }, [item.complaintId, item.registryEmail]);
  const usingList = contactList !== null;
  const listDestination = usingList ? (pickedContact ? { email: contactList.find(contact => contact.contactId === pickedContact)?.email ?? '', fromRegistry: false } : item.registryEmail ? { email: item.registryEmail, fromRegistry: true } : null) : null;
  const destination = usingList ? listDestination : noticeDestination(item, choice ?? undefined);
  const to = destination?.email ?? '';
 const registryBadge = destination?.fromRegistry ? <span className="commercial-badge">{registryEmailBadge}</span> : null;
 const run = async (action: () => Promise<{ ok: boolean; message?: string }>, done: string) => { setBusy(true); const result = await action(); setBusy(false); if (!result.ok) return showToast('error', result.message ?? 'Não foi possível concluir.'); showToast('success', done); onChanged(); };
 async function decide(event: React.FormEvent) {
  event.preventDefault();
  if (decision === 'rejected') { const problem = validateOpsReason(reason); if (problem) return showToast('error', problem, 'Confira os dados'); }
  const ok = await confirmAction(decision === 'approved'
   ? { title: 'Aprovar o aviso?', text: `O aviso vai para ${to}.${destination?.fromRegistry ? ' É o e-mail da Receita: confirme que é um canal da empresa.' : ''} ${automaticNoticeSendEnabled ? 'Depois de aprovado, o aviso entra na fila e sai automaticamente pela conta da plataforma.' : 'Depois de aprovado, você envia o texto fixo pela conta da plataforma.'}`, confirmLabel: 'Aprovar aviso' }
   : { title: 'Recusar o aviso?', text: 'O e-mail não recebe nada.', confirmLabel: 'Recusar aviso', danger: true });
  if (!ok) return;
  await run(() => decideNotice(item.complaintId, decision, reason, decision === 'approved' && !(usingList && pickedContact) ? (usingList ? 'receita' : choice) : null, decision === 'approved' && usingList ? pickedContact : null), decision === 'approved' ? (automaticNoticeSendEnabled ? 'Aviso aprovado. Ele entra na fila e sai automaticamente.' : 'Aviso aprovado. Envie e marque como enviado.') : 'Aviso recusado.');
 }
 const copy = async () => { try { await navigator.clipboard.writeText(`${noticeTexts.emailSubject}\n\n${noticeTexts.emailBody}`); showToast('success', 'Texto copiado.'); } catch { showToast('error', 'Não foi possível copiar. Selecione o texto e copie manualmente.'); } };
 const optOut = async () => { if (to && await confirmAction({ title: 'Registrar o pedido de não receber avisos?', text: `Nenhum aviso futuro vai para ${to}.`, confirmLabel: 'Registrar pedido', danger: true })) run(() => addNoticeOptOut(to), 'Pedido registrado.'); };
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar</button>
  <div className="worker-detail-heading"><div><span className="editorial-eyebrow">Aviso à empresa · {item.noticeStatus ? noticeStatusLabels[item.noticeStatus] : 'A decidir'}</span><h2>{item.companyName}</h2><p className="muted">Protocolo {item.protocol} · {to || 'sem e-mail de destino'} · {registrationLabels[item.registrationStatus] ?? item.registrationStatus}</p>{registryBadge}</div></div>
  <div className="worker-detail-grid"><div>
   {tab === 'decide' && <form className="worker-detail-section ops-decision" onSubmit={decide} noValidate><h3>Decisão da equipe</h3>
    <p className="muted small">Aprove só e-mail institucional (RH, ouvidoria, contato do site). Recuse e-mail pessoal ou de pessoa nomeada.</p>
    {locks.length > 0 && <div className="notice warn small"><strong>O banco vai recusar a aprovação:</strong><ul>{locks.map(line => <li key={line}>{line}</li>)}</ul></div>}
    {noConsent && <div className="notice warn small">Trabalhador não autorizou o aviso. Só é possível recusar.</div>}
    <fieldset className="response-rating"><legend>O que fazer</legend>
     {!noConsent && <label className="check-row"><input type="radio" name="notice-decision" checked={decision === 'approved'} onChange={() => setDecision('approved')} /> <span>Aprovar o aviso</span></label>}
     <label className="check-row"><input type="radio" name="notice-decision" checked={decision === 'rejected'} onChange={() => setDecision('rejected')} /> <span>Recusar o aviso</span></label></fieldset>
     {decision === 'approved' && usingList && (contactList.length + (item.registryEmail ? 1 : 0)) > 1 && <fieldset className="response-rating"><legend>Enviar para</legend>
      {contactList.map(contact => <label key={contact.contactId} className="check-row"><input type="radio" name="notice-destination" checked={pickedContact === contact.contactId} onChange={() => setPickedContact(contact.contactId)} /> <span>{contact.email} (indicado pelo trabalhador)</span></label>)}
      {item.registryEmail && <label className="check-row"><input type="radio" name="notice-destination" checked={pickedContact === null} onChange={() => setPickedContact(null)} /> <span>{item.registryEmail} ({registryEmailBadge})</span></label>}</fieldset>}
     {decision === 'approved' && !usingList && bothDestinations && <fieldset className="response-rating"><legend>Enviar para</legend>
     <label className="check-row"><input type="radio" name="notice-destination" checked={choice === 'worker'} onChange={() => setChoice('worker')} /> <span>{item.email} (indicado pelo trabalhador)</span></label>
     <label className="check-row"><input type="radio" name="notice-destination" checked={choice === 'receita'} onChange={() => setChoice('receita')} /> <span>{item.registryEmail} ({registryEmailBadge})</span></label></fieldset>}
    {decision === 'rejected' && <label className="field">Motivo<textarea rows={3} maxLength={300} value={reason} onChange={event => setReason(event.target.value)} placeholder="Ex.: e-mail pessoal de uma pessoa nomeada." /><small className="muted">{reason.trim().length}/300 caracteres. Sem conteúdo de relato.</small></label>}
    <div className="ops-decision-actions"><button className="btn primary" type="submit" disabled={busy}>{busy ? 'Registrando…' : decision === 'approved' ? 'Aprovar aviso' : 'Recusar aviso'}</button></div>
   </form>}
    {automaticNoticeSendEnabled && item.noticeStatus && item.noticeStatus !== 'rejected' && <section className="worker-detail-section notice-send-state" aria-live="polite"><h3>Envio do aviso</h3>
     <p><span className={`worker-status ${item.noticeStatus === 'sent' ? 'respondida' : item.noticeStatus === 'bounced' ? 'retida' : 'encaminhada-para-empresa'}`}>{noticeStatusLabels[item.noticeStatus]}</span></p>
     <p className="muted small">{noticeSendStateText[item.noticeStatus]} Destino: <strong>{to || 'definido na aprovação'}</strong>{destination?.fromRegistry ? ` (${registryEmailBadge})` : ''}.</p>
     {item.noticeStatus === 'sent' && item.noticeId && <div className="ops-decision-actions"><button className="btn" type="button" disabled={busy} onClick={async () => { if (await confirmAction({ title: 'Registrar que o e-mail voltou?', text: 'Use quando a mensagem de devolução chegar à conta da plataforma depois do envio. Registra na trilha que o aviso não foi entregue a este e-mail.', confirmLabel: 'Registrar retorno' })) run(() => markNoticeSent(item.noticeId as string, 'bounced'), 'Retorno registrado.'); }}>O e-mail voltou</button></div>}
    </section>}
    {!automaticNoticeSendEnabled && (tab === 'approved' || item.noticeStatus === 'sent') && <section className="worker-detail-section"><h3>Texto do aviso</h3>
    {noticeTextsInReview && <p className="legal-review-banner">Texto em revisão jurídica.</p>}
    <p className="muted small">Envie da conta da plataforma para <strong>{to}</strong>{destination?.fromRegistry ? ` (${registryEmailBadge})` : ''}, sem link e sem nenhuma informação do relato.</p>
    <label className="field">Assunto<input readOnly value={noticeTexts.emailSubject} /></label>
    <label className="field">Mensagem<textarea readOnly rows={10} value={noticeTexts.emailBody} /></label>
    <div className="ops-decision-actions"><button className="btn" type="button" onClick={copy}>Copiar texto</button>
     {tab === 'approved' && item.noticeId && <button className="btn primary" type="button" disabled={busy} onClick={async () => { if (await confirmAction({ title: 'Marcar o aviso como enviado?', text: 'Registra na trilha que o texto fixo foi enviado pela conta da plataforma.', confirmLabel: 'Marcar como enviado' })) run(() => markNoticeSent(item.noticeId as string, 'sent'), 'Envio registrado.'); }}>Marquei como enviado</button>}
     {item.noticeId && <button className="btn" type="button" disabled={busy} onClick={async () => { if (await confirmAction({ title: 'Registrar que o e-mail voltou?', text: 'Registra na trilha que o aviso não foi entregue a este e-mail.', confirmLabel: 'Registrar retorno' })) run(() => markNoticeSent(item.noticeId as string, 'bounced'), 'Retorno registrado.'); }}>O e-mail voltou</button>}</div>
   </section>}
   {tab === 'rejected' && <section className="worker-detail-section"><p className="muted">Aviso recusado. Nada foi enviado.</p></section>}
  </div><aside className="worker-detail-aside"><section className="worker-detail-section"><h3>Resumo</h3><ul className="ops-notice-facts">
   <li><span className="muted small">Trabalhador autorizou o aviso</span><strong>{item.workerConsent === true ? 'Sim' : item.workerConsent === false ? 'Não' : 'Não informado'}</strong></li>
   <li><span className="muted small">Possível envolvimento</span><strong>{item.possiblyInvolved ? 'Sim ou não sabe' : 'Não'}</strong></li>
   <li><span className="muted small">Pediu para não receber</span><strong>{item.optedOut ? 'Sim' : 'Não'}</strong></li>
   <li><span className="muted small">Último aviso à empresa</span><strong>{dateLabel(item.lastCompanyNoticeAt)}</strong></li>
  </ul>{!item.optedOut && <button className="btn" type="button" disabled={busy} onClick={optOut}>Pedido para não receber</button>}</section></aside></div></>;
}

const noticeTabs: [NoticeTab, string][] = [['decide', 'A decidir'], ['approved', automaticNoticeSendEnabled ? 'Na fila' : 'Aprovados para enviar'], ['sent', automaticNoticeSendEnabled ? 'Enviados ou voltaram' : 'Enviados'], ['rejected', 'Recusados']];

export function OpsNotices() {
 const [version, setVersion] = useState(0);
 const [tab, setTab] = useState<NoticeTab>('decide');
 const [openId, setOpenId] = useState<string | null>(null);
 const [busy, setBusy] = useState(false);
 const { rows, missing, failure } = useRows(listNoticeCandidates, version);
 const opened = rows?.find(row => row.complaintId === openId);
 if (opened) return <NoticeDetail key={opened.complaintId + (opened.noticeStatus ?? '') + opened.contactStatus} item={opened} onBack={() => setOpenId(null)} onChanged={() => { setOpenId(null); setVersion(value => value + 1); }} />;
 const listed = (rows ?? []).filter(row => noticeTab(row) === tab);
 async function purge() {
  if (!(await confirmAction({ title: 'Apagar os contatos vencidos?', text: 'São e-mails de manifestações encerradas ou avisos recusados há mais de 90 dias. A trilha dos avisos continua, sem o e-mail. Não dá para desfazer.', confirmLabel: 'Apagar contatos', danger: true }))) return;
  setBusy(true); const result = await purgeExpiredContacts(); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', result.value ? `${result.value} contato(s) apagado(s).` : 'Nenhum contato vencido.'); setVersion(value => value + 1);
 }
 return <>{heading('Avisos à empresa', automaticNoticeSendEnabled ? 'E-mails indicados pelos trabalhadores para avisar empresas sem conta. A equipe aprova; o aviso sai automaticamente pela conta da plataforma e o estado do envio aparece aqui.' : 'E-mails indicados pelos trabalhadores para avisar empresas sem conta. A equipe aprova, envia o texto fixo pela conta da plataforma e marca como enviado.')}
  {missing ? notActive('A fila de avisos') : <>
   <div className="account-tabs ops-response-tabs" role="tablist" aria-label="Situação do aviso">{noticeTabs.map(([value, label]) => <button key={value} role="tab" aria-selected={tab === value} className={`account-tab${tab === value ? ' active' : ''}`} onClick={() => setTab(value)}>{label}</button>)}</div>
   {failure ? <section className="commercial-panel"><p>{failure}</p></section> : rows === null ? <p className="muted">Carregando…</p> : !listed.length ? <EmptyState text={tab === 'decide' ? 'Nenhum aviso aguardando decisão.' : 'Nenhum aviso nesta situação.'} hint={tab === 'decide' ? 'Manifestações sobre empresas sem conta, com aviso autorizado pelo trabalhador, aparecem aqui.' : undefined} /> :
   <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Empresa</th><th>E-mail</th><th>Protocolo</th><th>Situação</th></tr></thead>
    <tbody>{listed.map(row => <tr key={row.complaintId} tabIndex={0} onClick={() => setOpenId(row.complaintId)} onKeyDown={event => event.key === 'Enter' && setOpenId(row.complaintId)}><td>{row.companyName}<small>{registrationLabels[row.registrationStatus] ?? row.registrationStatus}</small></td><td>{noticeDestination(row)?.email ?? '—'}{noticeDestination(row)?.fromRegistry && <small>{registryEmailBadge}</small>}</td><td>{row.protocol}</td><td>{row.noticeStatus ? noticeStatusLabels[row.noticeStatus] : row.workerConsent === false ? 'Trabalhador não autorizou o aviso' : blockers(row).length ? 'Com trava' : 'A decidir'}</td></tr>)}</tbody></table></div>}
   <section className="commercial-panel"><h2>Retenção</h2><p className="muted">Contatos são apagados 90 dias depois do encerramento da manifestação ou da recusa do aviso. Enquanto não houver rotina automática, rode aqui.</p><button className="btn" type="button" disabled={busy} onClick={purge}>{busy ? 'Apagando…' : 'Apagar contatos vencidos'}</button></section>
  </>}</>;
}
