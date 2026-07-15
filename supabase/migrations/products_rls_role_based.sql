-- ============================================================
-- products 원가 보호 + products_sell 뷰 (역할 기반 RLS)
--
-- 가이드: AsuraDB RLS 보안 점검 가이드 (4역할 모델)
-- 역할: super_admin · staff · distributor · end_user
--   - super_admin / staff : products(원가 포함) 조회 가능
--   - distributor / end_user : products RLS 차단 → products_sell 뷰(원가 없음)만
--   - 쓰기(insert/update/delete): super_admin 만
--
-- 사용 규약: app_metadata.role 만 신뢰 (user_metadata 는 사용자가 self-update 가능)
-- ============================================================

-- 1) 기존 광범위한 정책 제거 (enable_rls_all_tables.sql 의 products_auth_all 등)
DROP POLICY IF EXISTS products_anon_all  ON public.products;
DROP POLICY IF EXISTS products_auth_all  ON public.products;
DROP POLICY IF EXISTS products_read_priced ON public.products;
DROP POLICY IF EXISTS products_write_admin ON public.products;

-- 2) RLS 활성화 (재실행 안전)
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- 3) SELECT: 원가 포함 조회는 super_admin / staff 만
CREATE POLICY products_read_priced ON public.products
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') IN ('super_admin', 'staff'));

-- 4) INSERT/UPDATE/DELETE: super_admin 만
CREATE POLICY products_write_admin ON public.products
  FOR ALL TO authenticated
  USING      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');

-- ============================================================
-- 5) products_sell 뷰 — 원가 컬럼 제외, security_invoker=false(definer)로 RLS 우회
--    distributor / end_user 가 안전하게 판매가만 볼 수 있음.
--    unit_price = wh_price / 0.8 (25% 마진)을 서버 측에서 계산.
-- ============================================================
DROP VIEW IF EXISTS public.products_sell;

CREATE VIEW public.products_sell
  WITH (security_invoker = false)
  AS
  SELECT
    id,
    item,
    brand,
    description,
    sku,
    CASE WHEN wh_price IS NULL OR wh_price = 0
         THEN 0
         ELSE ROUND(wh_price / 0.8)
    END AS unit_price,
    CASE WHEN wh_price_set IS NULL OR wh_price_set = 0
         THEN NULL
         ELSE ROUND(wh_price_set / 0.8)
    END AS unit_price_set,
    unit,
    currency,
    is_active,
    created_at,
    updated_at
  FROM public.products
  WHERE is_active = TRUE;

-- 6) 뷰 권한 — 인증된 모든 사용자가 SELECT 가능
GRANT SELECT ON public.products_sell TO authenticated;

-- ============================================================
-- 검증 쿼리 (참고용 — 실행 시 결과로 정책 확인)
--
--   SELECT polname, polcmd, polroles::regrole[]
--   FROM   pg_policy WHERE polrelid = 'public.products'::regclass;
--
--   -- distributor 로 로그인한 JWT 로 호출 시:
--   --   GET /rest/v1/products?select=*           → []        (RLS 차단)
--   --   GET /rest/v1/products_sell?select=*      → 행 반환 (원가 컬럼 없음)
-- ============================================================
