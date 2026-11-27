import { useState } from 'react';
import { createWorkerComplaint, type DirectoryCompany } from '../services/data';
import { findCompanyByCnpj, lookupCnpj } from '../services/notices';
import { showToast } from '../app/toast';
import { brazilianStates, formatPhone, isValidCnpj, isValidPhone, maskCnpj, maskPhone } from '../domain/account-rules';
import { companyContactPhoneEnabled, involvementLabels, noticeConsentMissing, noticeConsentQuestion, noticeContactPayload, noticeContactsPayload, noticeTexts, noticeTextsInReview, registeredContactTexts, validateManualCompany, validateNoticeContacts, contactFilled, contactsConsentText, emptyExtraContact, maxNoticeContacts, multipleNoticeContactsEnabled, type ExtraNoticeContact, type Involvement, type NoticeConsent, type NoticeContactInput } from '../domain/company-notice';
import { brandName } from '../domain/brand';

// Assistente de nova manifestação em 9 etapas (conteúdo da POC, restaurado em 2026-10-30).
// ADR-0027 (2026-11-27): a empresa lê o texto que o trabalhador escreveu. Na revisão, o relato fica em modo leitura,
// com "Alterar relato", e "Enviar manifestação" manda o próprio relato também como versão compartilhável (shared =
// original; as duas colunas seguem separadas no banco). A equipe só libera.
// Relato, versão compartilhável e expectativas vão ao banco; respostas de contexto e contatos
// indicados ficam só nesta sessão até a aprovação do modelo de dados (ADR-0009).
// ADR-0023: a empresa é escolhida pelo CNPJ; fora da base, entra só no envio, com e-mail opcional para o aviso.
type Answer = string | string[];

export const directSendWarning = 'A empresa vai ler exatamente este texto, sem o seu nome. Antes de enviar, tire nomes, datas, setores e qualquer detalhe que identifique você ou outras pessoas.';

const contextSteps: { title: string; intro: string; fields: [string, string[]][] }[] = [
 { title: 'Seu contexto', intro: 'Antes de você falar sobre o que aconteceu, queremos entender um pouco do seu contexto.', fields: [
  ['Qual é sua relação atual com a empresa?', ['Trabalho atualmente nela', 'Trabalhei anteriormente', 'Prestador(a) / terceirizado(a)', 'Outro']],
  ['Há quanto tempo você tem ou teve vínculo?', ['Menos de 3 meses', '3 a 12 meses', '1 a 3 anos', 'Mais de 3 anos', 'Prefiro não informar']],
  ['Em qual formato você trabalha ou trabalhava?', ['Presencial', 'Híbrido', 'Remoto', 'Externo / campo', 'Outro']],
  ['Você lidera ou liderava outras pessoas?', ['Sim', 'Não', 'Prefiro não informar']]] },
 { title: 'Como está sua experiência', intro: 'Essas respostas ajudam a organizar sua experiência e não fazem parte da versão enviada à empresa.', fields: [
  ['Nas últimas semanas, com que frequência o trabalho tem causado tensão, medo, exaustão ou sobrecarga?', ['Nunca', 'Raramente', 'Às vezes', 'Frequentemente', 'Quase todos os dias']],
  ['Você sente que pode falar sobre problemas sem medo de consequências?', ['1', '2', '3', '4', '5']],
  ['Quando um problema é reportado, a empresa costuma ouvir e agir?', ['Sim', 'Às vezes', 'Raramente', 'Não', 'Nunca reportei']],
  ['Quais situações mais aparecem no seu dia a dia?', ['Sobrecarga', 'Cobrança excessiva', 'Conflitos', 'Assédio ou humilhação', 'Falta de apoio', 'Metas incompatíveis', 'Falta de autonomia', 'Jornada excessiva']]] },
 { title: 'Por que você veio até aqui', intro: 'Situações sensíveis recebem revisão com cuidado adicional.', fields: [
  ['O que melhor descreve o motivo de você estar aqui hoje?', ['Quero relatar algo que aconteceu comigo', 'Presenciei algo acontecendo com outra pessoa', 'É um problema recorrente na equipe', 'Quero registrar um alerta antes que piore', 'Outro']],
  ['Isso ainda está acontecendo?', ['Sim', 'Não', 'Não sei']],
  ['Você sente que há risco imediato para você ou outra pessoa?', ['Sim', 'Não', 'Não tenho certeza']]] },
 { title: 'Confiança e expectativa', intro: 'Queremos entender o que você espera desse acompanhamento.', fields: [
  ['Se a empresa recebesse uma versão revisada do seu relato, sem seu nome e seus contatos, isso ajudaria?', ['1', '2', '3', '4', '5']],
  ['O que você espera que aconteça depois de enviar um relato?', ['Quero apenas ser ouvido(a)', 'Quero que a empresa dê um retorno', 'Quero que a empresa investigue internamente', 'Quero que o problema não aconteça com outras pessoas', 'Quero acompanhar providências']]] },
];
const themes = ['Sobrecarga / excesso de trabalho', 'Pressão ou cobrança excessiva', 'Assédio / humilhação', 'Conflito com liderança', 'Conflito com colegas', 'Falta de apoio', 'Jornada / disponibilidade', 'Discriminação', 'Insegurança / medo de demissão', 'Outro'];
const expectations = ['Apenas registrar', 'Receber uma resposta', 'Que a empresa investigue', 'Que alguma prática seja revista', 'Que haja acompanhamento', 'Outro'];
const multiple = (step: number, question: number) => (step === 1 && question === 3) || (step === 3 && question === 1);

