import { useEffect, useMemo, useState } from 'react';
import { decideOpsComplaint, loadNotificationStats, listOpsComplaints, listOpsCompanies, listOpsRepresentatives, loadOpsMetrics, loadOpsTimeline, readOpsOriginal, type OpsComplaint, type OpsCompany, type OpsMetrics, type OpsTimelineItem, type NotificationStats, type ReviewDecision } from '../services/ops';
import type { ComplaintStatusDb } from '../services/data';
import { statusLabel } from '../domain/complaint-status';
import { notificationAlert, notificationAlertText, oldestFirst, opsReasonMax, releaseDelivery, releaseNextStep, validateOpsReason, waitingLabel, type ReleaseDelivery, type ReleaseView } from '../domain/ops-queue';
import { showToast } from '../app/toast';
import { Metric, Sidebar } from './portal-live';
import { EmptyState, QuickActions } from './ui';
import { ContactSolicitationsAdmin } from './contact-solicitations-admin';
import { OpsResponses } from './response-review';
import { OpsRepresentatives } from './representatives';
import { OpsNotices, OpsPendingCompanies } from './company-notices';
import { listNoticeCandidates, listPendingCompanies, loadComplaintContact, type ComplaintContact as ComplaintContactData } from '../services/notices';
import { noticeTab } from '../domain/company-notice';
import { formatPhone } from '../domain/account-rules';

// Área da equipe (ADR-0010): revisão antes da liberação, acesso ao original só com justificativa, números agregados.
type OpsView = 'overview' | 'queue' | 'responses' | 'representatives' | 'pending-companies' | 'notices' | 'all' | 'companies' | 'contacts';
// Menu em quatro seções (proposta aprovada em 2026-11-19); as telas de antes viram abas, nenhuma some.
type OpsSection = 'overview' | 'complaints' | 'companies' | 'contacts';
const sectionOf: Record<OpsView, OpsSection> = { overview: 'overview', queue: 'complaints', responses: 'complaints', all: 'complaints', companies: 'companies', representatives: 'companies', 'pending-companies': 'companies', notices: 'companies', contacts: 'contacts' };
const firstTab: Record<OpsSection, OpsView> = { overview: 'overview', complaints: 'queue', companies: 'companies', contacts: 'contacts' };
const sectionTabs: Partial<Record<OpsSection, [OpsView, string][]>> = {
 complaints: [['queue', 'Revisão do relato'], ['responses', 'Respostas da empresa'], ['all', 'Todas']],
 companies: [['companies', 'Todas'], ['representatives', 'Representantes'], ['pending-companies', 'A conferir'], ['notices', 'Avisos']],
};
export interface OpsCounts { queue: number; responses: number; all: number; companies: number; representatives: number | null; pendingCompanies: number | null; notices: number | null; contacts: number }

function SectionTabs({ section, view, counts, onView }: { section: OpsSection; view: OpsView; counts: Partial<Record<OpsView, number | null>>; onView: (view: OpsView) => void }) {
 const tabs = sectionTabs[section];
 if (!tabs) return null;
 return <div className="account-tabs ops-section-tabs" role="tablist" aria-label={section === 'complaints' ? 'Manifestações' : 'Empresas'}>{tabs.map(([key, label]) => { const count = counts[key]; return <button key={key} role="tab" aria-selected={view === key} className={`account-tab${view === key ? ' active' : ''}`} onClick={() => onView(key)}>{label}{typeof count === 'number' && count > 0 ? <span className="ops-tab-count" aria-label={`${count} pendentes`}>{count}</span> : null}</button>; })}</div>;
}

