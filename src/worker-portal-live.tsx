import { useEffect, useMemo, useState } from 'react';
import { closeWorkerComplaint, createWorkerComplaint, listCompanyDirectory, listWorkerComplaints, loadWorkerComplaintDetail, shareWorkerComplaint, type ComplaintFeedback, type ComplaintStatusDb, type DirectoryCompany, type WorkerComplaint, type WorkerComplaintDetail } from './data';
import { topics } from './editorial-model';
import { showToast } from './toast';

// Portal do trabalhador com dados reais (modelo v3). O relato original nunca sai daqui; a empresa recebe só a versão revisada.
type View = 'dashboard' | 'list' | 'detail' | 'new';
type Period = 'weekly' | 'monthly' | 'yearly';

const statusLabels: Record<ComplaintStatusDb, string> = { received: 'Guardada', shared: 'Aguardando empresa', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const eventLabels: Record<ComplaintStatusDb, string> = { received: 'Registrada', shared: 'Enviada à empresa', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const statusClass: Record<ComplaintStatusDb, string> = { received: 'em-aberto', shared: 'encaminhada-para-empresa', answered: 'respondida', closed: 'finalizada', canceled: 'finalizada' };
const outcomes = ['Receber uma resposta', 'Que alguma prática seja revista', 'Ter um canal de diálogo', 'Apenas registrar o ocorrido'];
const periods = ['Hoje', 'Nesta semana', 'Neste mês', 'Há mais de um mês'];
const recurrences = ['Uma vez', 'Algumas vezes', 'Recorrente'];
const feedbackLabels: Record<ComplaintFeedback, string> = { yes: 'Sim, ajudou', partial: 'Em parte', no: 'Não ajudou' };

function dateLabel(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value)); }
function Status({ status }: { status: ComplaintStatusDb }) { return <span className={`worker-status ${statusClass[status]}`}>{statusLabels[status]}</span>; }

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

