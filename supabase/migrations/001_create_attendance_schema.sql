-- 근태 관리 시스템 스키마
-- AsuraDB + Supabase

-- 1. 직원 테이블
CREATE TABLE IF NOT EXISTS employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  employee_code VARCHAR(20) UNIQUE NOT NULL,
  department VARCHAR(100),
  position VARCHAR(100),
  phone VARCHAR(20),
  profile_image TEXT,
  annual_leave_total INTEGER DEFAULT 15,
  annual_leave_used INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. 지오펜싱 영역 테이블
CREATE TABLE IF NOT EXISTS geofence_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(200) NOT NULL,
  description TEXT,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  radius_meters INTEGER NOT NULL DEFAULT 100,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. 출퇴근 기록 테이블
CREATE TABLE IF NOT EXISTS attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID REFERENCES employees(id) ON DELETE CASCADE,
  check_type VARCHAR(10) NOT NULL CHECK (check_type IN ('check_in', 'check_out')),
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  geofence_zone_id UUID REFERENCES geofence_zones(id),
  is_within_geofence BOOLEAN DEFAULT false,
  distance_meters DOUBLE PRECISION,
  device_info JSONB,
  check_time TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. 휴가/연차 신청 테이블
CREATE TABLE IF NOT EXISTS leave_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID REFERENCES employees(id) ON DELETE CASCADE,
  leave_type VARCHAR(20) NOT NULL CHECK (leave_type IN ('annual', 'sick', 'personal', 'other')),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  days_count DOUBLE PRECISION NOT NULL,
  reason TEXT,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  approved_by UUID REFERENCES employees(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. 초과근무 신청 테이블
CREATE TABLE IF NOT EXISTS overtime (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID REFERENCES employees(id) ON DELETE CASCADE,
  overtime_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  hours DOUBLE PRECISION NOT NULL,
  reason TEXT,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  approved_by UUID REFERENCES employees(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);


-- 인덱스 (재실행 가능하도록 IF NOT EXISTS)
CREATE INDEX IF NOT EXISTS idx_attendance_employee_id ON attendance(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_check_time ON attendance(check_time);
CREATE INDEX IF NOT EXISTS idx_attendance_employee_date ON attendance(employee_id, check_time);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_id ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_overtime_employee_id ON overtime(employee_id);
CREATE INDEX IF NOT EXISTS idx_overtime_status ON overtime(status);
CREATE INDEX IF NOT EXISTS idx_employees_user_id ON employees(user_id);
CREATE INDEX IF NOT EXISTS idx_employees_code ON employees(employee_code);

-- Row Level Security
ALTER TABLE employees      ENABLE ROW LEVEL SECURITY;
ALTER TABLE geofence_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance     ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE overtime       ENABLE ROW LEVEL SECURITY;

-- ── RLS 정책 ─────────────────────────────────────────────────────────────
-- 관리자 판정은 AsuraDB 역할 모델(app_metadata.role)을 그대로 따른다.
--   super_admin : 전체 읽기·쓰기      staff : 전체 읽기(read-only)
--   그 외 로그인 사용자 : 본인 행만 조회 + 본인 신청 등록 (직원 PWA용)
-- employees 테이블을 참조하는 자기참조 서브쿼리는 쓰지 않는다 —
-- employees 정책 안에서 employees 를 조회하면 Postgres 가
-- "infinite recursion detected in policy for relation employees"(42P17) 로 거부한다.
-- 모든 정책은 CLAUDE.md 규약대로 TO authenticated (anon 차단).

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['employees','geofence_zones','attendance','leave_requests','overtime'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'admin_all', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'staff_read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'Admin full access', t);
  END LOOP;
END $$;

-- super_admin: 전 테이블 읽기·쓰기
CREATE POLICY admin_all ON employees      FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
CREATE POLICY admin_all ON geofence_zones FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
CREATE POLICY admin_all ON attendance     FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
CREATE POLICY admin_all ON leave_requests FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
CREATE POLICY admin_all ON overtime       FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');

-- staff: 전 테이블 조회 전용 (근태 화면 열람)
CREATE POLICY staff_read ON employees      FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');
CREATE POLICY staff_read ON geofence_zones FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');
CREATE POLICY staff_read ON attendance     FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');
CREATE POLICY staff_read ON leave_requests FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');
CREATE POLICY staff_read ON overtime       FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');

-- 직원 본인: 자기 행만 조회 + 본인 명의 신청 등록 (직원 PWA)
DROP POLICY IF EXISTS emp_read_self          ON employees;
DROP POLICY IF EXISTS emp_read_zones         ON geofence_zones;
DROP POLICY IF EXISTS emp_read_own_att       ON attendance;
DROP POLICY IF EXISTS emp_insert_own_att     ON attendance;
DROP POLICY IF EXISTS emp_read_own_leave     ON leave_requests;
DROP POLICY IF EXISTS emp_insert_own_leave   ON leave_requests;
DROP POLICY IF EXISTS emp_read_own_ot        ON overtime;
DROP POLICY IF EXISTS emp_insert_own_ot      ON overtime;

CREATE POLICY emp_read_self ON employees FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- 근무지 좌표는 출퇴근 판정에 필요하므로 로그인 사용자 전체 조회 허용
CREATE POLICY emp_read_zones ON geofence_zones FOR SELECT TO authenticated
  USING (is_active = true);

CREATE POLICY emp_read_own_att ON attendance FOR SELECT TO authenticated
  USING (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));
CREATE POLICY emp_insert_own_att ON attendance FOR INSERT TO authenticated
  WITH CHECK (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));

CREATE POLICY emp_read_own_leave ON leave_requests FOR SELECT TO authenticated
  USING (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));
CREATE POLICY emp_insert_own_leave ON leave_requests FOR INSERT TO authenticated
  WITH CHECK (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));

