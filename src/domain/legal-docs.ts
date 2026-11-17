// Termos de uso e aviso de privacidade vindos de arquivos de conteúdo (src/content/legal).
// Leitor mínimo de Markdown, sem HTML: o texto vira dados e o React escapa tudo na renderização.
export type LegalBlock =
  | { kind: "heading"; level: 2 | 3; text: string }
  | { kind: "paragraph"; text: string }
  | { kind: "list"; items: string[] }
  | { kind: "note"; text: string };

export interface LegalDoc { title: string; version: string; inReview: boolean; blocks: LegalBlock[] }

export const legalRoutes = { terms: "termos", privacy: "privacidade" } as const;
export type LegalRoute = keyof typeof legalRoutes;

export function legalRouteFromHash(hash: string): LegalRoute | null {
  const value = hash.replace(/^#\/?/, "");
  return (Object.keys(legalRoutes) as LegalRoute[]).find(route => legalRoutes[route] === value) ?? null;
}

function meta(source: string, name: string): string {
  const match = source.match(new RegExp(`<!--\\s*${name}:\\s*([^\\s>]+)\\s*-->`));
  return match?.[1] ?? "";
}

export function parseLegalDoc(source: string): LegalDoc {
  const lines = source.replace(/<!--[\s\S]*?-->/g, "").split(/\r?\n/);
  const blocks: LegalBlock[] = [];
  let title = "";
  let paragraph: string[] = [];
  const flush = () => { if (paragraph.length) blocks.push({ kind: "paragraph", text: paragraph.join(" ") }); paragraph = []; };
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) { flush(); continue; }
    const heading = line.match(/^(#{1,3})\s+(.+)$/);
    if (heading) {
      flush();
      if (heading[1].length === 1) title ||= heading[2];
      else blocks.push({ kind: "heading", level: heading[1].length as 2 | 3, text: heading[2] });
      continue;
    }
    const item = line.match(/^-\s+(.+)$/);
    if (item) {
      flush();
      const last = blocks[blocks.length - 1];
      if (last?.kind === "list") last.items.push(item[1]); else blocks.push({ kind: "list", items: [item[1]] });
      continue;
    }
    const note = line.match(/^>\s?(.*)$/);
    if (note) { flush(); blocks.push({ kind: "note", text: note[1] }); continue; }
    paragraph.push(line);
  }
  flush();
  return { title, version: meta(source, "versao"), inReview: meta(source, "status") !== "aprovado", blocks };
}
