import { ContactSolicitationForm } from './contact-solicitation-form';

type Audience = 'worker' | 'company' | 'partner' | 'intelligence' | 'sponsor';

type ShowcaseContent = {
  label: string;
  title: string;
  lead: string;  aboutTitle: string;
  about: string;
  processTitle: string;
  steps: Array<[string, string]>;
  closing: string;
  note?: string;
};

const content: Record<Audience, ShowcaseContent> = {
  worker: {
    label: 'Para quem trabalha · acesso gratuito',
    title: 'Sua voz merece espaço.',
    lead: 'Conte sua experiência no trabalho, decida o que pode ser compartilhado e acompanhe os próximos passos.',    aboutTitle: 'Escutar também é cuidar do caminho depois.',
    about: 'O Escuta Aí Brasil está construindo um percurso de escuta psicossocial para que relatos não terminem no envio. O acesso de quem trabalha é gratuito.',
    processTitle: 'Do relato ao retorno',
    steps: [['Conte', 'Descreva o que aconteceu com suas palavras.'], ['Revise', 'Escolha o que pode ser compartilhado.'], ['Acompanhe', 'Volte para ver registros e respostas.']],
    closing: 'Você decide quando começar.',
    note: 'Esta é uma demonstração: use somente dados fictícios. A plataforma não substitui serviços de saúde, orientação jurídica ou atendimento de urgência.',
  },
  company: {
    label: 'Para empresas',
    title: 'Escutar é só o começo.',
    lead: 'Um caminho para receber a versão compartilhável de uma manifestação, organizar a atuação e dar retorno.',    aboutTitle: 'Escuta com continuidade e responsabilidade.',
    about: 'A proposta do Escuta Aí Brasil aproxima quem precisa falar e quem pode agir. A empresa acompanha apenas o conteúdo liberado para ela, sem acesso ao relato original ou à identidade do trabalhador.',
    processTitle: 'Um percurso de resposta',
    steps: [['Receba', 'Leia o contexto compartilhável do caso.'], ['Organize', 'Registre responsáveis e próximos passos.'], ['Responda', 'Devolva uma resposta clara ao trabalhador.']],
    closing: 'Sua empresa pode começar pela escuta.',
    note: 'Acesso a casos reais exige verificação e liberação segura. A visualização e a resposta à manifestação não dependem de pagamento.',
  },
  partner: {
    label: 'Para parceiros',
    title: 'Cuidado se faz em rede.',
    lead: 'Apresente sua especialidade e participe de uma rede dedicada ao contexto psicossocial do trabalho.',    aboutTitle: 'Um espaço para especialistas se apresentarem.',
    about: 'O Hub aproxima empresas de profissionais e organizações com competências complementares. Perfil, presença e conexões seguem as regras de cada plano demonstrativo.',
    processTitle: 'Como participar',
    steps: [['Apresente-se', 'Mostre sua atuação e região.'], ['Seja encontrado', 'Apareça nas buscas relevantes.'], ['Conecte-se', 'Converse quando houver interesse.']],
    closing: 'Faça parte da rede.',
    note: 'A oferta comercial ainda está em validação. Participar do Hub não concede acesso a relatos ou identidades.',
  },
  intelligence: {
    label: 'Para estudos e inteligência',
    title: 'Dados pedem contexto.',
    lead: 'Estudos e leituras agregadas para apoiar perguntas melhores sobre o ambiente de trabalho.',    aboutTitle: 'Evidência com limites claros.',
    about: 'A frente de inteligência está em planejamento. A proposta é trabalhar com perguntas definidas, método transparente e resultados agregados, quando houver base suficiente e governança aprovada.',
    processTitle: 'Da pergunta à leitura',
    steps: [['Defina', 'Formule a pergunta de estudo.'], ['Avalie', 'Verifique método e elegibilidade.'], ['Interprete', 'Leia resultados e limitações.']],
    closing: 'Vamos conversar sobre a pergunta certa.',
    note: 'Serviço planejado; nenhuma análise de relatos reais está disponível nesta demonstração.',
  },
  sponsor: {
    label: 'Para patrocinadores',
    title: 'Apoie a conversa.',
    lead: 'Contribua para conteúdos, encontros e estudos públicos sobre o trabalho e suas relações.',    aboutTitle: 'Apoio com fronteiras claras.',
    about: 'Patrocínios podem apoiar iniciativas educativas identificadas como tal. A marca apoiadora não participa do tratamento das manifestações nem acessa relatos ou identidades.',
    processTitle: 'Como o apoio se apresenta',
    steps: [['Escolha', 'Defina o formato de apoio.'], ['Identifique', 'A marca aparece com transparência.'], ['Acompanhe', 'Veja entregas agregadas.']],
    closing: 'Apoie um tema que importa.',
    note: 'Formatos e valores são hipóteses comerciais em validação.',
  },
};

export function PersonaShowcase({ audience, onPrimary, onSecondary }: { audience: Audience; onPrimary: () => void; onSecondary?: () => void }) {
  const item = content[audience];
  const primaryLabel = audience === 'worker' ? 'Relatar uma situação' : audience === 'company' ? 'Criar conta da empresa' : 'Ver soluções e planos';
  return <>
    <section className={`landing-intro landing-intro-${audience}`} aria-labelledby="landing-title">
      <span className="editorial-eyebrow">{item.label}</span>
      <h1 id="landing-title">{item.title}</h1>
      <p>{item.lead}</p>
      <div className="editorial-actions"><button className="btn primary" onClick={onPrimary}>{primaryLabel}</button>{onSecondary && <button className="btn" onClick={onSecondary}>Acompanhar manifestação</button>}</div>
    </section>
    <figure className="landing-hero-media landing-hero-video"><video controls playsInline preload="metadata" width="1920" height="1080" aria-label="Vídeo institucional da Escuta Aí Brasil (versão preliminar, 46 segundos)"><source src="/media/escuta-ai-brasil-institucional.mp4#t=0.5" type="video/mp4" />Seu navegador não reproduz vídeos. <a href="/media/escuta-ai-brasil-institucional.mp4">Baixe o vídeo institucional</a>.</video></figure>
    <section className="landing-about" aria-labelledby="landing-about-title"><span className="editorial-eyebrow">Quem somos · nosso objetivo</span><h2 id="landing-about-title">{item.aboutTitle}</h2><p>{item.about}</p></section>
    <section className="landing-process" aria-labelledby="landing-process-title"><div className="landing-process-heading"><span className="editorial-eyebrow">O percurso</span><h2 id="landing-process-title">{item.processTitle}</h2></div><ol>{item.steps.map(([title, copy], index) => <li key={title}><span aria-hidden="true">0{index + 1}</span><h3>{title}</h3><p>{copy}</p></li>)}</ol></section>
    <section className="landing-closing" aria-labelledby="landing-closing-title"><div><span className="editorial-eyebrow">Próximo passo</span><h2 id="landing-closing-title">{item.closing}</h2><p>{item.note}</p></div><button className="btn primary" onClick={onPrimary}>{primaryLabel}</button></section>
    <ContactSolicitationForm audience={audience} />
  </>;
}
