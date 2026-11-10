import { useEffect, useMemo, useState } from 'react';
import { listPartnerDirectory, loadCompanyContext, loadPartnerPhoto, uploadPartnerPhoto, type CompanyContext, type DirectoryPartner } from '../services/account';
import { listCompanyComplaints, listPartnerCompanies, listCompanyResponsiveness, loadMyCompanyResponsiveness, loadMyCompanySatisfaction, loadCompanyTimeline, loadPartnerProfile, requestPartner, respondCompanyComplaint, setPartnerConnection, updatePartnerProfile, loadPartnerPlan, listMyContents, listPartnerContents, createPartnerContent, deletePartnerContent, type PartnerContent, type CompanySatisfaction, type CompanyComplaint, type ComplaintStatusDb, type PartnerCompany, type PartnerProfileData, type MyResponsiveness, type ResponsivenessRow, type TimelineItem } from '../services/data';
import { showToast } from '../app/toast';
import { Icon, QuickActions, initials, type IconName } from './ui';
import { formatPhone, planIncludesContent, validateContent, whatsappLink } from '../domain/account-rules';
import { safeHttpUrl } from '../domain/html-safety';
import { buildCompanyPrint, printDateTime } from '../domain/print-document';
import { usePrintDocument } from './print-document';
import { CompanyProfile } from './profile-live';
import { MyResponsivenessPanel, ResponsivenessTable, responsivenessMethod } from './responsiveness';
import { statusLabel } from '../domain/complaint-status';

// Portais de empresa e parceiro com dados reais (modelo v3). A empresa lê apenas versões compartilhadas, sem identidade.
type CompanyView = 'dashboard' | 'complaints' | 'ranking' | 'partners' | 'profile';
type PartnerView = 'dashboard' | 'profile' | 'content' | 'companies' | 'leads' | 'clients';

