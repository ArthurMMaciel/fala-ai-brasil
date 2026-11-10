import { useEffect, useState } from 'react';
import { showToast } from '../app/toast';
import { correctedLabel, reviewOverdue, validateCorrectionReason, validateRatingComment, validateReturnReason, validateWorkerSummary } from '../domain/response-review';
import { rateResponse, type ComplaintFeedback, type ResponseRating, type TimelineItem } from '../services/data';
import { correctOpsResponseSummary, decideOpsResponse, listOpsResponses, type OpsResponse, type ResponseReviewStatus } from '../services/ops';

// Resposta da empresa revisada pela equipe (ADR-0013, TASK-0035).

const ratingLabels: Record<ComplaintFeedback, string> = { yes: 'Sim, ajudou', partial: 'Em parte', no: 'Não ajudou' };
const dateLabel = (value: string) => new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value));

function RateResponse({ responseId, onRated }: { responseId: string; onRated: () => void }) {
 const [rating, setRating] = useState<ComplaintFeedback | ''>('');
 const [comment, setComment] = useState('');
 const [busy, setBusy] = useState(false);
 async function submit(event: React.FormEvent) {
  event.preventDefault();
  if (!rating) return showToast('error', 'Escolha uma avaliação.');
  const problem = validateRatingComment(comment);
  if (problem) return showToast('error', problem);
  setBusy(true); const result = await rateResponse(responseId, rating, comment); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Avaliação registrada. Obrigado.'); onRated();
 }
 return <form className="response-rating" onSubmit={submit}>
  <fieldset><legend>Esta resposta ajudou?</legend>
   {(Object.keys(ratingLabels) as ComplaintFeedback[]).map(key => <label key={key}><input type="radio" name={`rating-${responseId}`} value={key} checked={rating === key} onChange={() => setRating(key)} /> {ratingLabels[key]}</label>)}
  </fieldset>
  <label className="field">Comentário (opcional)<textarea rows={2} maxLength={300} value={comment} onChange={event => setComment(event.target.value)} /><small className="muted">Só a equipe Escuta Aí Brasil lê. A empresa não vê o comentário. {comment.length}/300</small></label>
  <button className="btn" type="submit" disabled={busy}>{busy ? 'Enviando…' : 'Enviar avaliação'}</button>
 </form>;
}

/** Respostas liberadas ao trabalhador: descrição da equipe em destaque e, abaixo, o texto original da empresa. */
export function WorkerResponses({ responses, ratings, onRated }: { responses: TimelineItem[]; ratings: ResponseRating[]; onRated: () => void }) {
 if (!responses.length) return null;
 return <section className="worker-detail-section worker-responses"><h3>{responses.length > 1 ? 'Respostas da empresa' : 'Resposta da empresa'}</h3>
  {responses.map(response => {
   const rated = ratings.find(item => item.responseId === response.id);
   const corrected = correctedLabel(response.summaryCorrectedAt);
   return <article key={response.id ?? response.createdAt} className="worker-response">
    <p className="muted small">{dateLabel(response.releasedAt ?? response.createdAt)}</p>
    {response.workerSummary && <div className="commercial-callout worker-response-summary"><strong>Descrição da equipe Escuta Aí Brasil</strong><p>{response.workerSummary}</p>{corrected && <small>{corrected}</small>}</div>}
    <div className="worker-response-original"><strong>{response.workerSummary ? 'Resposta original da empresa' : 'Resposta da empresa'}</strong><p className="worker-original">{response.content}</p></div>
    {response.id && (rated ? <p className="muted small">Sua avaliação: <strong>{ratingLabels[rated.rating]}</strong></p> : <RateResponse responseId={response.id} onRated={onRated} />)}
   </article>;
  })}
 </section>;
}

const reviewTabs: [ResponseReviewStatus, string][] = [['in_review', 'Em revisão'], ['released', 'Liberadas'], ['returned', 'Devolvidas']];

