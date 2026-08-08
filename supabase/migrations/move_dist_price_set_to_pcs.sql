-- 대리점가 컬럼 정리 — 단품(pcs) 카테고리의 대리점가를 set → pcs 로 이동 (2026-08-04)
--
-- 근거: TUBE·FLAP·SOLID·재생타이어(VUL: Jadi·Jasa)는 전 제품이 단품(pcs) 거래로 세트 가격 개념이 없다
--   (products.unit 도 전부 'pcs'). 그런데 기존 데이터는 대리점가가 dist_price_set 에 들어가 있어
--   Databases.vue 가격 탭에서 '대리점가(set)' 열에 표시되고 '대리점가(pcs)' 는 전부 비어 있었다.
--
-- 대상: dist_price_set 이 채워진 TUBE 79 · FLAP 30 · SOLID 44 · Jadi 13 · Jasa 14 = 180행.
--   해당 행의 dist_price_pcs 는 전부 비어 있어 덮어쓰는 값이 없고, wh_price_set 도 전 행 비어 있다.
--   값 변환은 없다(대리점가 = VAT 포함가 기준 유지, CLAUDE.md 「가격 부가세(PPN) 기준」).
--
-- 미포함: PNEUMATIC 9행은 지시 범위 밖이라 dist_price_set 에 그대로 두었다(단품 여부 확인 필요).
-- 롤백 참조: public.products_price_backup_20260804 (이동 전 값이 dist_price_set 에 남아 있음)
update public.products_price pp
   set dist_price_pcs = pp.dist_price_set,
       dist_price_set = null,
       updated_at     = now()
  from public.products p
 where p.sku = pp.sku
   and p.item in ('TUBE', 'FLAP', 'SOLID', 'Jadi', 'Jasa')
   and pp.dist_price_set is not null;

-- 검증: 이동 후 dist_price_pcs = 백업본의 dist_price_set (불일치 0행), dist_price_set 잔여 0행.