const statusLabels: Record<ComplaintStatusDb, string> = { received: 'Guardada', in_review: 'Em revisão', adjustment_requested: 'Ajuste solicitado', held: 'Retida', shared: 'Liberada', answer_in_review: 'Resposta em revisão', answered: 'Respondida', closed: 'Finalizada', canceled: 'Retirada' };
const statusTone: Record<ComplaintStatusDb, string> = { received: 'em-aberto', in_review: 'em-revisão', adjustment_requested: 'em-revisão', held: 'retida', shared: 'encaminhada-para-empresa', answer_in_review: 'em-revisão', answered: 'respondida', closed: 'finalizada', canceled: 'em-aberto' };
const eventLabels: Record<ComplaintStatusDb, string> = { received: 'Registrada', in_review: 'Revisão solicitada', adjustment_requested: 'Ajuste solicitado', held: 'Retida', shared: 'Liberada para a empresa', answer_in_review: 'Resposta enviada · em revisão', answered: 'Respondida', closed: 'Finalizada', canceled: 'Retirada pelo trabalhador' };
const decisionLabels: Record<ReviewDecision, string> = { released: 'Liberar para a empresa', adjustment_requested: 'Pedir ajuste ao trabalhador', held: 'Reter para análise' };

function when(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(value)); }
function hours(value: number | null) { return value === null ? '—' : value < 48 ? `${String(value).replace('.', ',')} h` : `${(value / 24).toFixed(1).replace('.', ',')} dias`; }
function Status({ status }: { status: ComplaintStatusDb }) { return <span className={`worker-status ${statusLabel(statusTone, status, 'em-aberto')}`}>{statusLabel(statusLabels, status)}</span>; }
const head = (eyebrow: string, title: string, text: string) => <div className="commercial-page-head"><div><span className="editorial-eyebrow">{eyebrow}</span><h1>{title}</h1><p>{text}</p></div></div>;

// Cartão "E-mails da plataforma" (ADR-0020): contagens da fila; vermelho com senha recusada, amarelo com cota ou falha.
function EmailStatsCard({ stats }: { stats: NotificationStats }) {
 const alert = notificationAlert(stats);
 const item = (label: string, value: number, warn = false) => <div className={warn && value > 0 ? 'email-stat warn' : 'email-stat'}><dt>{label}</dt><dd>{value}</dd></div>;
 return <section className={`commercial-panel email-stats ${alert}`} aria-labelledby="email-stats-title"><h2 id="email-stats-title">E-mails da plataforma</h2>
  <p className={alert === 'ok' ? 'muted small' : 'email-stats-alert'} role={alert === 'ok' ? undefined : 'alert'}>{notificationAlertText[alert]}</p>
  <dl className="email-stats-grid">{item('Na fila', stats.pending)}{item('Enviando', stats.sending)}{item('Falhas', stats.failed, true)}{item('Parados por senha (24 h)', stats.stoppedAuth24h, true)}{item('Parados por cota (24 h)', stats.stoppedQuota24h, true)}{item('Avisos enviados (24 h)', stats.sent24h)}{item('E-mails entregues (24 h)', stats.messages24h)}</dl>
  <p className="muted small">Último envio: {stats.lastSentAt ? when(stats.lastSentAt) : 'nenhum ainda'}.</p></section>;
}

