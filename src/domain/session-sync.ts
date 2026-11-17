// Bug 17tu7rpc7ru: sessão encerrada ou trocada em outra aba (ou expirada sem renovação) precisa refletir na tela aberta.
// O cliente Supabase avisa as outras abas pelo onAuthStateChange; esta regra decide o que a tela faz com o aviso.
export type SessionChange = "ended" | "changed" | null;

export function sessionChange(event: string, sessionUserId: string | null, shownUserId: string | null): SessionChange {
  if (!shownUserId) return null; // nada aberto na tela: login, cadastro e confirmação de e-mail seguem como estão
  if (event === "SIGNED_OUT" || !sessionUserId) return "ended";
  if (event === "INITIAL_SESSION") return null;
  return sessionUserId === shownUserId ? null : "changed";
}

export const sessionChangeMessages: Record<Exclude<SessionChange, null>, string> = {
  ended: "Sua sessão terminou. Entre novamente para continuar.",
  changed: "Outra conta entrou neste navegador. Recarregamos a tela com a conta atual.",
};
