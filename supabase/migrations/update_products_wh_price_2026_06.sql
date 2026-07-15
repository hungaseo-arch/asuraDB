-- ─────────────────────────────────────────────────────────────────────────────
-- products · wh_price 일괄 갱신 (2026-06 · OTR 28건)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 적용 순서
--   ① PREVIEW  — 매칭 상태/변경분 확인 (DB 변경 없음)
--   ② APPLY    — UPSERT 실행
--                · 기존 SKU → wh_price + updated_at 만 갱신 (description/brand 보존)
--                · 신규 SKU → 전체 행 INSERT (description/brand/item/currency 포함)
--
-- 비고
--   - 실제 products 테이블에 currency 컬럼이 없어서 제거 (patch_products_unit.sql
--     의 currency 컬럼은 production 에 미적용 — 통화 구분이 필요하면 별도 ALTER).
--   - 가격 단위: 화면상 IDR (3,637,470 등 8자리 → 인도네시아 루피아)로 추정.
--   - sku 13/14 의 'E3/L340' / 'E3/L332' 슬래시는 스크린샷 그대로 유지.
--   - 동일 사양·다른 spec(20PR/24PR 등) 별로 SKU 가 분리되어 있음 — 수동 매칭 불필요.
-- ─────────────────────────────────────────────────────────────────────────────


-- ① PREVIEW ───────────────────────────────────────────────────────────────────
-- with input(sku, new_price, description, brand) as (values
--   -- ASCENDO OTR (Bias 사선)
--   ('OTR1-130024G2AS432',  3637470::numeric, 'ASC 13.00-24 G-2 AS432',           'ASCENDO'),
--   ('OTR1-140024G2AS432',  4348980,          'ASC 14.00-24 G-2 AS432',           'ASCENDO'),
--   ('OTR1-130025AE804',    8165160,          'ASC 13.00-25 E-3 AE804',           'ASCENDO'),
--   ('OTR1-140025AE804',    8874450,          'ASC 14.00-25 E-3 AE804',           'ASCENDO'),
--   ('OTR1-160025AE804',   13192350,          'ASC 16.00-25 E-3 AE804',           'ASCENDO'),
--   ('OTR1-17525AE803',     4617600,          'ASC 17.5-25 E-3/L-3 AE803',        'ASCENDO'),
--   ('OTR1-20525AE803',     6988560,          'ASC 20.5-25 E-3/L-3 AE803',        'ASCENDO'),
--   ('OTR1-23525AE803',     9573750,          'ASC 23.5-25 E-3/L-3 AE803',        'ASCENDO'),
--   ('OTR1-26525AE803',    16793190,          'ASC 26.5-25 E-3/L-3 AE803',        'ASCENDO'),
--   ('OTR1-17525E3L320',    5279160,          'ASC 17.5-25 E-3/L-3 20PR (R)',     'ASCENDO'),
--   ('OTR1-17525G2L220',    4568000,          'ASC 17.5-25 G2/L2 20PR TTF (R)',   'ASCENDO'),
--   ('OTR1-140024E3L324',   8344980,          'ASC 14.00-24 E3/L3 24PR (R)',      'ASCENDO'),
--   ('OTR1-180025E3/L340', 26164920,          'ASC 18.00-25 E-3/L-3 40PR TL (R)', 'ASCENDO'),
--   ('OTR1-29525E3/L332',  21772650,          'ASC 29.5-25 E3/L3 32PR (R)',       'ASCENDO'),
--   -- ASCENDO OTR (Radial)
--   ('OTR1-1400R25AD907M4', 9246000,          'ASC 14.00R25 AD907 TL M4 (R)',     'ASCENDO'),
--   ('OTR1-1400R25AD907M7', 9246000,          'ASC 14.00R25 AD907 TL M7 (R)',     'ASCENDO'),
--   ('OTR1-1600R25AD903M4',14387000,          'ASC 16.00R25 AD903 TL M4 (R)',     'ASCENDO'),
--   ('OTR1-1600R25AD903M7',14387000,          'ASC 16.00R25 AD903 TL M7 (R)',     'ASCENDO'),
--   ('OTR1-295R25AD905H2', 38364000,          'ASC 29.5R25 AD905 TL H2 (R)',      'ASCENDO'),
--   ('OTR1-295R25AD905R1', 38364000,          'ASC 29.5R25 AD905 TL R1 (R)',      'ASCENDO'),
--   -- TECHKING
--   ('1400R24ETCRANE',     11974680,          'TK 14.00R24 ETCRANE',              'TECHKING'),
--   ('1600R25ETRTV',       18372720,          'TK 16.00R25 ETRTV',                'TECHKING'),
--   -- MAXAM
--   ('I3-130024MS905G212',  4129200,          'MAXAM 13.00-24 MS905 12PR',        'MAXAM'),
--   ('I3-140024MS80128',    9462750,          'MAXAM 14.00-24 MS801 28PR',        'MAXAM'),
--   ('I3-140024MS90512',    4773000,          'MAXAM 14.00-24 MS905 12PR',        'MAXAM'),
--   ('I3-17525MS91216',     5910750,          'MAXAM 17.5-25 MS912 16PR',         'MAXAM'),
--   ('I3-195L24MS90412',    5294700,          'MAXAM 19.5L-24 MS904 12PR',        'MAXAM'),
--   ('I3-20525MS91316',    10078800,          'MAXAM 20.5-25 MS913 16PR',         'MAXAM')
-- )
-- select
--   i.sku,
--   i.brand,
--   i.new_price,
--   p.wh_price                                                  as old_price,
--   case
--     when p.id is null                       then '+ INSERT (신규)'
--     when p.wh_price = i.new_price           then '= 변경없음'
--     else '↻ UPDATE (' || p.wh_price::text || ' → ' || i.new_price::text || ')'
--   end                                                         as action,
--   i.description
-- from input i
-- left join products p on p.sku = i.sku
-- order by action, i.brand, i.sku;


