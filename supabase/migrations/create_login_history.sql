-- 회원 로그인/로그아웃 이력
-- 로그인·로그아웃 시점에 클라이언트(src/lib/auth.ts)가 직접 insert 한다.

CREATE TABLE IF NOT EXISTS login_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  email VARCHAR(255),
  role VARCHAR(20),
  event_type VARCHAR(10) NOT NULL CHECK (event_type IN ('login', 'logout')),
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_history_user_id    ON login_history(user_id);
CREATE INDEX IF NOT EXISTS idx_login_history_created_at ON login_history(created_at DESC);

ALTER TABLE login_history ENABLE ROW LEVEL SECURITY;

-- ── RLS 정책 ─────────────────────────────────────────────────────────────
-- 관리자 판정은 AsuraDB 역할 모델(app_metadata.role)을 그대로 따른다(001_create_attendance_schema.sql 과 동일 패턴).
--   super_admin : 전체 읽기·쓰기      staff : 전체 읽기(read-only, 로그 관리 화면 열람)
--   그 외 로그인 사용자 : 본인 로그인/로그아웃 이벤트만 기록(조회 불가 — 관리자 전용 화면)

DROP POLICY IF EXISTS admin_all    ON login_history;
DROP POLICY IF EXISTS staff_read   ON login_history;
DROP POLICY IF EXISTS self_insert  ON login_history;

CREATE POLICY admin_all ON login_history FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');

CREATE POLICY staff_read ON login_history FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');

CREATE POLICY self_insert ON login_history FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
