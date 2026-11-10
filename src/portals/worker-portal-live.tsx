import { useEffect, useMemo, useRef, useState } from 'react';
import { closeWorkerComplaint, listCompanyDirectory, listWorkerComplaints, listCompanyResponsiveness, loadWorkerComplaintDetail, shareWorkerComplaint, type ComplaintFeedback, type ComplaintStatusDb, type DirectoryCompany, type ResponsivenessRow, type WorkerComplaint, type WorkerComplaintDetail } from '../services/data';
import { showToast } from '../app/toast';
import { ComplaintWizard } from './complaint-wizard';
import { QuickActions } from './ui';
import { WorkerProfile } from './profile-live';
import { ResponsivenessTable, responsivenessMethod } from './responsiveness';
import { statusLabel } from '../domain/complaint-status';
import { buildWorkerPrint, printDateTime } from '../domain/print-document';
import { usePrintDocument } from './print-document';

// Portal do trabalhador com dados reais (modelo v3). O relato original nunca sai daqui; a empresa recebe só a versão revisada.
type View = 'dashboard' | 'list' | 'detail' | 'new' | 'companies' | 'profile';
export type WorkerEntryView = 'dashboard' | 'list' | 'companies' | 'profile';
type Period = 'weekly' | 'monthly' | 'yearly';

const statusLabels: Record<ComplaintStatusDb, string> = { received: 'Guardada', in_review: 'Em revisão', adjustment_requested: 'Ajuste solicitado', held: 'Em análise', shared: 'Aguardando empresa', answer_in_review: 'Resposta em análise pela equipe', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const eventLabels: Record<ComplaintStatusDb, string> = { received: 'Registrada', in_review: 'Revisão solicitada', adjustment_requested: 'Ajuste solicitado', held: 'Em análise pela equipe', shared: 'Liberada para a empresa', answer_in_review: 'Resposta da empresa em análise pela equipe', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const statusClass: Record<ComplaintStatusDb, string> = { received: 'em-aberto', in_review: 'em-revisão', adjustment_requested: 'em-revisão', held: 'em-revisão', shared: 'encaminhada-para-empresa', answer_in_review: 'em-revisão', answered: 'respondida', closed: 'finalizada', canceled: 'finalizada' };
const feedbackLabels: Record<ComplaintFeedback, string> = { yes: 'Sim, ajudou', partial: 'Em parte', no: 'Não ajudou' };

function dateLabel(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value)); }
function Status({ status }: { status: ComplaintStatusDb }) { return <span className={`worker-status ${statusLabel(statusClass, status, 'em-aberto')}`}>{statusLabel(statusLabels, status)}</span>; }


// Responsividade pública (TASK-0036): faixas em ordem de nome, sem posição nem contagem, sem dado de quem relatou.
function Companies({ companies, onNew }: { companies: DirectoryCompany[]; onNew: (companyId: string) => void }) {
 const [rows, setRows] = useState<ResponsivenessRow[] | null>(null);
 const [search, setSearch] = useState('');
 useEffect(() => { let active = true; listCompanyResponsiveness().then(data => { if (active) setRows(data); }); return () => { active = false; }; }, []);
 const listed = companies.filter(company => `${company.name} ${company.city} ${company.state}`.toLowerCase().includes(search.toLowerCase()));
 return <section className="worker-companies">
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Empresas</h2><p className="muted">Escolha a empresa para iniciar uma manifestação. Você também pode consultar como as empresas respondem.</p></div></div>
  <label className="field worker-company-search">Buscar empresa<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome ou cidade" /></label>
  {!listed.length ? <p className="muted">Nenhuma empresa encontrada.</p> : <div className="worker-company-list">{listed.map(company => <article key={company.id} className="worker-company-row"><div><strong>{company.name}</strong><small>{company.city}/{company.state}</small></div><button className="btn" onClick={() => onNew(company.id)}>Fazer manifestação</button></article>)}</div>}
  <h3>Como as empresas respondem</h3>
  <p className="muted small">{responsivenessMethod} Nenhum relato ou identidade aparece aqui.</p>
  {rows === null ? <p className="muted">Carregando…</p> : rows.length === 0 ? <p>Ainda não há empresas com manifestações liberadas suficientes.</p> : <ResponsivenessTable rows={rows} />}
 </section>;
}

// Próximo passo da manifestação mais recente (TASK-0044, item 3).
const nextStepText: Partial<Record<ComplaintStatusDb, string>> = {
 received: 'Você guardou esta manifestação. Revise a versão para a empresa e envie quando quiser.',
 in_review: 'A equipe está revisando a versão antes de liberar à empresa.',
 adjustment_requested: 'A equipe pediu um ajuste na versão para a empresa.',
 held: 'A equipe está analisando esta manifestação antes de liberar.',
 shared: 'A versão foi liberada. Agora é aguardar a resposta da empresa.',
 answered: 'A empresa respondeu. Leia o retorno e diga se ajudou.',
 closed: 'Acompanhamento encerrado.',
 canceled: 'Manifestação retirada. Ela não chegou à empresa.',
};

