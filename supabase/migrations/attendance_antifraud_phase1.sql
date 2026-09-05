-- 근태 관리 — 대리출석 방지 Phase 1 (스키마 + 정책 + 배치)
--
-- 배경: 기존 출퇴근 기록은 좌표만 서버가 검증하고(002_attendance_geofence_trigger.sql),
--       ① 반경이 지점별로 들쭉날쭉하고 ② 집(HOME)도 근무지로 등록돼 있어 대리출석·재택 허위출석이
--       가능했다. 이번 Phase 1 은 아래 결정사항 D1/D2/D4 를 반영하고, 4~7번 요건(이탈 알림·셀피 촬영·
--       미퇴근 자동 표시·HR 수기 보정 감사기록)에 필요한 스키마를 추가한다.
--       실제 판정 로직(RPC)·프론트엔드 촬영 플로우는 Phase 2/3 에서 다룬다.
--
-- ⚠ 이 파일은 auto-mode 보안 분류기에 의해 apply_migration 이 차단될 수 있어(RLS/정책 변경 포함),
--    Supabase SQL Editor 에서 직접 실행해야 할 수 있다.

-- ── D1. 본사 지오펜싱 반경 150m 로 표준화 ──────────────────────────────────
-- 기존 30m 는 GPS 오차 범위 내에서도 "영역 밖"으로 오판정되는 사례가 많아 150m 로 넓힌다.
UPDATE geofence_zones SET radius_meters = 150, updated_at = now()
WHERE name = 'PT. ASCENDO INTERNASIONAL';

-- ── D2. HOME 존 비활성화 ───────────────────────────────────────────────────
-- 재택을 근무지로 인정하면 사실상 지오펜싱이 무력화되므로 집 좌표는 근무지에서 제외한다.
-- (행은 과거 기록 참조용으로 남기고 is_active 만 false 로 끈다.)
UPDATE geofence_zones SET is_active = false, updated_at = now()
WHERE name = 'HOME';

-- ── 기기 바인딩: employee_devices ──────────────────────────────────────────
-- 직원 1명이 등록한 기기에서만 출퇴근을 찍게 해 "동료 폰으로 대신 찍기"를 막는다.
-- 실제 등록/승인 흐름(최초 1대 자동 등록, 기기 변경 시 관리자 승인 등)은 Phase 2 RPC 에서 구현한다.
CREATE TABLE IF NOT EXISTS employee_devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  device_id     VARCHAR(200) NOT NULL,
  device_label  VARCHAR(200),
  registered_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at  TIMESTAMPTZ DEFAULT now(),
  is_active     BOOLEAN DEFAULT true,
  UNIQUE (employee_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_employee_devices_employee_id ON employee_devices(employee_id);

-- ── 지오펜스 이탈 알림 로그: geofence_alerts (요건 4) ──────────────────────
-- 근무 중 이탈 감지 시 퇴근 打刻을 만들지 않고 "알림용 기록"만 남긴다.
-- 실제 이탈 감지(주기적 위치 전송)와 알림 발송(푸시 등)은 Phase 2/3 에서 붙인다.
CREATE TABLE IF NOT EXISTS geofence_alerts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id      UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  geofence_zone_id UUID REFERENCES geofence_zones(id),
  latitude         DOUBLE PRECISION NOT NULL,
  longitude        DOUBLE PRECISION NOT NULL,
  distance_meters  DOUBLE PRECISION,
  alert_type       VARCHAR(20) NOT NULL DEFAULT 'exit' CHECK (alert_type IN ('exit', 'reenter')),
  acknowledged      BOOLEAN DEFAULT false,
  acknowledged_by   UUID REFERENCES employees(id),
  acknowledged_at   TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_geofence_alerts_employee_id ON geofence_alerts(employee_id);
CREATE INDEX IF NOT EXISTS idx_geofence_alerts_created_at  ON geofence_alerts(created_at DESC);

-- ── attendance 확장: 셀피·기기·상태·HR 보정 감사기록 (요건 5~7) ────────────
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS selfie_url          TEXT,
  ADD COLUMN IF NOT EXISTS device_id           VARCHAR(200),
  ADD COLUMN IF NOT EXISTS status              VARCHAR(20) NOT NULL DEFAULT 'normal'
    CHECK (status IN ('normal', 'belum_checkout', 'corrected')),
  ADD COLUMN IF NOT EXISTS corrected_by        UUID REFERENCES employees(id),
  ADD COLUMN IF NOT EXISTS corrected_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS correction_reason   TEXT,
  ADD COLUMN IF NOT EXISTS original_check_time TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status);

-- ── 당일 마감 배치: 미퇴근(belum check-out) 자동 표시 (요건 6) ─────────────
-- check_in 은 있으나 같은 날짜(Asia/Jakarta 기준) check_out 이 없는 건을 다음날 새벽에 표시한다.
-- 당일(아직 퇴근 전일 수 있는 날)은 절대 건드리지 않는다 — 지난 날짜만 대상.
CREATE OR REPLACE FUNCTION attendance_flag_missing_checkout()
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE attendance a
  SET status = 'belum_checkout'
  WHERE a.check_type = 'check_in'
    AND a.status = 'normal'
    AND (a.check_time AT TIME ZONE 'Asia/Jakarta')::date < (now() AT TIME ZONE 'Asia/Jakarta')::date
    AND NOT EXISTS (
      SELECT 1 FROM attendance o
      WHERE o.employee_id = a.employee_id
        AND o.check_type = 'check_out'
        AND (o.check_time AT TIME ZONE 'Asia/Jakarta')::date = (a.check_time AT TIME ZONE 'Asia/Jakarta')::date
    );
