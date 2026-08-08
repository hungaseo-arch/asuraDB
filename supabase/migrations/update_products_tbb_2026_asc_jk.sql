-- ─────────────────────────────────────────────────────────────────────────────
-- products · TBB(바이어스) 2026 스펙 반영 (FOB·중량·입고가·입고가set)
-- 근거: 첨부 2026 시트 2종 (ASC TBB / JK TBB)
--   · 매칭은 제품명(브랜드·규격·패턴·PR) 정확 기준. DB에 없는 신규 패턴은 미추가.
--   · ASC 9행 中 2행 매칭(AB635 10.00-20·11.00-20). 7행(7.50-16/8.25-16 AB635·
--     AB616·AB651, 13.00-24 AB635)은 DB 미존재 신규 → 보류.
--   · JK 11행 中 9행 매칭. 2행 보류: 11.00-20 JET XTRA LOAD(DB엔 DX만 존재),
--     11.00-20 JET R PLUS(DB는 18PR·CSV는 16PR → PR 상이).
-- 값 규칙:
--   · fob         = 시트 FOB (USD). 항상 덮어씀.
--   · weight_kg   = 시트 중량(kg). JK 시트엔 중량 없음 → 기존값 보존(COALESCE).
--   · wh_price    = 시트 입고가(Rp).
--   · wh_price_set= 시트 입고가set(Rp). 공란이면 기존값 보존(COALESCE).
-- 적용: Supabase SQL Editor 1회 실행(멱등 — 재실행해도 동일 결과).
-- ─────────────────────────────────────────────────────────────────────────────

begin;

update products p set
  fob          = v.fob,
  weight_kg    = coalesce(v.weight_kg, p.weight_kg),
  wh_price     = coalesce(v.wh_price,  p.wh_price),
  wh_price_set = coalesce(v.wh_price_set, p.wh_price_set),
  updated_at   = now()
from (values
  -- ASC TBB (fob, weight, wh, set)
  ('B1-100020AB635',      122.6,  49, 2707357, 3009147),
  ('B1-110020AB635',      132.03, 58, 2907649, 3221649),
  -- JK TBB (중량 없음 → null)
  ('75016TRAKTUFXTRA14',   70.04, null, 1428876, 1594600),
  ('75016JETTRAK3914',     71.07, null, 1449074, 1614798),
  ('75016JETRIBXTRA14',    65.92, null, 1345709, 1511433),
  ('82516JETXTRALOAD14',   80.34, null, 1640011, 1820408),
  ('100020JETXTRALOADDX1',150.38, null, 3072660, 3374450),
  ('100020JETACESNI16',   140.08, null, 2866687, 3168477),
  ('100020JETPOWER10016', 154.5,  null, 3149463, 3451253),
  ('120020JETROCKXD18',   200.85, null, 4124231, 4458090),
  ('120020TIPPERKING20',  221.45, null, 4528197, 4862056)
) as v(sku, fob, weight_kg, wh_price, wh_price_set)
where p.sku = v.sku;

commit;
