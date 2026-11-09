import { useEffect, useId, useState } from 'react';
import { showToast } from '../app/toast';
import { brazilianStates, maskCnpj, maskCpf, maskPhone, streetTypeLabels, type AddressInput } from '../domain/account-rules';
import { companyProfileChanges, emailChangeEnabled, lockedDocumentNote, maskZip, validateCompanyProfile, validateLoginEmail, validateWorkerProfile, workerProfileChanges, type CompanyProfileForm, type WorkerProfileForm } from '../domain/profile';
import { loadCompanyProfile, loadWorkerProfile, requestLoginEmailChange, updateCompanyProfile, updateWorkerProfile, type CompanyProfileData, type WorkerProfileData } from '../services/profile';

// "Meu perfil" do trabalhador e da empresa (ADR-0014). CPF, CNPJ e razão social só a equipe altera.

/** Dados travados: somente leitura, com o caminho para pedir a troca. */
export function LockedFacts({ facts }: { facts: [string, string][] }) {
 const noteId = useId();
 return <section className="commercial-panel profile-locked" aria-describedby={noteId}><h2>Dados travados</h2>
  <dl className="company-facts">{facts.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value || '—'}</dd></div>)}</dl>
  <p id={noteId} className="commercial-callout">{lockedDocumentNote} Esses dados identificam a conta e só mudam com a conferência de um documento.</p>
 </section>;
}

