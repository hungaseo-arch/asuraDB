-- 솔리드·공기압 타이어 제원 갱신 — IND 카탈로그 통합 정리본 반영 (2026-08-04)
--
-- 출처: 'IND_솔리드_공기압_타이어_카탈로그_정리.xlsx' (2026-08-03 작성)
--   원본 = 'Industrial Tyre Ascendo.pdf' + 'Leaflet Diamond.pdf' (PT. Ascendo Internasional 배포본)
--
-- 매칭 원칙
--  1) 제품 설명에서 브랜드·시리즈·패턴·규격을 뽑아 카탈로그 행과 완전일치한 것만 반영한다.
--     유사 규격으로 대체하지 않는다.
--  2) '- 1/2M' 접미어, 규격 별칭 괄호(28*9-15 (8.15-15))는 같은 제원으로 본다.
--  3) 카탈로그에 없는 조합은 건너뛰고 아래 「미등재」에 남긴다.
--
-- 결과: SOLID 70/71행 · PNEU 13/21행 반영.
--   SOLID 값 변경 21건 — 신규 1(ASC 7.00-12 S2000), 패턴 표기 19(XN-018 (S300) → XN-018 등,
--   메인 표기 뒤 괄호 삭제 규칙 적용 · 괄호 안 시리즈는 새 series 컬럼으로 이관), 규격 표기 1(28X9-15).
--   PNEU 값 변경 0건 — 기존 13행이 카탈로그와 전부 일치(출처 표기만 통합본으로 갱신).
--
-- 컬럼 신설(카탈로그에 있으나 DB 에 없던 항목)
--   products_spec_solid.series  — 제품 라인. ASCENDO: S2000 / NON MARKING / S1000,
--                                 DIAMOND: S300(XN-018) / S400(XN-028). 기존 pattern 의 괄호 표기를 대체한다.
--   products_spec_solid.remarks — 카탈로그 주석(비오염 용도, 규격 별칭, 하중 기준 등) 영문 표기.
--   products_spec_pneu          — 카탈로그 10개 항목(PR·TT/TL·RIM·OD·SW·TD·WT·Max Load·Pres)이
--                                 전부 기존 컬럼에 있어 신설 없음.
--
-- 중복 컬럼 확인
--   · tire_type — 전 70행이 'Solid' 단일값이라 SOLID 탭에서 정보량이 없다. 컬럼은 보존하되
--     화면 헤더(Databases.vue SOLID_SPEC)에서는 제외한다.
--   · load_kg(구동륜) 과 load_6kmh_kg — DIAMOND XN-018/XN-028 은 두 값이 항상 같다(카탈로그 원본이 동일).
--     단 S200 라인은 서로 다르므로(예: 4.00-8 → 1,090 / 925) 별개 컬럼으로 유지한다.
--   · weight_kg — 제원표의 카탈로그 기준 중량. 가격 탭의 실중량(products_priced.weight_kg)과는
--     ±1 kg 내외로 다르며 용도(선적 계산)가 달라 별개로 둔다.
--
-- 미등재(카탈로그에 없어 제원 없음 — 확인 필요)
--   · SOLID 1건: ASC 23*10-12 S2000 (카탈로그 규격 목록에 없음)
--   · PNEU 8건: ASC 8.25-14 / 8.25-20 / 9.00-20 / 250-15 / 300-15 AB700,
--               ASC 6.50-10 · 28X9-15 AB702S(AB702S 패턴 자체가 카탈로그에 없음),
--               ASC 8.25-15 HS800 14
--   · 반대로 DIAMOND S200 라인 16개 규격은 카탈로그에 있으나 취급 제품이 없어 반영 대상에서 제외.
--
-- 확인 필요(원본 데이터 이슈)
--   · products 의 DIAMOND NON MARKING 품목은 SKU 와 설명의 규격이 서로 어긋나 있다
--     (예: SKU 1022006511010XN03(=6.50-10) 의 설명은 'DIAMOND 18*7-8 XN-028 NON MARKING').
--     제원은 설명 기준으로 붙였다.
--   · DIAMOND 카탈로그에는 NON MARKING 별도 제원이 없어 같은 규격 기본 제원을 적용했다(remarks 표기).

alter table public.products_spec_solid add column if not exists series  text;
alter table public.products_spec_solid add column if not exists remarks text;

comment on column public.products_spec_solid.series  is '제품 라인 — ASCENDO: S2000/NON MARKING/S1000, DIAMOND: S300(XN-018)/S400(XN-028)';
comment on column public.products_spec_solid.remarks is '카탈로그 주석(영문)';

