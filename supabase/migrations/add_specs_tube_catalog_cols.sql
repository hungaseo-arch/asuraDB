-- specs_tube 카탈로그 보강 (2026-08-04)
--
-- 출처: PT. Ascendo Internasional 'Tube Ascendo.pdf' (Google Drive, 2026-07-24 수정본, SNI 6700:2012)
--       → Ascendo_Tube_Catalog.xlsx '튜브 카탈로그' 64행(규격·밸브 조합 기준)
--
-- 대조 원칙
--   1) 매칭 키 = (규격, 밸브, 등급). 규격은 '600-14'↔'6.00-14', '13.00/1.400-24'(원본 오기)↔'13.00/14.00-24',
--      밸브는 공백 제거 + 끝의 'A'(TR75A↔TR75) 를 같은 값으로 보고 맞췄다. 등급(표준↔Heavy Duty)이
--      다른 행으로는 대체하지 않는다 — 포장·입수량이 등급마다 다르기 때문(HD 4건이 이 때문에 미수록으로 남음).
--   2) valve 는 덮어쓰지 않는다 — 밸브 종류는 제품 SKU 의 정체성이라 표기가 달라도 보고만 한다
--      (VA82520T75A: DB 'TR75A' ↔ 카탈로그 'TR75').
--   3) 생산 데이터(w_std·w_min·w_max·lebar·tebal·mold_qty·capa_day·capa_month)는 카탈로그에 없어 손대지 않는다.
--   4) 카탈로그 미수록 행(18건)도 category_label·sack_qty·box_qty 는 기존 packaging/qty 로 채워 컬럼을 비우지 않는다.
--
-- 중복 컬럼 확인 결과 (카탈로그 ↔ 기존 컬럼)
--   · 규격(SIZE) ↔ size          : 4건 정정. '13.00/1.400-24'→'13.00/14.00-24'(3건, 원본 오기),
--                                  '4.00/60-15.5'→'400/60-15.5'(메트릭 규격, 단면폭 400 mm).
--   · 규격 표시 ↔ size_label     : 30건 정정. 튜브는 레이디얼이 아니므로 '10.00R20' 표기를 '10.00-20' 로 통일.
--                                  '/'가 든 메트릭·복합 규격(400/60-15.5·13.00/14.00-24)은 카탈로그 표기 유지.
--   · 밸브(VALVE) ↔ valve        : 1건 표기 상이(위 원칙 2로 미변경).
--   · 구분(Category) ↔ category  : 기존 Type 1~4 는 내부 생산분류라 그대로 두고, 카탈로그 구분을
--                                  새 컬럼 category_label 로 받는다(스펙 탭 표시는 category_label 기준).
--                                  카탈로그에 없는 Type 4(지게차·산업용 11건)는 '지게차·산업용' 으로 채웠다.
--   · 포장 ↔ packaging + qty     : 2건 정정 — VA131424T78S Box 4→3, VA149247218 Box 4→5.
--                                  카탈로그는 SACK/BOX 를 열로 나눠 표기하므로 sack_qty·box_qty 를 신설한다
--                                  (한 행이 두 포장을 동시에 제공하는 경우는 카탈로그에 없음 — 생성 시 assert 로 확인).
--   · 비고(Keterangan)           : 기존에 없던 항목 → remarks 신설.
--
-- 신규 컬럼: category_label, sack_qty, box_qty, remarks, source_catalog
--
-- 매칭 결과: specs_tube 83행 중 65행이 카탈로그와 연결(제품 SKU 기준 82건 중 64건).
--            카탈로그 64행은 전부 소비됨.
--
-- 카탈로그 미수록 18건(기존 값 유지, source_catalog = null)
--   Type 2  VA70015T75S · VA70016T75S · VA140025T179S · VA160025T179S  ← 해당 규격의 Heavy Duty 행이 카탈로그에 없음
--   Type 3  VA11224T218(11.2-24 TR218) · VA19524TR218(19.5-24 TR218) · VA23126T218(23.1-26 TR218)
--   Type 4  VA1878J2 · VA18708J2(18x7-8 JS2 중복 SKU) · VA2189J2 · VA23910J2 · VA60009J2 · VA65010J2 ·
--           VA70012T75 · VA60015T13 · VA28915T77 · VA30015T77 · VA82515T77  ← 지게차·산업용, 카탈로그 대상 외
--
-- 비고
--   · 카탈로그 '500-10'(원본에 밸브 표기 없음) 1행은 대응 제품이 없어 sku = null 행으로 남는다.
--   · 카탈로그 원본 64행은 '13.00/1.400-24' 로 적혀 있어 그 비고를 remarks 에 그대로 옮겼다.

