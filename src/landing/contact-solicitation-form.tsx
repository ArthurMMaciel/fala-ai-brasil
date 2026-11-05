import { useState, type FormEvent } from 'react';
import { submitContactSolicitation, validateContactSolicitation, type ContactSolicitationInput, type LandingOrigin } from '../services/contact-solicitations';

const profileLabels = { worker: 'Trabalhador', company: 'Empresa', partner: 'Parceiro', sponsor: 'Patrocinador' };

export function ContactSolicitationForm({ audience }: { audience: LandingOrigin }) {
  const profile = audience === 'intelligence' ? 'company' : audience;
  const [form, setForm] = useState<ContactSolicitationInput>({ profile, origin: audience, name: '', email: '', phone: '', organization: '', website: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const update = (field: keyof ContactSolicitationInput, value: string) => { setForm(current => ({ ...current, [field]: value })); setError(''); };

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input = { ...form, profile, origin: audience };
    const validation = validateContactSolicitation(input);
    if (validation) { setError(validation); return; }
    setBusy(true);
    const result = await submitContactSolicitation(input);
    setBusy(false);
    if (!result.ok) { setError(result.message); return; }
    setSent(true);
  }

  return <section className="landing-contact" id="saiba-mais" aria-labelledby="landing-contact-title">
    <div className="landing-contact-copy"><span className="editorial-eyebrow">Saiba mais</span><h2 id="landing-contact-title">Vamos conversar?</h2><p>Deixe seus dados e nossa equipe retorna para apresentar o Escuta Aí Brasil para {audience === 'intelligence' ? 'sua organização' : profile === 'worker' ? 'você' : 'seu perfil'}.</p><p className="small">Usaremos estes dados somente para responder ao seu pedido. Não escreva relatos nem informações sensíveis aqui.</p></div>
    {sent ? <div className="landing-contact-success" role="status"><strong>Solicitação recebida.</strong><p>Retornaremos assim que possível pelo contato informado.</p></div> :
    <form className="landing-contact-form" onSubmit={submit} noValidate>
      <p className="landing-contact-context">Perfil: <strong>{profileLabels[profile]}</strong>{audience === 'intelligence' ? ' · interesse em estudos e inteligência' : ''}</p>
      <div className="field"><label htmlFor="lead-name">Nome</label><input id="lead-name" autoComplete="name" maxLength={120} required value={form.name} onChange={event => update('name', event.target.value)} /></div>
      <div className="landing-contact-pair"><div className="field"><label htmlFor="lead-email">E-mail</label><input id="lead-email" type="email" autoComplete="email" maxLength={254} required value={form.email} onChange={event => update('email', event.target.value)} /></div><div className="field"><label htmlFor="lead-phone">Telefone com DDD</label><input id="lead-phone" type="tel" autoComplete="tel" inputMode="tel" maxLength={20} required value={form.phone} onChange={event => update('phone', event.target.value)} /></div></div>
      {profile !== 'worker' && <div className="field"><label htmlFor="lead-organization">Organização <span className="small">(opcional)</span></label><input id="lead-organization" autoComplete="organization" maxLength={120} value={form.organization} onChange={event => update('organization', event.target.value)} /></div>}
      <div className="sr-only" aria-hidden="true"><label htmlFor="lead-website">Site</label><input id="lead-website" tabIndex={-1} autoComplete="off" value={form.website} onChange={event => update('website', event.target.value)} /></div>
      {error && <p className="field-error" role="alert">{error}</p>}
      <button className="btn primary" type="submit" disabled={busy}>{busy ? 'Enviando…' : 'Solicitar contato'}</button>
    </form>}
  </section>;
}
