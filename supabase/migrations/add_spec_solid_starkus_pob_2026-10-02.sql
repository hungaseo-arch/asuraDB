-- 솔리드 POB(Press-On Band) 제원 신규 등록 — STARKUS 16x6x10½ 4종 (2026-10-02)
--
-- 출처: 'Solid Tire Specification' 표(이미지, 2026-10-02 수신) — Price(-PPn)·SW·OD·WT·Load Capacity
--
-- · 신규 제품 4건(products·products_price·products_spec_solid). DB 에 STARKUS·POB 품목이 없어 함께 생성.
--   SKU 는 임시코드(STK-…) — ERP 정식 코드 확정 시 교체 필요(review_note 표기).
-- · 단가 = Price -PPn(VAT 미포함) → products_price.wh_price_pcs. 2026-10-02 Arami 튜브 HD+ 처리와 동일 기준.
-- · series = 컴파운드 색(GREY / BLACK), pattern = SM-100 / TR-200, tire_type = 'Press-On'.
-- · RIM 은 원본 공란 → null. POB 는 림 대신 내경 10½ inch 스틸밴드에 압입.
-- · Load Capacity: 원본 헤더 'Usage / Kg / Lbs' 아래 값 1,910 / 1,570 / 1,360 이 단위상 맞지 않아
--   (1,570 kg ≠ 1,360 lbs) 하중 컬럼에 넣지 않고 remarks 에 원문 그대로 보존. 속도구간 확인 후 이관 필요.

insert into public.products (item, brand, description, sku, unit, category_id, is_active)
values
  ('SOLID','STARKUS','STARKUS 16*6*10.5 SM-100 GREY POB',  'STK-16610-SM100-GY','pcs',8,true),
  ('SOLID','STARKUS','STARKUS 16*6*10.5 TR-200 GREY POB',  'STK-16610-TR200-GY','pcs',8,true),
  ('SOLID','STARKUS','STARKUS 16*6*10.5 SM-100 BLACK POB', 'STK-16610-SM100-BK','pcs',8,true),
  ('SOLID','STARKUS','STARKUS 16*6*10.5 TR-200 BLACK POB', 'STK-16610-TR200-BK','pcs',8,true)
on conflict do nothing;

insert into public.products_price (sku, description, weight_kg, wh_price_pcs, review_note)
values
  ('STK-16610-SM100-GY','STARKUS 16*6*10.5 SM-100 GREY POB', 18.27, 1205138, 'Starkus Price -PPn 2026-10-02 / 임시 SKU — ERP 코드 확인 필요'),
  ('STK-16610-TR200-GY','STARKUS 16*6*10.5 TR-200 GREY POB', 17.81, 1186015, 'Starkus Price -PPn 2026-10-02 / 임시 SKU — ERP 코드 확인 필요'),
  ('STK-16610-SM100-BK','STARKUS 16*6*10.5 SM-100 BLACK POB',17.99,  964146, 'Starkus Price -PPn 2026-10-02 / 임시 SKU — ERP 코드 확인 필요'),
  ('STK-16610-TR200-BK','STARKUS 16*6*10.5 TR-200 BLACK POB',17.34,  948741, 'Starkus Price -PPn 2026-10-02 / 임시 SKU — ERP 코드 확인 필요')
on conflict (sku) do update set weight_kg = excluded.weight_kg, wh_price_pcs = excluded.wh_price_pcs,
  review_note = excluded.review_note, updated_at = now();

insert into public.products_spec_solid (sku, brand, series, pattern, size, tire_type, rim_size,
  overall_diameter_mm, section_width_mm, weight_kg, remarks, source_catalog)
select v.sku, 'STARKUS', v.series, v.pat, '16X6X10.5', 'Press-On', null, v.od, v.sw, v.wt,
       'Press-on band (POB) / Load Capacity as printed (Usage / Kg / Lbs): 1,910 / 1,570 / 1,360', 'Starkus Solid Tire Specification 2026-10-02'
from (values
  ('STK-16610-SM100-GY','GREY', 'SM-100',407,143,18.27),
  ('STK-16610-TR200-GY','GREY', 'TR-200',404,147,17.81),
  ('STK-16610-SM100-BK','BLACK','SM-100',407,143,17.99),
  ('STK-16610-TR200-BK','BLACK','TR-200',404,147,17.34)
) as v(sku, series, pat, od, sw, wt)
where not exists (select 1 from public.products_spec_solid s where s.sku = v.sku);
