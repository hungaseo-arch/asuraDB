-- ASCENDO Pneumatic 타이어 16종 products 추가 (pneumatic.csv 기반)
--
-- 형식: 기존 products 컨벤션 일치
--   item='PNEUMATIC'(신규 카테고리), brand='ASCENDO', unit='pcs',
--   wh_price = IDR(Rupiah), wh_price_set=0, sku UNIQUE(필수)
-- SKU 규칙: PNE-<사이즈숫자>-<패턴>  (예: 6.50-10 AB700 → PNE-65010-AB700)
-- 멱등: sku 충돌 시 가격/설명/활성 갱신 (재실행 안전)
--
-- ⚠️ 가격 미정 2건(ASC 18X7-8, ASC 250-15)은 wh_price=0 으로 입력 — 추후 채워야 함.

insert into public.products (item, brand, description, sku, wh_price, wh_price_set, unit, is_active) values
  ('PNEUMATIC','ASCENDO','ASC 6.50-10 AB700',  'PNE-65010-AB700',    507834, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 28X9-15 AB700',  'PNE-28915-AB700',    994966, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 8.25-14 AB700',  'PNE-82514-AB700',   1692512, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 8.25-15 AB700',  'PNE-82515-AB700',   1306796, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 7.00-12 AB700',  'PNE-70012-AB700',    732441, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 8.25-12 AB700',  'PNE-82512-AB700',   1066803, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 7.00-9 AB700',   'PNE-7009-AB700',     568505, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 6.00-9 AB700',   'PNE-6009-AB700',     377783, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 18X7-8 AB700',   'PNE-1878-AB700',          0, 0,'pcs',true),  -- 가격 미정
  ('PNEUMATIC','ASCENDO','ASC 5.00-8 AB700',   'PNE-5008-AB700',     269023, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 8.25-20 AB700',  'PNE-82520-AB700',   1823579, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 9.00-20 AB700',  'PNE-90020-AB700',   2007688, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 250-15 AB700',   'PNE-25015-AB700',         0, 0,'pcs',true),  -- 가격 미정
  ('PNEUMATIC','ASCENDO','ASC 300-15 AB700',   'PNE-30015-AB700',   2328508, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 6.50-10 AB702S', 'PNE-65010-AB702S',   506665, 0,'pcs',true),
  ('PNEUMATIC','ASCENDO','ASC 28X9-15 AB702S', 'PNE-28915-AB702S',   986204, 0,'pcs',true)   -- 원본 28*9-15 → 28X9-15 정규화
on conflict (sku) do update set
  item         = excluded.item,
  brand        = excluded.brand,
  description  = excluded.description,
  wh_price     = excluded.wh_price,
  wh_price_set = excluded.wh_price_set,
  unit         = excluded.unit,
  is_active    = excluded.is_active,
  updated_at   = now();
