import { useEffect, useMemo, useState } from 'react';
import { closeWorkerComplaint, listCompanyDirectory, listWorkerComplaints, loadCompanyRanking, loadWorkerComplaintDetail, shareWorkerComplaint, type ComplaintFeedback, type ComplaintStatusDb, type DirectoryCompany, type RankingRow, type WorkerComplaint, type WorkerComplaintDetail } from '../services/data';
import { showToast } from '../app/toast';
import { ComplaintWizard } from './complaint-wizard';

// Portal do trabalhador com dados reais (modelo v3). O relato original nunca sai daqui; a empresa recebe só a versão revisada.
type View = 'dashboard' | 'list' | 'detail' | 'new' | 'companies';
export type WorkerEntryView = 'dashboard' | 'list' | 'companies';
type Period = 'weekly' | 'monthly' | 'yearly';

const statusLabels: Record<ComplaintStatusDb, string> = { received: 'Guardada', shared: 'Aguardando empresa', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const eventLabels: Record<ComplaintStatusDb, string> = { received: 'Registrada', shared: 'Enviada à empresa', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const statusClass: Record<ComplaintStatusDb, string> = { received: 'em-aberto', shared: 'encaminhada-para-empresa', answered: 'respondida', closed: 'finalizada', canceled: 'finalizada' };
const feedbackLabels: Record<ComplaintFeedback, string> = { yes: 'Sim, ajudou', partial: 'Em parte', no: 'Não ajudou' };

function dateLabel(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value)); }
function Status({ status }: { status: ComplaintStatusDb }) { return <span className={`worker-status ${statusClass[status]}`}>{statusLabels[status]}</span>; }

function hours(value: number | null) { return value === null ? '—' : value < 48 ? `${value} h` : `${(value / 24).toFixed(1).replace('.', ',')} dias`; }

// Ranking público de responsividade: só empresas com 3+ manifestações compartilhadas, sem nenhum dado de quem relatou.
function Companies({ companies, onNew }: { companies: DirectoryCompany[]; onNew: (companyId?: string) => void }) {
 const [rows, setRows] = useState<RankingRow[] | null>(null);
 const [search, setSearch] = useState('');
 useEffect(() => { let active = true; loadCompanyRanking().then(data => { if (active) setRows(data); }); return () => { active = false; }; }, []);
 const listed = companies.filter(company => `${company.name} ${company.city} ${company.state}`.toLowerCase().includes(search.toLowerCase()));
 return <section className="worker-companies">
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Empresas</h2><p className="muted">Como as empresas respondem às manifestações compartilhadas.</p></div><button className="btn primary" onClick={() => onNew()}>Nova manifestação</button></div>
  <label className="field worker-company-search">Buscar empresa<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome ou cidade" /></label>
  {!listed.length ? <p className="muted">Nenhuma empresa encontrada.</p> : <div className="worker-company-list">{listed.map(company => <article key={company.id} className="worker-company-row"><div><strong>{company.name}</strong><small>{company.city}/{company.state}</small></div><button className="btn" onClick={() => onNew(company.id)}>Fazer manifestação</button></article>)}</div>}
  <h3>Como as empresas respondem</h3>
  <p className="muted small">Entram no ranking empresas com pelo menos 3 manifestações compartilhadas, para uma comparação justa. Nenhum relato ou identidade aparece aqui.</p>
  {rows === null ? <p className="muted">Carregando…</p> : rows.length === 0 ? <p>Ainda não há empresas com volume suficiente.</p> :
  <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Posição</th><th>Empresa</th><th>Cidade</th><th>Manifestações</th><th>Taxa de resposta</th><th>Tempo médio até responder</th></tr></thead><tbody>{rows.map((row, index) => <tr key={row.companyId}><td>{index + 1}º</td><td>{row.name}</td><td>{row.city}/{row.state}</td><td>{row.received}</td><td>{row.responseRate}%</td><td>{hours(row.avgFirstResponseHours)}</td></tr>)}</tbody></table></div>}
 </section>;
}

