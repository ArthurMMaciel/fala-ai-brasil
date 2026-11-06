// Saída segura para HTML montado como texto (renderer legado em main.js) e para URLs vindas do
// usuário ou do banco (TASK-0002). React já escapa texto; atributos de URL continuam exigindo filtro.

const htmlEntities: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;", "`": "&#96;" };

/** Escapa qualquer valor para uso em conteúdo de elemento ou atributo entre aspas. */
export function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"'`]/g, character => htmlEntities[character]);
}

/**
 * Devolve a URL normalizada somente se for absoluta e usar http ou https; caso contrário, null.
 * Bloqueia javascript:, data:, vbscript:, URLs relativas ao protocolo e variações com espaços ou controles.
 */
export function safeHttpUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const raw = value.trim();
  if (!raw || /[\u0000-\u001f\u007f\s]/.test(raw)) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return null;
  if (!url.hostname) return null;
  return url.href;
}
