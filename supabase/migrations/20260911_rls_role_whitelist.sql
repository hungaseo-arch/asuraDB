-- RLS 정책 역할 화이트리스트 전환 (2026-09-11)
--
-- 문제: 정책 다수가 `app_metadata.role IS DISTINCT FROM 'viewer'` 로 쓰여 있었다.
-- 이 조건은 viewer 만 막으므로 distributor·end_user 가 그대로 통과한다. 실측(distributor JWT):
--   products 582행 · products_price 582행(FOB·도매원가) · margin_records 15,658행 ·
--   sap_purchase_invoice_lines 21,706행.
-- 라우터가 두 역할을 /quote·/price-compare 로 제한하지만 PostgREST 는 같은 토큰으로
-- 직접 호출되므로 화면 게이팅으로는 막히지 않는다.
--
-- 조치: 해당 조건을 `= ANY(ARRAY['super_admin','staff'])` 화이트리스트로 바꾼다.
-- viewer 전용 읽기는 기존 *_select_viewer 정책이 따로 있으므로 영향 없고,
-- 실질 변화는 distributor·end_user 차단뿐이다.
--
-- 사전 확인 — distributor/end_user 가 DB 에서 실제로 읽는 것은 products_sell 뷰 하나뿐:
--   · Quote.vue      : canViewCost(super_admin·staff) 아니면 products_sell 만 조회,
--                      customers 는 건너뛰고, 견적 저장·불러오기는 super_admin 전용
--   · PriceCompare.vue: 비권한 역할에게는 DB 조회 없는 로컬 계산기 (products·price_comparisons* 모두 게이팅)
--   · 직원용 PWA·수집기: RPC / service_role 경로라 무관

-- ── 1) products_sell — 원가 컬럼을 가리는 뷰. 소유자 권한 + 뷰 내부 역할 제한으로 되돌린다 ──
--
-- PostgREST 는 로그인 사용자를 모두 DB 역할 authenticated 로 묶으므로, 컬럼 단위 GRANT 로는
-- staff 와 distributor 를 구분할 수 없다. 따라서 '원가를 빼고 판매가만 보여주는 뷰'는
-- security_invoker 로 만들 수 없다(기반 products·products_price 가 super_admin·staff 전용이 되므로).
-- 대신 ① anon 권한 회수(오늘 조치 유지) ② 뷰 안에서 역할 화이트리스트로 직접 거른다.
alter view public.products_sell reset (security_invoker);

create or replace view public.products_sell as
select
  p.id,
  p.item,
  p.brand,
  p.description,
  p.sku,
  p.unit,
  p.is_active,
  ((round(((pp.wh_price_pcs / 0.70) / (1000)::numeric)) * (1000)::numeric))::integer as unit_price,
  ((round(((pp.wh_price_set / 0.70) / (1000)::numeric)) * (1000)::numeric))::integer as unit_price_set
from products p
  join products_price pp on pp.sku = p.sku
where p.is_active = true
  and (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)
       = any (array['super_admin'::text, 'staff'::text, 'distributor'::text, 'end_user'::text]));

revoke all on public.products_sell from anon;
grant select on public.products_sell to authenticated, service_role;

-- ── 2) 정책 43개 일괄 전환 ────────────────────────────────────────────────────
-- 정책별 qual/with_check 원문에서 해당 조건만 치환한다(다른 조건은 그대로 둔다).
-- 재실행해도 안전 — 패턴이 남아 있는 정책만 다시 손댄다.
do $$
declare
  p       record;
  old_txt constant text := 'IS DISTINCT FROM ''viewer''::text';
  new_txt constant text := '= ANY (ARRAY[''super_admin''::text, ''staff''::text])';
  n       int := 0;
begin
  for p in
    select tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (qual like '%' || old_txt || '%' or with_check like '%' || old_txt || '%')
  loop
    execute format('alter policy %I on public.%I%s%s',
      p.policyname, p.tablename,
      case when p.qual       is null then '' else format(' using (%s)',      replace(p.qual,       old_txt, new_txt)) end,
      case when p.with_check is null then '' else format(' with check (%s)', replace(p.with_check, old_txt, new_txt)) end);
    n := n + 1;
  end loop;
  raise notice 'rewritten policies: %', n;
end $$;
