import { useMemo, useState } from 'react';
import { companies, complaints as seedComplaints, histories } from './mockData';
import type { Complaint, ComplaintStatus } from './models';

type Period = 'daily' | 'monthly' | 'yearly';
type View = 'dashboard' | 'list' | 'detail';

const periodLabels: Record<Period, string> = { daily: 'Diário', monthly: 'Mensal', yearly: 'Anual' };
const lockedStatuses: ComplaintStatus[] = ['Empresa sendo contatada', 'Aguardando resposta da empresa', 'Respondida', 'Em mediação', 'Finalizada', 'Encerrada sem resposta'];
const finishableStatuses: ComplaintStatus[] = ['Respondida', 'Em mediação', 'Finalizada'];

function companyName(id: string) { return companies.find(company => company.id === id)?.tradeName ?? 'Empresa não identificada'; }
function statusGroup(status: ComplaintStatus) {
  if (status === 'Finalizada' || status === 'Encerrada sem resposta') return 'Finalizada';
  if (status === 'Respondida') return 'Respondida';
  if (status === 'Revisão necessária') return 'Em revisão';
  if (status === 'Empresa sendo contatada' || status === 'Aguardando resposta da empresa') return 'Encaminhada para empresa';
  return 'Em aberto';
}
function dateLabel(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value)); }
function canCancel(complaint: Complaint) { return !lockedStatuses.includes(complaint.status) && complaint.status !== ('Cancelada' as ComplaintStatus); }
function canFinish(complaint: Complaint) { return finishableStatuses.includes(complaint.status) && complaint.status !== 'Finalizada'; }
function deleteManifestation(id: string, status: 'canceled') { return { method: 'DELETE', id, status }; }

function Status({ status }: { status: ComplaintStatus }) { return <span className={`worker-status ${statusGroup(status).toLowerCase().replaceAll(' ', '-')}`}>{statusGroup(status)}</span>; }

function Dashboard({ complaints, onList }: { complaints: Complaint[]; onList: () => void }) {
 const [period, setPeriod] = useState<Period>('monthly');
 const metrics = useMemo(() => {
  const factor = period === 'daily' ? .5 : period === 'yearly' ? 2 : 1;
  const count = (value: number) => Math.round(value * factor);
  return {
   open: count(complaints.filter(complaint => !['Finalizada', 'Encerrada sem resposta'].includes(complaint.status)).length),
   waiting: count(complaints.filter(complaint => complaint.status.includes('Aguardando')).length),
   answered: count(complaints.filter(complaint => complaint.status === 'Respondida').length),
   closed: count(complaints.filter(complaint => complaint.status === 'Finalizada').length),
  };
 }, [complaints, period]);
 const chart = period === 'daily' ? [0, 1, 0, 2, 0, 1, 0] : period === 'yearly' ? [1, 2, 3, 2, 4, 3, 5, 4, 6, 5, 4, 3] : [1, 0, 2, 1, 0, 1];
 const labels = period === 'daily' ? ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'] : period === 'yearly' ? ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'] : ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun'];
 const max = Math.max(...chart, 1);
 return <>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Início</h2><p className="muted">Acompanhe o volume e o andamento das suas manifestações.</p></div><button className="btn" onClick={onList}>Ver manifestações</button></div>
  <div className="worker-funnel">{[['Em acompanhamento', metrics.open], ['Aguardando empresa', metrics.waiting], ['Respondidas', metrics.answered], ['Finalizadas', metrics.closed]].map(([label, value]) => <article key={String(label)}><span>{label}</span><strong>{value}</strong></article>)}</div>
  <section className="worker-dashboard-section"><div className="worker-section-heading"><div><h3>Manifestações criadas</h3><p className="muted">Veja quantos relatos você registrou em cada período.</p></div><label>Período<select value={period} onChange={event => setPeriod(event.target.value as Period)}><option value="daily">Diário</option><option value="monthly">Mensal</option><option value="yearly">Anual</option></select></label></div><div className="worker-columns-chart" aria-label={`Manifestações criadas no período ${periodLabels[period]}`}>{chart.map((value, index) => <div className="worker-column" key={labels[index]}><strong>{value}</strong><i style={{ height: `${Math.max(value / max * 100, value ? 16 : 4)}%` }} /><span>{labels[index]}</span></div>)}</div></section>
  <section className="worker-dashboard-note"><h3>O que acontece depois que eu envio?</h3><p>A Escuta Aí Brasil revisa o conteúdo, prepara uma versão sem dados identificáveis, convida a empresa a responder e mantém você informado com linguagem simples.</p></section>
 </>;
}

