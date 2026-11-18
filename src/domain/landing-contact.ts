import type { ContactProfile, ContactSolicitationInput, LandingOrigin } from '../services/contact-solicitations';

// Formulário de contato da landing estática: mesmos campos, validação e RPC do contact-solicitation-form.
// O "Site" visível não existe em contact_solicitations; o p_website da RPC é honeypot e recebe o bot-field.
const profiles: Record<string, [ContactProfile, LandingOrigin]> = {
  Trabalhador: ['worker', 'worker'], Empresa: ['company', 'company'], Parceiro: ['partner', 'partner'],
  Patrocinador: ['sponsor', 'sponsor'], Intelligence: ['company', 'intelligence'],
};
const origins: Record<string, LandingOrigin> = { inicio: 'worker', empresa: 'company', parceiros: 'partner', patrocinio: 'sponsor', intelligence: 'intelligence' };

export interface LandingContactFields { perfil: string; pagina: string; nome: string; email: string; telefone: string; organizacao: string; botField: string }

export function landingContactInput(fields: LandingContactFields): ContactSolicitationInput | null {
  const chosen = Object.prototype.hasOwnProperty.call(profiles, fields.perfil) ? profiles[fields.perfil] : null;
  if (!chosen) return null;
  const [profile, profileOrigin] = chosen;
  // Na home vale a origem do perfil escolhido; nas outras páginas, a da página.
  const pageOrigin = Object.prototype.hasOwnProperty.call(origins, fields.pagina) ? origins[fields.pagina] : 'worker';
  const origin = fields.pagina === 'inicio' ? profileOrigin : pageOrigin;
  return { profile, origin, name: fields.nome, email: fields.email, phone: fields.telefone, organization: profile === 'worker' ? '' : fields.organizacao, website: fields.botField };
}
