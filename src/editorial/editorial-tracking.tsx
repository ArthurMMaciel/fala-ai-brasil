import { useEffect, useRef, useState } from 'react';
import { Journey, Note } from './editorial-ui';
import { session } from './editorial-model';

type Props = { onRoute: (route: string) => void };

export function Confirmation({ onRoute }: Props) {
 const item = session.records.find(record => record.protocol === session.activeProtocol)!;
 const [feedback, setFeedback] = useState('');
 async function saveAccess() {
  try {
   await navigator.clipboard.writeText(`Escuta Aí Brasil — demonstração\nProtocolo fictício: ${item.protocol}\nChave fictícia: ${item.key}\nVálidos somente nesta aba, até recarregar. Não oferecem autenticação real.`);
   setFeedback('Dados fictícios copiados. Guarde em local reservado. O registro só existe nesta aba, até recarregar.');
  } catch {
   setFeedback('Não foi possível copiar. Selecione o protocolo e a chave acima e copie manualmente para um local reservado.');
  }
 }
 return <main className="confirmation-layout" id="main-content" tabIndex={-1}>
  <section className="confirmation-record">
   <span className="editorial-eyebrow">Envio concluído · Exemplo fictício</span>
   <h1>Seu relato abre um caminho.</h1>
   <p className="lead">Nenhum dado foi enviado. Guarde os dois dados abaixo para acompanhar a manifestação demonstrativa nesta aba.</p>
   <dl className="access-record">
    <div><dt>Protocolo fictício</dt><dd>{item.protocol}</dd></div>
    <div><dt>Chave de acesso fictícia</dt><dd>{item.key}</dd></div>
    <div className="access-caption"><dt className="sr-only">Limites da demonstração</dt><dd>Registro demonstrativo em {item.created}. Não use estes dados para um relato real.</dd></div>
   </dl>
   <div className="editorial-actions"><button className="btn" onClick={saveAccess}>Guardar dados de acesso</button><button className="btn primary" onClick={() => onRoute('tracking-case')}>Ir para acompanhamento</button></div>
   <p className="small">O botão copia apenas os dados fictícios de acesso. Eles não oferecem autenticação real. O registro desaparece ao recarregar. Não compartilhe a chave.</p>
   <p className={feedback ? 'editorial-feedback' : 'sr-only'} role="status">{feedback}</p>
  </section>
  <aside className="confirmation-next"><h2>A escuta precisa ter continuidade.</h2><Journey />
   <Note title="O que vem depois">{item.sharing ? 'Sua autorização foi registrada. No produto, a equipe revisará o relato e, quando cabível, preparará a versão compartilhável. Nesta demonstração, nada foi revisado ou encaminhado.' : 'Você não autorizou encaminhamento à empresa. Sua escolha foi registrada. Nenhum conteúdo foi encaminhado.'} Consulte o protocolo para acompanhar. Não há prazo garantido.</Note>
   <p>Protocolo e chave permitem voltar ao registro nesta sessão. A empresa não recebe sua chave. A perda dos dados pode impedir a consulta.</p>
  </aside>
 </main>;
}

