// Gerado a partir de empresa.html (landing oficial); textos, imagens e classes iguais aos da página estática.
import type { CSSProperties } from 'react';
import { BillButton, Caminhos, ContactForm, Per, Price, SponsorStrip } from '../site-parts';

export function EmpresaPage() {
  return (
    <>


<section className="hero">
  <div className="wrap">
    <div className="rv">
      <span className="eyebrow">Para empresas</span>
      <h1>Escutar é só <em>o começo.</em></h1>
      <p className="lead">Um caminho pra receber a versão compartilhável de um relato, organizar a atuação e dar retorno a quem falou.</p>
      <div className="hero-ctas"><a className="btn btn-pri" href="/#cadastrar-empresa">Criar conta da empresa <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></a><a className="btn btn-sec" href="#planos">Ver planos</a></div>
      <div className="trust"><div><i><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z" /><circle cx="12" cy="12" r="3" /></svg></i>Só o conteúdo liberado</div><div><i><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5" /><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.8c1.8.7 3 2.5 3.5 5.2" /></svg></i>RH e Compliance juntos</div><div><i><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="4" /><path d="M12 12l6-6" /></svg></i>Riscos vistos antes</div></div>
      
    </div>
    <div className="hero-art rv" aria-hidden="true">
      <div className="ha-blob"></div>
      <img className="ha-main" src="/landing/img/photo-1713947506934-c0b6519e069d-1100xx.jpg" alt="" />
      <img className="ha-sec" src="/landing/img/photo-1622675363311-3e1904dc1885-600x600.jpg" alt="" />
      <div className="ha-dot"></div>
      <div className="ha-card"><span className="ok" style={{ background: "var(--azul)" }}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z" /><path d="M14 3v6h6M8 13h8M8 17h5" /></svg></span><div><b>Novo relato compartilhado</b><small>Contexto liberado pelo trabalhador. Sem dados de identificação.</small></div></div>
      <div className="ha-card ha-card2"><span className="ok" style={{ background: "var(--verde)" }}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12l5 5L20 7" /></svg></span><div><b>Resposta enviada</b><small>O trabalhador já pode ver o retorno.</small></div></div>
    </div>
  </div>
</section>
<Caminhos active="empresa" />


<section className="sobre pad">
  <div className="wrap">
    <div className="sobre-art rv">
      <img src="/landing/img/photo-1600880292203-757bb62b4baf-900x1125.jpg" alt="Gestores conversando em reunião" />
      <div className="sobre-quote">Quem precisa falar, perto de quem pode agir.<small>Escuta com continuidade e responsabilidade</small></div>
    </div>
    <div className="rv">
      <span className="eyebrow">Quem somos · Nosso objetivo</span>
      <h2>Escuta com continuidade e responsabilidade.</h2>
      <p className="lead">A proposta da escuta.aí aproxima quem precisa falar e quem pode agir. A empresa acompanha apenas o conteúdo liberado pra ela, sem acesso ao relato original ou à identidade do trabalhador.</p>
      <div className="valores"><div className="valor"><i style={{ background: "var(--azul)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 6h10M4 12h16M4 18h7" /><circle cx="18" cy="6" r="2" /><circle cx="15" cy="18" r="2" /></svg></i><b>Fila e responsáveis</b><p>Cada caso com dono e próximo passo.</p></div><div className="valor"><i style={{ background: "var(--verde)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg></i><b>Prazos e escalonamento</b><p>Nada fica parado sem ninguém ver.</p></div><div className="valor"><i style={{ background: "var(--amarelo)", color: "var(--tinta)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" /></svg></i><b>Indicadores</b><p>Leitura da organização ao longo do tempo.</p></div><div className="valor"><i style={{ background: "var(--profundo)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3l8 4v5c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V7z" /><path d="M9 12l2 2 4-4" /></svg></i><b>Apoio à NR-1</b><p>Gestão de riscos psicossociais com registro.</p></div></div>
      
    </div>
  </div>
</section>

<section className="pad" style={{ paddingTop: "0" }}>
  <div className="wrap">
    <div className="rv"><span className="eyebrow">Privacidade por desenho</span><h2>O que a sua empresa vê. E o que fica protegido.</h2>
    <p className="lead">A empresa acompanha só o conteúdo que o trabalhador liberou. É isso que dá confiança pra pessoa falar.</p></div>
    <div className="ve">
      <div className="ve-col ve-sim rv"><h3><span><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12l5 5L20 7" /></svg></span>A empresa vê</h3><ul>
        <li>A versão compartilhável do relato, liberada pelo trabalhador</li><li>O contexto necessário pra agir</li><li>Responsáveis, prazos e próximos passos registrados</li><li>Indicadores da organização</li></ul></div>
      <div className="ve-col ve-nao rv"><h3><span>✕</span>Fica protegido</h3><ul>
        <li>O relato original</li><li>A identidade do trabalhador</li><li>Qualquer informação que ele não liberou</li><li>Dados pessoais de cadastro</li></ul></div>
    </div>
    <p className="ve-nota"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M12 8v5M12 16h.01" /></svg>Acesso a casos reais exige verificação e liberação segura. Ver e responder um relato não depende de pagamento.</p>
  </div>
</section>

<section className="percurso pad">
  <div className="wrap">
    <div className="rv"><span className="eyebrow">O percurso</span><h2>Um percurso de resposta.</h2><p className="lead">Do relato recebido ao retorno pro trabalhador, tudo registrado.</p></div>
    <div className="steps"><article className="step rv"><div className="step-img"><img src="/landing/img/photo-1604933762021-54a5858c9832-700x400.jpg" alt="Gestora lendo no notebook" /><span className="step-n" style={{ background: "var(--azul)", color: "#fff" }}>1</span></div>
        <div className="step-body"><h3>Receba</h3><p>Leia o contexto compartilhável do caso.</p></div><span className="arrow"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></span></article><article className="step rv"><div className="step-img"><img src="/landing/img/photo-1622675363311-3e1904dc1885-700x400.jpg" alt="Equipe reunida" /><span className="step-n" style={{ background: "var(--verde)", color: "#fff" }}>2</span></div>
        <div className="step-body"><h3>Organize</h3><p>Registre responsáveis e próximos passos.</p></div><span className="arrow"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></span></article><article className="step rv"><div className="step-img"><img src="/landing/img/photo-1751139846116-8c4bc6b64eea-700x400.jpg" alt="Equipe sorrindo em conversa" /><span className="step-n" style={{ background: "var(--amarelo)", color: "var(--tinta)" }}>3</span></div>
        <div className="step-body"><h3>Responda</h3><p>Devolva uma resposta clara ao trabalhador.</p></div></article></div>
  </div>
</section>

<section className="banner pad" style={{ paddingBottom: "0" }}>
  <div className="wrap">
    <div className="banner-box rv">
      <img src="/landing/img/photo-1538688423619-a81d3f23454b-1600xx.jpg" alt="" />
      <div className="banner-in">
        <span className="eyebrow">Próximo passo</span>
        <h2>Sua empresa pode começar pela escuta.</h2>
        <p>Crie a conta da empresa e conheça o percurso de resposta.</p>
        <div className="aviso"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M12 8v5M12 16h.01" /></svg>Acesso a casos reais exige verificação e liberação segura. A visualização e a resposta ao relato não dependem de pagamento.</div>
        <a className="btn btn-ama" href="/#cadastrar-empresa">Criar conta da empresa <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></a>
      </div>
    </div>
  </div>
</section>

<section className="planos pad" id="planos">
  <div className="wrap">
    <div className="planos-head rv">
      <div><span className="eyebrow">Planos para empresa</span><h2>Soluções, planos e acesso à conta</h2>
      <p className="trial"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M3 10h18M8 3v4M16 3v4" /></svg><span><b>1º mês de calendário grátis.</b> Depois, mensal ou anual com 5% de desconto.</span></p></div>
      <div className="toggle" role="group" aria-label="Período de cobrança"><BillButton bill="m">Mensal</BillButton><BillButton bill="a">Anual<em>-5%</em></BillButton></div>
    </div>
    <div className="pl-grid" style={{ "--n": "3" } as CSSProperties}><div className="pl rv"><h3>Essencial</h3><p className="para">Pra organizar a escuta de uma unidade.</p><div className="val">R$ <Price monthly={1500} /><small>/mês</small></div><div className="per"><Per /></div><ul><li>Fila e responsáveis</li><li>Resposta e acompanhamento</li><li>Indicadores da organização</li></ul><a className="btn btn-sec" href="/#cadastrar-plano-company-essential">Escolher Essencial</a></div><div className="pl rv dest"><span className="tag">Pra RH e Compliance</span><h3>Gestão</h3><p className="para">Pra RH e Compliance trabalharem juntos.</p><div className="val">R$ <Price monthly={3900} /><small>/mês</small></div><div className="per"><Per /></div><ul><li>Até 5 unidades</li><li>Prazos e escalonamento</li><li>Revisão executiva</li></ul><a className="btn btn-acc" href="/#cadastrar-plano-company-management">Escolher Gestão</a></div><div className="pl rv"><h3>Multiunidade</h3><p className="para">Pra grupos com operação em várias unidades.</p><div className="val sob">Sob proposta</div><div className="per">preço e escopo sob proposta</div><ul><li>Governança regional</li><li>Comparação interna protegida</li><li>Implantação sob proposta</li></ul><a className="btn btn-sec" href="/#cadastrar-plano-company-multi">Escolher Multiunidade</a></div></div>
    <div className="pl-nota"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M12 8v5M12 16h.01" /></svg>Demonstração comercial: preços e funcionalidades são hipóteses pra validação. Não há cobrança real. Ofertas sob proposta dependem de preço e escopo aprovados.</div>
  </div>
</section>


<section className="contato pad" id="contato" style={{ paddingBottom: "110px" }}>
  <div className="wrap">
    <div className="contato-box rv">
      <div className="contato-art">
        <img src="/landing/img/photo-1573497620053-ea5300f94f21-900x1100.jpg" alt="" />
        <div className="tag"><b>Apresentação pra sua empresa</b><span>Nossa equipe mostra o percurso de resposta na prática.</span></div>
      </div>
      <ContactForm pagina="empresa" perfil="Empresa" organizacao />
    </div>
  </div>
</section>

<SponsorStrip />
    </>
  );
}
