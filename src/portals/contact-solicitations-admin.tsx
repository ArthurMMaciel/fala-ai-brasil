import { useEffect, useState } from 'react';
import { listContactSolicitations, setContactSolicitationStatus, type ContactProfile, type ContactSolicitation, type ContactStatus } from '../services/contact-solicitations';

const profileLabels: Record<ContactProfile, string> = { worker: 'Trabalhador', company: 'Empresa', partner: 'Parceiro', sponsor: 'Patrocinador' };
const statusLabels: Record<ContactStatus, string> = { waiting_contact: 'Aguardando contato', contacted: 'Contatado' };
const formatDate = (value: string) => new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));

export function ContactSolicitationsAdmin() {
  const [status, setStatus] = useState<ContactStatus | ''>('');
  const [profile, setProfile] = useState<ContactProfile | ''>('');
  const [items, setItems] = useState<ContactSolicitation[] | null>(null);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    let current = true;
    setItems(null);
    setError('');
    listContactSolicitations(status, profile).then(rows => { if (current) setItems(rows); }).catch(() => { if (current) { setError('Não foi possível carregar as solicitações.'); setItems([]); } });
    return () => { current = false; };
  }, [status, profile, refresh]);

  async function change(item: ContactSolicitation) {
    const next: ContactStatus = item.status === 'waiting_contact' ? 'contacted' : 'waiting_contact';
    setBusyId(item.id);
    setError('');
    try {
      await setContactSolicitationStatus(item.id, next);
      setItems(current => current?.map(row => row.id === item.id ? { ...row, status: next, contactedAt: next === 'contacted' ? new Date().toISOString() : null } : row) ?? null);
      setRefresh(value => value + 1);
    } catch { setError('Não foi possível atualizar o status. Tente novamente.'); }
    finally { setBusyId(null); }
  }

  return <div className="contact-admin" id="main-content" tabIndex={-1}>
    <header className="contact-admin-heading"><span className="editorial-eyebrow">Equipe Escuta Aí Brasil</span><h1>Solicitações contato</h1><p>Pedidos enviados pelas páginas públicas. O status registra se a equipe já realizou o contato.</p></header>
    <div className="contact-admin-filters"><label>Status<select value={status} onChange={event => setStatus(event.target.value as ContactStatus | '')}><option value="">Todos</option><option value="waiting_contact">Aguardando contato</option><option value="contacted">Contatado</option></select></label><label>Perfil<select value={profile} onChange={event => setProfile(event.target.value as ContactProfile | '')}><option value="">Todos</option>{Object.entries(profileLabels).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label><button className="btn" onClick={() => setRefresh(value => value + 1)}>Atualizar lista</button></div>
    {error && <p className="field-error" role="alert">{error}</p>}
    {items === null ? <p role="status">Carregando solicitações…</p> : items.length === 0 ? <div className="contact-admin-empty"><h2>Nenhuma solicitação encontrada</h2><p>Revise os filtros ou atualize a lista.</p></div> :
    <div className="contact-admin-table-wrap"><table className="contact-admin-table"><caption className="sr-only">Solicitações de contato por perfil e status</caption><thead><tr><th>Recebida em</th><th>Contato</th><th>Perfil</th><th>Status</th><th>Último contato</th><th>Ação</th></tr></thead><tbody>{items.map(item => <tr key={item.id}><td>{formatDate(item.createdAt)}</td><td><strong>{item.name}</strong>{item.organization && <span>{item.organization}</span>}<a href={`mailto:${item.email}`}>{item.email}</a><a href={`tel:+55${item.phone}`}>{item.phone}</a></td><td>{profileLabels[item.profile]}{item.landingOrigin === 'intelligence' && <small>Interesse em Intelligence</small>}</td><td><span className={`contact-admin-status ${item.status}`}>{statusLabels[item.status]}</span></td><td>{item.contactedAt ? formatDate(item.contactedAt) : '—'}</td><td><button className="btn" disabled={busyId === item.id} onClick={() => change(item)}>{busyId === item.id ? 'Salvando…' : item.status === 'waiting_contact' ? 'Marcar como contatado' : 'Voltar para aguardando'}</button></td></tr>)}</tbody></table></div>}
    <p className="small contact-admin-limit">Exibindo até 200 solicitações mais recentes. Use os filtros para organizar a fila; não copie estes dados para sistemas externos sem avaliação.</p>
  </div>;
}