function Overview({ metrics, counts, emailStats, onView }: { metrics: OpsMetrics | null; counts: OpsCounts; emailStats: NotificationStats | null; onView: (view: OpsView) => void }) {
 if (!metrics) return <p className="muted">Carregando números…</p>;
 const s = metrics.byStatus;
 const max = Math.max(1, ...metrics.weekly.map(item => item.total));
 const badge = (value: number | null) => value ?? undefined;
 return <>{head('Operação', 'Visão geral', 'O que espera a equipe agora e os números agregados da plataforma. Nenhum dado individual aparece aqui.')}
  <QuickActions label="O que espera a equipe" items={[
   { icon: 'inbox', label: 'Relatos para revisar', badge: counts.queue, onClick: () => onView('queue') },
   { icon: 'briefcase', label: 'Respostas da empresa para revisar', badge: counts.responses, onClick: () => onView('responses') },
   { icon: 'user', label: 'Representantes a verificar', badge: badge(counts.representatives), onClick: () => onView('representatives') },
   { icon: 'building', label: 'Empresas a conferir', badge: badge(counts.pendingCompanies), onClick: () => onView('pending-companies') },
   { icon: 'info', label: 'Avisos a decidir', badge: badge(counts.notices), onClick: () => onView('notices') },
   { icon: 'users', label: 'Contatos aguardando', badge: counts.contacts, onClick: () => onView('contacts') },
  ]} />
  {emailStats && <EmailStatsCard stats={emailStats} />}
  <div className="commercial-metrics">
   <Metric label="Em revisão" value={s.in_review ?? 0} note="aguardando decisão da equipe" />
   <Metric label="Retidas" value={s.held ?? 0} note="exigem análise humana" />
   <Metric label="Liberadas sem resposta" value={s.shared ?? 0} note="aguardando a empresa" />
   <Metric label="Respondidas" value={(s.answered ?? 0) + (s.closed ?? 0)} note="inclui finalizadas" />
  </div>
  <div className="commercial-metrics ops-metrics-secondary">
   <Metric label="Tempo até a revisão" value={hours(metrics.avgHoursToReview)} note="média, do pedido à decisão" />
   <Metric label="Tempo até a resposta" value={hours(metrics.avgHoursToCompanyResponse)} note="média, da liberação à 1ª resposta" />
   <Metric label="Respostas em revisão" value={metrics.responsesInReview} note={`média ${hours(metrics.avgHoursResponseReview)} até a decisão`} />
   <Metric label="Manifestações em 30 dias" value={metrics.complaints30d} />
   <Metric label="Contas" value={metrics.workers + metrics.companies} note={`${metrics.workers} trabalhadores · ${metrics.companies} empresas`} />
  </div>
  <div className="commercial-grid-two">
   <section className="commercial-panel"><h2>Manifestações por semana</h2>
    {metrics.weekly.length ? <div className="worker-columns-chart ops-weekly" aria-label="Manifestações criadas por semana">{metrics.weekly.map(item => <div className="worker-column" key={item.week}><strong>{item.total}</strong><i style={{ height: `${Math.max(item.total / max * 100, 8)}%` }} /><span>{item.week}</span></div>)}</div> : <p className="muted">Sem manifestações nas últimas 8 semanas.</p>}</section>
   <section className="commercial-panel"><h2>Por situação</h2><dl className="company-facts">{(Object.keys(statusLabels) as ComplaintStatusDb[]).map(key => <div key={key}><dt>{statusLabels[key]}</dt><dd>{s[key] ?? 0}</dd></div>)}</dl>
    <div className="commercial-callout">Parceiros: {metrics.partners} · Patrocinadores: {metrics.sponsors}</div></section>
  </div></>;
}

function ComplaintList({ rows, onOpen, empty, waiting = false }: { rows: OpsComplaint[]; onOpen: (row: OpsComplaint) => void; empty: string; waiting?: boolean }) {
 if (!rows.length) return <EmptyState text={empty} hint={waiting ? 'Quando um trabalhador pedir a revisão, a manifestação aparece aqui, a mais antiga primeiro.' : undefined} />;
 return <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Protocolo</th><th>Empresa</th><th>Assunto</th><th>Situação</th><th>{waiting ? 'Aguardando' : 'Atualizada'}</th></tr></thead>
  <tbody>{rows.map(row => <tr key={row.id} tabIndex={0} onClick={() => onOpen(row)} onKeyDown={event => event.key === 'Enter' && onOpen(row)}><td>{row.protocol}</td><td>{row.companyName}</td><td>{row.title}<small>{row.category}</small></td><td><Status status={row.status} /></td><td>{waiting ? <span title={when(row.updatedAt)}>{waitingLabel(row.updatedAt)}</span> : when(row.updatedAt)}</td></tr>)}</tbody></table></div>;
}