END;
$$;

-- 매일 UTC 18:00 (Jakarta 01:00, 자정 이후 하루가 확정된 뒤) 실행.
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'attendance-flag-missing-checkout';
SELECT cron.schedule(
  'attendance-flag-missing-checkout',
  '0 18 * * *',
  $$SELECT attendance_flag_missing_checkout();$$
);

-- ── RLS: 신규 테이블 활성화 ────────────────────────────────────────────────
ALTER TABLE employee_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE geofence_alerts  ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['employee_devices', 'geofence_alerts'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'admin_all', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'staff_read', t);
  END LOOP;
END $$;

CREATE POLICY admin_all ON employee_devices FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
CREATE POLICY staff_read ON employee_devices FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');

CREATE POLICY admin_all ON geofence_alerts FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
CREATE POLICY staff_read ON geofence_alerts FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');

-- 직원 본인: 자기 기기 등록/조회, 자기 이탈 알림 기록(insert 는 Phase2 RPC 가 대신 하므로 조회만)
DROP POLICY IF EXISTS emp_read_own_devices   ON employee_devices;
DROP POLICY IF EXISTS emp_insert_own_device  ON employee_devices;
DROP POLICY IF EXISTS emp_read_own_alerts    ON geofence_alerts;

CREATE POLICY emp_read_own_devices ON employee_devices FOR SELECT TO authenticated
  USING (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));
CREATE POLICY emp_insert_own_device ON employee_devices FOR INSERT TO authenticated
  WITH CHECK (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));

CREATE POLICY emp_read_own_alerts ON geofence_alerts FOR SELECT TO authenticated
  USING (employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid()));

-- ── Storage: 출퇴근 셀피 버킷 (요건 5) ──────────────────────────────────────
-- 파일 경로 규약: <employee_id>/<attendance_id>.jpg (attendance.selfie_url 컬럼에는
-- 이 경로만 저장한다 — 버킷이 private 이라 공개 URL 이 아니며, 화면에서는 signed URL 로 열람한다).
INSERT INTO storage.buckets (id, name, public)
VALUES ('attendance-selfies', 'attendance-selfies', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS attendance_selfies_admin_all   ON storage.objects;
DROP POLICY IF EXISTS attendance_selfies_staff_read  ON storage.objects;
DROP POLICY IF EXISTS attendance_selfies_self_insert ON storage.objects;
DROP POLICY IF EXISTS attendance_selfies_self_read   ON storage.objects;

CREATE POLICY attendance_selfies_admin_all ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'attendance-selfies' AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  WITH CHECK (bucket_id = 'attendance-selfies' AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');

CREATE POLICY attendance_selfies_staff_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'attendance-selfies' AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'staff');

-- 본인 폴더(경로 첫 세그먼트 = 자신의 employees.id)에만 업로드/조회 허용
CREATE POLICY attendance_selfies_self_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'attendance-selfies'
    AND (storage.foldername(name))[1] IN (SELECT id::text FROM employees WHERE user_id = auth.uid())
  );
CREATE POLICY attendance_selfies_self_read ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'attendance-selfies'
    AND (storage.foldername(name))[1] IN (SELECT id::text FROM employees WHERE user_id = auth.uid())
  );

-- ── D4. 셀피 90일 보관 후 자동 삭제 ─────────────────────────────────────────
-- Storage 객체 삭제는 Storage API 호출이 필요해 순수 SQL(DELETE FROM storage.objects)만으로는
-- 실제 파일까지 지워진다는 보장이 없다 — 20260824_cloud_collectors_infra.sql 의
-- trigger_collector() 와 완전히 동일한 패턴(vault 시크릿 + pg_net → Edge Function)으로 구현한다.
-- project_url / service_role_key 는 그 마이그레이션에서 이미 vault 에 등록되어 있어 재사용한다.
CREATE OR REPLACE FUNCTION trigger_attendance_selfie_cleanup()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url text;
  v_key text;
  v_req bigint;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NULL OR v_key IS NULL OR v_url LIKE '%<%' OR v_key LIKE '%<%' THEN
    RAISE EXCEPTION 'trigger_attendance_selfie_cleanup: vault secret project_url/service_role_key 미등록';
  END IF;

  v_req := net.http_post(
    url     := v_url || '/functions/v1/attendance-selfie-cleanup',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_key),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );

  INSERT INTO cron_run_log (kind, request_id) VALUES ('attendance_selfie_cleanup', v_req);
  RETURN v_req;
END;
$$;

REVOKE ALL ON FUNCTION trigger_attendance_selfie_cleanup() FROM public, anon, authenticated;

-- 미퇴근 배치 다음, 매일 UTC 18:30 (Jakarta 01:30) 실행.
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'attendance-selfie-cleanup';
SELECT cron.schedule(
  'attendance-selfie-cleanup',
  '30 18 * * *',
  $$SELECT trigger_attendance_selfie_cleanup();$$
);