type CalendarPeriod = 'daily' | 'weekly' | 'monthly' | 'yearly';

function DashboardV2({ complaints, onList }: { complaints: Complaint[]; onList: () => void }) {
 const today = new Date();
 const [period, setPeriod] = useState<CalendarPeriod>('weekly');
 const [monthIndex, setMonthIndex] = useState(today.getMonth());
 const year = today.getFullYear();
 const monthNames = Array.from({ length: 12 }, (_, index) => new Intl.DateTimeFormat('pt-BR', { month: 'long' }).format(new Date(year, index, 1)));
 const monthDays = new Date(year, monthIndex + 1, 0).getDate();
 const chart = period === 'daily' ? [0] : period === 'weekly' ? [0, 1, 0, 2, 0, 1, 0] : period === 'monthly' ? Array.from({ length: monthDays }, (_, index) => monthIndex === today.getMonth() && [1, 3, 6, 11, 18].includes(index + 1) ? 1 : 0) : [1, 2, 3, 2, 4, 3, 5, 4, 6, 5, 4, 3];
 const labels = period === 'daily' ? ['Hoje'] : period === 'weekly' ? ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'] : period === 'monthly' ? Array.from({ length: monthDays }, (_, index) => String(index + 1)) : monthNames.map(name => name.slice(0, 3));
 const max = Math.max(...chart, 1);
 const base = { open: complaints.filter(complaint => !['Finalizada', 'Encerrada sem resposta'].includes(complaint.status)).length, waiting: complaints.filter(complaint => complaint.status.includes('Aguardando')).length, answered: complaints.filter(complaint => complaint.status === 'Respondida').length, closed: complaints.filter(complaint => complaint.status === 'Finalizada').length };
 const factor = period === 'daily' ? 0 : period === 'weekly' ? .5 : period === 'yearly' ? 2 : 1;
 const metric = (value: number) => Math.round(value * factor);
 return <>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Início</h2><p className="muted">Acompanhe o volume e o andamento das suas manifestações.</p></div><button className="btn" onClick={onList}>Ver manifestações</button></div>
  <div className="worker-funnel">{[['Em acompanhamento', metric(base.open)], ['Aguardando empresa', metric(base.waiting)], ['Respondidas', metric(base.answered)], ['Finalizadas', metric(base.closed)]].map(([label, value]) => <article key={String(label)}><span>{label}</span><strong>{value}</strong></article>)}</div>
  <section className="worker-dashboard-section"><div className="worker-section-heading"><div><h3>Manifestações criadas</h3><p className="muted">Acompanhe o período atual e altere o recorte quando precisar.</p></div><div className="worker-chart-controls"><label>Período<select value={period} onChange={event => setPeriod(event.target.value as CalendarPeriod)}><option value="daily">Diário</option><option value="weekly">Semanal</option><option value="monthly">Mensal</option><option value="yearly">Anual</option></select></label>{period === 'monthly' && <label>Mês<select value={monthIndex} onChange={event => setMonthIndex(Number(event.target.value))}>{monthNames.map((name, index) => <option value={index} key={name}>{name}</option>)}</select></label>}</div></div><div className={`worker-columns-chart worker-columns-${period}`} aria-label={`Manifestações criadas no período ${period}`}>{chart.map((value, index) => <button className="worker-column" key={`${labels[index]}-${index}`} type="button" onClick={() => { if (period === 'yearly') { setMonthIndex(index); setPeriod('monthly'); } }}><strong>{value}</strong><i style={{ height: `${Math.max(value / max * 100, value ? 16 : 4)}%` }} /><span>{labels[index]}</span></button>)}</div>{period === 'yearly' && <p className="small worker-chart-hint">Clique em um mês para abrir sua visão mensal.</p>}</section>
  <section className="worker-dashboard-note"><h3>O que acontece depois que eu envio?</h3><p>A Escuta Aí Brasil revisa o conteúdo, prepara uma versão sem dados identificáveis, convida a empresa a responder e mantém você informado com linguagem simples.</p></section>
 </>;
}

