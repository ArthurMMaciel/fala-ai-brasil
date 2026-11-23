// Gerado a partir de 404.html (landing oficial); textos, imagens e classes iguais aos da página estática.

export function NotFoundPage() {
  return (
    <>

<section className="pad" style={{ minHeight: "60vh", display: "flex", alignItems: "center" }}>
  <div className="wrap" style={{ textAlign: "center", maxWidth: "640px" }}>
    <span className="eyebrow">Erro 404</span>
    <h1 style={{ margin: "14px 0" }}>Essa página não existe.</h1>
    <p style={{ color: "var(--cinza)", marginBottom: "28px" }}>O link pode ter mudado ou estar digitado errado.</p>
    <a className="btn btn-pri" href="/">Voltar pro início</a>
  </div>
</section>
    </>
  );
}
