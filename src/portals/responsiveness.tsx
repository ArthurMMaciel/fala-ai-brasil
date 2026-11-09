import { bandLabel, bandTone, formatHours, responseBandLabels, responseTimeBandLabels, satisfactionBandLabels } from '../domain/responsiveness';
import type { MyResponsiveness, ResponsivenessRow } from '../services/data';

// Responsividade das empresas (TASK-0036): ordem por nome, faixas em selos, sem posição, contagem ou percentual.

export const responsivenessMethod = 'Entram empresas com pelo menos 3 manifestações liberadas, em ordem alfabética. A taxa considera manifestações com ao menos uma resposta. O tempo vai da liberação à empresa até a primeira resposta; o período de revisão pela equipe não conta.';

function Band({ labels, band }: { labels: Readonly<Record<string, string>>; band: string | null }) {
 return <span className={`worker-status ${bandTone(band)}`}>{bandLabel(labels, band)}</span>;
}

export function ResponsivenessTable({ rows, highlightMine = false }: { rows: ResponsivenessRow[]; highlightMine?: boolean }) {
 const showSatisfaction = rows.some(row => row.satisfactionBand);
 return <div className="commercial-panel commercial-table-wrap"><table className="commercial-table responsiveness-table">
  <caption className="sr-only">Empresas em ordem alfabética, com faixas de taxa e de tempo de resposta</caption>
  <thead><tr><th scope="col">Empresa</th><th scope="col">Cidade</th><th scope="col">Taxa de resposta</th><th scope="col">Tempo de resposta</th>{showSatisfaction && <th scope="col">Satisfação</th>}</tr></thead>
  <tbody>{rows.map(row => <tr key={row.companyId} className={highlightMine && row.isMine ? 'ranking-mine' : ''}>
   <td data-label="Empresa">{row.name}{highlightMine && row.isMine && <strong> · sua empresa</strong>}</td><td data-label="Cidade">{row.city}/{row.state}</td>
   <td data-label="Taxa de resposta"><Band labels={responseBandLabels} band={row.responseBand} /></td><td data-label="Tempo de resposta"><Band labels={responseTimeBandLabels} band={row.responseTimeBand} /></td>
   {showSatisfaction && <td data-label="Satisfação"><Band labels={satisfactionBandLabels} band={row.satisfactionBand} /></td>}
  </tr>)}</tbody></table></div>;
}

/** Números exatos só da própria empresa; o resto da lista vê apenas as faixas. */
export function MyResponsivenessPanel({ mine }: { mine: MyResponsiveness | undefined }) {
 if (!mine) return null;
 return <section className="commercial-panel"><h2>Sua empresa</h2>
  <dl className="company-facts">
   <div><dt>Manifestações liberadas</dt><dd>{mine.released}</dd></div>
   <div><dt>Com resposta</dt><dd>{mine.answered}</dd></div>
   <div><dt>Taxa de resposta</dt><dd>{mine.responseRate === null ? '—' : `${mine.responseRate}%`} {mine.responseBand && <Band labels={responseBandLabels} band={mine.responseBand} />}</dd></div>
   <div><dt>Tempo médio até a 1ª resposta</dt><dd>{formatHours(mine.avgFirstResponseHours)} {mine.responseTimeBand && <Band labels={responseTimeBandLabels} band={mine.responseTimeBand} />}</dd></div>
  </dl>
  <p className="commercial-callout">{mine.listed ? 'Sua empresa aparece na lista pública com as faixas acima. Os números exatos ficam só aqui, para a sua empresa.' : 'Sua empresa aparece na lista a partir de 3 manifestações liberadas.'}</p>
 </section>;
}