function Filters({ onChange }: { onChange: (filters: { company: string; protocol: string; start: string; end: string; status: string }) => void }) {
 const [filters, setFilters] = useState({ company: '', protocol: '', start: '', end: '', status: '' });
 return <form className="worker-filters" onSubmit={event => { event.preventDefault(); onChange(filters); }}><label>Empresa<input value={filters.company} onChange={event => setFilters({ ...filters, company: event.target.value })} placeholder="Nome ou CNPJ" /></label><label>Número da manifestação<input value={filters.protocol} onChange={event => setFilters({ ...filters, protocol: event.target.value })} placeholder="Ex.: M-001" /></label><label>Data inicial<input type="date" value={filters.start} onChange={event => setFilters({ ...filters, start: event.target.value })} /></label><label>Data final<input type="date" value={filters.end} onChange={event => setFilters({ ...filters, end: event.target.value })} /></label><label>Situação<select value={filters.status} onChange={event => setFilters({ ...filters, status: event.target.value })}><option value="">Todas</option><option>Em aberto</option><option>Em revisão</option><option>Encaminhada para empresa</option><option>Respondida</option><option>Finalizada</option></select></label><button className="btn primary">Filtrar</button></form>;
}

function ManifestationList({ complaints, onSelect, onNew }: { complaints: Complaint[]; onSelect: (complaint: Complaint) => void; onNew: () => void }) {
 const [filters, setFilters] = useState({ company: '', protocol: '', start: '', end: '', status: '' });
 const rows = complaints.filter(complaint => { const company = companies.find(item => item.id === complaint.companyId); const search = `${company?.tradeName ?? ''} ${company?.legalName ?? ''} ${company?.cnpj ?? ''}`.toLowerCase(); const created = complaint.createdAt.slice(0, 10); return (!filters.company || search.includes(filters.company.toLowerCase())) && (!filters.protocol || complaint.id.toLowerCase().includes(filters.protocol.toLowerCase())) && (!filters.start || created >= filters.start) && (!filters.end || created <= filters.end) && (!filters.status || statusGroup(complaint.status) === filters.status); });
 return <><div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Manifestações</h2><p className="muted">Consulte seus registros e abra os detalhes para acompanhar cada etapa.</p></div><button className="btn primary" onClick={onNew}>Nova manifestação</button></div><Filters onChange={setFilters} /><div className="worker-table-wrap"><table className="worker-table"><thead><tr><th>Número</th><th>Empresa</th><th>Situação</th><th>Data de criação</th><th><span className="sr-only">Abrir</span></th></tr></thead><tbody>{rows.map(complaint => <tr key={complaint.id} tabIndex={0} onClick={() => onSelect(complaint)} onKeyDown={event => { if (event.key === 'Enter' || event.key === ' ') onSelect(complaint); }}><td>{complaint.id}</td><td>{companyName(complaint.companyId)}</td><td><Status status={complaint.status} /></td><td>{dateLabel(complaint.createdAt)}</td><td><button className="worker-row-action" aria-label={`Abrir manifestação ${complaint.id}`} onClick={event => { event.stopPropagation(); onSelect(complaint); }}>›</button></td></tr>)}</tbody></table></div>{rows.length === 0 && <div className="worker-empty"><h3>Nenhuma manifestação encontrada</h3><p>Revise os filtros ou comece uma nova manifestação.</p></div>}</>;
}

