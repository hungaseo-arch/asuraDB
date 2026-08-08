-- ─────────────────────────────────────────────────────────────────────────────
-- 「확인 필요」 표시용 컬럼 추가 — 2026-08-03
--
-- 배경: 구글드라이브 가격 워크북 일괄 반영(add_wh_price_basis.sql) 과정에서
--   ① 기존 제원표와 값이 상충하거나 ② 기존 입고가 대비 변동폭이 비정상적으로 큰
--   품목이 나왔다. 값 자체는 최신 가격표 기준으로 넣되, 화면에서 「확인」 뱃지로
--   구분해 원본 대조 후 확정할 수 있게 한다.
--
--   · review_field → 확인 대상 컬럼 키 ('weight_kg' · 'wh_price_pcs' …). 해당 셀에 뱃지 표기.
--   · review_note  → 확인 사유(뱃지 tooltip). null 이면 정상 데이터.
--
-- 확인 기준(이번 반영분):
--   A. 중량 — 튜브 제원표(spec-tube.csv) 대비 5% 이상 차이 (6건)
--   B. 입고가 — 기존 DB 값 대비 ±30% 이상 변동 (3건)
--   (입고가 ÷ (FOB × 18,500) 비율 이상치는 0건 — 전 구간 0.98~1.34)
--
-- 뷰 products_priced 는 컬럼을 자동 승계하지 않으므로 함께 재생성한다.
-- ─────────────────────────────────────────────────────────────────────────────
begin;

alter table public.products_price
  add column if not exists review_field text,
  add column if not exists review_note  text;

comment on column public.products_price.review_field is
  '확인 필요 대상 컬럼 키 (weight_kg / fob / qty_40ft / wh_price_pcs / wh_price_set)';
comment on column public.products_price.review_note is
  '확인 필요 사유 — null 이면 정상. 값이 있으면 화면에 「확인」 뱃지 표기';

-- products_priced 재생성 (컬럼 추가분 노출)
drop view if exists public.products_priced;
create view public.products_priced
  with (security_invoker = true) as
select p.*,
       pp.weight_kg, pp.fob, pp.qty_40ft,
       pp.wh_price_pcs, pp.wh_price_set, pp.dist_price_pcs, pp.dist_price_set,
       pp.wh_price_basis, pp.review_field, pp.review_note
from public.products p
left join public.products_price pp on pp.sku = p.sku;
grant select on public.products_priced to authenticated, service_role;

-- ── A. 중량 상충 (기존=튜브 제원표 / 신규=08_TUBE 가격표) ─────────────────────
update public.products_price set review_field = 'weight_kg', review_note = v.note
from (values
  ('VA160020T78',   '중량 상충 — 제원표 5.450kg vs 가격표(08_TUBE 2.TUBE OTR r15) 4.505kg. 자리수 뒤바뀜 의심, 원본 확인 필요'),
  ('VA1241128T218', '중량 상충 — 제원표 4.160kg vs 가격표(08_TUBE 2.TUBE OTR r39) 3.850kg (7.5% 차)'),
  ('VA23126T179',   '중량 상충 — 제원표 11.900kg vs 가격표(08_TUBE 2.TUBE OTR r37) 11.276kg (5.2% 차)'),
  ('VA23126T218',   '중량 상충 — 제원표 11.900kg vs 가격표(08_TUBE 2.TUBE OTR r38) 11.276kg (5.2% 차)'),
  ('VA816T13',      '중량 상충 — 제원표 1.000kg vs 가격표(08_TUBE 2.TUBE OTR r9) 0.950kg (5.0% 차)'),
  ('VA818T13',      '중량 상충 — 제원표 1.600kg vs 가격표(08_TUBE 2.TUBE OTR r11) 1.520kg (5.0% 차)')
) as v(sku, note)
where products_price.sku = v.sku;

-- ── B. 입고가 급변 (기존 DB 값 대비 ±30% 이상) ───────────────────────────────
update public.products_price set review_field = 'wh_price_pcs', review_note = v.note
from (values
  ('1100R20TKALIII18M', '입고가 급변 — 기존 5,684,165 → 3,046,275 (-46%). 출처 11_LOCAL 1.MTI-TK r45((M) 로컬 품목). 기존 값이 수입가였는지 확인 필요'),
  ('1022006511010XN03', '입고가 급변 — 기존 1,667,957 → 972,621 (-42%). 07_SOLID 2.SOLID DIAMOND 시트의 Article No. 열이 규격과 어긋나 있어(6.50-10↔18X7-8) 규격 기준으로 매칭. 원본 확인 필요'),
  ('OTR1-140024E3L324', '입고가 급변 — 기존 8,811,180 → 5,260,000 (-40%). 출처 03_OTR 3.DONGYING-RUNGOLD r13(14.00-24 24PR). 같은 규격 28PR 은 8.3M 대로 24PR/28PR 혼동 여부 확인 필요')
) as v(sku, note)
where products_price.sku = v.sku;

commit;

notify pgrst, 'reload schema';