function NewComplaint({ companies, onCancel, onCreated }: { companies: DirectoryCompany[]; onCancel: () => void; onCreated: () => void }) {
 const [form, setForm] = useState({ companyId: '', category: '', title: '', incidentPeriod: '', recurrence: '', original: '', shared: '', expectedOutcomes: [] as string[] });
 const [companySearch, setCompanySearch] = useState('');
 const [reviewed, setReviewed] = useState(false);
 const [busy, setBusy] = useState(false);
 const set = (key: keyof typeof form, value: string | string[]) => setForm(current => ({ ...current, [key]: value }));
 const filtered = companies.filter(company => `${company.name} ${company.city}`.toLowerCase().includes(companySearch.toLowerCase())).slice(0, 8);
 function validate(share: boolean) {
  if (!form.companyId) return 'Escolha a empresa relacionada.';
  if (!form.category) return 'Escolha um assunto.';
  if (form.title.trim().length < 3) return 'Dê um título curto à manifestação.';
  if (form.original.trim().length < 10) return 'Descreva a situação com pelo menos 10 caracteres.';
  if (share && (!reviewed || form.shared.trim().length < 10)) return 'Revise a versão que a empresa vai ler antes de enviar.';
  return '';
 }
 async function submit(share: boolean) {
  const error = validate(share); if (error) return showToast('error', error);
  setBusy(true); const result = await createWorkerComplaint(form, share); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', share ? 'Manifestação registrada e enviada à empresa.' : 'Manifestação guardada. Você pode compartilhar depois.'); onCreated();
 }
 const selected = companies.find(company => company.id === form.companyId);
 return <><button className="text-action worker-back" onClick={onCancel}>← Voltar</button>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Nova manifestação</span><h2>Conte o que aconteceu</h2><p className="muted">Você escreve o relato e revisa a versão que a empresa vai ler. Seu nome e seus dados não são enviados.</p></div></div>
  <section className="worker-detail-section worker-form-step"><h3>1. Empresa</h3>{selected ? <p><strong>{selected.name}</strong> · {selected.city}/{selected.state} <button className="text-action" onClick={() => set('companyId', '')}>Trocar</button></p> : <><label>Buscar empresa<input value={companySearch} onChange={event => setCompanySearch(event.target.value)} placeholder="Nome ou cidade" /></label><div className="worker-company-options">{filtered.map(company => <button key={company.id} className="btn" type="button" onClick={() => set('companyId', company.id)}>{company.name} · {company.city}/{company.state}</button>)}{filtered.length === 0 && <p className="muted small">Nenhuma empresa encontrada. Nesta versão, só empresas cadastradas podem receber manifestações.</p>}</div></>}</section>
  <section className="worker-detail-section worker-form-step"><h3>2. Assunto</h3><div className="grid two"><label>Assunto<select value={form.category} onChange={event => set('category', event.target.value)}><option value="">Selecione</option>{topics.map(topic => <option key={topic}>{topic}</option>)}</select></label><label>Título curto<input value={form.title} maxLength={140} onChange={event => set('title', event.target.value)} placeholder="Ex.: Pedidos fora do horário" /></label><label>Quando aconteceu<select value={form.incidentPeriod} onChange={event => set('incidentPeriod', event.target.value)}><option value="">Prefiro não dizer</option>{periods.map(item => <option key={item}>{item}</option>)}</select></label><label>Com que frequência<select value={form.recurrence} onChange={event => set('recurrence', event.target.value)}><option value="">Prefiro não dizer</option>{recurrences.map(item => <option key={item}>{item}</option>)}</select></label></div></section>
  <section className="worker-detail-section worker-form-step"><h3>3. Seu relato</h3><p className="muted small">Este texto fica só com você. Pode escrever com suas palavras.</p><textarea rows={6} maxLength={5000} value={form.original} onChange={event => { set('original', event.target.value); setReviewed(false); }} aria-label="Relato original" /></section>
  <section className="worker-detail-section worker-form-step"><h3>4. Versão para a empresa</h3>{!reviewed ? <><p className="muted small">Vamos preparar uma cópia do relato para você revisar. Retire nomes, locais, datas e detalhes que identifiquem pessoas.</p><button className="btn" type="button" disabled={form.original.trim().length < 10} onClick={() => { set('shared', form.original); setReviewed(true); }}>Preparar versão para revisar</button></> : <><textarea rows={6} maxLength={5000} value={form.shared} onChange={event => set('shared', event.target.value)} aria-label="Versão para a empresa" /><p className="muted small">A empresa lerá exatamente este texto.</p></>}</section>
  <section className="worker-detail-section worker-form-step"><h3>5. O que você espera</h3><div className="worker-outcomes">{outcomes.map(item => <label key={item} className="check-row"><input type="checkbox" checked={form.expectedOutcomes.includes(item)} onChange={event => set('expectedOutcomes', event.target.checked ? [...form.expectedOutcomes, item] : form.expectedOutcomes.filter(value => value !== item))} /> <span>{item}</span></label>)}</div></section>
  <div className="nav-actions worker-form-actions"><button className="btn" disabled={busy} onClick={() => submit(false)}>Guardar sem compartilhar</button><button className="btn primary" disabled={busy} onClick={() => submit(true)}>Enviar à empresa</button></div></>;
}

export function WorkerPortalLive({ initialView = 'dashboard' }: { initialView?: 'dashboard' | 'list' }) {
 const [view, setView] = useState<View>(initialView);
 const [complaints, setComplaints] = useState<WorkerComplaint[] | null>(null);
 const [companies, setCompanies] = useState<DirectoryCompany[]>([]);
 const [selectedId, setSelectedId] = useState<string | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { setView(initialView); }, [initialView]);
 useEffect(() => { let active = true; Promise.all([listWorkerComplaints(), listCompanyDirectory()]).then(([rows, directory]) => { if (active) { setComplaints(rows); setCompanies(directory); } }); return () => { active = false; }; }, [version]);
 const byId = useMemo(() => new Map(companies.map(company => [company.id, company])), [companies]);
 const selected = complaints?.find(item => item.id === selectedId);
 const reload = () => setVersion(value => value + 1);
 return <main className="worker-portal-content" id="main-content" tabIndex={-1}>
  {complaints === null ? <p className="muted">Carregando suas manifestações…</p> :
   view === 'new' ? <NewComplaint companies={companies} onCancel={() => setView('list')} onCreated={() => { reload(); setView('list'); }} /> :
   view === 'detail' && selected ? <Detail complaint={selected} company={byId.get(selected.companyId)} onBack={() => setView('list')} onChanged={reload} /> :
   view === 'list' ? <List complaints={complaints} companies={byId} onSelect={item => { setSelectedId(item.id); setView('detail'); }} onNew={() => setView('new')} /> :
   <Dashboard complaints={complaints} onList={() => setView('list')} onNew={() => setView('new')} />}
 </main>;
}
