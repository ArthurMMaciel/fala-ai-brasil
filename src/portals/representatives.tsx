import { useEffect, useState } from 'react';
import { showToast } from '../app/toast';
import { allowedDecisions, validateVerification, verificationDecisionLabels, verificationMethodLabels, verificationStatusLabels, type VerificationDecision, type VerificationMethod, type VerificationStatus } from '../domain/representatives';
import { listOpsRepresentatives, loadRepresentativeHistory, verifyOpsRepresentative, type OpsRepresentative, type RepresentativeHistoryItem } from '../services/ops';

// Fila "Representantes a verificar" (ADR-0012). Sem a migration 20261117120000 a tela avisa e não quebra.
const tabs: [VerificationStatus, string][] = [['pending', 'A verificar'], ['verified', 'Verificados'], ['rejected', 'Recusados'], ['revoked', 'Revogados']];
const dateLabel = (value: string) => new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value));
const roleLabel = (role: OpsRepresentative['role']) => role === 'owner' ? 'Responsável pela conta' : 'Integrante';

function History({ companyId }: { companyId: string }) {
 const [rows, setRows] = useState<RepresentativeHistoryItem[] | null>(null);
 const [failure, setFailure] = useState('');
 useEffect(() => { let active = true; loadRepresentativeHistory(companyId).then(data => { if (active) setRows(data); }).catch(error => { if (active) setFailure(error instanceof Error ? error.message : 'Não foi possível carregar o histórico.'); }); return () => { active = false; }; }, [companyId]);
 if (failure) return <p className="muted small">{failure}</p>;
 if (rows === null) return <p className="muted small">Carregando…</p>;
 if (!rows.length) return <p className="muted small">Nenhuma decisão registrada para esta empresa.</p>;
 return <ol className="worker-timeline">{rows.map((row, index) => <li key={index}><strong>{verificationStatusLabels[row.decision]}</strong><span>{dateLabel(row.createdAt)}</span><p>{row.method ? `${verificationMethodLabels[row.method]}: ${row.evidenceRef ?? ''}` : row.reason}</p></li>)}</ol>;
}

function RepresentativeDetail({ item, onBack, onChanged }: { item: OpsRepresentative; onBack: () => void; onChanged: () => void }) {
 const decisions = allowedDecisions(item.status);
 const [decision, setDecision] = useState<VerificationDecision>(decisions[0]);
 const [method, setMethod] = useState<VerificationMethod | ''>('');
 const [evidenceRef, setEvidenceRef] = useState('');
 const [reason, setReason] = useState('');
 const [busy, setBusy] = useState(false);
 async function submit(event: React.FormEvent) {
  event.preventDefault();
  const problem = validateVerification(decision, method, evidenceRef, reason);
  if (problem) return showToast('error', problem, 'Confira os dados');
  const question = decision === 'verified' ? `Verificar ${item.email} como representante de ${item.companyName}? A empresa passará a ver casos e números.` : decision === 'revoked' ? `Revogar o acesso de ${item.email}? A empresa deixa de ver casos e números por esta conta.` : `Recusar ${item.email} como representante de ${item.companyName}?`;
  if (!window.confirm(question)) return;
  setBusy(true); const result = await verifyOpsRepresentative(item.companyId, item.userId, decision, method, evidenceRef, reason); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', decision === 'verified' ? 'Representante verificado.' : decision === 'revoked' ? 'Acesso revogado.' : 'Representante recusado.'); onChanged();
 }
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar</button>
  <div className="worker-detail-heading"><div><span className="editorial-eyebrow">Representante · {verificationStatusLabels[item.status]}</span><h2>{item.companyName}</h2><p className="muted">CNPJ {item.cnpj} · {item.email} · {roleLabel(item.role)} · vínculo em {dateLabel(item.linkedAt)}</p></div></div>
  <div className="worker-detail-grid"><div>
   <form className="worker-detail-section ops-decision" onSubmit={submit} noValidate><h3>Decisão da equipe</h3>
    <fieldset className="response-rating"><legend>O que fazer</legend>{decisions.map(value => <label key={value} className="check-row"><input type="radio" name="decision" value={value} checked={decision === value} onChange={() => setDecision(value)} /> <span>{verificationDecisionLabels[value]}</span></label>)}</fieldset>
    {decision === 'verified' ? <>
     <fieldset className="response-rating"><legend>Como a conferência foi feita</legend>{(Object.keys(verificationMethodLabels) as VerificationMethod[]).map(value => <label key={value} className="check-row"><input type="radio" name="method" value={value} checked={method === value} onChange={() => setMethod(value)} /> <span>{verificationMethodLabels[value]}</span></label>)}</fieldset>
     <label className="field">Referência da conferência<input maxLength={200} value={evidenceRef} onChange={event => setEvidenceRef(event.target.value)} placeholder="Ex.: ligação em 18/11 ao telefone do site, falou com o RH" /><small className="muted">Descreva quando e como conferiu. Não digite CPF, CNPJ nem número de documento aqui.</small></label>
    </> : <label className="field">Motivo<textarea rows={3} maxLength={500} value={reason} onChange={event => setReason(event.target.value)} placeholder={decision === 'revoked' ? 'Ex.: a pessoa deixou a empresa, segundo o RH.' : 'Ex.: o telefone público não confirma o vínculo.'} /><small className="muted">{reason.trim().length}/500 caracteres. Fica na trilha da equipe.</small></label>}
    <div className="ops-decision-actions"><button className="btn primary" type="submit" disabled={busy}>{busy ? 'Registrando…' : verificationDecisionLabels[decision]}</button></div>
   </form>
  </div><aside className="worker-detail-aside"><section className="worker-detail-section"><h3>Histórico da empresa</h3><History companyId={item.companyId} /></section></aside></div></>;
}

