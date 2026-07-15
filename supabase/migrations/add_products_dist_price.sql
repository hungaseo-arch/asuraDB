-- products.dist_price — 대리점가(Dist Price)
--
-- 견적서(Quote.vue)의 'Dist Price' 열이 참조한다.
-- 값이 없으면(null) 앱이 원가 기준 25% 마진 추천가로 대체한다:
--   추천 대리점가 = wh_price ÷ (1 − 0.25)   ← 가격비교(PriceCompare)와 동일한 마진 정의
-- 단위 주의: pcs 기준 단가. set 단위 라인은 dist_price 를 쓰지 않고 wh_price_set 기준 추천가를 쓴다.

alter table public.products add column if not exists dist_price numeric;

comment on column public.products.dist_price is
  '대리점가(IDR, pcs 기준). null 이면 앱에서 wh_price ÷ 0.75 (마진 25%) 추천가로 대체.';
