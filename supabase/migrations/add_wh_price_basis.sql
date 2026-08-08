-- ─────────────────────────────────────────────────────────────────────────────
-- 입고가 산정기준(API-P / API-U) 구분 컬럼 추가 — 2026-08-03
--
-- 배경: 구글드라이브 가격 워크북(01_TBR ~ 11_LOCAL)의 대부분 시트는 입고가를
--   「WH Price API-P (Rp)」와 「WH Price API-U (Rp)」 두 계열로 동시에 관리한다.
--   운영 기준은 **API-P** 이므로 입고가(pcs/set)에는 API-P 값을 넣되,
--   API-P 가 없어 API-U 로 채운 품목은 화면에서 구분할 수 있어야 한다.
--
--   · 'API-P'   → API-P 기준(정상)
--   · 'API-U'   → 해당 시트에 API-P 계열이 없어 API-U 로 채움 (Databases.vue 에서 뱃지 표기)
--   · null      → 원본에 API 구분이 없는 가격표(FLAP·TUBE·SOLID 단가표·로컬매입 MTI 등)
--
-- 뷰 products_priced 는 컬럼을 자동 승계하지 않으므로 함께 재생성한다.
-- ─────────────────────────────────────────────────────────────────────────────
begin;

alter table public.products_price
  add column if not exists wh_price_basis text;

alter table public.products_price
  drop constraint if exists products_price_wh_price_basis_chk;
alter table public.products_price
  add constraint products_price_wh_price_basis_chk
  check (wh_price_basis is null or wh_price_basis in ('API-P', 'API-U'));

comment on column public.products_price.wh_price_basis is
  '입고가 산정기준: API-P(기본) / API-U(대체) / null(원본에 API 구분 없음)';

-- products_priced 재생성 (컬럼 추가분 노출)
drop view if exists public.products_priced;
create view public.products_priced
  with (security_invoker = true) as
select p.*,
       pp.weight_kg, pp.fob, pp.qty_40ft,
       pp.wh_price_pcs, pp.wh_price_set, pp.dist_price_pcs, pp.dist_price_set,
       pp.wh_price_basis
from public.products p
left join public.products_price pp on pp.sku = p.sku;
grant select on public.products_priced to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

-- ── 데이터 반영(요약) — 2026-08-03 ──────────────────────────────────────────
-- 출처: 구글드라이브 가격 워크북 9종(01_TBR·02_TBB·03_OTR·04_PNEU·05_AGR·06_FLAP·07_SOLID·08_TUBE·11_LOCAL, Kurs 18,500)
-- 시트별 확정 열 (FOB / 중량 / 40ft / 입고가 API-U(Rp) / API-P(Rp) / SET):
--   01_TBR  1.ASC-HUBEI      F desc · J wt · N fob(New May 2026) · P q40 · Z u · AG p · AC/AJ set
--   01_TBR  3.ASC-YUELONG    F · H · L(June 2026) · M · W · AD · Z/AG    ※ 품번(G)이 복붙 잔재라 설명 기준으로만 매칭
--   01_TBR  2.TK-IMPORT      F · J · M(June) · N · X · AE · AA/AH
--   01_TBR  2.TK(16.800)     F · J · L · N · X · AE · AA/AH             ※ 구환율 시트 → 후순위
--   01_TBR  TK-TRASINDO      F · I · J(FEB/26) · K · U · AB · X/AE
--   01_TBR  4.ZHONGCE        F · - · H · I · S · Z · V/AC
--   01_TBR  5.JK TYRE        F · - · H · I · R(API-U 전용) · - · U
--   02_TBB  2.ASC            F · G · K(JUNI 2026) · M · W · AI · Z/AL
--   02_TBB  1.JK             G · - · I(Apr/2026) · K · T(API-U 전용) · - · W
--   03_OTR  3.DONGYING-RUNGOLD J · M · P(23 JUNE) · R · AB · AI · AE/AL
--   03_OTR  1.OTR ASC        F · G · L(JUN 2026) · N · X · AB
--   03_OTR  2.OTR TK         G · H · J · K · U · Y                      ※ I·J 모두 'FOB' 인데 원가계산은 J 사용
--   03_OTR  5.OTR MAXAM      C(복합표기) · - · D · E · N(API-U 전용)
--   04_PNEU 1.HUBEI-ASC      E · F · I(JUN 2026) · K · T · V
--   04_PNEU 2.RUNGOLD-ASC    E · F · G · H · Q · S
--   05_AGR  1.DONGYING RUNGOLD(UPDATE) J · L · O(23/JUNE) · Q · Z · AB
--   05_AGR  2.WH PRICE CHINA F · K · L · M · W · Y
--   05_AGR  4.WH PRICE HUBEI F · H · I · J · S · U
--   05_AGR  3.WH PRICE JK    G · - · L · M · U(API-U 전용)
--   06_FLAP 40FT(18.500)     F · G · I(APR '26) · K · S(API 구분 없음)   ※ 20FT 시트의 수량은 40ft 열에 넣지 않음
--   07_SOLID 3.DIAMOND(HUAIN)/1.SOLID ASC/2.SOLID DIAMOND — 단가표(API 구분 없음)
--   07_SOLID 3.SOLID ASD 40ft C size · D · E · F · L(API-U 전용)
--   08_TUBE 1.TUBE TB        G art · H wt(gr) · K 신 WH Price   ※ gr → kg 환산
--   08_TUBE 2.TUBE OTR       G art · I wt(gr) · L 신 WH Price   ※ 하단 Flap 블록 포함
--   11_LOCAL 2.MTI-ASC       G · H · M · R(WH PRICE TIRE ONLY -PPN) · r40~48(2026-07-01 시행분)
--   11_LOCAL 1.MTI-TK 18000  F · G · M · S · r24~33(2026-06-01 인상분) / r38~47((M) 로컬 품목)
--
-- 반영 결과: 533개 중 398건 upsert — FOB 250 · 중량 327 · 40ft 267 · 입고가(pcs) 389 · 입고가(set) 114
--            wh_price_basis = API-P 192 · API-U 14 · null 327