export function OpsRepresentatives({ onChanged }: { onChanged?: () => void }) {
 const [tab, setTab] = useState<VerificationStatus>('pending');
 const [rows, setRows] = useState<OpsRepresentative[] | null>(null);
 const [missing, setMissing] = useState(false);
 const [failure, setFailure] = useState('');
 const [openKey, setOpenKey] = useState<string | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; setRows(null); listOpsRepresentatives(tab).then(result => { if (!active) return; setFailure(''); setMissing(result.missing); setRows(result.missing ? [] : result.rows); }).catch(error => { if (active) setFailure(error instanceof Error ? error.message : 'Não foi possível carregar os representantes.'); }); return () => { active = false; }; }, [tab, version]);
 const key = (row: OpsRepresentative) => `${row.companyId}:${row.userId}`;
 const opened = rows?.find(row => key(row) === openKey);
 if (opened) return <RepresentativeDetail key={key(opened) + opened.status} item={opened} onBack={() => setOpenKey(null)} onChanged={() => { setOpenKey(null); setVersion(value => value + 1); onChanged?.(); }} />;
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Operação</span><h1>Representantes a verificar</h1><p>Confirme que quem se cadastrou representa a empresa antes de ela ver casos e números. Ligue para o telefone público da empresa ou confira um documento fora da plataforma.</p></div></div>
  {missing ? <section className="commercial-panel"><p>A verificação de representantes ainda não está ativa no banco. A fila aparece aqui assim que a atualização for aplicada.</p></section> : <>
  <div className="account-tabs ops-response-tabs" role="tablist" aria-label="Situação do representante">{tabs.map(([value, label]) => <button key={value} role="tab" aria-selected={tab === value} className={`account-tab${tab === value ? ' active' : ''}`} onClick={() => { setTab(value); setOpenKey(null); }}>{label}</button>)}</div>
  {failure ? <section className="commercial-panel"><p>{failure}</p></section> : rows === null ? <p className="muted">Carregando…</p> : !rows.length ? <section className="commercial-panel"><p className="muted">{tab === 'pending' ? 'Nenhum representante aguardando verificação.' : 'Nada por aqui.'}</p></section> :
  <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Empresa</th><th>Representante</th><th>Vínculo</th><th>{tab === 'pending' ? 'Cadastro em' : 'Situação'}</th></tr></thead>
   <tbody>{rows.map(row => <tr key={key(row)} tabIndex={0} onClick={() => setOpenKey(key(row))} onKeyDown={event => event.key === 'Enter' && setOpenKey(key(row))}><td>{row.companyName}<small>CNPJ {row.cnpj}</small></td><td>{row.email}</td><td>{roleLabel(row.role)}</td><td>{tab === 'pending' ? dateLabel(row.linkedAt) : verificationStatusLabels[row.status]}</td></tr>)}</tbody></table></div>}</>}</>;
}