const companyStatus: Record<ComplaintStatusDb, string> = { received: 'Recebida', in_review: 'Em revisão', adjustment_requested: 'Em revisão', held: 'Em revisão', shared: 'Aguardando resposta', answer_in_review: 'Resposta em revisão pela equipe', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const feedbackLabels = { yes: 'A resposta ajudou', partial: 'Ajudou em parte', no: 'Não ajudou' } as const;

function dateLabel(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value)); }
function formatCnpj(value: string) { return value.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5'); }
// initials vem de ./ui (compartilhado com o menu lateral).
function hours(value: number | null | undefined) { return value === null || value === undefined ? '—' : value < 48 ? `${value} h` : `${(value / 24).toFixed(1).replace('.', ',')} dias`; }

export function Metric({ label, value, note }: { label: string; value: string | number; note?: string }) {
 return <article className="commercial-metric"><span>{label}</span><strong>{value}</strong>{note && <small>{note}</small>}</article>;
}
const sidebarIcons: Record<string, IconName> = { overview: 'home', queue: 'inbox', all: 'list', contacts: 'users', dashboard: 'home', complaints: 'inbox', ranking: 'chart', partners: 'users', profile: 'user', content: 'image', companies: 'building', leads: 'star', clients: 'briefcase' };

export function Sidebar<T extends string>({ eyebrow, name, items, view, onView }: { eyebrow: string; name: string; items: [T, string][]; view: T; onView: (view: T) => void }) {
 return <aside className="commercial-sidebar"><div className="sys-account"><span className="sys-avatar" aria-hidden="true">{initials(name)}</span><span><strong className="commercial-sidebar-name">{name}</strong><small>{eyebrow}</small></span></div>
  <nav className="sys-nav" aria-label={eyebrow}>{items.map(([key, label]) => <button key={key} className={view === key ? 'active' : ''} aria-current={view === key ? 'page' : undefined} onClick={() => onView(key)}><Icon name={sidebarIcons[key] ?? 'list'} />{label}</button>)}</nav></aside>;
}

function CompanyDashboard({ company, complaints, mine, onOpen, onView }: { company: CompanyContext; complaints: CompanyComplaint[]; mine?: MyResponsiveness; onOpen: (id: string) => void; onView: (view: CompanyView) => void }) {
 const waiting = complaints.filter(item => item.status === 'shared');

 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Visão da organização</span><h1>Dashboard</h1><p>Acompanhe o que precisa de resposta e os sinais de responsividade da {company.name}.</p></div><button className="btn primary" onClick={() => onView('complaints')}>Ver manifestações</button></div>
  <QuickActions label="Atalhos da empresa" items={[
   { icon: 'inbox', label: 'Responder manifestações', badge: waiting.length, onClick: () => onView('complaints') },
   { icon: 'chart', label: 'Responsividade das empresas', onClick: () => onView('ranking') },
   { icon: 'users', label: 'Parceiros', onClick: () => onView('partners') },
  ]} />
  <div className="commercial-metrics"><Metric label="Manifestações recebidas" value={complaints.length} note="versões compartilhadas" /><Metric label="Aguardando resposta" value={waiting.length} note={waiting.length ? 'prioridade da equipe' : 'sem pendências'} /><Metric label="Taxa de resposta" value={mine?.responseRate === null || mine?.responseRate === undefined ? '—' : `${mine.responseRate}%`} note="liberadas com ao menos uma resposta" /><Metric label="Tempo médio" value={hours(mine?.avgFirstResponseHours)} note="até a primeira resposta" /></div>
  <div className="commercial-grid-two"><section className="commercial-panel"><h2>Fila de atenção</h2>{waiting.length ? waiting.slice(0, 4).map(item => <button className="commercial-list-row" key={item.id} onClick={() => onOpen(item.id)}><span><strong>{item.protocol} · {item.title}</strong><small>{item.category} · {dateLabel(item.createdAt)}</small></span><em>Responder ›</em></button>) : <p>Nenhuma manifestação aguardando resposta.</p>}</section>
   <section className="commercial-panel company-summary"><h2>Dados da empresa</h2><dl className="company-facts"><div><dt>Razão social</dt><dd>{company.legalName}</dd></div><div><dt>CNPJ</dt><dd className="nowrap">{formatCnpj(company.cnpj)}</dd></div><div><dt>Cidade</dt><dd>{company.city}/{company.state}</dd></div>
    <div><dt>Contato para parceiros</dt><dd>{company.contactEmail || company.contactPhone ? [company.contactEmail, company.contactPhone ? formatPhone(company.contactPhone) : ''].filter(Boolean).join(' · ') : 'Não informado'}</dd></div></dl>
    <div className="commercial-callout">A empresa acessa somente a versão compartilhável revisada por quem relatou, sem identidade.</div>
    <button className="btn" onClick={() => onView('profile')}>{company.isOwner ? 'Editar no Meu perfil' : 'Ver no Meu perfil'}</button></section></div></>;
}

// Mídia vinda do banco (TASK-0002): só URL http(s) vira src/href. Exportados para teste de renderização.
export function ContentMedia({ content }: { content: Pick<PartnerContent, 'kind' | 'url' | 'title'> }) {
 const url = safeHttpUrl(content.url);
 if (content.kind === 'image') return url ? <img src={url} alt={content.title} loading="lazy" /> : null;
 return url ? <a className="content-video" href={url} target="_blank" rel="noopener noreferrer"><span aria-hidden="true">▶</span> Assistir vídeo</a> : <span className="content-video">Link de vídeo indisponível</span>;
}

export function PartnerPhoto({ url, name, large = false }: { url: string | null | undefined; name: string; large?: boolean }) {
 const src = safeHttpUrl(url);
 return src ? <img className={`partner-avatar partner-photo${large ? ' large' : ''}`} src={src} alt={`Foto de ${name}`} /> : <div className={`partner-avatar${large ? ' large' : ''}`} style={{ background: 'var(--soft)' }} aria-hidden="true">{initials(name)}</div>;
}

function ContentGallery({ contents, onDelete }: { contents: PartnerContent[]; onDelete?: (content: PartnerContent) => void }) {
 return <div className="content-gallery">{contents.map(content => <article className="content-card" key={content.id}>
  <ContentMedia content={content} />
  <div><strong>{content.title}</strong>{content.caption && <p>{content.caption}</p>}{onDelete && <button className="btn ghost" onClick={() => onDelete(content)}>Remover</button>}</div>
 </article>)}</div>;
}

function CompanyComplaints({ complaints, openId, onOpen, onChanged, companyName }: { complaints: CompanyComplaint[]; openId: string | null; onOpen: (id: string | null) => void; onChanged: () => void; companyName: string }) {
 const [search, setSearch] = useState('');
 const [status, setStatus] = useState('');
 const selected = complaints.find(item => item.id === openId);
 if (selected) return <CompanyComplaintDetail item={selected} companyName={companyName} onBack={() => onOpen(null)} onChanged={onChanged} />;
 const rows = complaints.filter(item => `${item.protocol} ${item.title} ${item.category}`.toLowerCase().includes(search.toLowerCase()) && (!status || item.status === status));
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Operação da empresa</span><h1>Manifestações</h1><p>Leia a versão compartilhável, responda e acompanhe o retorno.</p></div><label className="commercial-search">Pesquisar<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Protocolo ou assunto" /></label></div>
  <div className="commercial-filter-row"><select value={status} onChange={event => setStatus(event.target.value)} aria-label="Situação"><option value="">Todas as situações</option><option value="shared">Aguardando resposta</option><option value="answer_in_review">Resposta em revisão pela equipe</option><option value="answered">Respondida</option><option value="closed">Finalizada</option></select></div>
  {rows.length === 0 ? <section className="commercial-panel"><h2>{complaints.length ? 'Nenhuma manifestação encontrada' : 'Nenhuma manifestação por enquanto'}</h2><p>{complaints.length ? 'Revise a busca ou a situação.' : 'Quando uma manifestação for compartilhada com sua empresa, ela aparece aqui.'}</p></section> :
  <section className="commercial-panel">{rows.map(item => <button className="commercial-list-row" key={item.id} onClick={() => onOpen(item.id)}><span><strong>{item.protocol} · {item.title}</strong><small>{item.category} · {dateLabel(item.createdAt)}{item.responses ? ` · ${item.responses} resposta${item.responses > 1 ? 's' : ''}` : ''}</small></span><em>{statusLabel(companyStatus, item.status)} ›</em></button>)}</section>}</>;
}

function CompanyComplaintDetail({ item, companyName, onBack, onChanged }: { item: CompanyComplaint; companyName: string; onBack: () => void; onChanged: () => void }) {
 const { print, host } = usePrintDocument();
 const [timeline, setTimeline] = useState<TimelineItem[] | null>(null);
 const [text, setText] = useState('');
 const [busy, setBusy] = useState(false);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; loadCompanyTimeline(item.id).then(rows => { if (active) setTimeline(rows); }); return () => { active = false; }; }, [item.id, version]);
 async function send() {
  setBusy(true); const result = await respondCompanyComplaint(item.id, text); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Resposta enviada. A pessoa que relatou será informada.'); setText(''); setVersion(value => value + 1); onChanged();
 }
 return <><button className="text-action" onClick={onBack}>← Voltar para manifestações</button>
  <div className="commercial-page-head"><div><span className="editorial-eyebrow">Manifestação {item.protocol}</span><h1>{item.title}</h1><p>{item.category} · recebida em {dateLabel(item.createdAt)} · {statusLabel(companyStatus, item.status)}</p></div>
   <button className="btn" type="button" disabled={timeline === null} onClick={() => print(buildCompanyPrint({ protocol: item.protocol, title: item.title, statusText: statusLabel(companyStatus, item.status), receivedAt: dateLabel(item.createdAt), generatedAt: printDateTime(), companyName, category: item.category, shared: item.shared, timeline: (timeline ?? []).map(entry => ({ title: entry.kind === 'response' ? 'Resposta enviada' : entry.kind === 'response_review' ? 'Revisão da equipe' : statusLabel(companyStatus, entry.status ?? 'shared'), date: dateLabel(entry.createdAt), text: entry.content })), feedbackText: item.feedback ? feedbackLabels[item.feedback] : null }))}>Baixar PDF</button></div>
  {host}
  <div className="commercial-grid-two"><section className="commercial-panel"><h2>Versão compartilhada</h2><p>{item.shared}</p><div className="commercial-callout">Texto revisado e autorizado por quem relatou. A identidade e o relato original não são compartilhados.</div>{item.feedback && <p><strong>Avaliação do retorno:</strong> {feedbackLabels[item.feedback]}</p>}</section>
   <section className="commercial-panel"><h2>Histórico</h2>{timeline === null ? <p className="muted">Carregando…</p> : <ol className="worker-timeline">{timeline.map((entry, index) => <li key={index} className={entry.kind === 'response' ? 'worker-timeline-response' : entry.kind === 'response_review' ? 'worker-timeline-review' : ''}><strong>{entry.kind === 'response' ? 'Resposta enviada' : entry.kind === 'response_review' ? 'Revisão da equipe' : statusLabel(companyStatus, entry.status ?? 'shared')}</strong><span>{dateLabel(entry.createdAt)}</span><p>{entry.content}</p></li>)}</ol>}</section></div>
  {item.status === 'answer_in_review' && <section className="commercial-panel"><h2>Resposta com a equipe</h2><p className="muted small">A equipe Escuta Aí Brasil revisa a resposta antes de entregá-la a quem relatou. Se precisar de ajuste, o motivo aparece no histórico e você poderá responder de novo.</p></section>}
  {['shared', 'answered'].includes(item.status) && <section className="commercial-panel"><h2>{item.status === 'shared' ? 'Responder' : 'Enviar nova atualização'}</h2><p className="muted small">Responda de forma institucional. Não tente identificar quem relatou.</p><textarea className="company-response-text" rows={5} maxLength={5000} value={text} onChange={event => setText(event.target.value)} aria-label="Resposta da empresa" /><div className="nav-actions"><button className="btn primary" disabled={busy || text.trim().length < 10} onClick={send}>Enviar resposta</button></div></section>}</>;
}

