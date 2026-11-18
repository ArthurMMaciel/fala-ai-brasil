// Landing oficial estática (public/inicio.html). Só o visitante anônimo que abre "/" sem hash e sem query vai para ela:
// /#termos, /#privacidade, /#entrar, /#cadastrar, retornos de confirmação (?code, #access_token, ?error) e quem tem sessão salva seguem no app.
(function () {
  try {
    if (location.pathname !== '/' || location.hash || location.search) return;
    for (var i = 0; i < localStorage.length; i++) if (/^sb-.+-auth-token$/.test(localStorage.key(i) || '')) return;
    location.replace('/inicio.html');
  } catch (error) { /* sem acesso ao armazenamento: fica no app */ }
})();