export function isBrazilianPhone(value: string): boolean {
 return isValidPhone(value);
}

function OptionGrid({ label, options, value, onSelect }: { label: string; options: string[]; value: Answer | undefined; onSelect: (option: string) => void }) {
 return <div className="option-grid" role="group" aria-label={label}>{options.map(option => {
  const selected = Array.isArray(value) ? value.includes(option) : value === option;
  return <button key={option} type="button" className={`option${selected ? ' selected' : ''}`} aria-pressed={selected} onClick={() => onSelect(option)}>{option}</button>;
 })}</div>;
}

interface ChosenCompany { id: string; name: string; city: string; state: string }
// Empresa não achada entre as cadastradas (ADR-0023): vai por CNPJ no create_complaint, que a cria no envio ("grava quando relatar").
interface PendingCompany { cnpj: string; name: string; city: string; state: string; source: 'lookup' | 'manual' }
type CompanyPhase = 'input' | 'searching' | 'found' | 'lookup' | 'manual' | 'legacy';

function LegacyCompanySearch({ companies, onChoose }: { companies: DirectoryCompany[]; onChoose: (company: ChosenCompany) => void }) {
 const [search, setSearch] = useState('');
 const listed = companies.filter(item => `${item.name} ${item.city} ${item.state}`.toLowerCase().includes(search.toLowerCase()));
 return <><label className="field worker-company-search">Empresa<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome ou cidade" autoFocus /></label>
  {listed.length ? <div className="worker-company-list">{listed.map(item => <article key={item.id} className="worker-company-row"><div><strong>{item.name}</strong><small>{item.city}/{item.state}</small></div><button className="btn primary" onClick={() => onChoose(item)}>É sobre esta empresa</button></article>)}</div>
   : <p className="muted">Nenhuma empresa encontrada. Nesta versão, só empresas cadastradas podem receber manifestações.</p>}</>;
}

