-- ─────────────────────────────────────────────────────────────────────────────
-- 가격 컬럼 단품/세트 구분 명시: wh_price → wh_price_pcs, dist_price → dist_price_pcs
--   · 기존 *_set 컬럼(wh_price_set·dist_price_set)은 그대로 유지 → pcs/set 대칭.
--   · 의존 뷰(products_priced·products_sell)도 새 컬럼명으로 재생성.
--     - products_priced 는 출력 컬럼명이 바뀌므로 DROP 후 재생성(CREATE OR REPLACE 불가).
--     - products_sell 은 출력 컬럼(unit_price 등) 불변 → 참조만 갱신.
-- 적용: 1회(트랜잭션 원자적). 앱 코드는 새 컬럼명을 사용하므로 본 SQL과 함께 배포.
-- ─────────────────────────────────────────────────────────────────────────────
begin;

-- 1) 컬럼 rename (pcs = 단품 단가)
alter table public.products_price rename column wh_price   to wh_price_pcs;
alter table public.products_price rename column dist_price to dist_price_pcs;

comment on column public.products_price.wh_price_pcs   is '입고가(원가) · 단품(pcs) 단가';
comment on column public.products_price.dist_price_pcs is '대리점가 · 단품(pcs) 단가';

-- 2) products_priced 재생성 (권한 경로 평면 뷰 · invoker → 기저 RLS 존중)
drop view if exists public.products_priced;
create view public.products_priced
  with (security_invoker = true) as
select p.*,
       pp.weight_kg, pp.fob, pp.qty_40ft,
       pp.wh_price_pcs, pp.wh_price_set, pp.dist_price_pcs, pp.dist_price_set
from public.products p
left join public.products_price pp on pp.sku = p.sku;
grant select on public.products_priced to authenticated, service_role;

-- 3) products_sell 재생성 (정의자 뷰 · 원가 비노출 · 출력 컬럼 불변)
create or replace view public.products_sell
  with (security_invoker = false) as
select p.id, p.item, p.brand, p.description, p.sku, p.unit, p.is_active,
  (round(pp.wh_price_pcs / 0.70 / 1000::numeric) * 1000::numeric)::integer as unit_price,
  (round(pp.wh_price_set / 0.70 / 1000::numeric) * 1000::numeric)::integer as unit_price_set
from public.products p
join public.products_price pp on pp.sku = p.sku
where p.is_active = true;
grant select on public.products_sell to anon, authenticated, service_role;

commit;

-- PostgREST 스키마 캐시 리로드
notify pgrst, 'reload schema';