// Contato na empresa indicado pelo trabalhador (só a equipe vê): ops_complaint_contact (contrato e0f43bd).
// Sem a função, usa a fila de avisos. Sem dado, a seção não aparece.
function ComplaintContact({ complaintId }: { complaintId: string }) {
 const [contact, setContact] = useState<ComplaintContactData | null>(null);
 useEffect(() => {
  let active = true;
  loadComplaintContact(complaintId, 'ops').then(async result => {
   if (!result.missing) { if (active) setContact(result.contact && (result.contact.email || result.contact.phone) ? result.contact : null); return; }
   const fallback = await listNoticeCandidates();
   const row = fallback.missing ? undefined : fallback.rows.find(item => item.complaintId === complaintId && (item.email || item.phone));
   if (active) setContact(row ? { email: row.email, phone: row.phone, possiblyInvolved: row.possiblyInvolved } : null);
  }).catch(() => undefined);
  return () => { active = false; };
 }, [complaintId]);
 if (!contact) return null;
 return <section className="worker-detail-section"><h3>Contato indicado pelo trabalhador</h3><p className="muted small">Só a equipe vê. A empresa não recebe este contato.</p>
  <ul className="ops-notice-facts">{contact.email && <li><span className="muted small">E-mail</span><strong>{contact.email}</strong></li>}{contact.phone && <li><span className="muted small">Telefone</span><strong>{formatPhone(contact.phone)}</strong></li>}
   <li><span className="muted small">Possível envolvimento</span><strong>{contact.possiblyInvolved ? 'Sim ou não sabe: não usar' : 'Não'}</strong></li></ul></section>;
}

// Para onde a manifestação vai depois da liberação: chegou à empresa, falta representante verificado ou empresa sem conta.
function NextStep({ delivery, before, onGo }: { delivery: ReleaseDelivery; before: boolean; onGo: (view: ReleaseView) => void }) {
 const step = releaseNextStep(delivery, before);
 return <section className="worker-detail-section ops-next-step" aria-live="polite"><h3>{before ? 'Depois de liberar' : 'Próximo passo'}</h3><p>{step.text}</p>
  <div className="ops-decision-actions">{step.links.map(link => <button key={link.view} className="btn" type="button" onClick={() => onGo(link.view)}>{link.label}</button>)}</div></section>;
}

