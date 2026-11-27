// Landing oficial em React (TASK do Gestor, 2026-11-19): rotas, SEO e chamadas de cada página.
// O conteúdo veio das páginas estáticas (inicio, empresa, parceiros, patrocinio, intelligence e 404), que saíram do build.
import { isVisibleAudience } from './entry-routes';
import { brandName } from './brand';

export type SitePageId = 'inicio' | 'empresa' | 'parceiros' | 'patrocinio' | 'intelligence' | '404';
type ContentPageId = Exclude<SitePageId, '404'>;

export type SitePage = {
  id: SitePageId;
  path: string | null;
  title: string;
  description: string | null;
  bodyClass: string;
  // Destinos de "Entrar" e "Cadastrar" no cabeçalho e no rodapé (hash lido pelo app em "/").
  entrar: string;
  cadastrar: string;
  cta: { href: string; label: string };
  contato: string;
};

const relatar = { href: '/#cadastrar', label: 'Relatar uma situação' };
const planos = { href: '#planos', label: 'Ver soluções e planos' };

export const sitePages: Record<SitePageId, SitePage> = {
  inicio: { id: 'inicio', path: '/', title: `${brandName} | Pra quem trabalha`, description: 'Plataforma gratuita e sigilosa de escuta psicossocial pra quem trabalha.', bodyClass: 'p-trab', entrar: '/#entrar', cadastrar: '/#cadastrar', cta: relatar, contato: '' },
  empresa: { id: 'empresa', path: '/empresa', title: `${brandName} | Pra empresas`, description: 'Receba manifestações de quem trabalha, organize a atuação e dê retorno.', bodyClass: 'p-empresa', entrar: '/#entrar-empresa', cadastrar: '/#cadastrar-empresa', cta: { href: '/#cadastrar-empresa', label: 'Criar conta da empresa' }, contato: '#contato' },
  parceiros: { id: 'parceiros', path: '/parceiros', title: `${brandName} | Pra parceiros do Hub`, description: 'Apresente sua especialidade e participe de uma rede dedicada ao contexto psicossocial do trabalho.', bodyClass: 'p-parceiros', entrar: '/#entrar-parceiro', cadastrar: '/#cadastrar-parceiro', cta: planos, contato: '#contato' },
  patrocinio: { id: 'patrocinio', path: '/patrocinio', title: `${brandName} | Patrocínio`, description: 'Contribua pra conteúdos, encontros e estudos públicos sobre o trabalho e suas relações.', bodyClass: 'p-patrocinio', entrar: '/#entrar-patrocinador', cadastrar: '/#cadastrar-patrocinador', cta: planos, contato: '#contato' },
  intelligence: { id: 'intelligence', path: '/intelligence', title: `${brandName} | Intelligence`, description: 'Estudos e leituras agregadas pra apoiar perguntas melhores sobre o ambiente de trabalho.', bodyClass: 'p-intelligence', entrar: '/#entrar-intelligence', cadastrar: '/#cadastrar-intelligence', cta: planos, contato: '#contato' },
  '404': { id: '404', path: null, title: `${brandName} | Página não encontrada`, description: null, bodyClass: 'p-trab', entrar: '/#entrar', cadastrar: '/#cadastrar', cta: relatar, contato: '' },
};

// Público de cada página. Página de público oculto (hiddenAudiences em entry-routes, a mesma lista do cadastro)
// sai do menu, do rodapé, dos caminhos e do formulário de contato, e o endereço dela leva ao início.
const pageAudience: Record<ContentPageId, string> = { inicio: 'worker', empresa: 'company', parceiros: 'partner', intelligence: 'intelligence', patrocinio: 'sponsor' };
export function isVisibleSitePage(id: SitePageId): boolean { return id === '404' || isVisibleAudience(pageAudience[id]); }

// Menu, rodapé e "caminhos" listam as páginas visíveis nesta ordem.
export const siteMenu: { id: ContentPageId; label: string }[] = ([
  { id: 'inicio', label: 'Trabalhador' },
  { id: 'empresa', label: 'Empresa' },
  { id: 'parceiros', label: 'Parceiros' },
  { id: 'intelligence', label: 'Intelligence' },
  { id: 'patrocinio', label: 'Patrocínio' },
] as { id: ContentPageId; label: string }[]).filter(item => isVisibleSitePage(item.id));

// Perfis do formulário de contato (valor lido por landingContactInput), só dos públicos visíveis.
export const contactProfiles: string[] = [
  { value: 'Trabalhador', audience: 'worker' },
  { value: 'Empresa', audience: 'company' },
  { value: 'Parceiro', audience: 'partner' },
  { value: 'Intelligence', audience: 'intelligence' },
  { value: 'Patrocinador', audience: 'sponsor' },
].filter(profile => isVisibleAudience(profile.audience)).map(profile => profile.value);

// "/" é a landing do trabalhador (ou a área de quem está logado); as outras páginas têm caminho próprio.
// Página oculta abre o início; qualquer outro caminho é a página 404. Aceita barra final e o antigo .html.
export function sitePageFromPath(pathname: string): SitePageId {
  const clean = pathname.replace(/\/+$/, '').replace(/\.html$/, '').toLowerCase() || '/';
  if (clean === '/' || clean === '/inicio') return 'inicio';
  const found = (Object.values(sitePages) as SitePage[]).find(page => page.path === clean);
  if (!found) return '404';
  return isVisibleSitePage(found.id) ? found.id : 'inicio';
}

// Visitante sem sessão salva que abre "/" vê a landing na hora, sem esperar a conferência da conta.
// Retornos de confirmação e recuperação (?code, ?error, #access_token=…) esperam o app tratá-los.
export function showsLandingImmediately(location: { search: string; hash: string }, storageKeys: string[]): boolean {
  if (location.search) return false;
  if (/[=&]/.test(location.hash)) return false;
  return !storageKeys.some(key => /^sb-.+-auth-token$/.test(key));
}

// Redirecionamentos do vercel.json (o teste confere os dois): endereços antigos .html, citados no e-mail de aviso,
// e páginas ocultas, que levam ao início.
const pathOrHome = (id: ContentPageId) => (isVisibleSitePage(id) ? sitePages[id].path ?? '/' : '/');
export const siteRedirects: { source: string; destination: string }[] = [
  { source: '/inicio.html', destination: '/' },
  { source: '/404.html', destination: '/' },
  ...(['empresa', 'parceiros', 'intelligence', 'patrocinio'] as ContentPageId[]).map(id => ({ source: `/${id}.html`, destination: pathOrHome(id) })),
  ...(['intelligence', 'patrocinio'] as ContentPageId[]).filter(id => !isVisibleSitePage(id)).map(id => ({ source: `/${id}`, destination: '/' })),
];
