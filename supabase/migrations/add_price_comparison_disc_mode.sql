-- 가격비교 할인 방식 저장 (2026-08-04) — 'seq' 순차(잔액 복리) / 'sum' 합계(소계 기준 합산)
alter table public.price_comparisons
  add column if not exists disc_mode text not null default 'seq'
  check (disc_mode in ('seq', 'sum'));
comment on column public.price_comparisons.disc_mode is '프로모션 할인 방식 — seq: 순차(직전 잔액), sum: 합계(소계 기준)';