function CompanyStep({ companies, onChoose, onPending, onCancel }: { companies: DirectoryCompany[]; onChoose: (company: ChosenCompany) => void; onPending: (company: PendingCompany) => void; onCancel: () => void }) {
 const [cnpj, setCnpj] = useState('');
 const [phase, setPhase] = useState<CompanyPhase>('input');
 const [found, setFound] = useState<ChosenCompany | null>(null);
 const [manual, setManual] = useState({ name: '', city: '', state: '' });
 const [error, setError] = useState('');
 async function search(event: React.FormEvent) {
  event.preventDefault();
  if (!isValidCnpj(cnpj)) return setError('Confira o CNPJ: são 14 caracteres com os dígitos verificadores.');
  setError(''); setPhase('searching');
  const result = await findCompanyByCnpj(cnpj);
  if (result.missing) return setPhase('legacy');
  if (!result.ok) { setPhase('input'); return showToast('error', result.message); }
  if (result.company) { setFound(result.company); return setPhase('found'); }
  const lookup = await lookupCnpj(cnpj);
  if (lookup.kind === 'found') { setFound({ id: '', ...lookup.company }); return setPhase('lookup'); }
  setPhase('manual');
 }
 function continueManual() {
  const problem = validateManualCompany(manual.name, manual.city, manual.state);
  if (problem) return setError(problem);
  onPending({ cnpj, name: manual.name.trim(), city: manual.city.trim(), state: manual.state.toUpperCase(), source: 'manual' });
 }
 const reset = () => { setPhase('input'); setFound(null); setError(''); };
 const errorLine = error && <p className="field-error" role="alert">{error}</p>;
 let body;
 if (phase === 'legacy') body = <LegacyCompanySearch companies={companies} onChoose={onChoose} />;
 else if ((phase === 'found' || phase === 'lookup') && found) body = <><div className="worker-company-list"><article className="worker-company-row"><div><strong>{found.name}</strong><small>{found.city}/{found.state} · CNPJ {maskCnpj(cnpj)}</small></div>
   <button className="btn primary" onClick={() => phase === 'found' ? onChoose(found) : onPending({ cnpj, name: found.name, city: found.city, state: found.state, source: 'lookup' })}>É sobre esta empresa</button></article></div>
  {phase === 'lookup' && <p className="muted small">Os dados desta empresa só são usados quando você enviar a manifestação.</p>}
  <div className="nav-actions"><button className="btn" type="button" onClick={reset}>Buscar outro CNPJ</button></div></>;
 else if (phase === 'manual') body = <div className="cnpj-search"><p className="muted">Não encontramos os dados deste CNPJ automaticamente. Preencha o nome e a cidade da empresa; a equipe confere na Receita Federal antes de qualquer aviso.</p>
  <label className="field">Nome da empresa<input value={manual.name} maxLength={160} onChange={event => { setManual({ ...manual, name: event.target.value }); setError(''); }} placeholder="Razão social ou nome conhecido" /></label>
  <div className="grid two"><label className="field">Município<input value={manual.city} maxLength={80} onChange={event => { setManual({ ...manual, city: event.target.value }); setError(''); }} /></label>
   <label className="field">UF<select value={manual.state} onChange={event => { setManual({ ...manual, state: event.target.value }); setError(''); }}><option value="">Selecione</option>{brazilianStates.map(uf => <option key={uf} value={uf}>{uf}</option>)}</select></label></div>
  <p className="muted small">Os dados desta empresa só são usados quando você enviar a manifestação.</p>
  {errorLine}<div className="nav-actions cnpj-actions"><button className="btn" type="button" onClick={reset}>Buscar outro CNPJ</button><button className="btn primary" type="button" onClick={continueManual}>Continuar</button></div></div>;
 else body = <form className="cnpj-search" onSubmit={search} noValidate><div className="cnpj-search-row"><label className="field worker-company-search">CNPJ da empresa<input value={cnpj} inputMode="text" maxLength={18} autoFocus placeholder="00.000.000/0000-00" onChange={event => { setCnpj(maskCnpj(event.target.value)); setError(''); }} /></label>
  <button className="btn primary" type="submit" disabled={phase === 'searching'}>{phase === 'searching' ? 'Buscando…' : 'Buscar empresa'}</button></div>
  <p className="muted small">Você encontra o CNPJ no contracheque, no contrato ou no site da empresa.</p>
  {errorLine}</form>;
 return <><button className="text-action worker-back" onClick={onCancel}>← Voltar</button>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Nova manifestação</span><h2>{phase === 'legacy' ? 'Pesquisar empresa' : 'Qual é o CNPJ da empresa?'}</h2><p className="muted">{phase === 'legacy' ? 'Digite o nome ou a cidade da empresa relacionada ao relato.' : 'Digite o CNPJ da empresa relacionada ao relato.'}</p></div></div>
  {body}</>;
}

