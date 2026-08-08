-- ─────────────────────────────────────────────────────────────────────────────
-- products · TBB(바이어스) 2026 신규 제품 등록 (ASC 7 + JK 2)
-- 근거: 첨부 2026 시트 2종(ASC TBB / JK TBB) 中 DB 미존재 패턴을 신규 등록(사용자 지시).
--   · item='TBB', unit='pcs', is_active=true, category_id/dist_price/marking=null.
--   · ASC SKU 규칙: B1-<규격숫자><패턴>.  JK SKU 규칙: <규격숫자><패턴><PR>.
--   · fob=USD, wh_price/wh_price_set=Rp. set 없는 행(13.00-24)은 0(기본값 관례).
--   · JK 시트엔 중량 열 없음 → weight_kg=null.
-- 멱등: sku 기준 not exists 가드(재실행해도 중복 삽입 없음).
-- ─────────────────────────────────────────────────────────────────────────────

begin;

insert into products (item, brand, description, sku, fob, weight_kg, wh_price, wh_price_set, unit, is_active)
select v.item, v.brand, v.description, v.sku, v.fob, v.weight_kg, v.wh_price, v.wh_price_set, 'pcs', true
from (values
  -- ASC 신규 7 (item, brand, description, sku, fob, weight, wh, set)
  ('TBB','ASCENDO','ASC 7.50-16 AB635 16PR', 'B1-75016AB635',  56.71, 22.2, 1194216, 1359940),
  ('TBB','ASCENDO','ASC 8.25-16 AB635 16PR', 'B1-82516AB635',  65.79, 27,   1390107, 1570504),
  ('TBB','ASCENDO','ASC 7.50-16 AB616 16PR', 'B1-75016AB616',  57.75, 26.2, 1214391, 1380115),
  ('TBB','ASCENDO','ASC 8.25-16 AB616 16PR', 'B1-82516AB616',  68.06, 30.5, 1434127, 1614524),
  ('TBB','ASCENDO','ASC 7.50-16 AB651 16PR', 'B1-75016AB651',  78.53, 23.4, 1617704, 1783428),
  ('TBB','ASCENDO','ASC 8.25-16 AB651 16PR', 'B1-82516AB651',  95.46, 30,   1965830, 2146227),
  ('TBB','ASCENDO','ASC 13.00-24 AB635 14PR','B1-130024AB635',153.97, 72,   3456031, 0),
  -- JK 신규 2 (중량 null)
  ('TBB','JK TYRE','JK 11.00-20 JET XTRA LOAD 16PR','110020JETXTRALOAD16',155.53, null, 3179707, 3493707),
  ('TBB','JK TYRE','JK 11.00-20 JET R PLUS 16PR',   '110020JETRPLUS16',   154.5,  null, 3157719, 3471719)
) as v(item, brand, description, sku, fob, weight_kg, wh_price, wh_price_set)
where not exists (select 1 from products p2 where p2.sku = v.sku);

commit;
