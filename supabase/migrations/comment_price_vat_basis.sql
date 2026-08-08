-- 가격 컬럼의 부가세(PPN) 기준 명시 (2026-08-04)
--
-- 운영 규칙(사용자 확정): **대리점가(dist_price_*)는 VAT 포함가, 그 외 가격은 VAT 미포함가.**
--   · 외부 자료를 반영할 때는 그 자료의 VAT 포함 여부를 먼저 확인하고 이 기준으로 환산한다.
--     예) ASCENDO MARGIN DASHBOARD_V3 는 VAT 포함가 → 입고가에 넣을 때 1.11 로 나눔
--         (update_prices_margin_dashboard_v3.sql).
--   · 화면 표기: Databases.vue 가격 탭 헤더에 '입고가(pcs) VAT 별도' / '대리점가(pcs) VAT 포함' 을 병기한다.
comment on column public.products_price.fob is 'FOB 단가(USD) — VAT 미포함';
comment on column public.products_price.wh_price_pcs is '입고가/pcs (Rp) — VAT 미포함';
comment on column public.products_price.wh_price_set is '입고가/set (Rp) — VAT 미포함 (타이어+튜브+플랩 세트)';
comment on column public.products_price.dist_price_pcs is '대리점가/pcs (Rp) — VAT 포함';
comment on column public.products_price.dist_price_set is '대리점가/set (Rp) — VAT 포함';