-- ── SOLID 70행 ────────────────────────────────────────────────────────────────
insert into public.products_spec_solid
  (sku, brand, series, pattern, size, tire_type, rim_size, overall_diameter_mm, section_width_mm, weight_kg, load_kg, steer_load_kg, load_6kmh_kg, load_10kmh_kg, load_25kmh_kg, remarks, source_catalog)
values
  ('10220160110083003', 'ASCENDO', 'NON MARKING', 'S2000', '16X6-8', 'Solid', '4.33R', 415.0, 148.0, 16.5, 1495.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220180110081003', 'ASCENDO', 'NON MARKING', 'S2000', '18X7-8', 'Solid', '4.33R', 450.0, 153.0, 20.75, 2145.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220210110093003', 'ASCENDO', 'NON MARKING', 'S2000', '21X8-9', 'Solid', '6.00E', 522.0, 185.0, 35.0, 2755.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220230110093003', 'ASCENDO', 'NON MARKING', 'S2000', '23X9-10', 'Solid', '6.50F', 582.0, 203.0, 48.5, 3445.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220081110152003', 'ASCENDO', 'NON MARKING', 'S2000', '28X9-15', 'Solid', '7.00', 688.0, 212.0, 59.2, 3445.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors / Also marked 8.15-15', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220050110081003', 'ASCENDO', 'NON MARKING', 'S2000', '5.00-8', 'Solid', '3.00D', 452.0, 120.0, 16.35, 1415.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220060110091003', 'ASCENDO', 'NON MARKING', 'S1000', '6.00-9', 'Solid', '4.00', 525.0, 145.0, 27.6, 1885.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220065110101003', 'ASCENDO', 'NON MARKING', 'S1000', '6.50-10', 'Solid', '5.00', 572.0, 168.0, 38.0, 2340.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220070110121003', 'ASCENDO', 'NON MARKING', 'S1000', '7.00-12', 'Solid', '5.00', 655.0, 173.0, 48.9, 2920.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220075110163003', 'ASCENDO', 'NON MARKING', 'S2000', '7.50-16', 'Solid', '6.00', 780.0, 199.0, 76.6, 3950.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220085110153003', 'ASCENDO', 'NON MARKING', 'S2000', '8.25-15', 'Solid', '6.50F', 810.0, 208.0, 91.0, 4750.0, null, null, null, null, 'Non-marking compound for pharmaceutical and food & beverage floors', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220060110091000', 'ASCENDO', 'S1000', 'S1000', '6.00-9', 'Solid', '4.00', 525.0, 145.0, 27.6, 1885.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220060110093000', 'ASCENDO', 'S1000', 'S1000', '6.00-9', 'Solid', '4.00', 525.0, 145.0, 27.6, 1885.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220065110101000', 'ASCENDO', 'S1000', 'S1000', '6.50-10', 'Solid', '5.00', 572.0, 168.0, 38.0, 2340.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220065110101001', 'ASCENDO', 'S1000', 'S1000', '6.50-10', 'Solid', '5.00', 572.0, 168.0, 38.0, 2340.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220070110121000', 'ASCENDO', 'S1000', 'S1000', '7.00-12', 'Solid', '5.00', 655.0, 173.0, 48.9, 2920.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220070110123000', 'ASCENDO', 'S1000', 'S1000', '7.00-12', 'Solid', '5.00', 655.0, 173.0, 48.9, 2920.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220100110200200', 'ASCENDO', 'S2000', 'Smooth', '10.00-20', 'Solid', '7.50', 1015.0, 218.0, 156.75, 6000.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220100110201000', 'ASCENDO', 'S2000', 'S2000', '10.00-20', 'Solid', '7.50', 1035.0, 253.0, 170.7, 6000.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220015450081000', 'ASCENDO', 'S2000', 'S2000', '15X4.5-8', 'Solid', '3.00D', 382.0, 109.0, 9.7, 1040.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220160110083000', 'ASCENDO', 'S2000', 'S2000', '16X6-8', 'Solid', '4.33R', 415.0, 148.0, 16.5, 1495.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220160110083002', 'ASCENDO', 'S2000', 'S2000', '16X6-8', 'Solid', '4.33R', 415.0, 148.0, 16.5, 1495.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220180110081000', 'ASCENDO', 'S2000', 'S2000', '18X7-8', 'Solid', '4.33R', 450.0, 153.0, 20.75, 2145.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220180110081001', 'ASCENDO', 'S2000', 'S2000', '18X7-8', 'Solid', '4.33R', 450.0, 153.0, 20.75, 2145.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220025110151000', 'ASCENDO', 'S2000', 'S2000', '2.50-15', 'Solid', '7.00', 715.0, 226.0, 69.0, 4745.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220025110152000', 'ASCENDO', 'S2000', 'S2000', '2.50-15', 'Solid', '7.00', 715.0, 226.0, 69.0, 4745.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220200500102000', 'ASCENDO', 'S2000', 'S2000', '200/50-10', 'Solid', '6.50F', 460.0, 195.0, 26.0, 2470.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220210110093000', 'ASCENDO', 'S2000', 'S2000', '21X8-9', 'Solid', '6.00E', 522.0, 185.0, 35.0, 2755.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220210110093001', 'ASCENDO', 'S2000', 'S2000', '21X8-9', 'Solid', '6.00E', 522.0, 185.0, 35.0, 2755.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220230110093000', 'ASCENDO', 'S2000', 'S2000', '23X9-10', 'Solid', '6.50F', 582.0, 203.0, 48.5, 3445.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220230110093001', 'ASCENDO', 'S2000', 'S2000', '23X9-10', 'Solid', '6.50F', 582.0, 203.0, 48.5, 3445.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220081110152000', 'ASCENDO', 'S2000', 'S2000', '28X9-15', 'Solid', '7.00', 688.0, 212.0, 59.2, 3445.0, null, null, null, null, 'Also marked 8.15-15', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220081110152001', 'ASCENDO', 'S2000', 'S2000', '28X9-15', 'Solid', '7.00', 688.0, 212.0, 59.2, 3445.0, null, null, null, null, 'Also marked 8.15-15', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220030110151000', 'ASCENDO', 'S2000', 'S2000', '3.00-15', 'Solid', '8.00', 802.0, 258.0, 109.0, 5850.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220300110153000', 'ASCENDO', 'S2000', 'S2000', '3.00-15', 'Solid', '8.00', 802.0, 258.0, 109.0, 5850.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220300110153001', 'ASCENDO', 'S2000', 'S2000', '3.00-15', 'Solid', '8.00', 802.0, 258.0, 109.0, 5850.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220040110080200', 'ASCENDO', 'S2000', 'S200 RIB', '4.00-8', 'Solid', '3.00D', 404.0, 113.0, 11.3, 950.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220050110081000', 'ASCENDO', 'S2000', 'S2000', '5.00-8', 'Solid', '3.00D', 452.0, 120.0, 16.35, 1415.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220050110081001', 'ASCENDO', 'S2000', 'S2000', '5.00-8', 'Solid', '3.00D', 452.0, 120.0, 16.35, 1415.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220060110152000', 'ASCENDO', 'S2000', 'S2000', '6.00-15', 'Solid', '4.50E', 690.0, 153.0, 43.0, 2455.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220060110092000', 'ASCENDO', 'S2000', 'S2000', '6.00-9', 'Solid', '4.00', 525.0, 145.0, 27.6, 1885.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220065110102000', 'ASCENDO', 'S2000', 'S2000', '6.50-10', 'Solid', '5.00', 572.0, 162.0, 36.5, 2340.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220070110122000', 'ASCENDO', 'S2000', 'S2000', '7.00-12', 'Solid', '5.00', 655.0, 173.0, 48.9, 2920.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220070110151000', 'ASCENDO', 'S2000', 'S2000', '7.00-15', 'Solid', '5.50', 733.0, 171.0, 57.7, 3545.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220700110153000', 'ASCENDO', 'S2000', 'S2000', '7.00-15', 'Solid', '5.50', 733.0, 171.0, 57.7, 3545.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220700110153001', 'ASCENDO', 'S2000', 'S2000', '7.00-15', 'Solid', '5.50', 733.0, 171.0, 57.7, 3545.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220075110163000', 'ASCENDO', 'S2000', 'S2000', '7.50-16', 'Solid', '6.00', 780.0, 199.0, 76.6, 3950.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220075110163001', 'ASCENDO', 'S2000', 'S2000', '7.50-16', 'Solid', '6.00', 780.0, 199.0, 76.6, 3950.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220085110153000', 'ASCENDO', 'S2000', 'S2000', '8.25-15', 'Solid', '6.50F', 810.0, 208.0, 91.0, 4750.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220085110153001', 'ASCENDO', 'S2000', 'S2000', '8.25-15', 'Solid', '6.50F', 810.0, 208.0, 91.0, 4750.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('10220090110201000', 'ASCENDO', 'S2000', 'S2000', '9.00-20', 'Solid', '7.00', 997.0, 233.0, 151.0, 5400.0, null, null, null, null, null, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022023011009XN00', 'DIAMOND', 'S300', 'XN-018', '23X9-10', 'Solid', '6.50', 592.0, 202.0, 47.8, 3445.0, 2650.0, 3445.0, 3125.0, 2650.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022023011009XN02', 'DIAMOND', 'S300', 'XN-018', '23X9-10', 'Solid', '6.50', 592.0, 202.0, 47.8, 3445.0, 2650.0, 3445.0, 3125.0, 2650.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022023011009XN03', 'DIAMOND', 'S300', 'XN-018', '23X9-10', 'Solid', '6.50', 592.0, 202.0, 47.8, 3445.0, 2650.0, 3445.0, 3125.0, 2650.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022008511015XN00', 'DIAMOND', 'S300', 'XN-018', '8.25-15', 'Solid', '6.50', 819.0, 212.0, 92.0, 4615.0, 3550.0, 4615.0, 4190.0, 3550.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022008511015XN03', 'DIAMOND', 'S300', 'XN-018', '8.25-15', 'Solid', '6.50', 819.0, 212.0, 92.0, 4615.0, 3550.0, 4615.0, 4190.0, 3550.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022006511010XN03', 'DIAMOND', 'S400', 'XN-028', '18X7-8', 'Solid', '4.33', 452.0, 165.0, 21.8, 2145.0, 1650.0, 2145.0, 1945.0, 1650.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022018011008XN00', 'DIAMOND', 'S400', 'XN-028', '18X7-8', 'Solid', '4.33', 452.0, 165.0, 21.8, 2145.0, 1650.0, 2145.0, 1945.0, 1650.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022006011009XN03', 'DIAMOND', 'S400', 'XN-028', '21X8-9', 'Solid', '6.00', 526.0, 190.0, 34.4, 2755.0, 2120.0, 2755.0, 2500.0, 2120.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022021011009XN00', 'DIAMOND', 'S400', 'XN-028', '21X8-9', 'Solid', '6.00', 526.0, 190.0, 34.4, 2755.0, 2120.0, 2755.0, 2500.0, 2120.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022008111015XN00', 'DIAMOND', 'S400', 'XN-028', '28X9-15', 'Solid', '7.00', 699.0, 218.0, 59.3, 3900.0, 3000.0, 3900.0, 3540.0, 3000.0, 'Also marked 8.15-15 / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022008111015XN03', 'DIAMOND', 'S400', 'XN-028', '28X9-15', 'Solid', '7.00', 699.0, 218.0, 59.3, 3900.0, 3000.0, 3900.0, 3540.0, 3000.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Also marked 8.15-15 / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022005011008XN00', 'DIAMOND', 'S400', 'XN-028', '5.00-8', 'Solid', '3.00', 455.0, 120.0, 15.4, 1415.0, 1090.0, 1415.0, 1285.0, 1090.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022005011008XN03', 'DIAMOND', 'S400', 'XN-028', '5.00-8', 'Solid', '3.00', 455.0, 120.0, 15.4, 1415.0, 1090.0, 1415.0, 1285.0, 1090.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022006011009XN00', 'DIAMOND', 'S400', 'XN-028', '6.00-9', 'Solid', '4.00', 530.0, 143.0, 25.4, 1885.0, 1450.0, 1885.0, 1710.0, 1450.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022018011008XN03', 'DIAMOND', 'S400', 'XN-028', '6.00-9', 'Solid', '4.00', 530.0, 143.0, 25.4, 1885.0, 1450.0, 1885.0, 1710.0, 1450.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022006511010XN00', 'DIAMOND', 'S400', 'XN-028', '6.50-10', 'Solid', '5.00', 576.0, 162.0, 35.4, 2340.0, 1800.0, 2340.0, 2125.0, 1800.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022021011009XN03', 'DIAMOND', 'S400', 'XN-028', '6.50-10', 'Solid', '5.00', 576.0, 162.0, 35.4, 2340.0, 1800.0, 2340.0, 2125.0, 1800.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022007011012XN00', 'DIAMOND', 'S400', 'XN-028', '7.00-12', 'Solid', '5.00', 660.0, 177.0, 47.9, 2920.0, 2240.0, 2920.0, 2645.0, 2240.0, 'Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('1022007011012XN03', 'DIAMOND', 'S400', 'XN-028', '7.00-12', 'Solid', '5.00', 660.0, 177.0, 47.9, 2920.0, 2240.0, 2920.0, 2645.0, 2240.0, 'Non-marking item; catalog has no separate spec, same-size standard spec applied / Drive load equals the ≤6 km/h rating in this catalog', 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)')
on conflict (sku) do update set
      brand = excluded.brand,
      series = excluded.series,
      pattern = excluded.pattern,
      size = excluded.size,
      tire_type = excluded.tire_type,
      rim_size = excluded.rim_size,
      overall_diameter_mm = excluded.overall_diameter_mm,
      section_width_mm = excluded.section_width_mm,
      weight_kg = excluded.weight_kg,
      load_kg = excluded.load_kg,
      steer_load_kg = excluded.steer_load_kg,
      load_6kmh_kg = excluded.load_6kmh_kg,
      load_10kmh_kg = excluded.load_10kmh_kg,
      load_25kmh_kg = excluded.load_25kmh_kg,
      remarks = excluded.remarks,
      source_catalog = excluded.source_catalog;

-- ── PNEU 13행 ─────────────────────────────────────────────────────────────────
insert into public.products_spec_pneu
  (sku, brand, pattern, size, ply_rating, tube_type, rim_size, overall_diameter_mm, section_width_mm, tread_depth_mm, weight_kg, max_load_kg, max_pressure_psi, source_catalog)
values
  ('PNE-1878-AB700', 'ASCENDO', 'AB700', '18X7-8', 14, 'TT', '4.33R', 465.0, 173.0, 16.0, 8.05, 1440.0, 130.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('I1-28915700', 'ASCENDO', 'AB700', '28X9-15', 16, 'TT', '7.00', 690.0, 220.0, 19.0, 24.5, 3115.0, 145.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-28915-AB700', 'ASCENDO', 'AB700', '28X9-15', 16, 'TT', '7.00', 690.0, 220.0, 19.0, 24.5, 3115.0, 145.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-5008-AB700', 'ASCENDO', 'AB700', '5.00-8', 10, 'TT', '3.50D', 470.0, 137.0, 12.0, 6.39, 1150.0, 145.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('I1-6009700', 'ASCENDO', 'AB700', '6.00-9', 12, 'TT', '4.00E', 533.0, 160.0, 14.0, 9.5, 1675.0, 150.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-6009-AB700', 'ASCENDO', 'AB700', '6.00-9', 12, 'TT', '4.00E', 533.0, 160.0, 14.0, 9.5, 1675.0, 150.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('I1-65010700', 'ASCENDO', 'AB700', '6.50-10', 12, 'TT', '5.00F', 586.0, 190.0, 15.0, 12.0, 1895.0, 125.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-65010-AB700', 'ASCENDO', 'AB700', '6.50-10', 12, 'TT', '5.00F', 586.0, 190.0, 15.0, 12.0, 1895.0, 125.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('I1-70012700', 'ASCENDO', 'AB700', '7.00-12', 12, 'TT', '5.00S', 665.0, 190.0, 16.5, 18.5, 2375.0, 125.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-70012-AB700', 'ASCENDO', 'AB700', '7.00-12', 12, 'TT', '5.00S', 665.0, 190.0, 16.5, 18.5, 2375.0, 125.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-7009-AB700', 'ASCENDO', 'AB700', '7.00-9', 10, 'TT', '5.00S', 590.0, 190.0, 14.0, 12.05, 1995.0, 125.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-82512-AB700', 'ASCENDO', 'AB700', '8.25-12', 12, 'TT', '6.50', 765.0, 235.0, 18.0, 22.18, 3060.0, 105.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)'),
  ('PNE-82515-AB700', 'ASCENDO', 'AB700', '8.25-15', 14, 'TT', '6.50', 820.0, 235.0, 19.5, 31.0, 3775.0, 120.0, 'IND Solid & Pneumatic Catalog 2026-08-03 (Ascendo + Diamond)')
on conflict (sku) do update set
      brand = excluded.brand,
      pattern = excluded.pattern,
      size = excluded.size,
      ply_rating = excluded.ply_rating,
      tube_type = excluded.tube_type,
      rim_size = excluded.rim_size,
      overall_diameter_mm = excluded.overall_diameter_mm,
      section_width_mm = excluded.section_width_mm,
      tread_depth_mm = excluded.tread_depth_mm,
      weight_kg = excluded.weight_kg,
      max_load_kg = excluded.max_load_kg,
      max_pressure_psi = excluded.max_pressure_psi,
      source_catalog = excluded.source_catalog;
