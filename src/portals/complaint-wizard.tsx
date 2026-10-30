import { useState } from 'react';
import { createWorkerComplaint, type DirectoryCompany } from '../services/data';
import { showToast } from '../app/toast';

// Assistente de nova manifestação em 9 etapas (conteúdo da POC, restaurado em 2026-10-30).
// Relato, versão compartilhável e expectativas vão ao banco; respostas de contexto e contatos
// indicados ficam só nesta sessão até a aprovação do modelo de dados (ADR-0009).
type Answer = string | string[];
interface Contact { name: string; role: string; email: string; phone: string }

const contextSteps: { title: string; intro: string; fields: [string, string[]][] }[] = [
 { title: 'Seu contexto', intro: 'Antes de você falar sobre o que aconteceu, queremos entender um pouco do seu contexto.', fields: [
  ['Qual é sua relação atual com a empresa?', ['Trabalho atualmente nela', 'Trabalhei anteriormente', 'Prestador(a) / terceirizado(a)', 'Outro']],
  ['Há quanto tempo você tem ou teve vínculo?', ['Menos de 3 meses', '3 a 12 meses', '1 a 3 anos', 'Mais de 3 anos', 'Prefiro não informar']],
  ['Em qual formato você trabalha ou trabalhava?', ['Presencial', 'Híbrido', 'Remoto', 'Externo / campo', 'Outro']],
  ['Você lidera ou liderava outras pessoas?', ['Sim', 'Não', 'Prefiro não informar']]] },
 { title: 'Como está sua experiência', intro: 'Essas respostas ajudam a organizar sua experiência sem revelar quem você é.', fields: [
  ['Nas últimas semanas, com que frequência o trabalho tem causado tensão, medo, exaustão ou sobrecarga?', ['Nunca', 'Raramente', 'Às vezes', 'Frequentemente', 'Quase todos os dias']],
  ['Você sente que pode falar sobre problemas sem medo de consequências?', ['1', '2', '3', '4', '5']],
  ['Quando um problema é reportado, a empresa costuma ouvir e agir?', ['Sim', 'Às vezes', 'Raramente', 'Não', 'Nunca reportei']],
  ['Quais situações mais aparecem no seu dia a dia?', ['Sobrecarga', 'Cobrança excessiva', 'Conflitos', 'Assédio ou humilhação', 'Falta de apoio', 'Metas incompatíveis', 'Falta de autonomia', 'Jornada excessiva']]] },
 { title: 'Por que você veio até aqui', intro: 'Situações sensíveis recebem revisão com cuidado adicional.', fields: [
  ['O que melhor descreve o motivo de você estar aqui hoje?', ['Quero relatar algo que aconteceu comigo', 'Presenciei algo acontecendo com outra pessoa', 'É um problema recorrente na equipe', 'Quero registrar um alerta antes que piore', 'Outro']],
  ['Isso ainda está acontecendo?', ['Sim', 'Não', 'Não sei']],
  ['Você sente que há risco imediato para você ou outra pessoa?', ['Sim', 'Não', 'Não tenho certeza']]] },
 { title: 'Confiança e expectativa', intro: 'Queremos entender o que você espera desse acompanhamento.', fields: [
  ['Se a empresa pudesse receber seu relato sem saber quem você é, isso ajudaria?', ['1', '2', '3', '4', '5']],
  ['O que você espera que aconteça depois de enviar um relato?', ['Quero apenas ser ouvido(a)', 'Quero que a empresa dê um retorno', 'Quero que a empresa investigue internamente', 'Quero que o problema não aconteça com outras pessoas', 'Quero acompanhar providências']]] },
];
const stepTitles = [...contextSteps.map(step => step.title), 'Tema', 'Relato', 'Formas de comunicação', 'O que você espera', 'Revisão protegida'];
const themes = ['Sobrecarga / excesso de trabalho', 'Pressão ou cobrança excessiva', 'Assédio / humilhação', 'Conflito com liderança', 'Conflito com colegas', 'Falta de apoio', 'Jornada / disponibilidade', 'Discriminação', 'Insegurança / medo de demissão', 'Outro'];
const expectations = ['Apenas registrar', 'Receber uma resposta', 'Que a empresa investigue', 'Que alguma prática seja revista', 'Que haja acompanhamento', 'Outro'];
const multiple = (step: number, question: number) => (step === 1 && question === 3) || (step === 3 && question === 1);
const emptyContact: Contact = { name: '', role: '', email: '', phone: '' };