function ResponseDetail({ item, onBack, onChanged }: { item: OpsResponse; onBack: () => void; onChanged: () => void }) {
 const [summary, setSummary] = useState(item.workerSummary ?? '');
 const [reason, setReason] = useState('');
 const [busy, setBusy] = useState(false);
 async function decide(decision: 'released' | 'returned') {
  const problem = decision === 'released' ? validateWorkerSummary(summary) : validateReturnReason(reason);
  if (problem) return showToast('error', problem, 'Confira os dados');
  if (decision === 'released' && !window.confirm('Liberar esta resposta ao trabalhador, com a descrição da equipe?')) return;
  setBusy(true); const result = await decideOpsResponse(item.id, decision, summary, reason); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', decision === 'released' ? 'Resposta liberada ao trabalhador.' : 'Resposta devolvida à empresa para ajuste.'); onChanged();
 }
 async function correct() {
  const problem = validateWorkerSummary(summary) ?? validateCorrectionReason(reason);
  if (problem) return showToast('error', problem, 'Confira os dados');
  setBusy(true); const result = await correctOpsResponseSummary(item.id, summary, reason); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Descrição corrigida. O trabalhador verá a data da correção.'); onChanged();
 }
 return <><button className="text-action worker-back" onClick={onBack}>← Voltar</button>
  <div className="worker-detail-heading"><div><span className="editorial-eyebrow">Resposta · manifestação {item.protocol}</span><h2>{item.title}</h2><p className="muted">{item.companyName} · {item.category} · enviada em {dateLabel(item.createdAt)}</p></div></div>
  <div className="worker-detail-grid"><div>
   <section className="worker-detail-section"><h3>Resposta da empresa</h3><p className="muted small">O texto da empresa não é editado. O trabalhador recebe a descrição da equipe e, abaixo, este texto.</p><p className="worker-original">{item.content}</p></section>
   {item.reviewStatus !== 'returned' && <section className="worker-detail-section ops-decision"><h3>{item.reviewStatus === 'in_review' ? 'Descrição para o trabalhador' : 'Corrigir a descrição'}</h3>
    <label className="field">Descrição da equipe<textarea rows={5} maxLength={1000} value={summary} onChange={event => setSummary(event.target.value)} placeholder="Explique em linguagem simples o que a empresa respondeu, sem dados que identifiquem pessoas." /><small className="muted">{summary.trim().length}/1.000 · mínimo 30</small></label>
    <label className="field">{item.reviewStatus === 'in_review' ? 'Motivo da devolução (só para devolver)' : 'Motivo da correção'}<textarea rows={2} maxLength={500} value={reason} onChange={event => setReason(event.target.value)} placeholder={item.reviewStatus === 'in_review' ? 'Ex.: a resposta cita uma pessoa; peça à empresa para retirar.' : 'Ex.: a descrição omitiu o prazo informado pela empresa.'} />{item.reviewStatus === 'in_review' && <small className="muted">Na devolução, o motivo aparece para a empresa.</small>}</label>
    <div className="ops-decision-actions">{item.reviewStatus === 'in_review' ? <><button className="btn primary" disabled={busy} onClick={() => decide('released')}>Liberar ao trabalhador</button><button className="btn" disabled={busy} onClick={() => decide('returned')}>Devolver à empresa</button></> : <button className="btn primary" disabled={busy} onClick={correct}>Salvar correção</button>}</div>
   </section>}
  </div><aside className="worker-detail-aside"><section className="worker-detail-section"><h3>Versão compartilhável</h3><p className="muted small">O que a empresa leu antes de responder.</p><p>{item.shared ?? '—'}</p></section></aside></div></>;
}

/** Fila de respostas da Operação, das mais antigas para as mais novas (prazo de 2 dias úteis). */
export function OpsResponses({ onChanged }: { onChanged?: () => void }) {
 const [tab, setTab] = useState<ResponseReviewStatus>('in_review');
 const [rows, setRows] = useState<OpsResponse[] | null>(null);
 const [failure, setFailure] = useState('');
 const [openId, setOpenId] = useState<string | null>(null);
 const [version, setVersion] = useState(0);
 useEffect(() => { let active = true; setRows(null); listOpsResponses(tab).then(data => { if (active) { setRows(data); setFailure(''); } }).catch(error => { if (active) setFailure(error instanceof Error ? error.message : 'Não foi possível carregar as respostas.'); }); return () => { active = false; }; }, [tab, version]);
 const opened = rows?.find(row => row.id === openId);
 if (opened) return <ResponseDetail key={opened.id + opened.reviewStatus} item={opened} onBack={() => setOpenId(null)} onChanged={() => { setOpenId(null); setVersion(value => value + 1); onChanged?.(); }} />;
 return <><div className="commercial-page-head"><div><span className="editorial-eyebrow">Operação</span><h1>Respostas das empresas</h1><p>Leia a resposta, escreva a descrição para o trabalhador e libere, ou devolva à empresa com o motivo. Prazo de revisão: 2 dias úteis.</p></div></div>
  <div className="account-tabs ops-response-tabs" role="tablist" aria-label="Situação da resposta">{reviewTabs.map(([key, label]) => <button key={key} role="tab" aria-selected={tab === key} className={`account-tab${tab === key ? ' active' : ''}`} onClick={() => { setTab(key); setOpenId(null); }}>{label}</button>)}</div>
  {failure ? <section className="commercial-panel"><p>{failure}</p></section> : rows === null ? <p className="muted">Carregando…</p> : !rows.length ? <section className="commercial-panel"><p className="muted">{tab === 'in_review' ? 'Nenhuma resposta aguardando revisão.' : 'Nada por aqui.'}</p></section> :
  <div className="commercial-table-wrap"><table className="commercial-table"><thead><tr><th>Protocolo</th><th>Empresa</th><th>Assunto</th><th>{tab === 'in_review' ? 'Aguardando' : 'Enviada em'}</th></tr></thead>
   <tbody>{rows.map(row => <tr key={row.id} tabIndex={0} onClick={() => setOpenId(row.id)} onKeyDown={event => event.key === 'Enter' && setOpenId(row.id)}><td>{row.protocol}</td><td>{row.companyName}</td><td>{row.title}<small>{row.category}</small></td>
    <td>{tab === 'in_review' ? <span className={reviewOverdue(row.waitingHours) ? 'ops-overdue' : ''}>{row.waitingHours === null ? '—' : row.waitingHours < 48 ? `há ${Math.floor(row.waitingHours)} h` : `há ${Math.floor(row.waitingHours / 24)} dias`}</span> : dateLabel(row.createdAt)}</td></tr>)}</tbody></table></div>}</>;
}
