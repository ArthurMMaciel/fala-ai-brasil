// Consulta CEP autorizada pelo responsável; escolha técnica registrada no ADR-0006.
export const postalCodeProvider: "pending" | "viacep" = "viacep";

export function normalizePostalCode(value: string): string {
  return value.trim().replace(/^(\d{5})-(\d{3})$/, "$1$2");
}

export function isValidPostalCode(value: string): boolean {
  return /^\d{8}$/.test(normalizePostalCode(value));
}

export async function lookupPostalCode(value: string, signal: AbortSignal, transport: typeof fetch = fetch): Promise<string> {
  const code = normalizePostalCode(value);
  if (!isValidPostalCode(code)) throw new Error("Informe um CEP com 8 dígitos.");
  const response = await transport(`https://viacep.com.br/ws/${code}/json/`, { signal, credentials: "omit", referrerPolicy: "no-referrer" });
  if (!response.ok) throw new Error("Não foi possível consultar o CEP. Preencha a Rua/Avenida manualmente.");
  const data: unknown = await response.json();
  if (!data || typeof data !== "object" || ("erro" in data && (data.erro === true || data.erro === "true"))) throw new Error("CEP não encontrado. Confira o CEP ou preencha a Rua/Avenida manualmente.");
  const street = "logradouro" in data ? data.logradouro : undefined;
  if (typeof street !== "string" || !street.trim()) throw new Error("Este CEP não informa a Rua/Avenida. Preencha esse campo manualmente.");
  return street.trim();
}

export function bindAddressLookup(root: HTMLElement, lookup = lookupPostalCode) {
  const input = root.querySelector<HTMLInputElement>('[name="postalCode"]');
  const street = root.querySelector<HTMLInputElement>('[name="street"]');
  const status = root.querySelector<HTMLElement>("#postal-code-status");
  if (!input || !street || !status) return;
  let controller: AbortController | undefined;
  let revision = 0;
  let previousCode = "";
  let autoFilledStreet = "";
  input.addEventListener("input", () => {
    revision++;
    controller?.abort();
    input.setCustomValidity("");
    status.textContent = "";
    if (autoFilledStreet && street.value === autoFilledStreet) street.value = "";
    autoFilledStreet = "";
    previousCode = "";
  });
  input.addEventListener("blur", async () => {
    if (!input.value) return;
    if (!isValidPostalCode(input.value)) {
      input.setCustomValidity("Informe um CEP com 8 dígitos.");
      status.textContent = "Informe um CEP com 8 dígitos.";
      return;
    }
    const code = normalizePostalCode(input.value);
    input.value = `${code.slice(0, 5)}-${code.slice(5)}`;
    if (postalCodeProvider !== "viacep") {
      status.textContent = "Consulta automática aguardando aprovação do provedor. Preencha a Rua/Avenida manualmente.";
      return;
    }
    if (previousCode === code) return;
    controller?.abort();
    controller = new AbortController();
    const ownController = controller;
    const ownRevision = ++revision;
    const previousStreet = street.value;
    status.textContent = "Consultando CEP…";
    const timeout = window.setTimeout(() => ownController.abort(), 8000);
    try {
      const foundStreet = await lookup(code, ownController.signal);
      if (ownRevision !== revision || !input.isConnected) return;
      if (street.value !== previousStreet) {
        status.textContent = "Consulta concluída. A Rua/Avenida que você digitou foi preservada.";
        return;
      }
      street.value = foundStreet;
      autoFilledStreet = foundStreet;
      previousCode = code;
      status.textContent = "Rua/Avenida preenchida. Informe o número e confira o endereço.";
    } catch (error) {
      if (ownRevision !== revision || !input.isConnected) return;
      status.textContent = ownController.signal.aborted ? "Consulta demorou demais. Preencha a Rua/Avenida manualmente." : error instanceof Error ? error.message : "Falha na consulta. Preencha a Rua/Avenida manualmente.";
    } finally {
      window.clearTimeout(timeout);
    }
  });
}