function CompanyResponsiveness({ rows, mine, satisfaction }: { rows: ResponsivenessRow[] | null; mine?: MyResponsiveness; satisfaction?: CompanySatisfaction }) {
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Referência pública</span><h1>Responsividade das empresas</h1><p>Como as empresas respondem às manifestações liberadas, em faixas e sem posição.</p></div></div>
  <div className="commercial-callout">{responsivenessMethod}</div>
  <MyResponsivenessPanel mine={mine} satisfaction={satisfaction} />
  {rows === null ? <p className="muted">Carregando…</p> : rows.length === 0 ? <section className="commercial-panel"><p>Ainda não há empresas com manifestações liberadas suficientes.</p></section> : <ResponsivenessTable rows={rows} highlightMine />}</>;
}

function PartnerDirectoryLive() {
 const [partners, setPartners] = useState<DirectoryPartner[] | null>(null);
 const [search, setSearch] = useState('');
 const [tab, setTab] = useState<'featured' | 'all'>('featured');
 const [selected, setSelected] = useState<DirectoryPartner | null>(null);
 const [contents, setContents] = useState<PartnerContent[]>([]);
 const [version, setVersion] = useState(0);
 useEffect(() => { setContents([]); if (!selected) return; let active = true; listPartnerContents(selected.id).then(rows => { if (active) setContents(rows); }); return () => { active = false; }; }, [selected?.id]);
 useEffect(() => { let active = true; listPartnerDirectory().then(rows => { if (active) setPartners(rows); }); return () => { active = false; }; }, [version]);
 const rows = (partners ?? []).filter(partner => (tab === 'all' || partner.featured) && `${partner.name} ${partner.specialty} ${partner.city} ${partner.state}`.toLowerCase().includes(search.toLowerCase()));
 const avatar = (partner: DirectoryPartner, large = false) => <PartnerPhoto url={partner.avatarUrl} name={partner.name} large={large} />;
 async function contact(partner: DirectoryPartner) {
  const result = await requestPartner(partner.id);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', `Interesse enviado. ${partner.name} verá sua empresa em "Possíveis clientes" e retornará diretamente.`);
  setSelected({ ...partner, requested: true }); setVersion(value => value + 1);
 }
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Rede de apoio</span><h1>Parceiros</h1><p>Profissionais cadastrados no Hub de Parceiros para apoiar os próximos passos da sua organização.</p></div><label className="commercial-search">Pesquisar<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome, especialidade ou cidade" /></label></div>
  <div className="commercial-tabs" role="tablist"><button role="tab" aria-selected={tab === 'featured'} className={tab === 'featured' ? 'active' : ''} onClick={() => setTab('featured')}>Destaques</button><button role="tab" aria-selected={tab === 'all'} className={tab === 'all' ? 'active' : ''} onClick={() => setTab('all')}>Geral</button></div>
  {partners === null ? <p className="muted">Carregando parceiros…</p> : rows.length === 0 ? <section className="commercial-panel"><h2>{!partners.length ? 'Ainda não há parceiros cadastrados' : tab === 'featured' && !search ? 'Nenhum parceiro em destaque' : 'Nenhum parceiro encontrado'}</h2><p>{!partners.length ? 'Quando profissionais se cadastrarem no Hub, eles aparecem aqui.' : tab === 'featured' && !search ? 'Veja todos os parceiros na aba Geral.' : 'Tente outro nome, especialidade ou cidade.'}</p></section> :
  <div className="partner-grid">{rows.map(partner => <button className="partner-card" key={partner.id} onClick={() => setSelected(partner)}>{avatar(partner)}<span className="commercial-badge">{partner.requested ? 'Interesse enviado' : partner.featured ? 'Destaque' : 'Parceiro cadastrado'}</span><h2>{partner.name}</h2><p>{partner.specialty}</p><small>{partner.city} / {partner.state}</small></button>)}</div>}
  {selected && <div className="commercial-modal-backdrop" onMouseDown={event => event.target === event.currentTarget && setSelected(null)}><section className="commercial-modal partner-modal" role="dialog" aria-modal="true" aria-labelledby="partner-title"><button className="commercial-modal-close" onClick={() => setSelected(null)} aria-label="Fechar">×</button>{avatar(selected, true)}<span className="editorial-eyebrow">Perfil profissional</span><h2 id="partner-title">{selected.name}</h2><p>{selected.specialty} · {selected.city} / {selected.state}</p>{selected.description && <p>{selected.description}</p>}{contents.length > 0 && <><h3>Conteúdos</h3><ContentGallery contents={contents} /></>}<div className="commercial-callout">A plataforma não intermedia o serviço. O parceiro recebe o interesse da sua empresa e retorna diretamente.</div>{selected.requested ? <p className="commercial-feedback" role="status">Interesse já enviado a este parceiro.</p> : <button className="btn primary" onClick={() => contact(selected)}>Entrar em contato</button>}</section></div>}</>;
}

