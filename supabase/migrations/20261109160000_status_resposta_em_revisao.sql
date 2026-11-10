-- TASK-0035 / ADR-0013, passo (a): valor novo de enum, em migration própria.
-- answer_in_review = a empresa respondeu e a equipe revisa antes de o trabalhador receber.
-- Fica entre 'shared' e 'answered' na ordem lógica (usada no desempate das linhas do tempo).
-- Nenhuma linha usa o valor até o passo (d) (20261109180000). Rollback: o valor fica sem uso (Postgres não remove valor de enum).
alter type public.complaint_status add value if not exists 'answer_in_review' after 'shared';
