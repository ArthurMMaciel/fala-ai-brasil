import { useEffect, useMemo, useState } from 'react';
import { decideOpsComplaint, listOpsComplaints, listOpsCompanies, loadOpsMetrics, loadOpsTimeline, readOpsOriginal, type OpsComplaint, type OpsCompany, type OpsMetrics, type OpsTimelineItem, type ReviewDecision } from '../services/ops';
import type { ComplaintStatusDb } from '../services/data';
import { statusLabel } from '../domain/complaint-status';
import { oldestFirst, waitingLabel } from '../domain/ops-queue';
import { showToast } from '../app/toast';
import { Metric, Sidebar } from './portal-live';
import { QuickActions } from './ui';
import { ContactSolicitationsAdmin } from './contact-solicitations-admin';
import { OpsResponses } from './response-review';

// Área da equipe (ADR-0010): revisão antes da liberação, acesso ao original só com justificativa, números agregados.
type OpsView = 'overview' | 'queue' | 'responses' | 'all' | 'companies' | 'contacts';

const statusLabels: Record<ComplaintStatusDb, string> = { received: 'Guardada pelo trabalhador', in_review: 'Em revisão', adjustment_requested: 'Ajuste solicitado', held: 'Retida', shared: 'Liberada · aguardando empresa', answer_in_review: 'Resposta em revisão', answered: 'Respondida', closed: 'Finalizada', canceled: 'Retirada' };
const statusTone: Record<ComplaintStatusDb, string> = { received: 'em-aberto', in_review: 'em-revisão', adjustment_requested: 'em-revisão', held: 'retida', shared: 'encaminhada-para-empresa', answer_in_review: 'em-revisão', answered: 'respondida', closed: 'finalizada', canceled: 'finalizada' };
const eventLabels: Record<ComplaintStatusDb, string> = { received: 'Registrada', in_review: 'Revisão solicitada', adjustment_requested: 'Ajuste solicitado', held: 'Retida', shared: 'Liberada para a empresa', answer_in_review: 'Resposta enviada · em revisão', answered: 'Respondida', closed: 'Finalizada', canceled: 'Retirada pelo trabalhador' };
const decisionLabels: Record<ReviewDecision, string> = { released: 'Liberar para a empresa', adjustment_requested: 'Pedir ajuste ao trabalhador', held: 'Reter para análise' };

function when(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(value)); }
function hours(value: number | null) { return value === null ? '—' : value < 48 ? `${String(value).replace('.', ',')} h` : `${(value / 24).toFixed(1).replace('.', ',')} dias`; }
function Status({ status }: { status: ComplaintStatusDb }) { return <span className={`worker-status ${statusLabel(statusTone, status, 'em-aberto')}`}>{statusLabel(statusLabels, status)}</span>; }
const head = (eyebrow: string, title: string, text: string) => <div className="commercial-page-head"><div><span className="editorial-eyebrow">{eyebrow}</span><h1>{title}</h1><p>{text}</p></div></div>;

function Overview({ metrics, onView }: { metrics: OpsMetrics | null; onView: (view: OpsView) => void }) {
 if (!metrics) return <p className="muted">Carregando números…</p>;
 const s = metrics.byStatus;
 const max = Math.max(1, ...metrics.weekly.map(item => item.total));
 return <>{head('Operação', 'Visão geral', 'Números agregados da plataforma. Nenhum dado individual aparece aqui.')}
  <QuickActions label="Atalhos da equipe" items={[
   { icon: 'inbox', label: 'Fila de revisão', badge: (s.in_review ?? 0) + (s.held ?? 0), onClick: () => onView('queue') },
   { icon: 'inbox', label: 'Respostas em revisão', badge: metrics.responsesInReview, onClick: () => onView('responses') },
   { icon: 'list', label: 'Todas as manifestações', onClick: () => onView('all') },
   { icon: 'building', label: 'Empresas', onClick: () => onView('companies') },
   { icon: 'users', label: 'Solicitações de contato', badge: metrics.contactsWaiting, onClick: () => onView('contacts') },
  ]} />
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
 if (!rows.length) return <section className="commercial-panel"><p className="muted">{empty}</p></section>;
 return <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Protocolo</th><th>Empresa</th><th>Assunto</th><th>Situação</th><th>{waiting ? 'Aguardando' : 'Atualizada'}</th></tr></thead>
  <tbody>{rows.map(row => <tr key={row.id} tabIndex={0} onClick={() => onOpen(row)} onKeyDown={event => event.key === 'Enter' && onOpen(row)}><td>{row.protocol}</td><td>{row.companyName}</td><td>{row.title}<small>{row.category}</small></td><td><Status status={row.status} /></td><td>{waiting ? <span title={when(row.updatedAt)}>{waitingLabel(row.updatedAt)}</span> : when(row.updatedAt)}</td></tr>)}</tbody></table></div>;
}

