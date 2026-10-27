import { useEffect, useMemo, useState } from 'react';
import { listPartnerDirectory, loadCompanyContext, type CompanyContext, type DirectoryPartner } from './account';
import { listCompanyComplaints, listPartnerCompanies, loadCompanyRanking, loadCompanyTimeline, loadPartnerProfile, requestPartner, respondCompanyComplaint, setPartnerConnection, type CompanyComplaint, type ComplaintStatusDb, type PartnerCompany, type PartnerProfileData, type RankingRow, type TimelineItem } from './data';
import { showToast } from './toast';

// Portais de empresa e parceiro com dados reais (modelo v3). A empresa lê apenas versões compartilhadas, sem identidade.
type CompanyView = 'dashboard' | 'complaints' | 'ranking' | 'partners';
type PartnerView = 'dashboard' | 'profile' | 'companies' | 'leads' | 'clients';

const companyStatus: Record<ComplaintStatusDb, string> = { received: 'Recebida', shared: 'Aguardando resposta', answered: 'Respondida', closed: 'Finalizada', canceled: 'Cancelada' };
const feedbackLabels = { yes: 'A resposta ajudou', partial: 'Ajudou em parte', no: 'Não ajudou' } as const;

function dateLabel(value: string) { return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value)); }
function formatCnpj(value: string) { return value.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5'); }
function initials(name: string) { return name.split(' ').filter(Boolean).map(part => part[0]).slice(0, 2).join('').toUpperCase(); }
function hours(value: number | null | undefined) { return value === null || value === undefined ? '—' : value < 48 ? `${value} h` : `${(value / 24).toFixed(1).replace('.', ',')} dias`; }

function Metric({ label, value, note }: { label: string; value: string | number; note?: string }) {
 return <article className="commercial-metric"><span>{label}</span><strong>{value}</strong>{note && <small>{note}</small>}</article>;
}
function Sidebar<T extends string>({ eyebrow, name, items, view, onView }: { eyebrow: string; name: string; items: [T, string][]; view: T; onView: (view: T) => void }) {
 return <aside className="commercial-sidebar"><span className="editorial-eyebrow">{eyebrow}</span><strong className="commercial-sidebar-name">{name}</strong>{items.map(([key, label]) => <button key={key} className={view === key ? 'active' : ''} onClick={() => onView(key)}>{label}</button>)}</aside>;
}

function CompanyDashboard({ company, complaints, mine, onOpen, onView }: { company: CompanyContext; complaints: CompanyComplaint[]; mine?: RankingRow; onOpen: (id: string) => void; onView: (view: CompanyView) => void }) {
 const waiting = complaints.filter(item => item.status === 'shared');
 const answered = complaints.filter(item => item.responses > 0).length;
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Visão da organização</span><h1>Dashboard</h1><p>Acompanhe o que precisa de resposta e os sinais de responsividade da {company.name}.</p></div><button className="btn primary" onClick={() => onView('complaints')}>Ver manifestações</button></div>
  <div className="commercial-metrics"><Metric label="Manifestações recebidas" value={complaints.length} note="versões compartilhadas" /><Metric label="Aguardando resposta" value={waiting.length} note={waiting.length ? 'prioridade da equipe' : 'sem pendências'} /><Metric label="Taxa de resposta" value={complaints.length ? `${Math.round(100 * answered / complaints.length)}%` : '—'} note="com ao menos uma resposta" /><Metric label="Tempo médio" value={hours(mine?.avgFirstResponseHours)} note="até a primeira resposta" /></div>
  <div className="commercial-grid-two"><section className="commercial-panel"><h2>Fila de atenção</h2>{waiting.length ? waiting.slice(0, 4).map(item => <button className="commercial-list-row" key={item.id} onClick={() => onOpen(item.id)}><span><strong>{item.protocol} · {item.title}</strong><small>{item.category} · {dateLabel(item.createdAt)}</small></span><em>Responder ›</em></button>) : <p>Nenhuma manifestação aguardando resposta.</p>}</section>
   <section className="commercial-panel"><h2>Dados da empresa</h2><dl className="company-facts"><div><dt>Razão social</dt><dd>{company.legalName}</dd></div><div><dt>CNPJ</dt><dd>{formatCnpj(company.cnpj)}</dd></div><div><dt>Cidade</dt><dd>{company.city}/{company.state}</dd></div></dl><div className="commercial-callout">A empresa acessa somente a versão compartilhável revisada por quem relatou, sem identidade.</div></section></div></>;
}

function CompanyComplaints({ complaints, openId, onOpen, onChanged }: { complaints: CompanyComplaint[]; openId: string | null; onOpen: (id: string | null) => void; onChanged: () => void }) {
 const [search, setSearch] = useState('');
 const [status, setStatus] = useState('');
 const selected = complaints.find(item => item.id === openId);
 if (selected) return <CompanyComplaintDetail item={selected} onBack={() => onOpen(null)} onChanged={onChanged} />;
 const rows = complaints.filter(item => `${item.protocol} ${item.title} ${item.category}`.toLowerCase().includes(search.toLowerCase()) && (!status || item.status === status));
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Operação da empresa</span><h1>Manifestações</h1><p>Leia a versão compartilhável, responda e acompanhe o retorno.</p></div><label className="commercial-search">Pesquisar<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Protocolo ou assunto" /></label></div>
  <div className="commercial-filter-row"><select value={status} onChange={event => setStatus(event.target.value)} aria-label="Situação"><option value="">Todas as situações</option><option value="shared">Aguardando resposta</option><option value="answered">Respondida</option><option value="closed">Finalizada</option></select></div>
  {rows.length === 0 ? <section className="commercial-panel"><h2>{complaints.length ? 'Nenhuma manifestação encontrada' : 'Nenhuma manifestação por enquanto'}</h2><p>{complaints.length ? 'Revise a busca ou a situação.' : 'Quando uma manifestação for compartilhada com sua empresa, ela aparece aqui.'}</p></section> :
  <section className="commercial-panel">{rows.map(item => <button className="commercial-list-row" key={item.id} onClick={() => onOpen(item.id)}><span><strong>{item.protocol} · {item.title}</strong><small>{item.category} · {dateLabel(item.createdAt)}{item.responses ? ` · ${item.responses} resposta${item.responses > 1 ? 's' : ''}` : ''}</small></span><em>{companyStatus[item.status]} ›</em></button>)}</section>}</>;
}

function CompanyComplaintDetail({ item, onBack, onChanged }: { item: CompanyComplaint; onBack: () => void; onChanged: () => void }) {
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
  <div className="commercial-page-head"><div><span className="editorial-eyebrow">Manifestação {item.protocol}</span><h1>{item.title}</h1><p>{item.category} · recebida em {dateLabel(item.createdAt)} · {companyStatus[item.status]}</p></div></div>
  <div className="commercial-grid-two"><section className="commercial-panel"><h2>Versão compartilhada</h2><p>{item.shared}</p><div className="commercial-callout">Texto revisado e autorizado por quem relatou. A identidade e o relato original não são compartilhados.</div>{item.feedback && <p><strong>Avaliação do retorno:</strong> {feedbackLabels[item.feedback]}</p>}</section>
   <section className="commercial-panel"><h2>Histórico</h2>{timeline === null ? <p className="muted">Carregando…</p> : <ol className="worker-timeline">{timeline.map((entry, index) => <li key={index} className={entry.kind === 'response' ? 'worker-timeline-response' : ''}><strong>{entry.kind === 'response' ? 'Resposta enviada' : companyStatus[entry.status ?? 'shared']}</strong><span>{dateLabel(entry.createdAt)}</span><p>{entry.content}</p></li>)}</ol>}</section></div>
  {['shared', 'answered'].includes(item.status) && <section className="commercial-panel"><h2>{item.status === 'shared' ? 'Responder' : 'Enviar nova atualização'}</h2><p className="muted small">Responda de forma institucional. Não tente identificar quem relatou.</p><textarea className="company-response-text" rows={5} maxLength={5000} value={text} onChange={event => setText(event.target.value)} aria-label="Resposta da empresa" /><div className="nav-actions"><button className="btn primary" disabled={busy || text.trim().length < 10} onClick={send}>Enviar resposta</button></div></section>}</>;
}

function CompanyRanking({ rows }: { rows: RankingRow[] | null }) {
 const mine = rows?.find(row => row.isMine);
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Referência pública</span><h1>Ranking</h1><p>Responsividade entre empresas com pelo menos 3 manifestações compartilhadas.</p></div></div>
  <div className="commercial-callout">{mine ? 'Sua empresa está destacada na tabela.' : 'Sua empresa entra no ranking a partir de 3 manifestações compartilhadas, para uma comparação justa.'} O cálculo considera volume, taxa de resposta e tempo até a primeira resposta.</div>
  {rows === null ? <p className="muted">Carregando…</p> : rows.length === 0 ? <section className="commercial-panel"><p>Ainda não há empresas com volume suficiente.</p></section> :
  <div className="commercial-panel commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Posição</th><th>Empresa</th><th>Cidade</th><th>Manifestações</th><th>Taxa de resposta</th><th>Tempo médio</th></tr></thead><tbody>{rows.map((row, index) => <tr key={row.companyId} className={row.isMine ? 'ranking-mine' : ''}><td>{index + 1}º</td><td>{row.name}{row.isMine && <strong> · sua empresa</strong>}</td><td>{row.city}/{row.state}</td><td>{row.received}</td><td>{row.responseRate}%</td><td>{hours(row.avgFirstResponseHours)}</td></tr>)}</tbody></table></div>}</>;
}

function PartnerDirectoryLive() {
 const [partners, setPartners] = useState<DirectoryPartner[] | null>(null);
 const [search, setSearch] = useState('');
 const [selected, setSelected] = useState<DirectoryPartner | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; listPartnerDirectory().then(rows => { if (active) setPartners(rows); }); return () => { active = false; }; }, [version]);
 const rows = (partners ?? []).filter(partner => `${partner.name} ${partner.specialty} ${partner.city} ${partner.state}`.toLowerCase().includes(search.toLowerCase()));
 const avatar = (partner: DirectoryPartner, large = false) => partner.avatarUrl ? <img className={`partner-avatar partner-photo${large ? ' large' : ''}`} src={partner.avatarUrl} alt={`Foto de ${partner.name}`} /> : <div className={`partner-avatar${large ? ' large' : ''}`} style={{ background: 'var(--soft)' }} aria-hidden="true">{initials(partner.name)}</div>;
 async function contact(partner: DirectoryPartner) {
  const result = await requestPartner(partner.id);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', `Interesse enviado. ${partner.name} verá sua empresa em "Possíveis clientes" e retornará diretamente.`);
  setSelected({ ...partner, requested: true }); setVersion(value => value + 1);
 }
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Rede de apoio</span><h1>Parceiros</h1><p>Profissionais cadastrados no Hub de Parceiros para apoiar os próximos passos da sua organização.</p></div><label className="commercial-search">Pesquisar<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome, especialidade ou cidade" /></label></div>
  {partners === null ? <p className="muted">Carregando parceiros…</p> : rows.length === 0 ? <section className="commercial-panel"><h2>{partners.length ? 'Nenhum parceiro encontrado' : 'Ainda não há parceiros cadastrados'}</h2><p>{partners.length ? 'Tente outro nome, especialidade ou cidade.' : 'Quando profissionais se cadastrarem no Hub, eles aparecem aqui.'}</p></section> :
  <div className="partner-grid">{rows.map(partner => <button className="partner-card" key={partner.id} onClick={() => setSelected(partner)}>{avatar(partner)}<span className="commercial-badge">{partner.requested ? 'Interesse enviado' : 'Parceiro cadastrado'}</span><h2>{partner.name}</h2><p>{partner.specialty}</p><small>{partner.city} / {partner.state}</small></button>)}</div>}
  {selected && <div className="commercial-modal-backdrop" onMouseDown={event => event.target === event.currentTarget && setSelected(null)}><section className="commercial-modal partner-modal" role="dialog" aria-modal="true" aria-labelledby="partner-title"><button className="commercial-modal-close" onClick={() => setSelected(null)} aria-label="Fechar">×</button>{avatar(selected, true)}<span className="editorial-eyebrow">Perfil profissional</span><h2 id="partner-title">{selected.name}</h2><p>{selected.specialty} · {selected.city} / {selected.state}</p>{selected.description && <p>{selected.description}</p>}<div className="commercial-callout">A plataforma não intermedia o serviço. O parceiro recebe o interesse da sua empresa e retorna diretamente.</div>{selected.requested ? <p className="commercial-feedback" role="status">Interesse já enviado a este parceiro.</p> : <button className="btn primary" onClick={() => contact(selected)}>Entrar em contato</button>}</section></div>}</>;
}