export function CompanyPortalLive({ companyId }: { companyId: string }) {
 const [view, setView] = useState<CompanyView>('dashboard');
 const [company, setCompany] = useState<CompanyContext | null | undefined>(undefined);
 const [complaints, setComplaints] = useState<CompanyComplaint[] | null>(null);
 const [ranking, setRanking] = useState<ResponsivenessRow[] | null>(null);
 const [myStats, setMyStats] = useState<MyResponsiveness[] | null>(null);
 const [satisfaction, setSatisfaction] = useState<CompanySatisfaction[]>([]);
 const [openId, setOpenId] = useState<string | null>(null);
 const [version, setVersion] = useState(0);
 const [contextVersion, setContextVersion] = useState(0);
 useEffect(() => { let active = true; loadCompanyContext(companyId).then(value => { if (active) setCompany(value); }).catch(() => active && setCompany(null)); return () => { active = false; }; }, [companyId, contextVersion]);
 useEffect(() => { let active = true; Promise.all([listCompanyComplaints(), listCompanyResponsiveness(), loadMyCompanyResponsiveness()]).then(([rows, rank, own]) => { if (active) { setComplaints(rows); setRanking(rank); setMyStats(own); } }); loadMyCompanySatisfaction().then(rows => { if (active) setSatisfaction(rows); }).catch(() => undefined); return () => { active = false; }; }, [companyId, version]);
 const mine = useMemo(() => myStats?.find(row => row.companyId === companyId), [myStats, companyId]);
 const open = (id: string | null) => { setOpenId(id); setView('complaints'); };
 const items: [CompanyView, string][] = [['dashboard', 'Dashboard'], ['complaints', 'Manifestações'], ['ranking', 'Responsividade'], ['partners', 'Parceiros'], ['profile', 'Meu perfil']];
 return <main className="commercial-portal-content"><Sidebar eyebrow="Área da empresa" name={company?.name ?? 'Carregando…'} items={items} view={view} onView={next => { setView(next); setOpenId(null); }} /><section className="commercial-portal-main">
  {company === undefined || complaints === null ? <p className="muted">Carregando dados da empresa…</p> : company === null ? <section className="commercial-panel"><h2>Não foi possível carregar sua empresa</h2><p>Saia e entre novamente. Se continuar, fale com o suporte.</p></section> :
   view === 'dashboard' ? <CompanyDashboard company={company} complaints={complaints} mine={mine} onOpen={open} onView={setView} /> :
   view === 'complaints' ? <CompanyComplaints complaints={complaints} openId={openId} onOpen={setOpenId} onChanged={() => setVersion(value => value + 1)} companyName={company.name} /> :
   view === 'ranking' ? <CompanyResponsiveness rows={ranking} mine={mine} satisfaction={satisfaction.find(row => row.companyId === companyId)} /> :
   view === 'profile' ? <CompanyProfile companyId={companyId} onSaved={() => setContextVersion(value => value + 1)} /> : <PartnerDirectoryLive />}
 </section></main>;
}