function ComplaintDetail({ complaint, delivery, onBack, onChanged, onGo }: { complaint: OpsComplaint; delivery: ReleaseDelivery; onBack: () => void; onChanged: () => void; onGo: (view: ReleaseView) => void }) {
 const [timeline, setTimeline] = useState<OpsTimelineItem[] | null>(null);
 const [reason, setReason] = useState('');
 const [busy, setBusy] = useState(false);
 const [originalOpen, setOriginalOpen] = useState(false);
 const [justification, setJustification] = useState('');
 const [original, setOriginal] = useState<string | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; loadOpsTimeline(complaint.id).then(rows => { if (active) setTimeline(rows); }); return () => { active = false; }; }, [complaint.id, version]);
 const canDecide = complaint.status === 'in_review' || complaint.status === 'held';
 async function decide(decision: ReviewDecision) {
  const reasonError = validateOpsReason(decision, reason);
  if (reasonError) return showToast('error', reasonError, 'Confira os dados');
  if (decision === 'released' && !window.confirm('Liberar esta versão para a empresa? Ela passará a ver o texto compartilhável.')) return;
  setBusy(true); const result = await decideOpsComplaint(complaint.id, decision, reason); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', decision === 'released' ? `Manifestação liberada. ${releaseNextStep(delivery).text}` : decision === 'held' ? 'Manifestação retida para análise.' : 'Ajuste solicitado ao trabalhador.');
  setReason(''); onChanged();
 }
 async function openOriginal() {
  if (justification.trim().length < 10) return showToast('error', 'Informe a justificativa com pelo menos 10 caracteres.', 'Confira os dados');
  setBusy(true); const result = await readOpsOriginal(complaint.id, justification); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  setOriginal(result.value); setOriginalOpen(false); setJustification(''); setVersion(value => value + 1);
  showToast('success', 'Acesso registrado na trilha de auditoria.');
 }
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar</button>
  <div className="worker-detail-heading"><div><span className="editorial-eyebrow">Manifestação {complaint.protocol}</span><h2>{complaint.title}</h2><p className="muted">{complaint.companyName} · {complaint.category} · criada em {when(complaint.createdAt)}</p></div><Status status={complaint.status} /></div>
  <div className="worker-detail-grid"><div>
   <section className="worker-detail-section"><h3>Versão compartilhável</h3><p className="muted small">É o único texto que a empresa pode receber. Confira se não há nomes, locais, datas ou detalhes que identifiquem pessoas.</p>{complaint.shared ? <p className="worker-original">{complaint.shared}</p> : <p className="muted">O trabalhador ainda não escreveu a versão compartilhável.</p>}</section>
   <section className="worker-detail-section"><h3>Contexto</h3><dl><div><dt>Quando aconteceu</dt><dd>{complaint.incidentPeriod ?? '—'}</dd></div><div><dt>Recorrência</dt><dd>{complaint.recurrence ?? '—'}</dd></div><div><dt>O que espera</dt><dd>{complaint.expectedOutcomes.length ? complaint.expectedOutcomes.join(', ') : '—'}</dd></div><div><dt>Respostas da empresa</dt><dd>{complaint.responses}</dd></div></dl></section>
   {complaint.status === 'shared' && <NextStep delivery={delivery} before={false} onGo={onGo} />}
   {canDecide && <NextStep delivery={delivery} before onGo={onGo} />}
   {canDecide && <section className="worker-detail-section ops-decision"><h3>Decisão da equipe</h3>
    <label className="field">Motivo (obrigatório para ajuste ou retenção)<textarea rows={3} maxLength={opsReasonMax} aria-describedby="ops-reason-count" value={reason} onChange={event => setReason(event.target.value)} placeholder="Ex.: a versão cita o nome do gestor; retire antes da liberação." /><small className="muted">No pedido de ajuste, o motivo aparece para o trabalhador. Na retenção, fica só na trilha da equipe.</small><small id="ops-reason-count" className={`muted ops-reason-count${reason.trim().length > opsReasonMax - 30 ? ' near-limit' : ''}`}>{reason.trim().length}/{opsReasonMax} caracteres</small></label>
    <div className="ops-decision-actions"><button className="btn primary" disabled={busy || !complaint.shared} onClick={() => decide('released')}>{decisionLabels.released}</button><button className="btn" disabled={busy} onClick={() => decide('adjustment_requested')}>{decisionLabels.adjustment_requested}</button>{complaint.status !== 'held' && <button className="btn" disabled={busy} onClick={() => decide('held')}>{decisionLabels.held}</button>}</div></section>}
   <section className="worker-detail-section"><h3>Relato original</h3>
    {original !== null ? <><p className="muted small">Acesso registrado. Não copie este texto para fora da plataforma.</p><p className="worker-original">{original}</p></> :
     originalOpen ? <><label className="field">Justificativa do acesso<textarea rows={2} maxLength={500} value={justification} onChange={event => setJustification(event.target.value)} placeholder="Ex.: o texto pode identificar pessoas; pedir ajuste." /></label><div className="ops-decision-actions"><button className="btn primary" disabled={busy} onClick={openOriginal}>Abrir e registrar acesso</button><button className="btn" onClick={() => setOriginalOpen(false)}>Cancelar</button></div></> :
     <><p className="muted small">Fica fechado por padrão. Abrir exige justificativa e fica registrado na trilha de auditoria.</p><button className="btn" onClick={() => setOriginalOpen(true)}>Ver relato original</button></>}
   </section>
  </div><aside className="worker-detail-aside"><ComplaintContact complaintId={complaint.id} /><section className="worker-detail-section"><h3>Trilha</h3>
   {timeline === null ? <p className="muted">Carregando…</p> : <ol className="worker-timeline">{timeline.map((item, index) => <li key={index}><strong>{item.kind === 'response' ? 'Resposta da empresa' : item.kind === 'review' ? 'Decisão da equipe' : item.kind === 'response_review' ? 'Revisão da resposta' : item.kind === 'access' ? 'Acesso ao original' : statusLabel(eventLabels, item.status ?? 'received')}</strong><span>{when(item.createdAt)}</span><p>{item.content}</p></li>)}</ol>}
  </section></aside></div></>;
}

