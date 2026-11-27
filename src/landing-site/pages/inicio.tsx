// Gerado a partir de inicio.html (landing oficial); textos, imagens e classes iguais aos da página estática.
import { Caminhos, ContactForm, Marquee, SponsorStrip } from '../site-parts';
import { brandName } from '../../domain/brand';

export function InicioPage() {
  return (
    <>


<section className="hero">
  <div className="wrap">
    <div className="rv">
      <span className="eyebrow">Para quem trabalha · Acesso gratuito</span>
      <h1>Sua voz merece <em>espaço.</em></h1>
      <p className="lead">Conte sua experiência no trabalho, decida o que pode ser compartilhado e acompanhe os próximos passos.</p>
      <div className="hero-ctas"><a className="btn btn-pri" href="/#cadastrar">Relatar uma situação <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></a><a className="btn btn-sec" href="/#entrar">Acompanhar meu relato</a></div>
      <div className="trust"><div><i><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="5" y="10" width="14" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg></i>Sigiloso</div><div><i><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v18M17 7.5c0-1.9-2.2-3-5-3s-5 1.1-5 3 2.2 2.8 5 3.3 5 1.4 5 3.4-2.2 3.3-5 3.3-5-1.2-5-3" /></svg></i>Gratuito</div><div><i><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 11l3 3 8-8" /><path d="M20 12v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h9" /></svg></i>Você decide o que compartilhar</div></div>
      
    </div>
    <div className="hero-art rv" aria-hidden="true">
      <div className="ha-blob"></div>
      <img className="ha-main" src="/landing/img/photo-1581092570490-cc40829efaae-1100xx.jpg" alt="" />
      <img className="ha-sec" src="/landing/img/photo-1761839258605-d1b118266ccc-600x600.jpg" alt="" />
      <div className="ha-dot"></div>
      <div className="ha-card"><span className="ok" style={{ background: "var(--verde)" }}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12l5 5L20 7" /></svg></span><div><b>Relato recebido</b><small>Seu relato é sigiloso. Você acompanha cada passo.</small></div></div>
      <div className="ha-card ha-card2"><span className="ok" style={{ background: "var(--azul)" }}><svg width="24" height="14" xmlns="http://www.w3.org/2000/svg" viewBox="113.77 138.11 131.01 73.27"><path fill="#FFFFFF" d="M179.24 159.79C176.94 164.26 175.64 169.32 175.64 174.68C175.64 180.1 176.97 185.21 179.31 189.7C181.61 185.24 182.91 180.18 182.91 174.81C182.91 169.39 181.58 164.29 179.24 159.79Z" /><path fill="#FFFFFF" d="M208.21 190.95C199.22 190.95 191.94 183.67 191.94 174.68C191.94 165.7 199.22 158.42 208.21 158.42C217.19 158.42 224.48 165.7 224.48 174.68C224.48 183.67 217.19 190.95 208.21 190.95ZM240.78 174.72C240.78 174.73 240.78 174.74 240.78 174.76C240.78 174.73 240.78 174.71 240.78 174.68C240.78 156.7 226.2 142.11 208.21 142.11C196.8 142.11 186.76 147.99 180.95 156.87C184.05 162.14 185.83 168.27 185.83 174.81C185.83 181.3 184.08 187.38 181.02 192.62C186.85 201.43 196.85 207.25 208.21 207.25C215.43 207.25 222.11 204.9 227.51 200.92C227.5 200.92 227.5 200.93 227.49 200.93L240.78 206.37L240.78 174.75C240.78 174.74 240.78 174.73 240.78 174.72Z" /><path fill="#FFFFFF" d="M150.34 158.54C159.33 158.54 166.61 165.83 166.61 174.81C166.61 183.8 159.33 191.08 150.34 191.08C141.36 191.08 134.07 183.8 134.07 174.81C134.07 165.83 141.36 158.54 150.34 158.54ZM150.34 207.38C168.33 207.38 182.91 192.8 182.91 174.81C182.91 156.82 168.33 142.24 150.34 142.24C143.12 142.24 136.45 144.6 131.04 148.58C131.05 148.57 131.05 148.57 131.06 148.56L117.77 143.13L117.77 174.75C117.77 174.76 117.77 174.77 117.77 174.78C117.77 174.77 117.77 174.75 117.78 174.74C117.78 174.76 117.77 174.79 117.77 174.81C117.77 192.8 132.36 207.38 150.34 207.38Z" /></svg></span><div><b>Escuta aí</b><small>Como tá o clima no seu trabalho?</small></div></div>
    </div>
  </div>
</section>
<Caminhos active="inicio" />

<section className="faixa" aria-label="Profissões">
  <div className="wrap faixa-head rv">
    <div><span className="eyebrow">Toda profissão tem voz</span><h2>Da fábrica ao escritório, do campo ao hospital.</h2></div>
    <p>Não importa o setor, o cargo ou o tamanho da empresa. Se você trabalha, a escuta é pra você.</p>
  </div>
  <Marquee><div className="prof"><img src="/landing/img/photo-1753354868590-81ed82047c4f-500x640.jpg" alt="" /><span>Comércio</span></div><div className="prof"><img src="/landing/img/photo-1624727828489-a1e03b79bba8-500x640.jpg" alt="" /><span>Saúde</span></div><div className="prof"><img src="/landing/img/photo-1589923188900-85dae523342b-500x640.jpg" alt="" /><span>Campo</span></div><div className="prof"><img src="/landing/img/photo-1600565193348-f74bd3c7ccdf-500x640.jpg" alt="" /><span>Alimentação</span></div><div className="prof"><img src="/landing/img/photo-1742203103007-8b79bdede0f8-500x640.jpg" alt="" /><span>Logística</span></div><div className="prof"><img src="/landing/img/photo-1504222490345-c075b6008014-500x640.jpg" alt="" /><span>Serviços</span></div><div className="prof"><img src="/landing/img/photo-1766066014237-00645c74e9c6-500x640.jpg" alt="" /><span>Atendimento</span></div><div className="prof"><img src="/landing/img/photo-1541888946425-d81bb19240f5-500x640.jpg" alt="" /><span>Construção</span></div></Marquee>
</section>

<section className="sobre pad">
  <div className="wrap">
    <div className="sobre-art rv">
      <img src="/landing/img/photo-1573497620053-ea5300f94f21-900x1125.jpg" alt="Duas mulheres conversando à mesa" />
      <div className="sobre-quote">Escutar também é cuidar do caminho depois.<small>{brandName}</small></div>
    </div>
    <div className="rv">
      <span className="eyebrow">Quem somos · Nosso objetivo</span>
      <h2>Um relato não pode terminar no envio.</h2>
      <p className="lead">A {brandName} está construindo um percurso de escuta psicossocial pra que relatos não terminem no envio. O acesso de quem trabalha é gratuito.</p>
      <div className="valores"><div className="valor"><i style={{ background: "var(--azul)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 5h16v11H9l-5 4z" /><path d="M8 9h8M8 12h5" /></svg></i><b>Escuta de verdade</b><p>Atenção e respeito, sem julgamento.</p></div><div className="valor"><i style={{ background: "var(--verde)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="5" y="10" width="14" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg></i><b>Sigilo como regra</b><p>Seus dados de identificação não vão pra empresa.</p></div><div className="valor"><i style={{ background: "var(--amarelo)", color: "var(--tinta)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="4" /><path d="M12 12l6-6" /></svg></i><b>Prevenção</b><p>Sinais vistos cedo, antes de virar problema.</p></div><div className="valor"><i style={{ background: "var(--profundo)" }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3l8 4v5c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V7z" /></svg></i><b>Independência</b><p>Ninguém compra influência sobre a escuta.</p></div></div>
      <a className="video-link" href="/media/escuta-ai-brasil-institucional.mp4" download><span className="play"><svg width="20" height="20" viewBox="0 0 24 24" fill="#16213A"><path d="M8 5v14l11-7z" /></svg></span><span>Baixe o vídeo institucional<small>Conheça a {brandName} em poucos minutos</small></span></a>
    </div>
  </div>
</section>

<section className="gratis pad">
  <div className="wrap">
    <div className="preco rv">
      <span className="preco-sel">Sempre gratuito</span>
      <span className="eyebrow">Seu acesso</span>
      <div className="preco-v"><small>R$</small><span>0</span></div>
      <p>pra relatar e acompanhar. Sem plano, sem cartão.</p>
      <ul className="check">
        <li>Relatar e acompanhar sem custo, com sigilo</li>
        <li>Você escolhe o que compartilhar</li>
        <li>Acompanhamento de cada etapa</li>
        <li>O pagamento não define prioridade de atendimento</li>
      </ul>
      <a className="btn btn-pri" href="/#cadastrar">Criar conta gratuita</a>
    </div>
    <div className="gratis-art rv">
      <span className="eyebrow">Seu acesso</span>
      <h2>Pra você, o acesso é gratuito.</h2>
      <p className="lead" style={{ marginBottom: "30px" }}>Você não precisa contratar um plano pra relatar e acompanhar. Empresas, parceiros e patrocinadores não têm acesso ao seu relato nem à sua identidade.</p>
      <img src="/landing/img/photo-1538688423619-a81d3f23454b-1000x800.jpg" alt="Colegas de trabalho conversando e sorrindo" />
    </div>
  </div>
</section>

<section className="percurso pad">
  <div className="wrap">
    <div className="rv"><span className="eyebrow">O percurso</span><h2>Do relato ao retorno.</h2><p className="lead">3 passos. Você no controle do começo ao fim.</p></div>
    <div className="steps"><article className="step rv"><div className="step-img"><img src="/landing/img/photo-1766066014237-00645c74e9c6-700x400.jpg" alt="Pessoa usando computador" /><span className="step-n" style={{ background: "var(--azul)", color: "#fff" }}>1</span></div>
        <div className="step-body"><h3>Conte</h3><p>Descreva o que aconteceu com as suas palavras.</p></div><span className="arrow"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></span></article><article className="step rv"><div className="step-img"><img src="/landing/img/photo-1742203103007-8b79bdede0f8-700x400.jpg" alt="Mulher revisando informações" /><span className="step-n" style={{ background: "var(--verde)", color: "#fff" }}>2</span></div>
        <div className="step-body"><h3>Revise</h3><p>Escolha o que pode ser compartilhado. Nada sai sem a sua autorização.</p></div><span className="arrow"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></span></article><article className="step rv"><div className="step-img"><img src="/landing/img/photo-1761839258605-d1b118266ccc-700x400.jpg" alt="Homem conversando e sendo ouvido" /><span className="step-n" style={{ background: "var(--amarelo)", color: "var(--tinta)" }}>3</span></div>
        <div className="step-body"><h3>Acompanhe</h3><p>Volte pra ver registros e respostas.</p></div></article></div>
  </div>
</section>

<section className="banner pad" style={{ paddingBottom: "0" }}>
  <div className="wrap">
    <div className="banner-box rv">
      <img src="/landing/img/photo-1516216628859-9bccecab13ca-1600xx.jpg" alt="" />
      <div className="banner-in">
        <span className="eyebrow">Próximo passo</span>
        <h2>Você decide quando começar.</h2>
        <p>Quando se sentir pronto, é só começar. E você volta pra acompanhar quando quiser.</p>
        <div className="aviso"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M12 8v5M12 16h.01" /></svg>Esta é uma demonstração: use somente dados fictícios. A plataforma não substitui serviços de saúde, orientação jurídica ou atendimento de urgência.</div>
        <a className="btn btn-ama" href="/#cadastrar">Relatar uma situação <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></a>
      </div>
    </div>
  </div>
</section>


<section className="contato pad" id="contato" style={{ paddingBottom: "110px" }}>
  <div className="wrap">
    <div className="contato-box rv">
      <div className="contato-art">
        <img src="/landing/img/photo-1600880292203-757bb62b4baf-900x1100.jpg" alt="" />
        <div className="tag"><b>Fale com a nossa equipe</b><span>Pra relatar, use o botão "Relatar uma situação". Este formulário é só pra contato.</span></div>
      </div>
      <ContactForm pagina="inicio" perfil="Trabalhador" />
    </div>
  </div>
</section>

<SponsorStrip />
    </>
  );
}