function PartnerProfileEditor({ partnerId, profile, onSaved }: { partnerId: string; profile: PartnerProfileData; onSaved: (next: PartnerProfileData) => void }) {
 const [form, setForm] = useState({ displayName: profile.displayName, specialty: profile.specialty, description: profile.description ?? '' });
 const [photo, setPhoto] = useState<string | null | undefined>(undefined);
 const [busy, setBusy] = useState(false);
 useEffect(() => { let active = true; loadPartnerPhoto(partnerId).then(value => { if (active) setPhoto(value.url); }); return () => { active = false; }; }, [partnerId]);
 async function save(event: React.FormEvent) {
  event.preventDefault(); setBusy(true);
  const result = await updatePartnerProfile(partnerId, form); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Perfil atualizado. Empresas já veem a nova versão.');
  onSaved({ ...profile, displayName: form.displayName.trim(), specialty: form.specialty.trim(), description: form.description.trim() || null });
 }
 async function upload(file: File | undefined) {
  if (!file) return;
  setBusy(true); const result = await uploadPartnerPhoto(partnerId, file); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  setPhoto(result.value.url); showToast('success', 'Foto de perfil atualizada.');
 }
 return <div className="commercial-grid-two partner-profile-editor">
  <section className="commercial-panel"><h2>Dados públicos</h2><form className="partner-profile-form" onSubmit={save}>
   <label className="field">Nome profissional<input value={form.displayName} maxLength={160} required onChange={event => setForm({ ...form, displayName: event.target.value })} /></label>
   <label className="field">Especialidade<input value={form.specialty} maxLength={120} required onChange={event => setForm({ ...form, specialty: event.target.value })} /></label>
   <label className="field">Descrição<textarea rows={6} maxLength={2000} value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} /><small className="muted">{form.description.length}/2000</small></label>
   <p className="muted small">Cidade: {profile.city}/{profile.state}. Endereço e documento não aparecem para empresas.</p>
   <button className="btn primary" type="submit" disabled={busy}>{busy ? 'Salvando…' : 'Salvar alterações'}</button>
  </form></section>
  <section className="commercial-panel"><h2>Foto de perfil</h2><PartnerPhoto url={photo} name={form.displayName} large />
   <label className="btn partner-photo-upload">{photo ? 'Trocar foto' : 'Enviar foto'}<input type="file" accept="image/jpeg,image/png,image/webp" hidden disabled={busy} onChange={event => upload(event.target.files?.[0])} /></label>
   <p className="muted small">JPG, PNG ou WebP até 5 MB. A foto aparece no diretório de parceiros.</p></section>
 </div>;
}