export function WorkerCase({ onRoute }: Props) {
 const item = session.records.find(record => record.protocol === session.activeProtocol)!;
 const company = session.cases.find(entry => entry.protocol === item.protocol);
 const [complements, setComplements] = useState([...item.complement]);
 const [draft, setDraft] = useState('');
 const [reviewing, setReviewing] = useState(false);
 const [error, setError] = useState('');
 const [feedback, setFeedback] = useState('');
 const fieldRef = useRef<HTMLTextAreaElement>(null);
 const reviewRef = useRef<HTMLHeadingElement>(null);
 const feedbackRef = useRef<HTMLParagraphElement>(null);
 useEffect(() => { if (reviewing) reviewRef.current?.focus(); }, [reviewing]);
 function edit() { setReviewing(false); requestAnimationFrame(() => fieldRef.current?.focus()); }
 function confirm() {
  // Confirmação local: não publica nem encaminha conteúdo à empresa.
  if (!reviewing || !draft.trim()) return;
  item.complement.push(draft.trim());
  setComplements([...item.complement]); setDraft(''); setReviewing(false);
  setFeedback('Complemento registrado nesta sessão, aguardando revisão. Nenhuma informação foi enviada à empresa.');
  requestAnimationFrame(() => feedbackRef.current?.focus());
 }
 const history = [
  { date: item.created, title: 'Relato registrado', text: 'Situação e autorização recebidas. Protocolo fictício criado.' },
  ...(company?.published ? [
   { date: '14/10/2026', title: 'Revisão realizada', text: 'A equipe preparou uma versão compartilhável dentro da autorização.' },
   { date: '15/10/2026', title: 'Encaminhamento realizado', text: 'Somente a versão compartilhável foi encaminhada à empresa.' },
   { date: '17/10/2026', title: 'Retorno publicado', text: 'Resposta da empresa revisada pela equipe e disponibilizada neste histórico.' },
  ] : []),
 ];
 return <main className="worker-tracking" id="main-content" tabIndex={-1}>
  <div className="operational-title"><div><span className="editorial-eyebrow">Caso fictício / {item.protocol}</span><h1>Sua manifestação, em continuidade.</h1></div><span className="editorial-status">{company?.published ? 'Retorno disponível' : 'Recebida nesta sessão'}</span></div>
  <p className="tracking-meta">{item.topic} · Registro em {item.created} · Consulta demonstrativa</p>
  <Journey active={company?.published ? 3 : 0} />
  <div className="worker-case-columns">
   <section className="worker-timeline" aria-labelledby="history-heading"><h2 id="history-heading">O que já aconteceu</h2><ol>{history.map((entry, index) => <li key={entry.title}><span className={`history-marker${index === history.length - 1 ? ' current' : ''}`} aria-hidden="true">{String(index + 1).padStart(2, '0')}</span><div><span className="history-date">{entry.date} · Exemplo fictício</span><strong>{entry.title}</strong><p>{entry.text}</p></div></li>)}</ol>
    {!company?.published && <p className="small">Aguardar revisão do registro. A POC não executa revisão humana ou contato externo.</p>}
   </section>
   <section className="worker-participation" aria-label="Retorno e complemento">
    {company?.published ? <><section className="worker-published"><span className="editorial-eyebrow">Retorno publicado / 17/10/2026</span><h2>Uma proposta de encaminhamento.</h2><p>{company.published}</p><p className="small">Origem: empresa · Revisão: equipe responsável · Vinculado a este protocolo. Retorno não significa resolução.</p></section>
     <Note title="Previsto, ainda não realizado">A empresa indicou uma revisão interna dos combinados para 22/10/2026. É uma previsão sujeita a alteração, não um prazo garantido. Até esta consulta, nenhuma medida concluída foi registrada.</Note></> : <Note title="Próximo passo">O registro aguarda revisão. Sua escolha de compartilhamento foi registrada. Nenhum encaminhamento foi realizado.</Note>}
    <section className="worker-complement" aria-labelledby="complement-heading"><h2 id="complement-heading">Quer acrescentar algo?</h2><p>Seu próximo passo é ler o retorno e, se desejar, complementar. O complemento aguarda revisão; não é enviado diretamente à empresa.</p>
     {reviewing ? <section className="complement-review" aria-labelledby="complement-review-heading"><h3 id="complement-review-heading" ref={reviewRef} tabIndex={-1}>Revise seu complemento</h3><p className="complement-copy">{draft.trim()}</p><Note title="Antes de confirmar">O texto ficará somente nesta sessão, aguardando revisão. A confirmação não envia o conteúdo à empresa e não altera sua autorização de compartilhamento.</Note><div className="editorial-actions"><button className="btn" onClick={edit}>Voltar e editar complemento</button><button className="btn primary" onClick={confirm}>Confirmar complemento</button></div></section> : <form noValidate onSubmit={event => { event.preventDefault(); setFeedback(''); if (!draft.trim()) { setError('Escreva um complemento para revisar, ou continue acompanhando sem acrescentar informações.'); fieldRef.current?.focus(); return; } setError(''); setReviewing(true); }}>
      <div className="field"><label htmlFor="case-complement">Complemento · opcional</label><p id="complement-help">Evite nomes e outros detalhes identificadores. Não inclua dados reais neste protótipo.</p><textarea ref={fieldRef} id="case-complement" name="complement" value={draft} onChange={event => { setDraft(event.target.value); setError(''); }} maxLength={6000} placeholder="Conte o que precisa ser acrescentado ao caso." aria-describedby={`complement-help${error ? ' complement-error' : ''}`} aria-invalid={!!error} /></div>
      {error && <p id="complement-error" className="field-error" role="alert">{error}</p>}
      <button className="btn">Revisar complemento</button><p className="form-disclaimer">Antes de um novo compartilhamento, o conteúdo e os limites precisam de revisão. Demonstração somente nesta sessão.</p>
     </form>}
     <p role="status" ref={feedbackRef} tabIndex={-1} className={feedback ? 'editorial-feedback' : 'sr-only'}>{feedback}</p>
     {complements.map((text, index) => <article className="review-section" key={index}><strong>Complemento {index + 1} · Aguarda revisão</strong><p>{text}</p></article>)}
    </section>
   </section>
  </div>
  <Note title="Seus dados de acesso ficam com você" tone="green">Não compartilhe protocolo e chave. A empresa não acessa o relato original, identidade, contato ou chave de acesso. Por contexto, pode haver risco de reconhecimento; não há promessa de anonimato absoluto.</Note>
  <div className="editorial-actions"><button className="text-action" onClick={() => onRoute('tracking')}>← Voltar à consulta</button><details className="worker-original"><summary>Consultar meu registro e autorização</summary><p>{item.description}</p><p>{item.sharing ? 'Você autorizou uma versão compartilhável. O original não é mostrado à empresa.' : 'Você não autorizou encaminhamento à empresa.'}</p></details></div>
 </main>;
}