alter table public.specs_tube
  add column if not exists category_label text,   -- 카탈로그 구분: 표준 / 고하중 / 건설·농업용 / 건설용 고하중 / 지게차·산업용
  add column if not exists sack_qty smallint,     -- SACK 포장 입수량(EA). null = 해당 포장 미제공
  add column if not exists box_qty smallint,      -- BOX 포장 입수량(EA). null = 해당 포장 미제공
  add column if not exists remarks text,          -- 비고(Keterangan)
  add column if not exists source_catalog text;

update public.specs_tube t set
  size = v.size, size_label = v.size_label, category_label = v.category_label,
  sack_qty = v.sack_qty, box_qty = v.box_qty, packaging = v.packaging, qty = v.qty,
  remarks = v.remarks, source_catalog = v.source_catalog
from (values
  (42, 'VA160025T179', '16.00-25', '16.00-25', '건설·농업용', null, 3, 'Box', 3, null, 'Ascendo Tube Catalog 2026-07-24'),
  (4, 'VA60014T13', '600-14', '6.00-14', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (5, 'VA65014T13', '650-14', '6.50-14', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (6, 'VA70015T75', '700-15', '7.00-15', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (7, 'VA70016T75', '700-16', '7.00-16', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (8, 'VA70016T177', '700-16', '7.00-16', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (9, 'VA75016T75A', '750-16', '7.50-16', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (10, 'VA75016T177', '750-16', '7.50-16', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (23, 'VA75016T177S', '750-16', '7.50-16', '고하중', null, 9, 'Box', 9, null, 'Ascendo Tube Catalog 2026-07-24'),
  (12, 'VA82516T177', '825-16', '8.25-16', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (24, 'VA82516T177S', '825-16', '8.25-16', '고하중', null, 9, 'Box', 9, null, 'Ascendo Tube Catalog 2026-07-24'),
  (14, 'VA82520T177A', '825-20', '8.25-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (25, 'VA82520T78S', '825-20', '8.25-20', '고하중', null, 6, 'Box', 6, null, 'Ascendo Tube Catalog 2026-07-24'),
  (15, 'VA90020T78', '900-20', '9.00-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (16, 'VA100020T78', '1000-20', '10.00-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (17, 'VA110020T78', '1100-20', '11.00-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (19, 'VA120020T179', '1200-20', '12.00-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (30, 'VA120020T179S', '1200-20', '12.00-20', '고하중', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (20, 'VA120024T78', '12.00-24', '12.00-24', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (54, 'VA816T13', '8-16', '8-16', '건설·농업용', null, 15, 'Box', 15, null, 'Ascendo Tube Catalog 2026-07-24'),
  (55, 'VA818T13', '8-18', '8-18', '건설·농업용', null, 15, 'Box', 15, null, 'Ascendo Tube Catalog 2026-07-24'),
  (36, 'VA1258018T218', '12.5/80-18', '12.5/80-18', '건설·농업용', null, 10, 'Box', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (37, 'VA140020T78', '14.00-20', '14.00-20', '건설·농업용', null, 5, 'Box', 5, null, 'Ascendo Tube Catalog 2026-07-24'),
  (56, 'VA167020T75', '16.0/70-20', '16.0/70-20', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (57, 'VA83824T218', '8.3/8-24', '8.3/8-24', '건설·농업용', null, 10, 'Box', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (58, 'VA93924T218', '9.3/9-24', '9.3/9-24', '건설·농업용', null, 10, 'Box', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (59, 'VA11224T218', '11.2 - 24', '11.2-24', '건설·농업용', null, 6, 'Box', 6, null, null),
  (38, 'VA12424T218', '12.4-24', '12.4-24', '건설·농업용', null, 6, 'Box', 6, null, 'Ascendo Tube Catalog 2026-07-24'),
  (21, 'VA131424T78', '13.00/14.00-24', '13.00/14.00-24', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (22, 'VA131424T179', '13.00/14.00-24', '13.00/14.00-24', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (32, 'VA131424T78S', '13.00/14.00-24', '13.00/14.00-24', '건설용 고하중', null, 3, 'Box', 3, '원본 카탈로그 표기 그대로. 13.00/14.00-24의 오기로 추정', 'Ascendo Tube Catalog 2026-07-24'),
  (41, 'VA15525T179', '15.5-25', '15.5-25', '건설·농업용', null, 5, 'Box', 5, null, 'Ascendo Tube Catalog 2026-07-24'),
  (43, 'VA17525T1175', '17.5-25', '17.5-25', '건설·농업용', null, 3, 'Box', 3, null, 'Ascendo Tube Catalog 2026-07-24'),
  (44, 'VA17525T179', '17.5-25', '17.5-25', '건설·농업용', null, 3, 'Box', 3, null, 'Ascendo Tube Catalog 2026-07-24'),
  (34, 'VA160025T179S', '16.00-25', '16.00-25', '고하중', null, 3, 'Box', 3, null, null),
  (45, 'VA180025T179', '18.00-25', '18.00-25', '건설·농업용', null, 2, 'Box', 2, null, 'Ascendo Tube Catalog 2026-07-24'),
  (46, 'VA20525T1175', '20.5-25', '20.5-25', '건설·농업용', null, 2, 'Box', 2, null, 'Ascendo Tube Catalog 2026-07-24'),
  (47, 'VA20525T179', '20.5-25', '20.5-25', '건설·농업용', null, 2, 'Box', 2, null, 'Ascendo Tube Catalog 2026-07-24'),
  (48, 'VA23525T1175', '23.5-25', '23.5-25', '건설·농업용', null, 2, 'Box', 2, null, 'Ascendo Tube Catalog 2026-07-24'),
  (49, 'VA23525T179', '23.5-25', '23.5-25', '건설·농업용', null, 2, 'Box', 2, null, 'Ascendo Tube Catalog 2026-07-24'),
  (61, 'VA13614926T218', '13.6/14.9-26', '13.6/14.9-26', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (50, 'VA16928T218', '16.9-28', '16.9-28', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (51, 'VA16928T220', '16.9-28', '16.9-28', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (52, 'VA18430T218', '18.4-30', '18.4-30', '건설·농업용', null, 3, 'Box', 3, null, 'Ascendo Tube Catalog 2026-07-24'),
  (53, 'VA18434T218', '18.4-34', '18.4-34', '건설·농업용', null, 3, 'Box', 3, null, 'Ascendo Tube Catalog 2026-07-24'),
  (18, 'VA120020T78', '1200-20', '12.00-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (29, 'VA120020T78S', '1200-20', '12.00-20', '고하중', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (11, 'VA82516T75A', '825-16', '8.25-16', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (1, null, '500-10', '5.00-10', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (2, 'VA50012T13', '500-12', '5.00-12', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (3, 'VA55013T13', '550-13', '5.50-13', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (26, 'VA90020T78S', '900-20', '9.00-20', '고하중', null, 6, 'Box', 6, null, 'Ascendo Tube Catalog 2026-07-24'),
  (27, 'VA100020T78S', '1000-20', '10.00-20', '고하중', null, 5, 'Box', 5, null, 'Ascendo Tube Catalog 2026-07-24'),
  (28, 'VA110020T78S', '1100-20', '11.00-20', '고하중', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (31, 'VA120024TR78HD', '12.00-24', '12.00-24', '고하중', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (60, 'VA149247218', '14.9-24', '14.9-24', '건설·농업용', null, 5, 'Box', 5, null, 'Ascendo Tube Catalog 2026-07-24'),
  (39, 'VA16924T218', '16.9-24', '16.9-24', '건설·농업용', null, 5, 'Box', 5, null, 'Ascendo Tube Catalog 2026-07-24'),
  (40, 'VA140025T179', '14.00-25', '14.00-25', '건설·농업용', null, 5, 'Box', 5, null, 'Ascendo Tube Catalog 2026-07-24'),
  (33, 'VA140025T179S', '14.00-25', '14.00-25', '고하중', null, 3, 'Box', 3, null, null),
  (84, 'VA1878J2', '18x7-8', '18*7-8', '지게차·산업용', 10, null, 'Sack', 10, null, null),
  (63, 'VA4006011555T', '400/60-15.5', '400/60-15.5', '건설·농업용', null, 6, 'Box', 6, null, 'Ascendo Tube Catalog 2026-07-24'),
  (65, 'VA12165T15', '12-16.5', '12-16.5', '건설·농업용', null, 12, 'Box', 12, null, 'Ascendo Tube Catalog 2026-07-24'),
  (66, 'VA1058018T15', '10.5/80-18', '10.5/80-18', '건설·농업용', null, 10, 'Box', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (64, 'VA160020T78', '16.00-20', '16.00-20', '건설·농업용', null, 3, 'Box', 3, null, 'Ascendo Tube Catalog 2026-07-24'),
  (67, 'VA19524TR218', '19.5-24', '19.5-24', '건설·농업용', null, 4, 'Box', 4, null, null),
  (68, 'VA23126T179', '23.1-26', '23.1-26', '건설·농업용', null, 2, 'Box', 2, null, 'Ascendo Tube Catalog 2026-07-24'),
  (69, 'VA23126T218', '23.1-26', '23.1-26', '건설·농업용', null, 2, 'Box', 2, null, null),
  (70, 'VA1241128T218', '12.4/11-28', '12.4/11-28', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (62, 'VA13614928T218', '13.6/14.9-28', '13.6/14.9-28', '건설·농업용', null, 4, 'Box', 4, null, 'Ascendo Tube Catalog 2026-07-24'),
  (83, 'VA82520T75A', '825-20', '8.25-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (13, 'VA82520T75', '825-20', '8.25-20', '표준', 10, null, 'Sack', 10, null, 'Ascendo Tube Catalog 2026-07-24'),
  (71, 'VA18708J2', '18x7-8', '18*7-8', '지게차·산업용', 10, null, 'Sack', 10, null, null),
  (72, 'VA60009J2', '6.00-9', '6.00-9', '지게차·산업용', 30, null, 'Sack', 30, null, null),
  (73, 'VA2189J2', '21X8-9', '21*8-9', '지게차·산업용', 10, null, 'Sack', 10, null, null),
  (74, 'VA65010J2', '6.50-10', '6.50-10', '지게차·산업용', 30, null, 'Sack', 30, null, null),
  (76, 'VA70012T75', '7.00-12', '7.00-12', '지게차·산업용', 18, null, 'Sack', 18, null, null),
  (77, 'VA60015T13', '6.00-15', '6.00-15', '지게차·산업용', 10, null, 'Sack', 10, null, null),
  (78, 'VA28915T77', '28*9-15', '28*9-15', '지게차·산업용', 15, null, 'Sack', 15, null, null),
  (79, 'VA30015T77', '300-15', '3.00-15', '지게차·산업용', 10, null, 'Sack', 10, null, null),
  (80, 'VA82515T77', '8.25-15', '8.25-15', '지게차·산업용', 15, null, 'Sack', 15, null, null),
  (75, 'VA23910J2', '23x9-10', '23*9-10', '지게차·산업용', 10, null, 'Sack', 10, null, null),
  (81, 'VA70015T75S', '700-15', '7.00-15', '고하중', null, null, null, null, null, null),
  (82, 'VA70016T75S', '700-16', '7.00-16', '고하중', null, null, null, null, null, null)
) as v(no, sku, size, size_label, category_label, sack_qty, box_qty, packaging, qty, remarks, source_catalog)
where t.no = v.no;
