-- ADR-0010: revisão humana antes de liberar a manifestação à empresa (aprovado em 2026-11-06).
-- Valores novos ficam em migration própria: o Postgres não usa um valor de enum na mesma transação que o cria.
-- "shared" passa a significar "liberada para a empresa" após a revisão da equipe.
alter type public.complaint_status add value if not exists 'in_review' after 'received';
alter type public.complaint_status add value if not exists 'adjustment_requested' after 'in_review';
alter type public.complaint_status add value if not exists 'held' after 'adjustment_requested';