function ComplaintDetail({ complaint, onBack, onChanged }: { complaint: OpsComplaint; onBack: () => void; onChanged: () => void }) {
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
  if (decision !== 'released' && reason.trim().length < 10) return showToast('error', 'Explique o motivo com pelo menos 10 caracteres.', 'Confira os dados');
  if (decision === 'released' && !window.confirm('Liberar esta versão para a empresa? Ela passará a ver o texto compartilhável.')) return;
  setBusy(true); const result = await decideOpsComplaint(complaint.id, decision, reason); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', decision === 'released' ? 'Manifestação liberada para a empresa.' : decision === 'held' ? 'Manifestação retida para análise.' : 'Ajuste solicitado ao trabalhador.');
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
   {canDecide && <section className="worker-detail-section ops-decision"><h3>Decisão da equipe</h3>
    <label className="field">Motivo (obrigatório para ajuste ou retenção)<textarea rows={3} maxLength={500} value={reason} onChange={event => setReason(event.target.value)} placeholder="Ex.: a versão cita o nome do gestor; retire antes da liberação." /><small className="muted">No pedido de ajuste, o motivo aparece para o trabalhador. Na retenção, fica só na trilha da equipe.</small></label>
    <div className="ops-decision-actions"><button className="btn primary" disabled={busy || !complaint.shared} onClick={() => decide('released')}>{decisionLabels.released}</button><button className="btn" disabled={busy} onClick={() => decide('adjustment_requested')}>{decisionLabels.adjustment_requested}</button>{complaint.status !== 'held' && <button className="btn" disabled={busy} onClick={() => decide('held')}>{decisionLabels.held}</button>}</div></section>}
   <section className="worker-detail-section"><h3>Relato original</h3>
    {original !== null ? <><p className="muted small">Acesso registrado. Não copie este texto para fora da plataforma.</p><p className="worker-original">{original}</p></> :
     originalOpen ? <><label className="field">Justificativa do acesso<textarea rows={2} maxLength={500} value={justification} onChange={event => setJustification(event.target.value)} placeholder="Ex.: o texto pode identificar pessoas; pedir ajuste." /></label><div className="ops-decision-actions"><button className="btn primary" disabled={busy} onClick={openOriginal}>Abrir e registrar acesso</button><button className="btn" onClick={() => setOriginalOpen(false)}>Cancelar</button></div></> :
     <><p className="muted small">Fica fechado por padrão. Abrir exige justificativa e fica registrado na trilha de auditoria.</p><button className="btn" onClick={() => setOriginalOpen(true)}>Ver relato original</button></>}
   </section>
  </div><aside className="worker-detail-aside"><section className="worker-detail-section"><h3>Trilha</h3>
   {timeline === null ? <p className="muted">Carregando…</p> : <ol className="worker-timeline">{timeline.map((item, index) => <li key={index}><strong>{item.kind === 'response' ? 'Resposta da empresa' : item.kind === 'review' ? 'Decisão da equipe' : item.kind === 'response_review' ? 'Revisão da resposta' : item.kind === 'access' ? 'Acesso ao original' : statusLabel(eventLabels, item.status ?? 'received')}</strong><span>{when(item.createdAt)}</span><p>{item.content}</p></li>)}</ol>}
  </section></aside></div></>;
}

