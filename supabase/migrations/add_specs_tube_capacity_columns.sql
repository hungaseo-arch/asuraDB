-- 튜브 스펙 탭(Databases.vue「제품 > 스펙 > TUBE」) 표시용 컬럼 추가 — 2026-08-03
--
-- 헤더 구성: No. · 분류 · 제품 · 규격 · 밸브 · 중량(kg) · 폭(mm) · 두께(mm) · 포장(pcs) · 몰드(조) · 월생산(pcs)
--   · 규격  = specs_tube.size_label   (기존 size('825-20')는 TubeSpecTable.vue 가 사용하므로 보존)
--   · 밸브  = specs_tube.valve
--   · 중량  = products_price.weight_kg (products_priced 뷰)
--   · 폭·두께·포장 = specs_tube.lebar · tebal · qty (기존 컬럼, 신규 추가 아님)
--   · 몰드  = specs_tube.mold_qty
--   · 월생산 = specs_tube.capa_month = capa_day × 24일
--
-- 값 출처: spec-tube.csv (SIZE / Valve / Mold Q'ty / Capacity per day / Total Capa per Month).
--   CSV 의 SIZE 빈칸 행(밸브만 다른 파생 SKU)은 size_label 만 위 행에서 forward-fill 하고,
--   몰드·생산능력은 같은 몰드를 공유하므로 중복 계상하지 않도록 비워 둔다.

alter table public.specs_tube
  add column if not exists size_label text,
  add column if not exists mold_qty   integer,
  add column if not exists capa_day   integer,
  add column if not exists capa_month integer;

comment on column public.specs_tube.size_label is '표시용 규격 표기 (spec-tube.csv SIZE)';
comment on column public.specs_tube.capa_month is '월생산량(pcs) = capa_day × 24일';

-- ── 데이터 반영(요약) ──
-- · CSV 기준 64행 갱신 (size_label / mold_qty / capa_day / capa_month)
-- · sku 미기입 스펙 행 3건을 규격·밸브·중량 완전 일치로 연결
--     no=11 → VA82516T75A(825-16 TR75 1.80) / no=13 → VA82520T75(825-20 TR75 2.15)
--     no=75 → VA23910J2(23x9-10 JS2 0.71)   ※ 이로써 TUBE 중량 82/82 완결
-- · CSV 에만 있던 스펙 3건 신규 행 추가: VA70015T75S · VA70016T75S · VA82520T75A
-- · size_label 미보유 12건은 products.description 에서 브랜드·밸브·'Heavy Duty' 를 제거해 도출
--     (예: 'ASC 12.00-20TR78 Heavy Duty' → '12.00-20')
-- · products.sku='VA82520T75' 의 빈 description 을 'ASC 8.25-20TR75A' 로 보정
-- · VA1878J2 는 VA18708J2 와 description 이 동일한 중복 SKU — 스펙 행을 복제해 연결
--     (근본적인 중복 정리는 별건)
--
-- ── 추가 정정 ──
-- 신규 추가한 VA70015T75S · VA70016T75S(7.00R15/16 Heavy Duty)는 삽입 시 같은 규격의
-- Standar 행에서 category·lebar·tebal·packaging·qty 를 그대로 복사했으나, 제원표에는
-- 700-15/700-16 의 Heavy Duty 항목이 없다(HD 는 Box 포장·두께 상이). 잘못된 값을 남기지 않도록
-- category 만 'Type 2' 로 바로잡고 폭·두께·포장은 비운다.
update public.specs_tube
   set category = 'Type 2', lebar = null, tebal = null, packaging = null, qty = null
 where sku in ('VA70015T75S', 'VA70016T75S');
-- category 코드 대응: Type 1=Standar · Type 2=Heavy Duty · Type 3=OTR/AGR · Type 4=IND