function Companies({ rows }: { rows: OpsCompany[] | null }) {
 return <>{head('Operação', 'Empresas', 'Empresas cadastradas, volume e resposta. Representantes, empresas a conferir e avisos ficam nas abas ao lado.')}
  {rows === null ? <p className="muted">Carregando…</p> : <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Empresa</th><th>Cidade</th><th className="num">Usuários</th><th className="num">Manifestações</th><th className="num">Liberadas</th><th className="num">Respondidas</th><th>Contato</th><th>Cadastro</th></tr></thead>
   <tbody>{rows.map(row => <tr key={row.id}><td>{row.name}<small>{row.legalName}</small></td><td>{row.city}/{row.state}</td><td className="num">{row.users}</td><td className="num">{row.complaints}</td><td className="num">{row.released}</td><td className="num">{row.answered}</td><td>{row.hasContact ? 'Sim' : '—'}</td><td>{when(row.createdAt)}</td></tr>)}</tbody></table></div>}</>;
}

export function OpsPortalLive() {
 const [view, setView] = useState<OpsView>('overview');
 const [metrics, setMetrics] = useState<OpsMetrics | null>(null);
 const [complaints, setComplaints] = useState<OpsComplaint[] | null>(null);
 const [companies, setCompanies] = useState<OpsCompany[] | null>(null);
 const [openId, setOpenId] = useState<string | null>(null);
 const [filter, setFilter] = useState<ComplaintStatusDb | ''>('');
 const [search, setSearch] = useState('');
 const [version, setVersion] = useState(0);
 const [failure, setFailure] = useState('');
 const [emailStats, setEmailStats] = useState<NotificationStats | null>(null);
 const [delivery, setDelivery] = useState<{ verified: Set<string> | null; pending: Set<string> | null }>({ verified: null, pending: null });
 const [pendingCounts, setPendingCounts] = useState<{ representatives: number | null; pendingCompanies: number | null; notices: number | null }>({ representatives: null, pendingCompanies: null, notices: null });
 useEffect(() => {
  let active = true;
  Promise.all([loadOpsMetrics(), listOpsComplaints(), listOpsCompanies()])
   .then(([m, c, co]) => { if (active) { setMetrics(m); setComplaints(c); setCompanies(co); setFailure(''); } })
   .catch(error => { if (active) setFailure(error instanceof Error ? error.message : 'Não foi possível carregar a área da equipe.'); });
  // Contadores das abas: sem a função no banco ou com erro, a aba fica sem número.
  // Fila de e-mails: sem a função ou com erro, o cartão não aparece.
  loadNotificationStats().then(value => { if (active) setEmailStats(value.missing ? null : value.stats); }).catch(() => { if (active) setEmailStats(null); });
  Promise.allSettled([listOpsRepresentatives('pending'), listPendingCompanies(), listNoticeCandidates(), listOpsRepresentatives('verified')]).then(([reps, pending, notices, verified]) => {
   if (!active) return;
   setDelivery({
    verified: verified.status === 'fulfilled' && !verified.value.missing ? new Set(verified.value.rows.map(row => row.companyId)) : null,
    pending: pending.status === 'fulfilled' && !pending.value.missing ? new Set(pending.value.rows.map(row => row.companyId)) : null,
   });
   setPendingCounts({
    representatives: reps.status === 'fulfilled' && !reps.value.missing ? reps.value.rows.length : null,
    pendingCompanies: pending.status === 'fulfilled' && !pending.value.missing ? pending.value.rows.filter(row => row.registrationStatus === 'pending_check' && !row.reviewDecision).length : null,
    notices: notices.status === 'fulfilled' && !notices.value.missing ? notices.value.rows.filter(row => noticeTab(row) === 'decide').length : null,
   });
  });
  return () => { active = false; };
 }, [version]);
 const queue = useMemo(() => oldestFirst((complaints ?? []).filter(item => item.status === 'in_review' || item.status === 'held')), [complaints]);
 const filtered = useMemo(() => (complaints ?? []).filter(item => (!filter || item.status === filter) && `${item.protocol} ${item.companyName} ${item.title} ${item.category}`.toLowerCase().includes(search.toLowerCase())), [complaints, filter, search]);
 const opened = complaints?.find(item => item.id === openId) ?? null;
 const go = (next: OpsView) => { setView(next); setOpenId(null); };
 const counts: OpsCounts = { queue: queue.length, responses: metrics?.responsesInReview ?? 0, all: complaints?.length ?? 0, companies: companies?.length ?? 0, ...pendingCounts, contacts: metrics?.contactsWaiting ?? 0 };
 const tabCounts: Partial<Record<OpsView, number | null>> = { queue: counts.queue, responses: counts.responses, representatives: counts.representatives, 'pending-companies': counts.pendingCompanies, notices: counts.notices };
 const sum = (...values: (number | null)[]) => values.reduce<number>((total, value) => total + (value ?? 0), 0);
 const section = sectionOf[view];
 const items: [OpsSection, string][] = [
  ['overview', 'Visão geral'],
  ['complaints', `Manifestações${counts.queue + counts.responses ? ` (${counts.queue + counts.responses})` : ''}`],
  ['companies', `Empresas${sum(counts.representatives, counts.pendingCompanies, counts.notices) ? ` (${sum(counts.representatives, counts.pendingCompanies, counts.notices)})` : ''}`],
  ['contacts', `Contatos${counts.contacts ? ` (${counts.contacts})` : ''}`],
 ];
 return <main className="commercial-portal-content"><Sidebar eyebrow="Operação" name="Equipe Escuta Aí Brasil" items={items} view={section} onView={next => go(firstTab[next])} /><section className="commercial-portal-main">
  {!opened && <SectionTabs section={section} view={view} counts={tabCounts} onView={go} />}
  {failure ? <section className="commercial-panel"><h2>Não foi possível carregar</h2><p>{failure}</p></section> :
   opened ? <ComplaintDetail key={opened.id + opened.status} complaint={opened} delivery={releaseDelivery(opened.companyId, delivery.verified, delivery.pending)} onBack={() => setOpenId(null)} onChanged={() => setVersion(value => value + 1)} onGo={go} /> :
   view === 'overview' ? <Overview metrics={metrics} counts={counts} emailStats={emailStats} onView={go} /> :
   view === 'queue' ? <>{head('Operação', 'Fila de revisão', 'Confira a versão compartilhável e decida: liberar para a empresa, pedir ajuste ao trabalhador ou reter para análise.')}
    {complaints === null ? <p className="muted">Carregando…</p> : <ComplaintList rows={queue} waiting onOpen={row => setOpenId(row.id)} empty="Nenhuma manifestação aguardando revisão." />}</> :
   view === 'all' ? <>{head('Operação', 'Manifestações', 'Todas as manifestações, sem identidade de quem relatou.')}
    <div className="worker-filters"><label>Buscar<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Protocolo, empresa ou assunto" /></label><label>Situação<select value={filter} onChange={event => setFilter(event.target.value as ComplaintStatusDb | '')}><option value="">Todas</option>{(Object.keys(statusLabels) as ComplaintStatusDb[]).map(key => <option key={key} value={key}>{statusLabels[key]}</option>)}</select></label></div>
    {complaints === null ? <p className="muted">Carregando…</p> : <ComplaintList rows={filtered} onOpen={row => setOpenId(row.id)} empty="Nenhuma manifestação com esse filtro." />}</> :
   view === 'responses' ? <OpsResponses onChanged={() => setVersion(value => value + 1)} /> :
   view === 'representatives' ? <OpsRepresentatives onChanged={() => setVersion(v => v + 1)} /> :
   view === 'pending-companies' ? <OpsPendingCompanies /> :
   view === 'notices' ? <OpsNotices /> :
   view === 'companies' ? <Companies rows={companies} /> :
   <ContactSolicitationsAdmin />}
 </section></main>;
}