export function isBrazilianPhone(value: string): boolean {
 let digits = value.trim().replace(/\D/g, '');
 if ((digits.length === 12 || digits.length === 13) && digits.startsWith('55')) digits = digits.slice(2);
 return /^[1-9]\d/.test(digits) && (/^\d{2}[2-5]\d{7}$/.test(digits) || /^\d{2}9\d{8}$/.test(digits));
}

function OptionGrid({ label, options, value, onSelect }: { label: string; options: string[]; value: Answer | undefined; onSelect: (option: string) => void }) {
 return <div className="option-grid" role="group" aria-label={label}>{options.map(option => {
  const selected = Array.isArray(value) ? value.includes(option) : value === option;
  return <button key={option} type="button" className={`option${selected ? ' selected' : ''}`} aria-pressed={selected} onClick={() => onSelect(option)}>{option}</button>;
 })}</div>;
}

export function ComplaintWizard({ companies, initialCompanyId = '', onCancel, onCreated }: { companies: DirectoryCompany[]; initialCompanyId?: string; onCancel: () => void; onCreated: () => void }) {
 const [companyId, setCompanyId] = useState(initialCompanyId);
 const [search, setSearch] = useState('');
 const [step, setStep] = useState(0);
 const [answers, setAnswers] = useState<Record<string, Answer>>({});
 const [draft, setDraft] = useState({ category: '', title: '', original: '', incidentPeriod: '', recurrence: '', shared: '', expectedOutcomes: [] as string[] });
 const [contacts, setContacts] = useState<Contact[]>([]);
 const [contact, setContact] = useState<Contact>(emptyContact);
 const [error, setError] = useState('');
 const [reviewed, setReviewed] = useState(false);
 const [busy, setBusy] = useState(false);
 const company = companies.find(item => item.id === companyId);
 const set = (key: keyof typeof draft, value: string | string[]) => setDraft(current => ({ ...current, [key]: value }));
 const go = (next: number) => { setError(''); setStep(next); window.scrollTo({ top: 0 }); };

 if (!company) {
  const listed = companies.filter(item => `${item.name} ${item.city} ${item.state}`.toLowerCase().includes(search.toLowerCase()));
  return <><button className="text-action worker-back" onClick={onCancel}>← Voltar</button>
   <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Nova manifestação</span><h2>Pesquisar empresa</h2><p className="muted">Digite o nome ou a cidade da empresa relacionada ao relato.</p></div></div>
   <label className="field worker-company-search">Empresa<input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome ou cidade" autoFocus /></label>
   {listed.length ? <div className="worker-company-list">{listed.map(item => <article key={item.id} className="worker-company-row"><div><strong>{item.name}</strong><small>{item.city}/{item.state}</small></div><button className="btn primary" onClick={() => setCompanyId(item.id)}>É sobre esta empresa</button></article>)}</div>
    : <p className="muted">Nenhuma empresa encontrada. Nesta versão, só empresas cadastradas podem receber manifestações.</p>}</>;
 }

 function select(question: number, option: string) {
  const key = `${step}-${question}`;
  setAnswers(all => {
   const current = all[key];
   const value = multiple(step, question) ? (Array.isArray(current) ? (current.includes(option) ? current.filter(item => item !== option) : [...current, option]) : [option]) : option;
   return { ...all, [key]: value };
  });
  setError('');
 }
 function next() {
  if (step < contextSteps.length && contextSteps[step].fields.some((_, index) => { const value = answers[`${step}-${index}`]; return !value || (Array.isArray(value) && !value.length); })) return setError('Responda todas as perguntas desta etapa para continuar.');
  if (step === 4 && !draft.category) return setError('Escolha o tema que melhor descreve o que aconteceu.');
  if (step === 5 && draft.title.trim().length < 3) return setError('Dê um título curto ao relato (pelo menos 3 caracteres).');
  if (step === 5 && draft.original.trim().length < 10) return setError('Conte o que aconteceu com pelo menos 10 caracteres.');
  if (step === 7 && !draft.expectedOutcomes.length) return setError('Escolha pelo menos uma expectativa.');
  if (step === 7 && !reviewed) { set('shared', draft.original); setReviewed(true); }
  go(step + 1);
 }
 function addContact() {
  const value = { name: contact.name.trim(), role: contact.role.trim(), email: contact.email.trim(), phone: contact.phone.trim() };
  if (!value.name || !value.email || !value.phone || !value.role) return setError('Preencha nome, e-mail, telefone e cargo do contato.');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/i.test(value.email) || !isBrazilianPhone(value.phone)) return setError('Digite um e-mail profissional válido e um telefone brasileiro com DDD.');
  if (contacts.some(item => item.email.toLowerCase() === value.email.toLowerCase() || item.phone.replace(/\D/g, '') === value.phone.replace(/\D/g, ''))) return setError('Este contato já foi adicionado.');
  setContacts([...contacts, value]); setContact(emptyContact); setError('');
 }
 async function submit(share: boolean) {
  if (share && draft.shared.trim().length < 10) return setError('Revise a versão que a empresa vai ler (pelo menos 10 caracteres).');
  setBusy(true);
  const result = await createWorkerComplaint({ companyId, category: draft.category, title: draft.title, original: draft.original, shared: share ? draft.shared : '', incidentPeriod: draft.incidentPeriod.slice(0, 80), recurrence: draft.recurrence.slice(0, 80), expectedOutcomes: draft.expectedOutcomes }, share);
  setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  showToast('success', share ? 'Manifestação registrada e enviada à empresa.' : 'Manifestação guardada. Você pode compartilhar depois.'); onCreated();
 }

 const errorLine = error && <p className="field-error" role="alert">{error}</p>;
 const back = <button className="btn" type="button" onClick={() => step === 0 ? setCompanyId('') : go(step - 1)}>Voltar</button>;
 let body;
 if (step < contextSteps.length) {
  const current = contextSteps[step];
  body = <><span className="eyebrow">Contexto desta manifestação</span><h2>{current.title}</h2><p className="muted">{current.intro} Responda pensando especificamente na empresa selecionada e na situação que você vai relatar.</p>
   {current.fields.map(([label, options], index) => <div className="field" key={label}><label>{label}{multiple(step, index) && <span className="muted small"> (selecione uma ou mais)</span>}</label><OptionGrid label={label} options={options} value={answers[`${step}-${index}`]} onSelect={option => select(index, option)} />
    {step === 2 && index === 2 && <div className="notice warn small">Situações de risco imediato recebem atenção humana. Não faremos contato externo automático em casos de alto risco.</div>}</div>)}
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Continuar</button></div></>;
 } else if (step === 4) {
  body = <><h2>O que melhor descreve o que aconteceu?</h2><OptionGrid label="Tema" options={themes} value={draft.category} onSelect={option => { set('category', option); setError(''); }} />
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Continuar</button></div></>;
 } else if (step === 5) {
  body = <><h2>Conte o que aconteceu do seu jeito.</h2><p className="muted">Você não precisa escrever de forma perfeita. Explique como se estivesse contando para alguém de confiança.</p>
   <div className="notice">Evite colocar seu nome, telefone, e-mail ou informações que facilitem sua identificação. Antes de enviar, você revisa a versão que a empresa vai ler.</div>
   <label className="field">Título curto<input value={draft.title} maxLength={140} onChange={event => set('title', event.target.value)} placeholder="Ex.: Sobrecarga e cobranças fora do horário" /></label>
   <label className="field">Relato<textarea rows={7} maxLength={5000} value={draft.original} onChange={event => { set('original', event.target.value); setReviewed(false); }} /></label>
   <div className="grid two"><label className="field">Quando isso aconteceu?<input value={draft.incidentPeriod} maxLength={80} onChange={event => set('incidentPeriod', event.target.value)} placeholder="Ex.: Últimas semanas" /></label><label className="field">Isso é recorrente?<input value={draft.recurrence} maxLength={80} onChange={event => set('recurrence', event.target.value)} placeholder="Ex.: Recorrente" /></label></div>
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Continuar</button></div></>;
 } else if (step === 6) {
  const field = (key: keyof Contact, label: string, props: Record<string, string> = {}) => <div className="field"><label htmlFor={`contact-${key}`}>{label}</label><input id={`contact-${key}`} value={contact[key]} onChange={event => { setContact({ ...contact, [key]: event.target.value }); setError(''); }} aria-describedby="communication-help" {...props} /></div>;
  body = <><h2>Formas de comunicação</h2><p className="muted">Estes dados servem para indicar pessoas específicas da empresa que possam receber e encaminhar esta manifestação, como RH, ouvidoria, compliance ou uma liderança responsável. A Escuta Aí Brasil validará o destino antes de qualquer contato.</p>
   <div className="notice warn small">Se o contato for proprietário(a), sócio(a) ou estiver diretamente envolvido no relato, informe o cargo com clareza. Esse contato exige revisão humana e pode não ser usado para proteger a pessoa manifestante.</div>
   <div className="grid two contact-form">{field('name', 'Nome do contato', { autoComplete: 'off' })}{field('role', 'Cargo', { placeholder: 'Ex.: Analista de RH, Ouvidor(a), Proprietário(a)' })}{field('email', 'E-mail profissional', { type: 'email', placeholder: 'contato@empresa.com.br' })}{field('phone', 'Telefone', { inputMode: 'tel', placeholder: '(11) 99999-9999' })}</div>
   <button className="btn primary" type="button" onClick={addContact}>Adicionar contato</button>
   <p id="communication-help" className="muted small">Use dados profissionais e, no telefone, inclua o DDD. Não informe contatos pessoais sem necessidade.</p>
   {errorLine}
   <div className="contact-list" aria-live="polite">{contacts.length ? contacts.map((item, index) => <div className="contact-chip" key={item.email}><span><strong>{item.name}</strong> · {item.role}<br /><span className="small">{item.email} · {item.phone}</span></span><button type="button" onClick={() => setContacts(contacts.filter((_, i) => i !== index))} aria-label={`Remover contato ${item.name}`}>×</button></div>) : <div className="empty-contact">Nenhum contato adicionado ainda.</div>}</div>
   <div className="nav-actions">{back}<button className="btn primary" type="button" disabled={!contacts.length} onClick={next}>Continuar</button></div></>;
 } else if (step === 7) {
  body = <><h2>O que você espera?</h2><OptionGrid label="O que você espera" options={expectations} value={draft.expectedOutcomes} onSelect={option => { setDraft(current => ({ ...current, expectedOutcomes: current.expectedOutcomes.includes(option) ? current.expectedOutcomes.filter(item => item !== option) : [...current.expectedOutcomes, option] })); setError(''); }} />
   {errorLine}<div className="nav-actions">{back}<button className="btn primary" type="button" onClick={next}>Preparar revisão</button></div></>;
 } else {
  body = <><h2>Revisão protegida</h2><p className="muted">À esquerda, seu relato original, que fica só com você. À direita, a versão que a empresa vai ler: retire nomes, locais, datas e detalhes que identifiquem pessoas.</p>
   <div className="comparison"><div className="text-panel"><h3>Seu relato original</h3><p>{draft.original}</p></div>
    <div className="text-panel"><h3>Versão que será enviada à empresa</h3><textarea rows={8} maxLength={5000} value={draft.shared} onChange={event => { set('shared', event.target.value); setError(''); }} aria-label="Versão que será enviada à empresa" /><span className="badge green">Identidade protegida perante a empresa</span></div></div>
   <p className="muted small">Contatos indicados: {contacts.map(item => `${item.name} (${item.role})`).join(', ')}. Demonstração: contatos e respostas de contexto não são armazenados nem usados para contato.</p>
   {errorLine}<div className="nav-actions"><button className="btn" type="button" onClick={() => go(5)}>Quero ajustar meu relato</button><button className="btn" type="button" disabled={busy} onClick={() => submit(false)}>Guardar sem compartilhar</button><button className="btn primary" type="button" disabled={busy} onClick={() => submit(true)}>{busy ? 'Enviando…' : 'Aprovar e enviar'}</button></div></>;
 }
 return <><button className="text-action worker-back" onClick={onCancel}>← Voltar</button>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Nova manifestação</span><h2>Nova manifestação</h2><p className="muted">Empresa selecionada: <strong>{company.name}</strong>. Etapa {step + 1} de 9 · {stepTitles[step]}</p></div></div>
  <section className="wizard-box"><div className="progress"><span style={{ width: `${(step + 1) / 9 * 100}%` }} /></div>{body}</section></>;
}
