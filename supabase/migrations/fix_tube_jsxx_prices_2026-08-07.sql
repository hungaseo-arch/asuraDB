-- TUBE(ASCENDO) 소형 튜브 10종 정비 — 사용자 제공 가격표(2026-08-07) 대조 결과 반영
--
-- 대조 결과
--   · 제공 가격표의 wh_price 는 DB 값의 정확히 ×1.11 → **VAT 포함가**. 우리 기준(CLAUDE.md)은
--     wh_price_pcs = VAT 별도 / dist_price_pcs = VAT 포함 이므로, 9종의 입고가는 이미 일치한다(변경 없음).
--   · dist_price_pcs 도 9종 중 8종 일치. VA70012T75 만 910,000 → 자릿수 오타(가격표 91,000).
--   · 가격표의 VA213910J2(ASC 23*9-10JS2) 는 DB 에 VA23910J2 코드로 존재. 둘 다 SAP 거래이력에는
--     없는 코드 → 가격표 기준으로 코드 통일(rename). specs_tube·products_price 는 on update cascade.
--   · 10종 모두 is_active=false 였으나 SAP 상 2026-07 까지 매입·판매가 계속됨 → 활성화.
--     같은 품명(ASC 18*7-8JS2)의 중복 코드 VA1878J2 는 SAP 거래이력이 없어 비활성 처리(카탈로그 중복 방지).

begin;

-- 1) SKU 코드 통일: VA23910J2 → VA213910J2 (가격표 기준)
update public.products
   set sku = 'VA213910J2', updated_at = now()
 where sku = 'VA23910J2';

-- 2) VA213910J2 입고가 — 0 이던 값을 가격표 VAT 포함가 54,188 ÷ 1.11 로 역산해 채운다(확인 플래그).
update public.products_price
   set wh_price_pcs = 48818,
       dist_price_pcs = 70000,
       review_field = 'wh_price_pcs',
       review_note = '입고가 0 → 2026-08-07 가격표 VAT 포함가 54,188 ÷ 1.11 역산(48,818). VAT 별도 원본 확인 필요',
       updated_at = now()
 where sku = 'VA213910J2';

-- 3) 대리점가 자릿수 오타 정정 (910,000 → 91,000)
update public.products_price
   set dist_price_pcs = 91000, updated_at = now()
 where sku = 'VA70012T75' and dist_price_pcs = 910000;

-- 4) 가격표 10종 활성화
update public.products
   set is_active = true, updated_at = now()
 where sku in ('VA18708J2','VA60009J2','VA2189J2','VA213910J2','VA65010J2',
               'VA70012T75','VA28915T77','VA30015T77','VA60015T13','VA82515T77');

-- 5) 중복 코드 비활성 (VA18708J2 와 같은 품명 · SAP 거래이력 없음)
update public.products
   set is_active = false, updated_at = now()
 where sku = 'VA1878J2';

commit;
