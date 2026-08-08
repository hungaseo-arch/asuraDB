-- TBR 제원 대조·갱신 — 「TBR_카탈로그_브랜드별정리.xlsx」(2026-07-24 수정본) 기준
--
-- 출처: '00-Working/_sql_ascendo/TBR_카탈로그_브랜드별정리.xlsx' 시트 「통합 All」 59행
--   (원본 PDF = TBR Ascendo.pdf / Techking TBR.pdf, PT Ascendo Internasional)
--   ASCENDO 10패턴 30규격 / TECHKING 15패턴 29규격.
--   기존 products_spec_tbr 값은 PDF 렌더 이미지에서 읽어 넣은 것이라, 정식 표로 정리된
--   이 파일을 기준으로 값 정정 29건 · 공란 채움 72건을 반영한다(22행).
--
-- 적용 원칙
--   1) PR(ply_rating)은 덮어쓰지 않는다. PR 은 제품 SKU 의 정체성이고 하중·공기압이
--      PR 에 따라 달라지므로, 카탈로그 PR 과 다른 행은 아예 손대지 않았다(11행, 아래).
--   2) 쓰기 대상 = (브랜드·패턴·규격·PR) 완전일치 행, 또는 DB PR 이 null 이고
--      해당 패턴·규격의 카탈로그 행이 유일한 행(이때만 PR 도 함께 채움).
--
-- PR 불일치로 건너뛴 행(제품 PR ↔ 카탈로그 PR) — 제품 PR 또는 카탈로그 확인 필요:
--   id 21 ASCENDO AR585 11.00R20 (16↔18) / id 32 AR102HD 12.00R20 (20↔18)
--   id 61 AR102HD 9.00R20 (14↔16) / id 64 TK ETFN U 10.00R20 (18↔16)
--   id 65 TK SUPER AM S 10.00R20 (18↔16) / id 67 TK TKAL III 10.00R20 (18↔16)
--   id 72 TK ETFN U 11.00R20 (18↔16) / id 74 TK ETOT 11.00R20 (18↔16)
--   id 77 TK SUPER AM S 11.00R20 (18↔16) / id 80 TK TKAM II S 11.00R20 (18↔16)
--   id 113 TK TKAM S 8.25R16 (16↔14)
--
-- 카탈로그에만 있고 제품에 없는 규격: ASCENDO AR3137 7.50R16(14PR)·11.00R20(18PR),
--   TECHKING TKAM III XL 12.00R24(20PR) — DB 는 'TKAM II XL' 로 등록되어 있어 명칭 확인 필요.
--
-- 카탈로그 자체의 LI↔하중 불일치(원문 그대로 반영, 확인 필요):
--   id 13 ASCENDO AR112 11.00R20 — LI 152/149 인데 단륜 3350 (152 → 3550)
--   id 34 ASCENDO AR535 12.00R20 — LI 156/153 인데 3750/3450 (156/153 → 4000/3650)
--   id 90 TECHKING ETFN U 12.00R24 — 트레드 깊이 기존 32 → 카탈로그 23.5
--
-- 미반영 항목(테이블에 대응 컬럼 없음): 최대하중 Max Load(TECHKING 전용) · 장착위치 ·
--   노면조건 · 최대속도 · 주행거리 · 최대하중능력(%).