CREATE POLICY emp_read_own_ot ON overtime FOR SELECT TO authenticated
  USING (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));
CREATE POLICY emp_insert_own_ot ON overtime FOR INSERT TO authenticated
  WITH CHECK (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));

-- ── 지오펜싱 함수 ────────────────────────────────────────────────────────
-- search_path 를 고정한다 (Supabase security advisor: function_search_path_mutable)

-- 두 좌표 간 거리(m) — Haversine
CREATE OR REPLACE FUNCTION haversine_distance(
  lat1 DOUBLE PRECISION, lon1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION, lon2 DOUBLE PRECISION
) RETURNS DOUBLE PRECISION
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
DECLARE
  R DOUBLE PRECISION := 6371000;
  dlat DOUBLE PRECISION;
  dlon DOUBLE PRECISION;
  a DOUBLE PRECISION;
  c DOUBLE PRECISION;
BEGIN
  dlat := radians(lat2 - lat1);
  dlon := radians(lon2 - lon1);
  a := sin(dlat / 2) * sin(dlat / 2) +
       cos(radians(lat1)) * cos(radians(lat2)) *
       sin(dlon / 2) * sin(dlon / 2);
  c := 2 * atan2(sqrt(a), sqrt(1 - a));
  RETURN R * c;
END;
$$;

-- 현재 좌표에서 가장 가까운 활성 근무지와 반경 내 여부
CREATE OR REPLACE FUNCTION check_geofence(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION
) RETURNS TABLE(zone_id UUID, zone_name TEXT, distance DOUBLE PRECISION, within BOOLEAN)
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    gz.id,
    gz.name::text,
    haversine_distance(p_lat, p_lon, gz.latitude, gz.longitude) AS dist,
    haversine_distance(p_lat, p_lon, gz.latitude, gz.longitude) <= gz.radius_meters AS within
  FROM geofence_zones gz
  WHERE gz.is_active = true
  ORDER BY dist ASC
  LIMIT 1;
END;
$$;
