-- ─────────────────────────────────────────────────────────────────────────────
-- products 가격/스펙 분리 → products_price 테이블 신설 (사용자 지시: 완전 분리 + 앱 연동)
-- 키: products.sku = products_price.sku (sku 는 유니크 제약 존재).
-- 구성: sku(PK,FK) · description · weight_kg · fob · qty_40ft · wh_price ·
--        wh_price_set · dist_price · dist_price_set   (+ created_at/updated_at)
--   · '40feet_qty' 는 숫자로 시작해 SQL 식별자 부적합 → qty_40ft 로 명명(snake_case).
--   · qty_40ft · dist_price_set 는 현재 소스값 없음 → NULL(추후 입력).
-- 절차: 백필 → products 에서 price 컬럼 제거 → 뷰 2종 재/신설 → RLS·grant 복제.
-- RLS: products 와 100% 동일 정책 복제(현행 접근권한 유지, 회귀 없음).
--   ※ 참고: products_auth_all(ALL/true) 가 permissive 라 실제로는 인증 사용자 전체가
--     조회 가능. read_priced 제한은 사실상 무력. 이 이슈는 이번 작업 범위 밖(현행 유지).
-- 앱: 권한 경로(Databases/PriceCompare/Quote)는 평면 뷰 products_priced 를 읽음.
--     비권한 경로(Quote distributor/end_user)는 products_sell(정의자 뷰, 원가 비노출).
-- 적용: 1회 실행(트랜잭션 원자적). 되돌리려면 컬럼 복원 후 백필 역적용 필요.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- 1) products_price 생성 (sku FK → products.sku, 제품 삭제/변경 시 연쇄)
create table public.products_price (
  sku            text primary key references public.products(sku) on update cascade on delete cascade,
  description    text,
  weight_kg      numeric,
  fob            numeric,
  qty_40ft       integer,
  wh_price       numeric,
  wh_price_set   numeric,
  dist_price     numeric,
  dist_price_set numeric,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
comment on table  public.products_price is '제품 가격/스펙 SSOT — products.sku 로 1:1 연결. 원가(wh_price/dist_price)는 민감정보.';
comment on column public.products_price.qty_40ft is '40ft 컨테이너 적재수량 (구 40Ft QTY)';
comment on column public.products_price.dist_price_set is '대리점가(set 단위) — 추후 입력';

-- 2) 백필 (sku 기준 · 495행). qty_40ft·dist_price_set 은 소스 없어 NULL.
insert into public.products_price (sku, description, weight_kg, fob, wh_price, wh_price_set, dist_price)
select sku, description, weight_kg, fob, wh_price, wh_price_set, dist_price
from public.products;

-- 3) products_sell 뷰 드롭 (products.wh_price 의존 → 컬럼 제거 전 선행)
drop view if exists public.products_sell;

-- 4) products 에서 price/스펙 컬럼 제거 (분리 완료)
alter table public.products
  drop column if exists weight_kg,
  drop column if exists fob,
  drop column if exists wh_price,
  drop column if exists wh_price_set,
  drop column if exists dist_price;

-- 5) products_sell 재생성 (products_price 기준 판매가 = 원가/0.70 → 1000단위 반올림)
--    정의자 뷰(security_invoker=false)로 유지 → 비권한 역할도 원가 없이 판매가만 조회.
create view public.products_sell
  with (security_invoker = false) as
select p.id, p.item, p.brand, p.description, p.sku, p.unit, p.is_active,
  (round(pp.wh_price     / 0.70 / 1000::numeric) * 1000::numeric)::integer as unit_price,
  (round(pp.wh_price_set / 0.70 / 1000::numeric) * 1000::numeric)::integer as unit_price_set
from public.products p
join public.products_price pp on pp.sku = p.sku
where p.is_active = true;

-- 6) products_priced 뷰 (권한 경로용 · 기존 products 평면 형태 복원 + 신규 컬럼)
--    invoker 뷰 → 기저 테이블 RLS 존중(향후 RLS 강화 시 자동 반영).
create view public.products_priced
  with (security_invoker = true) as
select p.*,
       pp.weight_kg, pp.fob, pp.qty_40ft,
       pp.wh_price, pp.wh_price_set, pp.dist_price, pp.dist_price_set
from public.products p
left join public.products_price pp on pp.sku = p.sku;

-- 7) RLS — products 정책 3종 동일 복제
alter table public.products_price enable row level security;
create policy products_price_auth_all    on public.products_price for all    to authenticated using (true) with check (true);
create policy products_price_read_priced  on public.products_price for select to authenticated
  using ((((auth.jwt() -> 'app_metadata') ->> 'role') = any (array['super_admin','staff'])));
create policy products_price_write_admin  on public.products_price for all    to authenticated
  using ((((auth.jwt() -> 'app_metadata') ->> 'role') = 'super_admin'))
  with check ((((auth.jwt() -> 'app_metadata') ->> 'role') = 'super_admin'));

-- 8) grant — 기저 테이블/뷰 접근권 (products 와 동일 수준)
grant select, insert, update, delete, truncate, references, trigger on public.products_price to anon, authenticated, service_role;
grant select on public.products_sell   to anon, authenticated, service_role;
grant select on public.products_priced to authenticated, service_role;

commit;
