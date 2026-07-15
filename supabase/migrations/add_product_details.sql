-- 2026-07-01 — products 상세 컬럼 추가 ('제품' 상세페이지: 가격/규격/분류)
-- 기존: wh_price(WhPrice)·wh_price_set·unit 보유. 아래는 선택적(nullable) 확장 컬럼.
alter table public.products add column if not exists category      text;    -- 분류(카테고리)
alter table public.products add column if not exists spec          text;    -- 스펙(치수/패턴 등)
alter table public.products add column if not exists weight_kg     numeric; -- 중량(kg)
alter table public.products add column if not exists fob           numeric; -- FOB 단가
alter table public.products add column if not exists cif           numeric; -- CIF 단가
alter table public.products add column if not exists landed_cost   numeric; -- Landed Cost
alter table public.products add column if not exists selling_price numeric; -- 판매가(미입력 시 UI에서 wh_price/0.8 로 산출)
