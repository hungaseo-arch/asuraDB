-- products(sku, primary) ← specs_tube(sku, foreign) 연결
--
-- 주의: 적용 당시 테이블명은 tube_specs 였고, 같은 날 specs_tube 로 리네임되었다.
--       (제약은 리네임을 따라가므로 이미 적용된 DB 는 재실행 불필요 — 아래는 재현용)
-- 사전 상태: products.sku 430건 전부 채워짐·중복 0 (단 UNIQUE 제약 없음 → FK 대상 불가),
--            스펙 80건 중 products 매칭 65 / 고아 11 / sku NULL 4 / sku 중복 1.
-- 고아 11건은 '스펙은 있으나 가격표에 없는 튜브'로, products 에 보강해 FK 를 정상 적용한다.
-- 멱등: on conflict do nothing / if not exists 로 재실행 안전.

-- 1) 중복 스펙 정리 — VA12165T15 가 no=35(qty 없음) / no=65(qty=12) 로 2행.
--    내용 동일하므로 qty 가 채워진 no=65 를 남기고 no=35 삭제.
delete from public.specs_tube where no = 35 and sku = 'VA12165T15' and qty is null;

-- 2) 고아 11건을 products 에 보강
--    is_active=false 로 넣는 이유: 앱의 가격/견적/가격비교 화면은 모두 is_active=eq.true 로 조회한다.
--    가격(wh_price)을 아직 모르는 상태로 활성화하면 판매가가 0원으로 계산되어
--    0원 견적이 나갈 수 있으므로, 가격 확보 전까지 비활성 플레이스홀더로 둔다.
--    → 가격 입수 후: update public.products set wh_price=<가격>, is_active=true where sku='...';
--    category_id: 9=TUBE 일반, 10=TUBE Heavy Duty (기존 데이터 기준)
insert into public.products (sku, item, brand, unit, description, wh_price, wh_price_set, is_active, category_id) values
  ('VA120020T78',  'TUBE', 'ASCENDO', 'pcs', 'ASC 12.00-20TR78',             null, 0, false,  9),
  ('VA120020T78S', 'TUBE', 'ASCENDO', 'pcs', 'ASC 12.00-20TR78 Heavy Duty',  null, 0, false, 10),
  ('VA18708J2',    'TUBE', 'ASCENDO', 'pcs', 'ASC 18*7-8JS2',                null, 0, false,  9),
  ('VA60009J2',    'TUBE', 'ASCENDO', 'pcs', 'ASC 6.00-9JS2',                null, 0, false,  9),
  ('VA2189J2',     'TUBE', 'ASCENDO', 'pcs', 'ASC 21*8-9JS2',                null, 0, false,  9),
  ('VA65010J2',    'TUBE', 'ASCENDO', 'pcs', 'ASC 6.50-10JS2',               null, 0, false,  9),
  ('VA70012T75',   'TUBE', 'ASCENDO', 'pcs', 'ASC 7.00-12TR75',              null, 0, false,  9),
  ('VA60015T13',   'TUBE', 'ASCENDO', 'pcs', 'ASC 6.00-15TR13',              null, 0, false,  9),
  ('VA28915T77',   'TUBE', 'ASCENDO', 'pcs', 'ASC 28*9-15TR77',              null, 0, false,  9),
  ('VA30015T77',   'TUBE', 'ASCENDO', 'pcs', 'ASC 3.00-15TR77',              null, 0, false,  9),
  ('VA82515T77',   'TUBE', 'ASCENDO', 'pcs', 'ASC 8.25-15TR77',              null, 0, false,  9)
on conflict (sku) do nothing;

-- 3) products.sku UNIQUE — FK 참조 대상이 되기 위한 필수 조건
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'products_sku_key') then
    alter table public.products add constraint products_sku_key unique (sku);
  end if;
end $$;

-- 4) 외래키 tube_specs.sku → products.sku
--    on delete restrict: 스펙이 달린 상품이 products 에서 삭제되는 것을 차단
--    on update cascade : SKU 정정 시 스펙 행도 함께 따라감
--    sku 가 NULL 인 스펙 4건은 FK 적용 대상 아님(NULL 은 참조 검사 제외)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tube_specs_sku_fkey') then
    alter table public.specs_tube
      add constraint tube_specs_sku_fkey foreign key (sku)
      references public.products (sku) on update cascade on delete restrict;
  end if;
end $$;