function NextStep({ latest, company, onOpen, onNew }: { latest?: WorkerComplaint; company?: DirectoryCompany; onOpen: (item: WorkerComplaint) => void; onNew: () => void }) {
 if (!latest) return <section className="worker-dashboard-note worker-next-step"><h3>Comece por aqui</h3><p>Conte o que aconteceu no trabalho. Você revisa a versão que a empresa vai ler antes de enviar.</p><button className="btn primary" onClick={onNew}>Relatar uma situação</button></section>;
 return <section className="worker-dashboard-note worker-next-step" aria-labelledby="worker-next-title"><h3 id="worker-next-title">Sua manifestação mais recente</h3>
  <div className="worker-next-row"><div><strong>{latest.title}</strong><small>{company?.name ?? '—'} · {latest.protocol}</small></div><Status status={latest.status} /></div>
  <p>{nextStepText[latest.status] ?? 'Acompanhe o andamento pelo detalhe da manifestação.'}</p>
  <button className="btn primary" onClick={() => onOpen(latest)}>Abrir manifestação</button></section>;
}

function Dashboard({ complaints, companies, onList, onNew, onCompanies, onOpen }: { complaints: WorkerComplaint[]; companies: Map<string, DirectoryCompany>; onList: () => void; onNew: () => void; onCompanies: () => void; onOpen: (item: WorkerComplaint) => void }) {
 const latest = useMemo(() => [...complaints].sort((a, b) => b.createdAt.localeCompare(a.createdAt))[0], [complaints]);
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
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Início</h2><p className="muted">Acompanhe o volume e o andamento das suas manifestações.</p></div></div>
  <NextStep latest={latest} company={latest ? companies.get(latest.companyId) : undefined} onOpen={onOpen} onNew={onNew} />
  <QuickActions label="Atalhos" items={[
   { icon: 'plus', label: 'Nova manifestação', onClick: onNew },
   { icon: 'list', label: 'Minhas manifestações', badge: count(['answered']), onClick: onList },
   { icon: 'building', label: 'Empresas', onClick: onCompanies },
  ]} />
  <div className="worker-funnel">{[['Em acompanhamento', count(['received', 'in_review', 'adjustment_requested', 'held', 'shared', 'answer_in_review', 'answered'])], ['Em revisão', count(['in_review', 'adjustment_requested', 'held', 'answer_in_review'])], ['Aguardando empresa', count(['shared'])], ['Respondidas', count(['answered'])], ['Finalizadas', count(['closed'])]].map(([label, value]) => <article key={String(label)}><span>{label}</span><strong>{value}</strong></article>)}</div>
  <section className="worker-dashboard-section"><div className="worker-section-heading"><div><h3>Manifestações criadas</h3><p className="muted">Quantos relatos você registrou no período.</p></div><div className="worker-chart-controls"><label>Período<select value={period} onChange={event => setPeriod(event.target.value as Period)}><option value="weekly">Últimos 7 dias</option><option value="monthly">Este mês</option><option value="yearly">Este ano</option></select></label></div></div>
   {values.some(Boolean) ? <div className={`worker-columns-chart worker-columns-${period}`} aria-label="Manifestações criadas no período">{values.map((value, index) => <div className="worker-column" key={`${labels[index]}-${index}`}><strong>{value}</strong><i style={{ height: `${Math.max(value / max * 100, value ? 16 : 4)}%` }} /><span>{labels[index]}</span></div>)}</div> : <p className="muted worker-chart-empty">Nenhuma manifestação criada neste período.</p>}</section>
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
 useEffect(() => { let active = true; loadWorkerComplaintDetail(complaint.id).then(value => { if (active) { setDetail(value); setShareText(complaint.status === 'adjustment_requested' ? value.shared ?? '' : ''); } }); return () => { active = false; }; }, [complaint.id, complaint.status]);
 const preRelease = ['received', 'in_review', 'adjustment_requested', 'held'].includes(complaint.status);
 // PDF (TASK-0043): o relato original só entra se a pessoa marcar; o padrão é sem.
 const { print, host } = usePrintDocument();
 const pdfDialog = useRef<HTMLDialogElement>(null);
 const [withOriginal, setWithOriginal] = useState(false);
 function generatePdf() {
  if (!detail) return;
  pdfDialog.current?.close();
  print(buildWorkerPrint({
   protocol: complaint.protocol, title: complaint.title, statusText: statusLabel(statusLabels, complaint.status), createdAt: dateLabel(complaint.createdAt), generatedAt: printDateTime(),
   companyName: company?.name ?? '—', category: complaint.category, incidentPeriod: complaint.incidentPeriod, recurrence: complaint.recurrence, expectedOutcomes: complaint.expectedOutcomes,
   shared: detail.shared, sharedReleased: !preRelease,
   timeline: detail.timeline.map(item => ({ title: item.kind === 'response' ? 'Resposta da empresa' : statusLabel(eventLabels, item.status ?? 'received'), date: dateLabel(item.createdAt), text: item.content })),
   feedbackText: complaint.feedback ? feedbackLabels[complaint.feedback] : null, original: detail.original, includeOriginal: withOriginal,
  }));
 }
 const adjustmentNote = detail?.timeline.filter(item => item.status === 'adjustment_requested').slice(-1)[0]?.content;
 async function share() {
  if (shareText.trim().length < 10) return showToast('error', 'Revise a versão para a empresa (mínimo de 10 caracteres).');
  setBusy(true); const result = await shareWorkerComplaint(complaint.id, shareText); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Revisão solicitada. A equipe confere a versão antes de liberar à empresa.'); onChanged();
 }
 async function close() {
  setBusy(true); const result = await closeWorkerComplaint(complaint.id, preRelease ? null : feedback || null); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', preRelease ? 'Manifestação retirada. Ela não chegará à empresa.' : 'Acompanhamento encerrado. Obrigado pelo retorno.'); onChanged();
 }
 const open = !['closed', 'canceled'].includes(complaint.status);
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar para manifestações</button>
  <div className="worker-detail-heading"><div><span className="editorial-eyebrow">Manifestação {complaint.protocol}</span><h2>{complaint.title}</h2><p className="muted">{company?.name ?? '—'} · criada em {dateLabel(complaint.createdAt)}</p></div><div className="worker-detail-heading-actions"><Status status={complaint.status} /><button className="btn" type="button" disabled={!detail} onClick={() => { setWithOriginal(false); pdfDialog.current?.showModal(); }}>Baixar PDF</button></div></div>
  <dialog ref={pdfDialog} className="pdf-dialog" aria-labelledby="pdf-dialog-title"><form method="dialog" onSubmit={event => { event.preventDefault(); generatePdf(); }}>
   <h3 id="pdf-dialog-title">Baixar PDF</h3>
   <p className="muted small">O PDF não traz seu nome nem seus dados de contato. Na janela de impressão, escolha "Salvar como PDF".</p>
   <fieldset><legend className="sr-only">O que incluir</legend>
    <label><input type="radio" name="pdf-content" checked={!withOriginal} onChange={() => setWithOriginal(false)} /> Só a versão compartilhável e o acompanhamento</label>
    <label><input type="radio" name="pdf-content" checked={withOriginal} onChange={() => setWithOriginal(true)} /> Incluir meu relato original</label>
   </fieldset>
   {withOriginal && <p className="commercial-callout">O relato original é só seu. Guarde o arquivo com cuidado e evite encaminhá-lo.</p>}
   <div className="nav-actions"><button className="btn" type="button" onClick={() => pdfDialog.current?.close()}>Cancelar</button><button className="btn primary" type="submit">Gerar PDF</button></div>
  </form></dialog>
  {host}
  {!detail ? <p className="muted">Carregando detalhes…</p> : <div className="worker-detail-grid"><div>
   <section className="worker-detail-section"><h3>Resumo</h3><dl><div><dt>Empresa</dt><dd>{company?.name ?? '—'}</dd></div><div><dt>Assunto</dt><dd>{complaint.category}</dd></div><div><dt>Quando aconteceu</dt><dd>{complaint.incidentPeriod ?? '—'}</dd></div><div><dt>Recorrência</dt><dd>{complaint.recurrence ?? '—'}</dd></div></dl></section>
   <section className="worker-detail-section"><h3>Seu relato original</h3><p className="muted small">Só você vê este texto.</p><p className="worker-original">{detail.original}</p></section>
   {(complaint.status === 'received' || complaint.status === 'adjustment_requested') ? <section className="worker-detail-section"><h3>{complaint.status === 'adjustment_requested' ? 'Ajustar a versão para a empresa' : 'Compartilhar com a empresa'}</h3>
     {complaint.status === 'adjustment_requested' && adjustmentNote && <div className="commercial-callout">{adjustmentNote}</div>}
     <p className="muted small">Escreva uma versão separada. Inclua o necessário para a empresa entender e responder, sem nomes, locais, datas ou detalhes que possam identificar pessoas. A equipe revisa antes de liberar.</p><textarea className="worker-share-text" rows={6} value={shareText} onChange={event => setShareText(event.target.value)} aria-label="Versão para a empresa" placeholder="Escreva a versão que poderá ser mostrada à empresa." /><button className="btn primary" disabled={busy} onClick={share}>{complaint.status === 'adjustment_requested' ? 'Enviar ajuste para revisão' : 'Solicitar revisão'}</button></section>
    : detail.shared && <section className="worker-detail-section"><h3>{preRelease ? 'Versão em revisão' : 'Versão que a empresa recebeu'}</h3>{preRelease && <p className="muted small">A equipe confere esta versão antes de liberar à empresa. Até lá, a empresa não vê nada.</p>}<p className="worker-original">{detail.shared}</p></section>}
   {complaint.expectedOutcomes.length > 0 && <section className="worker-detail-section"><h3>O que você espera</h3><ul>{complaint.expectedOutcomes.map(item => <li key={item}>{item}</li>)}</ul></section>}
  </div><aside className="worker-detail-aside">
   <section className="worker-detail-section"><h3>Acompanhamento</h3><ol className="worker-timeline">{detail.timeline.map((item, index) => <li key={index} className={item.kind === 'response' ? 'worker-timeline-response' : ''}><strong>{item.kind === 'response' ? 'Resposta da empresa' : statusLabel(eventLabels, item.status ?? 'received')}</strong><span>{dateLabel(item.createdAt)}</span><p>{item.content}</p></li>)}</ol></section>
   {open && <section className="worker-detail-section worker-actions"><h3>{preRelease ? 'Retirar manifestação' : 'Encerrar acompanhamento'}</h3>{!preRelease && <label>A resposta ajudou?<select value={feedback} onChange={event => setFeedback(event.target.value as ComplaintFeedback | '')}><option value="">Prefiro não avaliar</option>{Object.entries(feedbackLabels).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label>}<button className="btn" disabled={busy} onClick={close}>{preRelease ? 'Retirar manifestação' : 'Encerrar acompanhamento'}</button></section>}
   {complaint.feedback && <section className="worker-detail-section"><h3>Sua avaliação</h3><p>{feedbackLabels[complaint.feedback]}</p></section>}
  </aside></div>}</>;
}


export function WorkerPortalLive({ initialView = 'dashboard', onViewChange }: { initialView?: WorkerEntryView; onViewChange?: (view: WorkerEntryView) => void }) {
 const [view, setView] = useState<View>(initialView);
 const [complaints, setComplaints] = useState<WorkerComplaint[] | null>(null);
 const [companies, setCompanies] = useState<DirectoryCompany[]>([]);
 const [selectedId, setSelectedId] = useState<string | null>(null);
 const [newCompanyId, setNewCompanyId] = useState('');
 const startNew = (companyId: string) => { setNewCompanyId(companyId); setView('new'); };
 const [version, setVersion] = useState(0);
 useEffect(() => { setView(initialView); }, [initialView]);
 useEffect(() => { onViewChange?.(view === 'dashboard' ? 'dashboard' : view === 'profile' ? 'profile' : view === 'companies' || view === 'new' ? 'companies' : 'list'); }, [view, onViewChange]);
 useEffect(() => { let active = true; Promise.all([listWorkerComplaints(), listCompanyDirectory()]).then(([rows, directory]) => { if (active) { setComplaints(rows); setCompanies(directory); } }); return () => { active = false; }; }, [version]);
 const byId = useMemo(() => new Map(companies.map(company => [company.id, company])), [companies]);
 const selected = complaints?.find(item => item.id === selectedId);
 const reload = () => setVersion(value => value + 1);
 return <main className="worker-portal-content" id="main-content" tabIndex={-1}>
  {view === 'profile' ? <WorkerProfile /> :
   complaints === null ? <p className="muted">Carregando suas manifestações…</p> :
   view === 'new' ? <ComplaintWizard key={newCompanyId} companies={companies} initialCompanyId={newCompanyId} onCancel={() => setView('companies')} onCreated={() => { reload(); setView('list'); }} /> :
   view === 'detail' && selected ? <Detail complaint={selected} company={byId.get(selected.companyId)} onBack={() => setView('list')} onChanged={reload} /> :
   view === 'companies' ? <Companies companies={companies} onNew={startNew} /> :
   view === 'list' ? <List complaints={complaints} companies={byId} onSelect={item => { setSelectedId(item.id); setView('detail'); }} onNew={() => setView('companies')} /> :
   <Dashboard complaints={complaints} companies={byId} onList={() => setView('list')} onNew={() => setView('companies')} onCompanies={() => setView('companies')} onOpen={item => { setSelectedId(item.id); setView('detail'); }} />}
 </main>;
}