export function CompanyPortalLive({ companyId }: { companyId: string }) {
 const [view, setView] = useState<CompanyView>('dashboard');
 const [company, setCompany] = useState<CompanyContext | null | undefined>(undefined);
 const [complaints, setComplaints] = useState<CompanyComplaint[] | null>(null);
 const [ranking, setRanking] = useState<RankingRow[] | null>(null);
 const [openId, setOpenId] = useState<string | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; loadCompanyContext(companyId).then(value => { if (active) setCompany(value); }).catch(() => active && setCompany(null)); return () => { active = false; }; }, [companyId]);
 useEffect(() => { let active = true; Promise.all([listCompanyComplaints(), loadCompanyRanking()]).then(([rows, rank]) => { if (active) { setComplaints(rows); setRanking(rank); } }); return () => { active = false; }; }, [companyId, version]);
 const mine = useMemo(() => ranking?.find(row => row.isMine), [ranking]);
 const open = (id: string | null) => { setOpenId(id); setView('complaints'); };
 const items: [CompanyView, string][] = [['dashboard', 'Dashboard'], ['complaints', 'Manifestações'], ['ranking', 'Ranking'], ['partners', 'Parceiros']];
 return <main className="commercial-portal-content"><Sidebar eyebrow="Área da empresa" name={company?.name ?? 'Carregando…'} items={items} view={view} onView={next => { setView(next); setOpenId(null); }} /><section className="commercial-portal-main">
  {company === undefined || complaints === null ? <p className="muted">Carregando dados da empresa…</p> : company === null ? <section className="commercial-panel"><h2>Não foi possível carregar sua empresa</h2><p>Saia e entre novamente. Se continuar, fale com o suporte.</p></section> :
   view === 'dashboard' ? <CompanyDashboard company={company} complaints={complaints} mine={mine} onOpen={open} onView={setView} /> :
   view === 'complaints' ? <CompanyComplaints complaints={complaints} openId={openId} onOpen={setOpenId} onChanged={() => setVersion(value => value + 1)} /> :
   view === 'ranking' ? <CompanyRanking rows={ranking} /> : <PartnerDirectoryLive />}
 </section></main>;
}