function Dashboard({ complaints, onList, onNew }: { complaints: WorkerComplaint[]; onList: () => void; onNew: () => void }) {
 const [period, setPeriod] = useState<Period>('monthly');
 const now = new Date();
 const { labels, values } = useMemo(() => {
  if (period === 'weekly') {
   const days = Array.from({ length: 7 }, (_, index) => { const day = new Date(now); day.setDate(now.getDate() - 6 + index); return day; });
   return { labels: days.map(day => new Intl.DateTimeFormat('pt-BR', { weekday: 'short' }).format(day).replace('.', '')), values: days.map(day => complaints.filter(item => new Date(item.createdAt).toDateString() === day.toDateString()).length) };
  }
  if (period === 'monthly') {
   const total = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
   return { labels: Array.from({ length: total }, (_, index) => String(index + 1)), values: Array.from({ length: total }, (_, index) => complaints.filter(item => { const created = new Date(item.createdAt); return created.getFullYear() === now.getFullYear() && created.getMonth() === now.getMonth() && created.getDate() === index + 1; }).length) };
  }
  return { labels: Array.from({ length: 12 }, (_, index) => new Intl.DateTimeFormat('pt-BR', { month: 'short' }).format(new Date(now.getFullYear(), index, 1)).replace('.', '')), values: Array.from({ length: 12 }, (_, index) => complaints.filter(item => { const created = new Date(item.createdAt); return created.getFullYear() === now.getFullYear() && created.getMonth() === index; }).length) };
 }, [complaints, period]);
 const max = Math.max(...values, 1);
 const count = (statuses: ComplaintStatusDb[]) => complaints.filter(item => statuses.includes(item.status)).length;
 return <>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Início</h2><p className="muted">Acompanhe o volume e o andamento das suas manifestações.</p></div><div className="nav-actions"><button className="btn" onClick={onList}>Ver manifestações</button><button className="btn primary" onClick={onNew}>Nova manifestação</button></div></div>
  <div className="worker-funnel">{[['Em acompanhamento', count(['received', 'shared', 'answered'])], ['Aguardando empresa', count(['shared'])], ['Respondidas', count(['answered'])], ['Finalizadas', count(['closed'])]].map(([label, value]) => <article key={String(label)}><span>{label}</span><strong>{value}</strong></article>)}</div>
  <section className="worker-dashboard-section"><div className="worker-section-heading"><div><h3>Manifestações criadas</h3><p className="muted">Quantos relatos você registrou no período.</p></div><div className="worker-chart-controls"><label>Período<select value={period} onChange={event => setPeriod(event.target.value as Period)}><option value="weekly">Últimos 7 dias</option><option value="monthly">Este mês</option><option value="yearly">Este ano</option></select></label></div></div>
   <div className={`worker-columns-chart worker-columns-${period}`} aria-label="Manifestações criadas no período">{values.map((value, index) => <div className="worker-column" key={`${labels[index]}-${index}`}><strong>{value}</strong><i style={{ height: `${Math.max(value / max * 100, value ? 16 : 4)}%` }} /><span>{labels[index]}</span></div>)}</div></section>
  <section className="worker-dashboard-note"><h3>O que acontece depois que eu envio?</h3><p>Você revisa a versão que a empresa vai ler e decide se envia agora. A empresa nunca vê seu relato original nem sua identidade, e você acompanha cada resposta por aqui.</p></section>
 </>;
}