-- ② APPLY (PREVIEW 결과가 의도와 일치하면 아래 블록의 주석 해제 후 실행) ────────
begin;

insert into products (sku, description, wh_price, brand, item)
values
  ('OTR1-130024G2AS432',  'ASC 13.00-24 G-2 AS432',            3637470,  'ASCENDO',  'OTR'),
  ('OTR1-140024G2AS432',  'ASC 14.00-24 G-2 AS432',            4348980,  'ASCENDO',  'OTR'),
  ('OTR1-130025AE804',    'ASC 13.00-25 E-3 AE804',            8165160,  'ASCENDO',  'OTR'),
  ('OTR1-140025AE804',    'ASC 14.00-25 E-3 AE804',            8874450,  'ASCENDO',  'OTR'),
  ('OTR1-160025AE804',    'ASC 16.00-25 E-3 AE804',           13192350,  'ASCENDO',  'OTR'),
  ('OTR1-17525AE803',     'ASC 17.5-25 E-3/L-3 AE803',         4617600,  'ASCENDO',  'OTR'),
  ('OTR1-20525AE803',     'ASC 20.5-25 E-3/L-3 AE803',         6988560,  'ASCENDO',  'OTR'),
  ('OTR1-23525AE803',     'ASC 23.5-25 E-3/L-3 AE803',         9573750,  'ASCENDO',  'OTR'),
  ('OTR1-26525AE803',     'ASC 26.5-25 E-3/L-3 AE803',        16793190,  'ASCENDO',  'OTR'),
  ('OTR1-17525E3L320',    'ASC 17.5-25 E-3/L-3 20PR (R)',      5279160,  'ASCENDO',  'OTR'),
  ('OTR1-17525G2L220',    'ASC 17.5-25 G2/L2 20PR TTF (R)',    4568000,  'ASCENDO',  'OTR'),
  ('OTR1-140024E3L324',   'ASC 14.00-24 E3/L3 24PR (R)',       8344980,  'ASCENDO',  'OTR'),
  ('OTR1-180025E3/L340',  'ASC 18.00-25 E-3/L-3 40PR TL (R)', 26164920,  'ASCENDO',  'OTR'),
  ('OTR1-29525E3/L332',   'ASC 29.5-25 E3/L3 32PR (R)',       21772650,  'ASCENDO',  'OTR'),
  ('OTR1-1400R25AD907M4', 'ASC 14.00R25 AD907 TL M4 (R)',      9246000,  'ASCENDO',  'OTR'),
  ('OTR1-1400R25AD907M7', 'ASC 14.00R25 AD907 TL M7 (R)',      9246000,  'ASCENDO',  'OTR'),
  ('OTR1-1600R25AD903M4', 'ASC 16.00R25 AD903 TL M4 (R)',     14387000,  'ASCENDO',  'OTR'),
  ('OTR1-1600R25AD903M7', 'ASC 16.00R25 AD903 TL M7 (R)',     14387000,  'ASCENDO',  'OTR'),
  ('OTR1-295R25AD905H2',  'ASC 29.5R25 AD905 TL H2 (R)',      38364000,  'ASCENDO',  'OTR'),
  ('OTR1-295R25AD905R1',  'ASC 29.5R25 AD905 TL R1 (R)',      38364000,  'ASCENDO',  'OTR'),
  ('1400R24ETCRANE',      'TK 14.00R24 ETCRANE',              11974680,  'TECHKING', 'OTR'),
  ('1600R25ETRTV',        'TK 16.00R25 ETRTV',                18372720,  'TECHKING', 'OTR'),
  ('I3-130024MS905G212',  'MAXAM 13.00-24 MS905 12PR',         4129200,  'MAXAM',    'OTR'),
  ('I3-140024MS80128',    'MAXAM 14.00-24 MS801 28PR',         9462750,  'MAXAM',    'OTR'),
  ('I3-140024MS90512',    'MAXAM 14.00-24 MS905 12PR',         4773000,  'MAXAM',    'OTR'),
  ('I3-17525MS91216',     'MAXAM 17.5-25 MS912 16PR',          5910750,  'MAXAM',    'OTR'),
  ('I3-195L24MS90412',    'MAXAM 19.5L-24 MS904 12PR',         5294700,  'MAXAM',    'OTR'),
  ('I3-20525MS91316',     'MAXAM 20.5-25 MS913 16PR',         10078800,  'MAXAM',    'OTR')
on conflict (sku) do update set
  wh_price   = excluded.wh_price,
  updated_at = now()
returning sku, wh_price, description,
  case when xmax::text::int = 0 then 'INSERTED' else 'UPDATED' end as action;

commit;