update public.products_spec_tbr set load_index = '149/146 J', rim_width = '7.50', overall_diameter_mm = 1050, section_width_mm = 276, tread_depth_mm = 14.5, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 2;
update public.products_spec_tbr set load_index = '152/149 J', rim_width = '8.00', overall_diameter_mm = 1083, section_width_mm = 288, tread_depth_mm = 16.5, single_load_kg = 3350, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 13;
update public.products_spec_tbr set single_load_kg = 3750, dual_load_kg = 3450, max_pressure_psi = 120, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 34;
update public.products_spec_tbr set overall_diameter_mm = 1127, section_width_mm = 308, tread_depth_mm = 24.5, max_pressure_psi = 135, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 37;
update public.products_spec_tbr set ply_rating = 18, load_index = '152/149 M', rim_width = '9.00', overall_diameter_mm = 1041, section_width_mm = 285, tread_depth_mm = 15, single_load_kg = 3550, dual_load_kg = 3250, max_pressure_psi = 130, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 46;
update public.products_spec_tbr set load_index = '122/120 L', single_load_kg = 1510, dual_load_kg = 1440, max_pressure_psi = 102, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 51;
update public.products_spec_tbr set load_index = '122/120 F', single_load_kg = 1510, dual_load_kg = 1440, max_pressure_psi = 102, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 54;
update public.products_spec_tbr set max_pressure_psi = 111, source_catalog = 'ASCENDO TBR 2026-07-24' where id = 55;
update public.products_spec_tbr set ply_rating = 16, load_index = '146/143 K', single_load_kg = 3000, dual_load_kg = 2725, max_pressure_psi = 120, source_catalog = 'TECHKING TBR 2026-07-24' where id = 66;
update public.products_spec_tbr set ply_rating = 16, load_index = '146/143 K', single_load_kg = 3000, dual_load_kg = 2725, max_pressure_psi = 120, source_catalog = 'TECHKING TBR 2026-07-24' where id = 68;
update public.products_spec_tbr set ply_rating = 16, load_index = '150/147 K', single_load_kg = 3350, dual_load_kg = 3075, max_pressure_psi = 120, source_catalog = 'TECHKING TBR 2026-07-24' where id = 75;
update public.products_spec_tbr set ply_rating = 18, load_index = '152/149 L', overall_diameter_mm = 1079, section_width_mm = 288, tread_depth_mm = 16, single_load_kg = 3550, dual_load_kg = 3250, max_pressure_psi = 135, source_catalog = 'TECHKING TBR 2026-07-24' where id = 79;
update public.products_spec_tbr set load_index = '160/157 K', tread_depth_mm = 23.5, dual_load_kg = 4125, max_pressure_psi = 130, source_catalog = 'TECHKING TBR 2026-07-24' where id = 90;
update public.products_spec_tbr set overall_diameter_mm = 1136, source_catalog = 'TECHKING TBR 2026-07-24' where id = 93;
update public.products_spec_tbr set overall_diameter_mm = 1136, source_catalog = 'TECHKING TBR 2026-07-24' where id = 94;
update public.products_spec_tbr set load_index = '152/148 M', dual_load_kg = 3150, max_pressure_psi = 120, source_catalog = 'TECHKING TBR 2026-07-24' where id = 101;
update public.products_spec_tbr set load_index = '122/118 L', overall_diameter_mm = 804, section_width_mm = 215, tread_depth_mm = 14, single_load_kg = 1500, dual_load_kg = 1320, max_pressure_psi = 110, source_catalog = 'TECHKING TBR 2026-07-24' where id = 105;
update public.products_spec_tbr set ply_rating = 14, load_index = '122/118 L', overall_diameter_mm = 804, section_width_mm = 215, tread_depth_mm = 14, single_load_kg = 1500, dual_load_kg = 1320, max_pressure_psi = 110, source_catalog = 'TECHKING TBR 2026-07-24' where id = 106;
update public.products_spec_tbr set load_index = '122/118 L', overall_diameter_mm = 804, section_width_mm = 215, tread_depth_mm = 14, single_load_kg = 1500, dual_load_kg = 1320, max_pressure_psi = 110, source_catalog = 'TECHKING TBR 2026-07-24' where id = 108;
update public.products_spec_tbr set ply_rating = 14, load_index = '122/118 L', overall_diameter_mm = 804, section_width_mm = 215, tread_depth_mm = 14, single_load_kg = 1500, dual_load_kg = 1320, max_pressure_psi = 110, source_catalog = 'TECHKING TBR 2026-07-24' where id = 109;
update public.products_spec_tbr set load_index = '122/120 L', dual_load_kg = 1400, source_catalog = 'TECHKING TBR 2026-07-24' where id = 110;
update public.products_spec_tbr set max_pressure_psi = 110, source_catalog = 'TECHKING TBR 2026-07-24' where id = 112;