function List({ complaints, companies, onSelect, onNew }: { complaints: WorkerComplaint[]; companies: Map<string, DirectoryCompany>; onSelect: (item: WorkerComplaint) => void; onNew: () => void }) {
 const [search, setSearch] = useState('');
 const [status, setStatus] = useState('');
 const rows = complaints.filter(item => `${item.protocol} ${item.title} ${companies.get(item.companyId)?.name ?? ''}`.toLowerCase().includes(search.toLowerCase()) && (!status || item.status === status));
 return <><div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Manifestações</h2><p className="muted">Consulte seus registros e abra os detalhes para acompanhar cada etapa.</p></div><button className="btn primary" onClick={onNew}>Nova manifestação</button></div>
  <div className="worker-filters"><label>Buscar<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Protocolo, assunto ou empresa" /></label><label>Situação<select value={status} onChange={event => setStatus(event.target.value)}><option value="">Todas</option>{Object.entries(statusLabels).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label></div>
  {rows.length === 0 ? <div className="worker-empty"><h3>{complaints.length ? 'Nenhuma manifestação encontrada' : 'Você ainda não registrou manifestações'}</h3><p>{complaints.length ? 'Revise a busca ou a situação.' : 'Quando quiser, comece uma nova manifestação. Você decide o que a empresa vai ler.'}</p></div> :
  <div className="worker-table-wrap"><table className="worker-table"><thead><tr><th>Protocolo</th><th>Assunto</th><th>Empresa</th><th>Situação</th><th>Criada em</th><th><span className="sr-only">Abrir</span></th></tr></thead><tbody>{rows.map(item => <tr key={item.id} tabIndex={0} onClick={() => onSelect(item)} onKeyDown={event => { if (event.key === 'Enter' || event.key === ' ') onSelect(item); }}><td>{item.protocol}</td><td>{item.title}</td><td>{companies.get(item.companyId)?.name ?? '—'}</td><td><Status status={item.status} /></td><td>{dateLabel(item.createdAt)}</td><td><button className="worker-row-action" aria-label={`Abrir manifestação ${item.protocol}`} onClick={event => { event.stopPropagation(); onSelect(item); }}>›</button></td></tr>)}</tbody></table></div>}</>;
}