function Companies({ rows }: { rows: OpsCompany[] | null }) {
 return <>{head('Operação', 'Empresas', 'Empresas cadastradas, volume e resposta. A verificação de representante entra na próxima etapa (TASK-0011).')}
  {rows === null ? <p className="muted">Carregando…</p> : <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Empresa</th><th>Cidade</th><th>Usuários</th><th>Manifestações</th><th>Liberadas</th><th>Respondidas</th><th>Contato</th><th>Cadastro</th></tr></thead>
   <tbody>{rows.map(row => <tr key={row.id}><td>{row.name}<small>{row.legalName}</small></td><td>{row.city}/{row.state}</td><td>{row.users}</td><td>{row.complaints}</td><td>{row.released}</td><td>{row.answered}</td><td>{row.hasContact ? 'Sim' : '—'}</td><td>{when(row.createdAt)}</td></tr>)}</tbody></table></div>}</>;
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
 useEffect(() => {
  let active = true;
  Promise.all([loadOpsMetrics(), listOpsComplaints(), listOpsCompanies()])
   .then(([m, c, co]) => { if (active) { setMetrics(m); setComplaints(c); setCompanies(co); setFailure(''); } })
   .catch(error => { if (active) setFailure(error instanceof Error ? error.message : 'Não foi possível carregar a área da equipe.'); });
  return () => { active = false; };
 }, [version]);
 const queue = useMemo(() => oldestFirst((complaints ?? []).filter(item => item.status === 'in_review' || item.status === 'held')), [complaints]);
 const filtered = useMemo(() => (complaints ?? []).filter(item => (!filter || item.status === filter) && `${item.protocol} ${item.companyName} ${item.title} ${item.category}`.toLowerCase().includes(search.toLowerCase())), [complaints, filter, search]);
 const opened = complaints?.find(item => item.id === openId) ?? null;
 const go = (next: OpsView) => { setView(next); setOpenId(null); };
 const items: [OpsView, string][] = [['overview', 'Visão geral'], ['queue', `Fila de revisão${queue.length ? ` (${queue.length})` : ''}`], ['responses', `Respostas em revisão${metrics?.responsesInReview ? ` (${metrics.responsesInReview})` : ''}`], ['all', 'Manifestações'], ['companies', 'Empresas'], ['contacts', 'Solicitações de contato']];
 return <main className="commercial-portal-content"><Sidebar eyebrow="Operação" name="Equipe Escuta Aí Brasil" items={items} view={view} onView={go} /><section className="commercial-portal-main">
  {failure ? <section className="commercial-panel"><h2>Não foi possível carregar</h2><p>{failure}</p></section> :
   opened ? <ComplaintDetail key={opened.id + opened.status} complaint={opened} onBack={() => setOpenId(null)} onChanged={() => setVersion(value => value + 1)} /> :
   view === 'overview' ? <Overview metrics={metrics} onView={go} /> :
   view === 'queue' ? <>{head('Operação', 'Fila de revisão', 'Confira a versão compartilhável e decida: liberar para a empresa, pedir ajuste ao trabalhador ou reter para análise.')}
    {complaints === null ? <p className="muted">Carregando…</p> : <ComplaintList rows={queue} waiting onOpen={row => setOpenId(row.id)} empty="Nenhuma manifestação aguardando revisão." />}</> :
   view === 'all' ? <>{head('Operação', 'Manifestações', 'Todas as manifestações, sem identidade de quem relatou.')}
    <div className="worker-filters"><label>Buscar<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Protocolo, empresa ou assunto" /></label><label>Situação<select value={filter} onChange={event => setFilter(event.target.value as ComplaintStatusDb | '')}><option value="">Todas</option>{(Object.keys(statusLabels) as ComplaintStatusDb[]).map(key => <option key={key} value={key}>{statusLabels[key]}</option>)}</select></label></div>
    {complaints === null ? <p className="muted">Carregando…</p> : <ComplaintList rows={filtered} onOpen={row => setOpenId(row.id)} empty="Nenhuma manifestação com esse filtro." />}</> :
   view === 'responses' ? <OpsResponses onChanged={() => setVersion(value => value + 1)} /> :
   view === 'companies' ? <Companies rows={companies} /> :
   <ContactSolicitationsAdmin />}
 </section></main>;
}