function PartnerContents({ partnerId, planId }: { partnerId: string; planId: string | null }) {
 const [contents, setContents] = useState<PartnerContent[] | null>(null);
 const [form, setForm] = useState({ kind: 'image' as 'image' | 'video', title: '', caption: '', videoUrl: '' });
 const [file, setFile] = useState<File | undefined>();
 const [busy, setBusy] = useState(false);
 const [version, setVersion] = useState(0);
 const allowed = planIncludesContent(planId);
 useEffect(() => { let active = true; listMyContents(partnerId).then(rows => { if (active) setContents(rows); }); return () => { active = false; }; }, [partnerId, version]);
 async function publish(event: React.FormEvent<HTMLFormElement>) {
  event.preventDefault();
  // currentTarget vira null depois do await (React); guarde o elemento antes.
  const formElement = event.currentTarget;
  const error = validateContent({ ...form, hasFile: Boolean(file) });
  if (error) return showToast('error', error);
  setBusy(true); const result = await createPartnerContent(partnerId, form, file); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Conteúdo publicado no seu perfil.');
  setForm({ kind: form.kind, title: '', caption: '', videoUrl: '' }); setFile(undefined); formElement.reset(); setVersion(value => value + 1);
 }
 async function remove(content: PartnerContent) {
  if (!window.confirm(`Remover "${content.title}" do seu perfil?`)) return;
  const result = await deletePartnerContent(content);
  result.ok ? (showToast('success', 'Conteúdo removido.'), setVersion(value => value + 1)) : showToast('error', result.message);
 }
 if (!allowed) return <section className="commercial-panel"><h2>Disponível nos planos Profissional e Nacional</h2><p>Publique fotos e vídeos com descrição para apresentar seu trabalho às empresas. Altere seu plano em "Minha assinatura".</p></section>;
 return <div className="commercial-grid-two partner-contents">
  <section className="commercial-panel"><h2>Novo conteúdo</h2><form className="partner-profile-form" onSubmit={publish}>
   <fieldset className="content-kind"><legend>Tipo</legend><label><input type="radio" name="kind" checked={form.kind === 'image'} onChange={() => setForm({ ...form, kind: 'image' })} /> Foto</label><label><input type="radio" name="kind" checked={form.kind === 'video'} onChange={() => setForm({ ...form, kind: 'video' })} /> Vídeo</label></fieldset>
   <label className="field">Título<input value={form.title} maxLength={120} required onChange={event => setForm({ ...form, title: event.target.value })} /></label>
   {form.kind === 'image' ? <label className="field">Foto<input type="file" accept="image/jpeg,image/png,image/webp" onChange={event => setFile(event.target.files?.[0])} /><small className="muted">JPG, PNG ou WebP até 5 MB.</small></label> :
    <label className="field">Link do vídeo<input type="url" value={form.videoUrl} placeholder="https://www.youtube.com/watch?v=…" onChange={event => setForm({ ...form, videoUrl: event.target.value })} /><small className="muted">YouTube ou Vimeo. O vídeo fica hospedado lá.</small></label>}
   <label className="field">Descrição<textarea rows={4} maxLength={1000} value={form.caption} onChange={event => setForm({ ...form, caption: event.target.value })} /><small className="muted">{form.caption.length}/1000</small></label>
   <button className="btn primary" type="submit" disabled={busy}>{busy ? 'Publicando…' : 'Publicar'}</button>
  </form></section>
  <section className="commercial-panel"><h2>Publicados</h2>{contents === null ? <p className="muted">Carregando…</p> : contents.length === 0 ? <p className="muted">Nenhum conteúdo publicado ainda. Empresas veem seus conteúdos ao abrir seu perfil no diretório.</p> : <ContentGallery contents={contents} onDelete={remove} />}</section>
 </div>;
}