export function AddressFields({ value, onChange, disabled }: { value: AddressInput; onChange: (next: AddressInput) => void; disabled?: boolean }) {
 const set = (patch: Partial<AddressInput>) => onChange({ ...value, ...patch });
 return <fieldset className="profile-address" disabled={disabled}><legend>Endereço</legend><div className="profile-grid">
  <label className="field">CEP<input value={value.zipCode} inputMode="numeric" autoComplete="postal-code" maxLength={9} required onChange={event => set({ zipCode: maskZip(event.target.value) })} placeholder="00000-000" /></label>
  <label className="field">Tipo de logradouro<select value={value.streetType} required onChange={event => set({ streetType: event.target.value })}><option value="">Selecione</option>{Object.entries(streetTypeLabels).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label>
  <label className="field profile-wide">Rua/Avenida<input value={value.streetName} autoComplete="address-line1" maxLength={200} required onChange={event => set({ streetName: event.target.value })} /></label>
  <label className="field">Número<input value={value.number} maxLength={20} required onChange={event => set({ number: event.target.value })} /></label>
  <label className="field">Complemento (opcional)<input value={value.complement ?? ''} autoComplete="address-line2" maxLength={100} onChange={event => set({ complement: event.target.value })} /></label>
  <label className="field">Bairro (opcional)<input value={value.neighborhood ?? ''} maxLength={120} onChange={event => set({ neighborhood: event.target.value })} /></label>
  <label className="field">Cidade<input value={value.city} autoComplete="address-level2" maxLength={120} required onChange={event => set({ city: event.target.value })} /></label>
  <label className="field">UF<select value={value.state} required onChange={event => set({ state: event.target.value })}><option value="">Selecione</option>{brazilianStates.map(state => <option key={state} value={state}>{state}</option>)}</select></label>
 </div></fieldset>;
}

/** E-mail de login: atrás da flag até o responsável confirmar a dupla confirmação no remoto. */
export function LoginEmail({ current }: { current: string }) {
 const [email, setEmail] = useState('');
 const [busy, setBusy] = useState(false);
 const [sent, setSent] = useState<string | null>(null);
 async function submit(event: React.FormEvent) {
  event.preventDefault();
  const problem = validateLoginEmail(email, current);
  if (problem) return showToast('error', problem);
  setBusy(true); const result = await requestLoginEmailChange(email); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  setSent(email.trim().toLowerCase()); setEmail('');
  showToast('success', 'Enviamos um link para o e-mail atual e outro para o novo. A troca vale depois das duas confirmações.');
 }
 return <section className="commercial-panel"><h2>E-mail de acesso</h2>
  <dl className="company-facts"><div><dt>E-mail atual</dt><dd>{current || '—'}</dd></div></dl>
  {!emailChangeEnabled ? <p className="commercial-callout">A troca do e-mail de acesso ainda não está disponível. Se precisar trocar agora, fale com a equipe.</p> :
   <form className="partner-profile-form profile-email-form" onSubmit={submit}>
    <label className="field">Novo e-mail<input type="email" autoComplete="email" value={email} maxLength={254} required onChange={event => setEmail(event.target.value)} /></label>
    <p className="muted small">Por segurança, a troca só vale depois de você confirmar pelo link enviado ao e-mail atual e pelo link enviado ao novo.</p>
    {sent && <p className="commercial-callout" role="status">Confirmação pendente para {sent}.</p>}
    <button className="btn" type="submit" disabled={busy}>{busy ? 'Enviando…' : 'Trocar e-mail'}</button>
   </form>}
 </section>;
}

function useSave<T>(initial: T | null) {
 const [form, setForm] = useState<T | null>(initial);
 const [busy, setBusy] = useState(false);
 return { form, setForm, busy, setBusy };
}

const workerForm = (data: WorkerProfileData): WorkerProfileForm => ({ fullName: data.fullName, phone: maskPhone(data.phone), address: data.address });

export function WorkerProfile() {
 const [data, setData] = useState<WorkerProfileData | null | undefined>(undefined);
 const { form, setForm, busy, setBusy } = useSave<WorkerProfileForm>(null);
 useEffect(() => { let active = true; loadWorkerProfile().then(value => { if (!active) return; setData(value); if (value) setForm(workerForm(value)); }).catch(() => active && setData(null)); return () => { active = false; }; }, []);
 async function save(event: React.FormEvent) {
  event.preventDefault();
  if (!data || !form) return;
  const problem = validateWorkerProfile(form);
  if (problem) return showToast('error', problem);
  const changes = workerProfileChanges(workerForm(data), form);
  if (!Object.keys(changes).length) return showToast('success', 'Nenhuma alteração para salvar.');
  setBusy(true); const result = await updateWorkerProfile(changes); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  const next = { ...data, fullName: form.fullName.trim(), phone: form.phone, address: form.address };
  setData(next); setForm(workerForm(next));
  showToast('success', 'Perfil atualizado.');
 }
 return <>
  <div className="worker-portal-heading"><div><span className="editorial-eyebrow">Área do trabalhador</span><h2>Meu perfil</h2><p className="muted">Seus dados de cadastro. A empresa nunca vê seu nome, telefone ou endereço.</p></div></div>
  {data === undefined ? <p className="muted">Carregando seu perfil…</p> : data === null || !form ? <section className="commercial-panel"><h2>Não foi possível carregar seu perfil</h2><p>Saia e entre novamente. Se continuar, fale com a equipe.</p></section> :
  <div className="commercial-grid-two profile-layout">
   <section className="commercial-panel"><h2>Dados pessoais</h2><form className="partner-profile-form" onSubmit={save}>
    <label className="field">Nome completo<input value={form.fullName} autoComplete="name" minLength={2} maxLength={160} required onChange={event => setForm({ ...form, fullName: event.target.value })} /></label>
    <label className="field">Telefone<input type="tel" inputMode="tel" autoComplete="tel-national" value={form.phone} maxLength={15} required onChange={event => setForm({ ...form, phone: maskPhone(event.target.value) })} placeholder="(11) 98765-4321" /></label>
    <AddressFields value={form.address} onChange={address => setForm({ ...form, address })} disabled={busy} />
    <button className="btn primary" type="submit" disabled={busy}>{busy ? 'Salvando…' : 'Salvar alterações'}</button>
   </form></section>
   <div className="profile-side"><LockedFacts facts={[['CPF', maskCpf(data.cpf)]]} /><LoginEmail current={data.email} /></div>
  </div>}
 </>;
}

const companyForm = (data: CompanyProfileData): CompanyProfileForm => ({ tradeName: data.tradeName, contactEmail: data.contactEmail, contactPhone: data.contactPhone ? maskPhone(data.contactPhone) : '', address: data.address });

function addressLine(address: AddressInput) {
 const street = [streetTypeLabels[address.streetType as keyof typeof streetTypeLabels], address.streetName].filter(Boolean).join(' ');
 return [[street, address.number].filter(Boolean).join(', '), address.complement, address.neighborhood, [address.city, address.state].filter(Boolean).join('/'), address.zipCode].filter(Boolean).join(' · ');
}

export function CompanyProfile({ companyId, onSaved }: { companyId: string; onSaved?: () => void }) {
 const [data, setData] = useState<CompanyProfileData | null | undefined>(undefined);
 const { form, setForm, busy, setBusy } = useSave<CompanyProfileForm>(null);
 useEffect(() => { let active = true; loadCompanyProfile(companyId).then(value => { if (!active) return; setData(value); if (value) setForm(companyForm(value)); }).catch(() => active && setData(null)); return () => { active = false; }; }, [companyId]);
 async function save(event: React.FormEvent) {
  event.preventDefault();
  if (!data || !form) return;
  const problem = validateCompanyProfile(form);
  if (problem) return showToast('error', problem);
  const changes = companyProfileChanges(companyForm(data), form);
  if (!Object.keys(changes).length) return showToast('success', 'Nenhuma alteração para salvar.');
  setBusy(true); const result = await updateCompanyProfile(companyId, changes); setBusy(false);
  if (!result.ok) return showToast('error', result.message);
  const next = { ...data, tradeName: form.tradeName.trim(), contactEmail: form.contactEmail.trim().toLowerCase(), contactPhone: form.contactPhone, address: form.address };
  setData(next); setForm(companyForm(next)); onSaved?.();
  showToast('success', 'Dados da empresa atualizados.');
 }
 const head = <div className="commercial-page-head"><div><span className="editorial-eyebrow">Área da empresa</span><h1>Meu perfil</h1><p>Dados da empresa na plataforma. O nome fantasia aparece no diretório e no ranking.</p></div></div>;
 if (data === undefined) return <>{head}<p className="muted">Carregando dados da empresa…</p></>;
 if (data === null || !form) return <>{head}<section className="commercial-panel"><h2>Não foi possível carregar os dados da empresa</h2><p>Saia e entre novamente. Se continuar, fale com a equipe.</p></section></>;
 const locked = <LockedFacts facts={[['Razão social', data.legalName], ['CNPJ', maskCnpj(data.cnpj)]]} />;
 if (!data.isOwner) return <>{head}<div className="commercial-grid-two profile-layout">
  <section className="commercial-panel"><h2>Dados da empresa</h2>
   <p className="commercial-callout" role="note">Só o responsável pela conta da empresa altera estes dados. Você pode consultá-los.</p>
   <dl className="company-facts"><div><dt>Nome fantasia</dt><dd>{data.tradeName || '—'}</dd></div><div><dt>E-mail de contato</dt><dd>{data.contactEmail || '—'}</dd></div><div><dt>Telefone de contato</dt><dd>{data.contactPhone ? maskPhone(data.contactPhone) : '—'}</dd></div><div><dt>Endereço</dt><dd>{addressLine(data.address) || '—'}</dd></div></dl>
  </section>
  <div className="profile-side">{locked}<LoginEmail current={data.loginEmail} /></div>
 </div></>;
 return <>{head}<div className="commercial-grid-two profile-layout">
  <section className="commercial-panel"><h2>Dados da empresa</h2><form className="partner-profile-form" onSubmit={save}>
   <label className="field">Nome fantasia (opcional)<input value={form.tradeName} autoComplete="organization" maxLength={160} onChange={event => setForm({ ...form, tradeName: event.target.value })} /></label>
   <label className="field">E-mail de contato (opcional)<input type="email" autoComplete="email" value={form.contactEmail} maxLength={254} onChange={event => setForm({ ...form, contactEmail: event.target.value })} /></label>
   <label className="field">Telefone de contato (opcional)<input type="tel" inputMode="tel" autoComplete="tel-national" value={form.contactPhone} maxLength={15} onChange={event => setForm({ ...form, contactPhone: maskPhone(event.target.value) })} placeholder="(11) 3333-4444" /></label>
   <p className="muted small">O contato aparece para parceiros com quem a empresa tem interesse ou contrato.</p>
   <AddressFields value={form.address} onChange={address => setForm({ ...form, address })} disabled={busy} />
   <button className="btn primary" type="submit" disabled={busy}>{busy ? 'Salvando…' : 'Salvar alterações'}</button>
  </form></section>
  <div className="profile-side">{locked}<LoginEmail current={data.loginEmail} /></div>
 </div></>;
}
