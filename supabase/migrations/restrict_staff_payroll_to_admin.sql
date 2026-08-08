-- ============================================================
-- 인사·급여 접근제어 — staff_payroll 조회를 super_admin 전용으로
--
-- 배경: add_staff_payroll.sql 의 정책이 `to authenticated using (true)` 라
--       로그인한 모든 역할(staff·distributor·end_user 포함)이 실명·NIK·기본급·Gross 를
--       REST 로 그대로 읽을 수 있었다. 화면(Databases.vue 직원 탭)은 super_admin 에게만
--       보이지만, 화면 숨김은 표시 제어일 뿐이라 실제 차단은 여기(RLS)에서 한다.
--
-- 사용 규약: app_metadata.role 만 신뢰 (user_metadata 는 사용자가 self-update 가능)
--            — products_rls_role_based.sql 과 동일한 패턴.
--
-- 적용: 2026-08-07 적용 완료 (MCP apply_migration · 재실행 안전)
-- 영향: staff 역할 계정은 staff_payroll 조회 시 빈 배열을 받는다.
--       (직원 탭이 이미 super_admin 전용이라 화면 동작에는 영향 없음)
--       쓰기 정책은 두지 않는다 — 현재도 정책이 없어 REST 쓰기는 전 역할 차단이고,
--       importer 는 service_role 이라 RLS 를 우회한다. 새 권한을 만들지 않기 위함.
--
-- ※ public.staff (실명·NIK 마스터) 는 건드리지 않는다.
--   이미 branch-sales 서브시스템의 정책(staff_read = spb_is_member())으로 좁혀져 있어,
--   여기서 다시 정의하면 그 앱의 sales·branch 계정 접근이 깨진다.
-- ============================================================

ALTER TABLE public.staff_payroll ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff_payroll read authenticated" ON public.staff_payroll;
DROP POLICY IF EXISTS staff_payroll_auth_all   ON public.staff_payroll;
DROP POLICY IF EXISTS staff_payroll_read_admin ON public.staff_payroll;

CREATE POLICY staff_payroll_read_admin ON public.staff_payroll
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');

-- 확인용 — 적용 후 정책 목록
-- SELECT tablename, policyname, cmd, qual FROM pg_policies
--  WHERE tablename = 'staff_payroll';