function PartnerCompanyRows({ rows, actions, onChanged }: { rows: PartnerCompany[]; actions: boolean; onChanged: () => void }) {
 async function update(company: PartnerCompany, stage: 'partner_contacted' | 'client') {
  const result = await setPartnerConnection(company.id, stage);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', stage === 'client' ? `${company.name} foi adicionada aos seus clientes.` : `Contato com ${company.name} registrado.`); onChanged();
 }
 if (!rows.length) return <p className="muted">Nenhuma empresa nesta lista por enquanto.</p>;
 return <>{rows.map(company => <article className="partner-company-row" key={company.id}><div><strong>{company.name}</strong><span>{company.legalName}</span><small>{company.city}/{company.state}{company.stage === 'company_interest' ? ' · demonstrou interesse no seu perfil' : company.stage === 'partner_contacted' ? ' · contato iniciado' : ''}</small></div><div className="partner-company-actions">{company.contactEmail && <a className="btn" href={`mailto:${company.contactEmail}`}>Entrar em contato</a>}{company.contactPhone && <a className="btn" href={whatsappLink(company.contactPhone)} target="_blank" rel="noopener noreferrer">WhatsApp</a>}{company.stage === 'client' && !company.contactEmail && !company.contactPhone && <span className="muted small">A empresa ainda não cadastrou um contato.</span>}{actions && company.stage !== 'client' && !company.contactEmail && !company.contactPhone && <button className="btn" disabled={company.stage === 'partner_contacted'} onClick={() => update(company, 'partner_contacted')}>{company.stage === 'partner_contacted' ? 'Contato iniciado' : 'Entrar em contato'}</button>}{actions && company.stage !== 'client' && <button className="btn primary" onClick={() => update(company, 'client')}>Marcar como cliente</button>}</div></article>)}</>;
}