function Detail({ complaint, company, onBack, onChanged }: { complaint: WorkerComplaint; company?: DirectoryCompany; onBack: () => void; onChanged: () => void }) {
 const [detail, setDetail] = useState<WorkerComplaintDetail | null>(null);
 const [shareText, setShareText] = useState('');
 const [busy, setBusy] = useState(false);
 const [feedback, setFeedback] = useState<ComplaintFeedback | ''>('');
 useEffect(() => { let active = true; loadWorkerComplaintDetail(complaint.id).then(value => { if (active) { setDetail(value); setShareText(value.original); } }); return () => { active = false; }; }, [complaint.id]);
 async function share() {
  if (shareText.trim().length < 10) return showToast('error', 'Revise a versão para a empresa (mínimo de 10 caracteres).');
  setBusy(true); const result = await shareWorkerComplaint(complaint.id, shareText); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Versão enviada à empresa.'); onChanged();
 }
 async function close() {
  setBusy(true); const result = await closeWorkerComplaint(complaint.id, complaint.status === 'received' ? null : feedback || null); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', complaint.status === 'received' ? 'Manifestação cancelada.' : 'Acompanhamento encerrado. Obrigado pelo retorno.'); onChanged();
 }
 const open = !['closed', 'canceled'].includes(complaint.status);
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar para manifestações</button>
  <div className="worker-detail-heading"><div><span className="editorial-eyebrow">Manifestação {complaint.protocol}</span><h2>{complaint.title}</h2><p className="muted">{company?.name ?? '—'} · criada em {dateLabel(complaint.createdAt)}</p></div><Status status={complaint.status} /></div>
  {!detail ? <p className="muted">Carregando detalhes…</p> : <div className="worker-detail-grid"><div>
   <section className="worker-detail-section"><h3>Resumo</h3><dl><div><dt>Empresa</dt><dd>{company?.name ?? '—'}</dd></div><div><dt>Assunto</dt><dd>{complaint.category}</dd></div><div><dt>Quando aconteceu</dt><dd>{complaint.incidentPeriod ?? '—'}</dd></div><div><dt>Recorrência</dt><dd>{complaint.recurrence ?? '—'}</dd></div></dl></section>
   <section className="worker-detail-section"><h3>Seu relato original</h3><p className="muted small">Só você vê este texto.</p><p className="worker-original">{detail.original}</p></section>
   {detail.shared ? <section className="worker-detail-section"><h3>Versão que a empresa recebeu</h3><p className="worker-original">{detail.shared}</p></section> : complaint.status === 'received' && <section className="worker-detail-section"><h3>Compartilhar com a empresa</h3><p className="muted small">Revise o texto abaixo e retire nomes, locais, datas ou detalhes que possam identificar você ou outras pessoas. Só esta versão será enviada.</p><textarea className="worker-share-text" rows={6} value={shareText} onChange={event => setShareText(event.target.value)} aria-label="Versão para a empresa" /><button className="btn primary" disabled={busy} onClick={share}>Enviar esta versão à empresa</button></section>}
   {complaint.expectedOutcomes.length > 0 && <section className="worker-detail-section"><h3>O que você espera</h3><ul>{complaint.expectedOutcomes.map(item => <li key={item}>{item}</li>)}</ul></section>}
  </div><aside className="worker-detail-aside">
   <section className="worker-detail-section"><h3>Acompanhamento</h3><ol className="worker-timeline">{detail.timeline.map((item, index) => <li key={index} className={item.kind === 'response' ? 'worker-timeline-response' : ''}><strong>{item.kind === 'response' ? 'Resposta da empresa' : eventLabels[item.status ?? 'received']}</strong><span>{dateLabel(item.createdAt)}</span><p>{item.content}</p></li>)}</ol></section>
   {open && <section className="worker-detail-section worker-actions"><h3>{complaint.status === 'received' ? 'Cancelar' : 'Encerrar acompanhamento'}</h3>{complaint.status !== 'received' && <label>A resposta ajudou?<select value={feedback} onChange={event => setFeedback(event.target.value as ComplaintFeedback | '')}><option value="">Prefiro não avaliar</option>{Object.entries(feedbackLabels).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label>}<button className="btn" disabled={busy} onClick={close}>{complaint.status === 'received' ? 'Cancelar manifestação' : 'Encerrar acompanhamento'}</button></section>}
   {complaint.feedback && <section className="worker-detail-section"><h3>Sua avaliação</h3><p>{feedbackLabels[complaint.feedback]}</p></section>}
  </aside></div>}</>;
}


export function WorkerPortalLive({ initialView = 'dashboard' }: { initialView?: WorkerEntryView }) {
 const [view, setView] = useState<View>(initialView);
 const [complaints, setComplaints] = useState<WorkerComplaint[] | null>(null);
 const [companies, setCompanies] = useState<DirectoryCompany[]>([]);
 const [selectedId, setSelectedId] = useState<string | null>(null);
 const [newCompanyId, setNewCompanyId] = useState('');
 const startNew = (companyId = '') => { setNewCompanyId(companyId); setView('new'); };
 const [version, setVersion] = useState(0);
 useEffect(() => { setView(initialView); }, [initialView]);
 useEffect(() => { let active = true; Promise.all([listWorkerComplaints(), listCompanyDirectory()]).then(([rows, directory]) => { if (active) { setComplaints(rows); setCompanies(directory); } }); return () => { active = false; }; }, [version]);
 const byId = useMemo(() => new Map(companies.map(company => [company.id, company])), [companies]);
 const selected = complaints?.find(item => item.id === selectedId);
 const reload = () => setVersion(value => value + 1);
 return <main className="worker-portal-content" id="main-content" tabIndex={-1}>
  {complaints === null ? <p className="muted">Carregando suas manifestações…</p> :
   view === 'new' ? <ComplaintWizard key={newCompanyId} companies={companies} initialCompanyId={newCompanyId} onCancel={() => setView('list')} onCreated={() => { reload(); setView('list'); }} /> :
   view === 'detail' && selected ? <Detail complaint={selected} company={byId.get(selected.companyId)} onBack={() => setView('list')} onChanged={reload} /> :
   view === 'companies' ? <Companies companies={companies} onNew={startNew} /> :
   view === 'list' ? <List complaints={complaints} companies={byId} onSelect={item => { setSelectedId(item.id); setView('detail'); }} onNew={() => startNew()} /> :
   <Dashboard complaints={complaints} onList={() => setView('list')} onNew={() => startNew()} />}
 </main>;
}