export function ComplaintWizard({ companies, initialCompanyId = '', onCancel, onCreated }: { companies: DirectoryCompany[]; initialCompanyId?: string; onCancel: () => void; onCreated: () => void }) {
 const initial = companies.find(item => item.id === initialCompanyId);
 const [chosen, setChosen] = useState<ChosenCompany | null>(initial ? { id: initial.id, name: initial.name, city: initial.city, state: initial.state } : null);
 const [pending, setPending] = useState<PendingCompany | null>(null);
 const [step, setStep] = useState(0);
 const [answers, setAnswers] = useState<Record<string, Answer>>({});
 const [draft, setDraft] = useState({ category: '', title: '', original: '', incidentPeriod: '', recurrence: '', expectedOutcomes: [] as string[] });
 const [notice, setNotice] = useState<NoticeContactInput>({ email: '', involvement: '', consent: false });
 const [noticeConsent, setNoticeConsent] = useState<NoticeConsent>('');
 // Contatos 2 e 3 (até 3 por manifestação). Só aparecem com multipleNoticeContactsEnabled, ligado com o contrato do Back.
 const [extraContacts, setExtraContacts] = useState<ExtraNoticeContact[]>([]);
 const [error, setError] = useState('');
 const [busy, setBusy] = useState(false);
 // Edição no lugar, na revisão: rascunho separado até "Salvar alterações".
 const [editing, setEditing] = useState<{ title: string; original: string } | null>(null);
 const set = (key: keyof typeof draft, value: string | string[]) => setDraft(current => ({ ...current, [key]: value }));
 const go = (next: number) => { setError(''); setStep(next); window.scrollTo({ top: 0 }); };

 if (!chosen && !pending) return <CompanyStep companies={companies} onCancel={onCancel} onChoose={company => { setChosen(company); setStep(0); }} onPending={company => { setPending(company); setStep(0); }} />;
 const companyName = chosen?.name ?? pending?.name ?? '';
 // O e-mail do aviso é oferecido para toda empresa não achada entre as cadastradas, inclusive uma pré-cadastrada que já existe.
 // Contato na empresa em toda manifestação (decisão do responsável, 2026-11-19): aviso para a não cadastrada,
 // segundo canal só da equipe para a cadastrada.
 const keys = [...contextSteps.map(() => 'context'), 'theme', 'report', 'notice', 'expect', 'review'];
 const registered = !pending;
 const key = keys[step];
 const titles: Record<string, string> = { theme: 'Tema', report: 'Relato', notice: pending ? 'Aviso à empresa' : 'Contato na empresa', expect: 'O que você espera', review: 'Revise seu relato' };
 const total = keys.length;

 function select(question: number, option: string) {
  const answerKey = `${step}-${question}`;
  setAnswers(all => {
   const current = all[answerKey];
   const value = multiple(step, question) ? (Array.isArray(current) ? (current.includes(option) ? current.filter(item => item !== option) : [...current, option]) : [option]) : option;
   return { ...all, [answerKey]: value };
  });
  setError('');
 }
 function next() {
  if (key === 'context' && contextSteps[step].fields.some((_, index) => { const value = answers[`${step}-${index}`]; return !value || (Array.isArray(value) && !value.length); })) return setError('Responda todas as perguntas desta etapa para continuar.');
  if (key === 'theme' && !draft.category) return setError('Escolha o tema que melhor descreve o que aconteceu.');
  if (key === 'report' && draft.title.trim().length < 3) return setError('Dê um título curto ao relato (pelo menos 3 caracteres).');
  if (key === 'report' && draft.original.trim().length < 10) return setError('Conte o que aconteceu com pelo menos 10 caracteres.');
  if (key === 'notice') {
   if (!registered && !noticeConsent) return setError(noticeConsentMissing);
   const problem = validateNoticeContacts(notice, multipleNoticeContactsEnabled ? extraContacts : [], registered); if (problem) return setError(problem);
  }
  if (key === 'expect' && !draft.expectedOutcomes.length) return setError('Escolha pelo menos uma expectativa.');
  go(step + 1);
 }
 function saveEdit() {
  if (!editing) return;
  if (editing.title.trim().length < 3) return setError('Dê um título curto ao relato (pelo menos 3 caracteres).');
  if (editing.original.trim().length < 10) return setError('Conte o que aconteceu com pelo menos 10 caracteres.');
  setDraft(current => ({ ...current, title: editing.title, original: editing.original })); setEditing(null); setError('');
 }
 async function submit() {
  if (editing) return setError('Salve ou cancele a alteração do relato antes de enviar.');
  if (draft.original.trim().length < 10) return setError('Conte o que aconteceu com pelo menos 10 caracteres.');
  setBusy(true);
  // Contrato final da ADR-0023: cadastrada vai por company_id; fora da base, por CNPJ, e o create_complaint cria a empresa.
  // company_manual vai sempre que a cnpj-lookup não respondeu found.
  const company = chosen ? { companyId: chosen.id } : { companyId: '', companyCnpj: pending?.cnpj ?? '', companyManual: pending?.source === 'manual' ? { name: pending.name, city: pending.city, state: pending.state } : null };
  const result = await createWorkerComplaint({ ...company, category: draft.category, title: draft.title, original: draft.original, shared: draft.original, incidentPeriod: draft.incidentPeriod.slice(0, 80), recurrence: draft.recurrence.slice(0, 80), expectedOutcomes: draft.expectedOutcomes, ...(multipleNoticeContactsEnabled ? { noticeContacts: noticeContactsPayload(notice, extraContacts, registered), noticeContact: null } : { noticeContact: noticeContactPayload(notice, registered) }), noticeConsent: registered ? null : noticeConsent === 'yes' }, true);
  setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', 'Manifestação enviada. A equipe confere e libera para a empresa.'); onCreated();
 }

 const errorLine = error && <p className="field-error" role="alert">{error}</p>;
 const back = <button className="btn" type="button" onClick={() => { if (step > 0) return go(step - 1); setChosen(null); setPending(null); }}>Voltar</button>;
 const involved = notice.involvement === 'yes' || notice.involvement === 'unknown';
 let body;
 if (key === 'context') {
  const current = contextSteps[step];
  body = <><span className="eyebrow">Contexto desta manifestação</span><h2>{current.title}</h2><p className="muted">{current.intro} Responda pensando especificamente na empresa selecionada e na situação que você vai relatar.</p>
   {current.fields.map(([label, options], index) => <div className="field" key={label}><label>{label}{multiple(step, index) && <span className="muted small"> (selecione uma ou mais)</span>}</label><OptionGrid label={label} options={options} value={answers[`${step}-${index}`]} onSelect={option => select(index, option)} />
    {step === 2 && index === 2 && <div className="notice warn small">Se houver risco imediato para você ou outra pessoa, procure agora ajuda: CVV 188 (apoio emocional, 24 horas), SAMU 192 ou Polícia Militar 190. A {brandName} não é canal de emergência e não acompanha casos em tempo real. Nenhum contato com a empresa é feito de forma automática.</div>}</div>)}
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Continuar</button></div></>;
 } else if (key === 'theme') {
  body = <><h2>O que melhor descreve o que aconteceu?</h2><OptionGrid label="Tema" options={themes} value={draft.category} onSelect={option => { set('category', option); setError(''); }} />
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Continuar</button></div></>;
 } else if (key === 'report') {
  body = <><h2>Conte o que aconteceu do seu jeito.</h2><p className="muted">Você não precisa escrever de forma perfeita. Explique como se estivesse contando para alguém de confiança.</p>
   <div className="notice">Evite colocar seu nome, telefone, e-mail ou informações que facilitem sua identificação. A empresa vai ler o texto que você escrever, sem o seu nome.</div>
   <label className="field">Título curto<input value={draft.title} maxLength={140} onChange={event => set('title', event.target.value)} placeholder="Ex.: Sobrecarga e cobranças fora do horário" /></label>
   <label className="field">Relato<textarea rows={7} maxLength={5000} value={draft.original} onChange={event => set('original', event.target.value)} /></label>
   <div className="grid two"><label className="field">Quando isso aconteceu? (opcional)<input value={draft.incidentPeriod} maxLength={80} onChange={event => set('incidentPeriod', event.target.value)} placeholder="Ex.: Últimas semanas" /></label><label className="field">Isso é recorrente? (opcional)<input value={draft.recurrence} maxLength={80} onChange={event => set('recurrence', event.target.value)} placeholder="Ex.: Recorrente" /></label></div>
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Continuar</button></div></>;
 } else if (key === 'notice') {
  const update = (next: Partial<NoticeContactInput>) => { setNotice(current => ({ ...current, ...next })); setError(''); };
  const filled = Boolean(notice.email.trim() || (companyContactPhoneEnabled && (notice.phone ?? '').replace(/\D/g, '')));
  body = <><h2>{registered ? 'Contato na empresa' : 'Aviso à empresa'}</h2><p className="muted">{registered ? registeredContactTexts.intro : `Esta empresa ainda não usa a ${brandName}. Diga se autoriza a equipe a avisar a empresa de que existe um relato. Se quiser, indique também um contato da empresa, como o RH. Sem contato, a equipe pode usar o e-mail público da empresa na Receita Federal, só com a sua autorização.`}</p>
   {noticeTextsInReview && <p className="legal-review-banner">Texto em revisão jurídica.</p>}
   {!registered && <fieldset className="response-rating"><legend>{noticeConsentQuestion}</legend>
    <label className="check-row"><input type="radio" name="notice-consent" value="yes" checked={noticeConsent === 'yes'} onChange={() => { setNoticeConsent('yes'); setError(''); }} /> <span>Sim</span></label>
    <label className="check-row"><input type="radio" name="notice-consent" value="no" checked={noticeConsent === 'no'} onChange={() => { setNoticeConsent('no'); setError(''); }} /> <span>Não</span></label></fieldset>}
   {!registered && noticeConsent === 'no' && <div className="notice small">Nenhum aviso será enviado à empresa. Um contato que você indicar fica só com a equipe, como segundo canal.</div>}
   <div className="field"><label htmlFor="notice-email">{registered ? registeredContactTexts.email : noticeTexts.field}</label><input id="notice-email" type="email" maxLength={254} autoComplete="off" value={notice.email} onChange={event => update({ email: event.target.value })} placeholder="rh@empresa.com.br" aria-describedby="notice-help" /><small id="notice-help" className="muted">{noticeTexts.help}</small></div>
   {companyContactPhoneEnabled && <div className="field"><label htmlFor="notice-phone">{registeredContactTexts.phone}</label><input id="notice-phone" type="tel" inputMode="tel" maxLength={15} autoComplete="off" placeholder="(00) 00000-0000" value={notice.phone ?? ''} onChange={event => update({ phone: maskPhone(event.target.value) })} /></div>}
   {filled && <>
    <fieldset className="response-rating"><legend>{noticeTexts.question}</legend>{(Object.keys(involvementLabels) as Exclude<Involvement, ''>[]).map(value => <label key={value} className="check-row"><input type="radio" name="notice-involvement" value={value} checked={notice.involvement === value} onChange={() => update({ involvement: value })} /> <span>{involvementLabels[value]}</span></label>)}</fieldset>
    {involved && <div className="notice warn small">{registered ? 'Com essa resposta, a equipe não usa esse contato.' : noticeTexts.involvedWarning}</div>}
   </>}
   {multipleNoticeContactsEnabled && extraContacts.map((extra, index) => {
    const number = index + 2;
    const change = (next: Partial<ExtraNoticeContact>) => { setExtraContacts(list => list.map((item, position) => position === index ? { ...item, ...next } : item)); setError(''); };
    const extraInvolved = extra.involvement === 'yes' || extra.involvement === 'unknown';
    return <fieldset className="notice-contact" key={index}><legend>Contato {number}</legend>
     <div className="field"><label htmlFor={`notice-email-${number}`}>{registered ? registeredContactTexts.email : noticeTexts.field}</label><input id={`notice-email-${number}`} type="email" maxLength={254} autoComplete="off" value={extra.email} onChange={event => change({ email: event.target.value })} placeholder="rh@empresa.com.br" /></div>
     {companyContactPhoneEnabled && <div className="field"><label htmlFor={`notice-phone-${number}`}>{registeredContactTexts.phone}</label><input id={`notice-phone-${number}`} type="tel" inputMode="tel" maxLength={15} autoComplete="off" placeholder="(00) 00000-0000" value={extra.phone} onChange={event => change({ phone: maskPhone(event.target.value) })} /></div>}
     {contactFilled(extra) && <fieldset className="response-rating"><legend>{noticeTexts.question}</legend>{(Object.keys(involvementLabels) as Exclude<Involvement, ''>[]).map(value => <label key={value} className="check-row"><input type="radio" name={`notice-involvement-${number}`} value={value} checked={extra.involvement === value} onChange={() => change({ involvement: value })} /> <span>{involvementLabels[value]}</span></label>)}</fieldset>}
     {extraInvolved && <div className="notice warn small">{registered ? 'Com essa resposta, a equipe não usa esse contato.' : noticeTexts.involvedWarning}</div>}
     <button className="btn" type="button" onClick={() => { setExtraContacts(list => list.filter((_, position) => position !== index)); setError(''); }}>Remover contato {number}</button>
    </fieldset>;
   })}
   {multipleNoticeContactsEnabled && filled && extraContacts.length < maxNoticeContacts - 1 && <button className="btn" type="button" onClick={() => setExtraContacts(list => [...list, emptyExtraContact()])}>Adicionar outro contato</button>}
   {(filled || (multipleNoticeContactsEnabled && extraContacts.some(contactFilled))) && <label className="check-row"><input type="checkbox" checked={notice.consent} onChange={event => update({ consent: event.target.checked })} /> <span>{contactsConsentText([notice, ...(multipleNoticeContactsEnabled ? extraContacts : [])].filter(contactFilled).length)}</span></label>}
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Continuar</button></div></>;
 } else if (key === 'expect') {
  body = <><h2>O que você espera?</h2><OptionGrid label="O que você espera" options={expectations} value={draft.expectedOutcomes} onSelect={option => { setDraft(current => ({ ...current, expectedOutcomes: current.expectedOutcomes.includes(option) ? current.expectedOutcomes.filter(item => item !== option) : [...current.expectedOutcomes, option] })); setError(''); }} />
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Revisar relato</button></div></>;
 } else {
  const contact = noticeContactPayload(notice, registered);
  const contacts = multipleNoticeContactsEnabled ? noticeContactsPayload(notice, extraContacts, registered) : contact ? [contact] : [];
  const contactLabel = (item: { email?: string; phone?: string }) => [item.email, item.phone ? formatPhone(item.phone) : ''].filter(Boolean).join(' · ');
  body = <><h2>Revise seu relato</h2><p className="muted">Confira o texto antes de enviar. A equipe confere e libera para a empresa.</p>
   {editing ? <div className="text-panel review-edit">
     <label className="field">Título curto<input value={editing.title} maxLength={140} onChange={event => { setEditing({ ...editing, title: event.target.value }); setError(''); }} /></label>
     <label className="field">Relato<textarea rows={8} maxLength={5000} value={editing.original} onChange={event => { setEditing({ ...editing, original: event.target.value }); setError(''); }} /></label>
     <div className="nav-actions"><button className="btn" type="button" onClick={() => { setEditing(null); setError(''); }}>Cancelar</button><button className="btn primary" type="button" onClick={saveEdit}>Salvar alterações</button></div></div>
    : <div className="text-panel review-read"><h3>{draft.title}</h3><p className="review-text">{draft.original}</p>
     <button className="btn" type="button" onClick={() => { setEditing({ title: draft.title, original: draft.original }); setError(''); }}>Alterar relato</button></div>}
   {contacts.length ? <div className="muted small"><p>{registered ? (contacts.length > 1 ? 'Contatos na empresa (só a equipe vê)' : 'Contato na empresa (só a equipe vê)') : (contacts.length > 1 ? 'Contatos para o aviso à empresa' : 'Aviso à empresa')}:</p>
    <ul className="notice-contact-list">{contacts.map((item, index) => <li key={index}>{contactLabel(item)}.{' '}{item.possibly_involved ? (registered ? 'Com a sua resposta, a equipe não usa esse contato.' : noticeTexts.involvedWarning) : registered ? '' : 'A equipe confere o e-mail antes de decidir pelo envio.'}</li>)}</ul>
    {/* ADR-0027: sem "guardar sem compartilhar", o aviso de notSharedWarning (em revisão jurídica) não se aplica aqui. */}
    <p>{contacts.length > 1 ? 'Os contatos só são guardados' : 'O contato só é guardado'} quando você envia a manifestação.</p></div> : <p className="muted small">{registered ? 'Nenhum contato na empresa indicado.' : 'Nenhum contato indicado.'}</p>}
   {!registered && <p className="muted small">{noticeConsent === 'yes' ? 'Você autorizou o aviso à empresa, que sai só depois da revisão da equipe.' : 'Você não autorizou o aviso: nada será enviado à empresa.'} A autorização só é guardada quando você envia a manifestação.</p>}
   <p className="muted small">As respostas de contexto ficam só nesta tela e não são armazenadas.</p>
   <div className="notice warn direct-send-warning" role="note">{directSendWarning}</div>
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" disabled={busy || Boolean(editing)} onClick={submit}>{busy ? 'Enviando…' : 'Enviar manifestação'}</button></div></>;
 }
 const stepTitle = key === 'context' ? contextSteps[step].title : titles[key];
 return <><button className="text-action worker-back" onClick={onCancel}>← Voltar</button>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Nova manifestação</span><h2>Nova manifestação</h2><p className="muted">Empresa selecionada: <strong>{companyName}</strong>.</p></div></div>
  {/* Design P1.5: um indicador de progresso só (texto na barra) e o aviso de emergência em faixa discreta, em todas as etapas. */}
  <section className="wizard-box"><div className="wizard-progress"><p className="wizard-progress-label">Etapa {step + 1} de {total} · {stepTitle}</p><div className="progress" aria-hidden="true"><span style={{ width: `${(step + 1) / total * 100}%` }} /></div></div>
   <p className="wizard-emergency" role="note">Em caso de risco imediato, procure ajuda: CVV 188, SAMU 192 ou Polícia Militar 190. A {brandName} não é um canal de emergência.</p>{body}</section></>;
}