export function PartnerPortalLive({ partnerId }: { partnerId: string }) {
 const [view, setView] = useState<PartnerView>('dashboard');
 const [profile, setProfile] = useState<PartnerProfileData | null | undefined>(undefined);
 const [companies, setCompanies] = useState<PartnerCompany[] | null>(null);
 const [planId, setPlanId] = useState<string | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; loadPartnerPlan(partnerId).then(value => { if (active) setPlanId(value); }); return () => { active = false; }; }, [partnerId]);
 useEffect(() => { let active = true; loadPartnerProfile(partnerId).then(value => { if (active) setProfile(value); }); return () => { active = false; }; }, [partnerId]);
 useEffect(() => { let active = true; listPartnerCompanies().then(rows => { if (active) setCompanies(rows); }); return () => { active = false; }; }, [partnerId, version]);
 const leads = (companies ?? []).filter(company => company.stage === 'company_interest');
 const clients = (companies ?? []).filter(company => company.stage === 'client');
 const contacted = (companies ?? []).filter(company => company.stage === 'partner_contacted');
 const items: [PartnerView, string][] = [['dashboard', 'Dashboard'], ['profile', 'Meu perfil'], ['content', 'Meus conteúdos'], ['companies', 'Empresas'], ['leads', 'Possíveis clientes'], ['clients', 'Clientes']];
 const reload = () => setVersion(value => value + 1);
 const head = (eyebrow: string, title: string, text: string) => <div className="commercial-page-head"><div><span className="editorial-eyebrow">{eyebrow}</span><h1>{title}</h1><p>{text}</p></div></div>;
 return <main className="commercial-portal-content"><Sidebar eyebrow="Hub de parceiros" name={profile?.displayName ?? 'Carregando…'} items={items} view={view} onView={setView} /><section className="commercial-portal-main">
  {profile === undefined || companies === null ? <p className="muted">Carregando seu hub…</p> : profile === null ? <section className="commercial-panel"><h2>Não foi possível carregar seu perfil</h2><p>Saia e entre novamente.</p></section> :
   view === 'dashboard' ? <>{head('Seu hub profissional', 'Dashboard', 'Acompanhe empresas interessadas e sua carteira.')}<div className="commercial-metrics"><Metric label="Empresas na plataforma" value={companies.length} /><Metric label="Possíveis clientes" value={leads.length} note="demonstraram interesse" /><Metric label="Contatos iniciados" value={contacted.length} /><Metric label="Clientes" value={clients.length} note="na sua carteira" /></div><div className="commercial-grid-two"><section className="commercial-panel"><h2>Possíveis clientes</h2><PartnerCompanyRows rows={leads.slice(0, 3)} actions onChanged={reload} /></section><section className="commercial-panel"><h2>Próximo passo</h2><p>Mantenha foto e descrição atualizadas: empresas veem esses dados ao buscar parceiros.</p><button className="btn" onClick={() => setView('profile')}>Ver meu perfil</button></section></div></> :
   view === 'profile' ? <>{head('Hub de parceiros', 'Meu perfil', 'É assim que empresas encontram você no diretório.')}<PartnerProfileEditor partnerId={partnerId} profile={profile} onSaved={setProfile} /></> :
   view === 'content' ? <>{head('Hub de parceiros', 'Meus conteúdos', 'Fotos e vídeos com descrição que aparecem no seu perfil para as empresas.')}<PartnerContents partnerId={partnerId} planId={planId} /></> :
   view === 'companies' ? <>{head('Hub de parceiros', 'Empresas', 'Empresas cadastradas na plataforma.')}<section className="commercial-panel partner-company-panel"><PartnerCompanyRows rows={companies} actions onChanged={reload} /></section></> :
   view === 'leads' ? <>{head('Hub de parceiros', 'Possíveis clientes', 'Empresas que demonstraram interesse no seu perfil.')}<section className="commercial-panel partner-company-panel"><PartnerCompanyRows rows={leads} actions onChanged={reload} /></section></> :
   <>{head('Hub de parceiros', 'Clientes', 'Empresas que você marcou como clientes pela plataforma.')}<section className="commercial-panel partner-company-panel"><PartnerCompanyRows rows={clients} actions={false} onChanged={reload} /></section></>}
 </section></main>;
}
