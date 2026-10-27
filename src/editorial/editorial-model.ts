// POC: apenas memória desta aba. Estes códigos públicos não autenticam pessoas.
export const topics = ['Organização e carga de trabalho', 'Relações e convivência', 'Respeito e tratamento no trabalho', 'Condições para trabalhar', 'Outro assunto ou não sei definir'];
export type ReportDraft = { topic: string; description: string; sharing: 'yes' | 'no' | ''; step: number };
export type DemoRecord = { protocol: string; key: string; topic: string; description: string; sharing: boolean; created: string; complement: string[] };
export type CompanyCase = { protocol: string; topic: string; status: string; pending: string; pendingOwner: 'company' | 'team'; date: string; shared: string; published: string; draft: string; queued: boolean };
export type CompanyFilters = { status: string; topic: string; pending: string };
export const sharedExample = 'Mudanças frequentes de prioridade e demandas fora do horário combinado têm dificultado a organização do trabalho. Solicita-se clareza sobre prioridades e canais para comunicar sobrecarga.';
export const publishedExample = 'A empresa propõe revisar os combinados sobre prioridades e demandas fora do horário e informar os canais disponíveis para comunicar sobrecarga. A revisão interna está prevista para 22/10/2026, sujeita a alteração. Esta é uma proposta de encaminhamento; as medidas ainda não foram realizadas.';
export const draftExample = 'A análise dos combinados ainda não foi concluída. Está prevista para 22/10/2026 uma revisão interna sobre prioridades e demandas fora do horário. Essa data é uma previsão sujeita a alteração, não um prazo garantido. Ainda não há medida concluída para registrar.';
export const session = {
 draft: { topic: '', description: '', sharing: '', step: 0 } as ReportDraft,
 records: [{ protocol: 'EAB-2026-0042', key: 'DEMO-0042', topic: topics[0], description: 'Na minha rotina, as prioridades mudam com frequência e chegam demandas fora do horário combinado. Isso tem dificultado organizar as entregas e descansar. Gostaria que houvesse mais clareza sobre prioridades e uma forma de conversar sobre a carga de trabalho.', sharing: true, created: '14/10/2026', complement: [] }] as DemoRecord[],
 activeProtocol: 'EAB-2026-0042',
 cases: [
  { protocol: 'EAB-2026-0042', topic: topics[0], status: 'Retorno disponível', pending: 'Atualizar andamento da ação prevista', pendingOwner: 'company', date: '17/10/2026', shared: sharedExample, published: publishedExample, draft: draftExample, queued: false },
  { protocol: 'EAB-2026-0047', topic: topics[3], status: 'Aguarda resposta', pending: 'Preparar primeira resposta', pendingOwner: 'company', date: '19/10/2026', shared: 'O contexto relatado aponta dificuldades nas condições disponíveis para realizar o trabalho. Solicita-se avaliação das condições e orientação sobre os próximos passos.', published: '', draft: '', queued: false },
  { protocol: 'EAB-2026-0038', topic: topics[1], status: 'Resposta em revisão', pending: 'Aguardar revisão da equipe', pendingOwner: 'team', date: '16/10/2026', shared: 'A manifestação solicita melhoria no diálogo e nos combinados de convivência no trabalho.', published: '', draft: '', queued: true },
  { protocol: 'EAB-2026-0031', topic: topics[0], status: 'Aguarda complemento', pending: 'Aguardar informação revisada', pendingOwner: 'team', date: '12/10/2026', shared: 'O relato aponta dificuldades na organização de prioridades e pede orientação sobre a distribuição de demandas.', published: '', draft: '', queued: false },
 ] as CompanyCase[],
 activeCompanyProtocol: 'EAB-2026-0042',
};
export function companyCaseStatus(item: CompanyCase) {
 return item.queued ? 'Resposta em revisão' : item.status;
}
export function filterCompanyCases(cases: CompanyCase[], filters: CompanyFilters) {
 return cases.filter(item => (!filters.status || companyCaseStatus(item) === filters.status)
  && (!filters.topic || item.topic === filters.topic)
  && (!filters.pending || (filters.pending === 'action' ? !item.queued && item.pendingOwner === 'company'
   : filters.pending === 'review' ? item.queued : !item.queued && item.pendingOwner === 'team')));
}
export function validateReport(draft: ReportDraft) {
 if (draft.step === 0 && !topics.includes(draft.topic)) return 'Escolha um assunto para continuar.';
 if (draft.step === 1 && !draft.description.trim()) return 'Descreva a situação para continuar. Não precisa incluir nomes.';
 if (draft.step === 2 && !['yes', 'no'].includes(draft.sharing)) return 'Escolha o que autoriza compartilhar para continuar.';
 return '';
}
export function submitReport(draft: ReportDraft): DemoRecord {
 for (const step of [0, 1, 2]) { const error = validateReport({ ...draft, step }); if (error) throw Error(error); }
 const serial = 48 + session.records.length;
 const record: DemoRecord = { protocol: `EAB-2026-${String(serial).padStart(4, '0')}`, key: `DEMO-${String(serial).padStart(4, '0')}`, topic: draft.topic, description: draft.description.trim(), sharing: draft.sharing === 'yes', created: new Date().toLocaleDateString('pt-BR'), complement: [] };
 session.records.push(record);
 session.activeProtocol = record.protocol;
 session.draft = { topic: '', description: '', sharing: '', step: 0 };
 // O registro não entra na fila da empresa: nenhuma revisão humana foi executada.
 return record;
}
export function lookupReport(protocol: string, key: string) {
 return session.records.find(record => record.protocol === protocol.trim().toUpperCase() && record.key === key.trim());
}
export function queueCompanyUpdate(item: CompanyCase) {
 if (!item.draft.trim()) throw Error('Escreva a atualização antes de enviar para revisão.');
 item.queued = true;
 // Mantém o retorno publicado. Revisão/publicação reais não existem na POC.
}