function Detail({ complaint, onBack, onCancel, onDelete, onFinish, onNewFrom }: { complaint: Complaint; onBack: () => void; onCancel: (complaint: Complaint) => void; onDelete: (complaint: Complaint) => void; onFinish: (complaint: Complaint, satisfied: boolean) => void; onNewFrom: (complaint: Complaint) => void }) {
 const timeline = histories.filter(history => history.complaintId === complaint.id);
 const [showFinishModal, setShowFinishModal] = useState(false);
 const cancelEnabled = canCancel(complaint);
 const finishEnabled = canFinish(complaint);
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar para manifestações</button><div className="worker-detail-heading"><div><span className="editorial-eyebrow">Manifestação {complaint.id}</span><h2>{complaint.title}</h2><p className="muted">{companyName(complaint.companyId)} · criada em {dateLabel(complaint.createdAt)}</p></div><Status status={complaint.status} /></div><div className="worker-detail-grid"><div><section className="worker-detail-section"><h3>Resumo</h3><dl><div><dt>Empresa</dt><dd>{companyName(complaint.companyId)}</dd></div><div><dt>Categoria</dt><dd>{complaint.category}</dd></div><div><dt>Quando aconteceu</dt><dd>{complaint.incidentDate}</dd></div><div><dt>Recorrência</dt><dd>{complaint.recurrence}</dd></div></dl></section><section className="worker-detail-section"><h3>Relato enviado</h3><p className="worker-original">{complaint.originalContent}</p></section><section className="worker-detail-section"><h3>O que você espera</h3><ul>{complaint.expectedOutcome.map(item => <li key={item}>{item}</li>)}</ul></section></div><aside className="worker-detail-aside"><section className="worker-detail-section"><h3>Acompanhamento</h3><ol className="worker-timeline">{timeline.map(item => <li key={`${item.status}-${item.timestamp}`}><strong>{item.status}</strong><span>{dateLabel(item.timestamp)}</span><p>{item.note}</p></li>)}</ol></section><section className="worker-detail-section worker-actions"><h3>Ações</h3><div className="worker-action-buttons"><button className="btn danger" disabled={!cancelEnabled} onClick={() => onCancel(complaint)}>Cancelar manifestação</button><button className="btn danger worker-delete" disabled={!cancelEnabled} onClick={() => onDelete(complaint)}>Excluir manifestação</button><button className="btn primary" disabled={!finishEnabled} onClick={() => setShowFinishModal(true)}>Finalizar</button></div>{!cancelEnabled && <p className="small">Cancelar e excluir ficam indisponíveis depois que a manifestação é encaminhada para a empresa.</p>}{!finishEnabled && <p className="small">Finalizar ficará disponível quando houver uma resposta da empresa.</p>}</section></aside></div>{showFinishModal && <div className="worker-modal-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setShowFinishModal(false); }}><section className="worker-modal" role="dialog" aria-modal="true" aria-labelledby="finish-title"><button className="worker-modal-close" type="button" onClick={() => setShowFinishModal(false)} aria-label="Fechar">×</button><span className="editorial-eyebrow">Retorno recebido</span><h2 id="finish-title">Como você avalia a resposta?</h2><p>Se você estiver satisfeito, podemos finalizar esta manifestação. Caso ainda precise de ajuda, abra uma nova manifestação ligada a este registro.</p><div className="worker-modal-actions"><button className="btn primary" onClick={() => { setShowFinishModal(false); onFinish(complaint, true); }}>Estou satisfeito</button><button className="btn" onClick={() => { setShowFinishModal(false); onNewFrom(complaint); }}>Abrir nova manifestação a partir desta</button></div></section></div>}</>;
}

export function WorkerPortal({ onNew, initialView = 'dashboard' }: { onNew: (complaint?: Complaint) => void; initialView?: View }) {
 const [view, setView] = useState<View>(initialView);
 const [selectedId, setSelectedId] = useState<string | null>(null);
 const [complaints, setComplaints] = useState(() => seedComplaints.filter(complaint => complaint.userId === 'u-worker'));
 const selected = complaints.find(complaint => complaint.id === selectedId) ?? null;
 function cancel(complaint: Complaint) { setComplaints(current => current.map(item => item.id === complaint.id ? { ...item, status: 'Cancelada' as ComplaintStatus } : item)); }
 function remove(complaint: Complaint) { const deletion = deleteManifestation(complaint.id, 'canceled'); if (deletion.status === 'canceled') setComplaints(current => current.filter(item => item.id !== complaint.id)); setSelectedId(null); setView('list'); }
 function finish(complaint: Complaint, satisfied: boolean) { if (satisfied) setComplaints(current => current.map(item => item.id === complaint.id ? { ...item, status: 'Finalizada' as ComplaintStatus } : item)); }
 return <main className="worker-portal-content" id="main-content" tabIndex={-1}>{view === 'dashboard' && <DashboardV2 complaints={complaints} onList={() => setView('list')} />}{view === 'list' && <ManifestationList complaints={complaints} onSelect={complaint => { setSelectedId(complaint.id); setView('detail'); }} onNew={onNew} />}{view === 'detail' && selected && <Detail complaint={selected} onBack={() => setView('list')} onCancel={cancel} onDelete={remove} onFinish={finish} onNewFrom={onNew} />}</main>;
}