function PartnerCompanyRows({ rows, actions, onChanged }: { rows: PartnerCompany[]; actions: boolean; onChanged: () => void }) {
 async function update(company: PartnerCompany, stage: 'partner_contacted' | 'client') {
  const result = await setPartnerConnection(company.id, stage);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', stage === 'client' ? `${company.name} foi adicionada aos seus clientes.` : `Contato com ${company.name} registrado.`); onChanged();
 }
 if (!rows.length) return <p className="muted">Nenhuma empresa nesta lista por enquanto.</p>;
 return <>{rows.map(company => <article className="partner-company-row" key={company.id}><div><strong>{company.name}</strong><span>{company.legalName}</span><small>{company.city}/{company.state}{company.stage === 'company_interest' ? ' · demonstrou interesse no seu perfil' : company.stage === 'partner_contacted' ? ' · contato iniciado' : ''}</small></div><div className="partner-company-actions">{actions && company.stage !== 'client' && <button className="btn" disabled={company.stage === 'partner_contacted'} onClick={() => update(company, 'partner_contacted')}>{company.stage === 'partner_contacted' ? 'Contato iniciado' : 'Entrar em contato'}</button>}{actions && company.stage !== 'client' && <button className="btn primary" onClick={() => update(company, 'client')}>Marcar como cliente</button>}</div></article>)}</>;
}

