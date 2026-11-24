// Revisor simulado da versão para a empresa (pedido do responsável, 2026-11-23), até existir a revisão por IA.
// Roda só no navegador: o relato não sai da tela para gerar a sugestão. É uma sugestão simples, por regras;
// o trabalhador confere e edita, e a equipe revisa antes de liberar. Não garante que nada identifique alguém.

export type SuggestionCounts = { people: number; emails: number; phones: number; documents: number; dates: number; offensive: number };
export type SharedVersionSuggestion = { text: string; counts: SuggestionCounts };

export const suggestionLabel = "Sugestão automática simples. Confira antes de enviar; a equipe também revisa.";

const upper = "A-ZÀ-ÖØ-Þ";
const letter = "A-Za-zÀ-ÖØ-öø-ÿ";
const months = "janeiro|fevereiro|março|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro";

// Termos ofensivos de uma lista curta, trocados por uma marcação neutra. Comparação sem diferenciar maiúsculas.
const offensiveTerms = ["idiota", "imbecil", "babaca", "otário", "otaria", "otária", "burro", "burra", "retardado", "retardada", "vagabundo", "vagabunda", "desgraçado", "desgraçada", "canalha", "safado", "safada", "nojento", "nojenta", "porra", "merda", "caralho", "puta", "fdp", "filho da puta", "cretino", "cretina", "lixo de pessoa"];
const offensiveRe = new RegExp(`(?<![${letter}])(${[...offensiveTerms].sort((a, b) => b.length - a.length).map(term => term.replace(/ /g, "\\s+")).join("|")})(?![${letter}])`, "giu");

// Palavras com inicial maiúscula que não são nomes de pessoas e aparecem no meio de frases de trabalho.
const notNames = new Set(["RH", "Eu", "Deus", "Brasil", "CLT", "CIPA", "SESMT", "INSS", "CAT", "PJ", "TI", "CEO", "Ltda", "SA", "S.A.", "Natal", "Carnaval", "Páscoa"]);

function count(text: string, re: RegExp): number { return (text.match(re) ?? []).length; }

export function suggestSharedVersion(original: string): SharedVersionSuggestion {
  let text = String(original ?? "").replace(/\r\n?/g, "\n");
  const counts: SuggestionCounts = { people: 0, emails: 0, phones: 0, documents: 0, dates: 0, offensive: 0 };
  const swap = (re: RegExp, by: string, key: keyof SuggestionCounts) => { counts[key] += count(text, re); text = text.replace(re, by); };

  swap(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, "[e-mail]", "emails");
  swap(/\b\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}\b/g, "[documento]", "documents"); // CNPJ
  swap(/\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/g, "[documento]", "documents"); // CPF
  swap(/(?:\+?55\s?)?(?:\(\d{2}\)\s?|\b\d{2}\s)?\b9?\d{4}[-\s]?\d{4}\b/g, "[telefone]", "phones");
  swap(/\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/g, "[data]", "dates");
  swap(new RegExp(`\\b\\d{1,2}\\s+de\\s+(?:${months})(?:\\s+de\\s+\\d{4})?`, "giu"), "[data]", "dates");
  swap(new RegExp(`\\bdia\\s+\\d{1,2}\\b`, "giu"), "[data]", "dates");
  swap(offensiveRe, "[expressão ofensiva retirada]", "offensive");

  // Possíveis nomes: sequência de palavras com inicial maiúscula que não começa a frase (nem é sigla da lista).
  // Siglas (só maiúsculas) não entram: depois da inicial, a palavra precisa de letras minúsculas.
  const lowerRest = "a-zß-öø-ÿ'’-";
  const nameRe = new RegExp(`([${upper}][${lowerRest}]+)(?:\\s+(?:d[aeo]s?\\s+)?[${upper}][${lowerRest}]+)*`, "gu");
  text = text.replace(nameRe, (match, first: string, offset: number) => {
    const before = text.slice(0, offset);
    const sentenceStart = /(^|[.!?…:]\s*|\n\s*|["“(]\s*)$/.test(before);
    if (notNames.has(match) || notNames.has(first) || /^[A-ZÀ-Þ]{2,}$/.test(first)) return match;
    if (sentenceStart && !/\s/.test(match)) return match;
    counts.people += 1;
    return "[pessoa]";
  });

  text = text.replace(/(\[pessoa\])(\s+\[pessoa\])+/g, "$1").replace(/[ \t]{2,}/g, " ").trim();
  return { text, counts };
}

/** Resumo do que a sugestão trocou, para mostrar ao trabalhador ("2 possíveis nomes, 1 telefone"). */
export function suggestionSummary(counts: SuggestionCounts): string {
  const parts: [number, string, string][] = [
    [counts.people, "possível nome", "possíveis nomes"], [counts.emails, "e-mail", "e-mails"], [counts.phones, "telefone", "telefones"],
    [counts.documents, "documento", "documentos"], [counts.dates, "data", "datas"], [counts.offensive, "expressão ofensiva", "expressões ofensivas"],
  ];
  const used = parts.filter(([n]) => n > 0).map(([n, one, many]) => `${n} ${n === 1 ? one : many}`);
  return used.length ? `Trocamos ${used.join(", ")}.` : "Não encontramos nomes, contatos, documentos, datas nem expressões ofensivas na lista simples.";
}