export function PartnerPortalLive({ partnerId }: { partnerId: string }) {
 const [view, setView] = useState<PartnerView>('dashboard');
 const [profile, setProfile] = useState<PartnerProfileData | null | undefined>(undefined);
 const [companies, setCompanies] = useState<PartnerCompany[] | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; loadPartnerProfile(partnerId).then(value => { if (active) setProfile(value); }); return () => { active = false; }; }, [partnerId]);
 useEffect(() => { let active = true; listPartnerCompanies().then(rows => { if (active) setCompanies(rows); }); return () => { active = false; }; }, [partnerId, version]);
 const leads = (companies ?? []).filter(company => company.stage === 'company_interest');
 const clients = (companies ?? []).filter(company => company.stage === 'client');
 const contacted = (companies ?? []).filter(company => company.stage === 'partner_contacted');
 const items: [PartnerView, string][] = [['dashboard', 'Dashboard'], ['profile', 'Meu perfil'], ['companies', 'Empresas'], ['leads', 'Possíveis clientes'], ['clients', 'Clientes']];
 const reload = () => setVersion(value => value + 1);
 const head = (eyebrow: string, title: string, text: string) => <div className="commercial-page-head"><div><span className="editorial-eyebrow">{eyebrow}</span><h1>{title}</h1><p>{text}</p></div></div>;
 return <main className="commercial-portal-content"><Sidebar eyebrow="Hub de parceiros" name={profile?.displayName ?? 'Carregando…'} items={items} view={view} onView={setView} /><section className="commercial-portal-main">
  {profile === undefined || companies === null ? <p className="muted">Carregando seu hub…</p> : profile === null ? <section className="commercial-panel"><h2>Não foi possível carregar seu perfil</h2><p>Saia e entre novamente.</p></section> :
   view === 'dashboard' ? <>{head('Seu hub profissional', 'Dashboard', 'Acompanhe empresas interessadas e sua carteira.')}<div className="commercial-metrics"><Metric label="Empresas na plataforma" value={companies.length} /><Metric label="Possíveis clientes" value={leads.length} note="demonstraram interesse" /><Metric label="Contatos iniciados" value={contacted.length} /><Metric label="Clientes" value={clients.length} note="na sua carteira" /></div><div className="commercial-grid-two"><section className="commercial-panel"><h2>Possíveis clientes</h2><PartnerCompanyRows rows={leads.slice(0, 3)} actions onChanged={reload} /></section><section className="commercial-panel"><h2>Próximo passo</h2><p>Mantenha foto e descrição atualizadas: empresas veem esses dados ao buscar parceiros.</p><button className="btn" onClick={() => setView('profile')}>Ver meu perfil</button></section></div></> :
   view === 'profile' ? <>{head('Hub de parceiros', 'Meu perfil', 'É assim que empresas encontram você no diretório.')}<section className="commercial-panel"><dl className="company-facts"><div><dt>Nome profissional</dt><dd>{profile.displayName}</dd></div><div><dt>Especialidade</dt><dd>{profile.specialty}</dd></div><div><dt>Cidade</dt><dd>{profile.city}/{profile.state}</dd></div><div><dt>Descrição</dt><dd>{profile.description ?? '—'}</dd></div></dl><div className="commercial-callout">Foto de perfil e plano ficam em "Minha assinatura".</div></section></> :
   view === 'companies' ? <>{head('Hub de parceiros', 'Empresas', 'Empresas cadastradas na plataforma.')}<section className="commercial-panel partner-company-panel"><PartnerCompanyRows rows={companies} actions onChanged={reload} /></section></> :
   view === 'leads' ? <>{head('Hub de parceiros', 'Possíveis clientes', 'Empresas que demonstraram interesse no seu perfil.')}<section className="commercial-panel partner-company-panel"><PartnerCompanyRows rows={leads} actions onChanged={reload} /></section></> :
   <>{head('Hub de parceiros', 'Clientes', 'Empresas que você marcou como clientes pela plataforma.')}<section className="commercial-panel partner-company-panel"><PartnerCompanyRows rows={clients} actions={false} onChanged={reload} /></section></>}
 </section></main>;
}
