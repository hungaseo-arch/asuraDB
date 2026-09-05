-- 근태 관리 — 대리출석 방지 Phase 2 (RPC + RLS 강화)
--
-- 배경: Phase 1(attendance_antifraud_phase1.sql)에서 스키마(기기 바인딩·이탈 알림 로그·
--       셀피/상태/HR 보정 컬럼)를 만들었지만, 판정 로직이 없어 지금도 employee-pwa 는
--       attendance/employee_devices 에 클라이언트가 원하는 값을 그대로 REST insert 할 수 있었다
--       (기기 미승인·셀피 없음 상태로도 출퇴근 기록이 그대로 들어감 — 스키마만 있고 강제력이 없던 상태).
--       Phase 2 는 그 강제력을 RPC(SECURITY DEFINER)로 만들고, 우회 가능한 직접 insert 경로를 막는다.
--
-- ⚠ 이 파일도 RLS 정책 변경을 포함해 apply_migration 이 auto-mode 분류기에 차단될 수 있다 —
--    Supabase SQL Editor 에서 직접 실행해야 할 수 있다.
--
-- ⚠ 중요: 이 마이그레이션 적용 후 employee-pwa/src/lib/attendance.ts 의 기존 checkIn()/checkOut()
--    (attendance 테이블에 직접 REST insert)는 즉시 RLS 위반(42501)으로 실패한다 — 아래 emp_insert_own_att
--    정책을 제거하기 때문. Phase 3 에서 프론트를 attendance_check_in()/attendance_check_out() RPC 호출로
--    바꾸기 전까지 PWA 출퇴근 버튼이 동작하지 않는다. 다만 실직원 12명은 아직 user_id 가 비어 있어
--    로그인 자체가 안 되므로(근태관리기능.md §9 체크리스트) 실사용 영향은 없고, 테스트 계정 2개만 영향받는다.

-- ── 기기 등록/검증: attendance_register_device ─────────────────────────────
-- 최초 1대는 자동 승인(is_active=true), 이미 활성 기기가 있는 상태에서 새 device_id 가 들어오면
-- 승인 대기(is_active=false)로 넣는다 — 관리자가 employee_devices 를 직접 UPDATE 해 승인한다
-- (admin_all 정책으로 이미 가능, 별도 승인 RPC 불필요). employee_id 는 클라이언트 입력을 신뢰하지 않고
-- auth.uid() 로 서버가 직접 찾는다(스푸핑 방지).
CREATE OR REPLACE FUNCTION attendance_register_device(
  p_device_id text,
  p_device_label text DEFAULT NULL
) RETURNS TABLE(status text, is_active boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_existing     employee_devices;
  v_has_active   boolean;
  v_new_active   boolean;
BEGIN
  SELECT id INTO v_employee_id FROM employees WHERE user_id = auth.uid();
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'attendance_register_device: 연결된 직원 정보가 없습니다';
  END IF;
  IF p_device_id IS NULL OR length(trim(p_device_id)) = 0 THEN
    RAISE EXCEPTION 'attendance_register_device: device_id 는 필수입니다';
  END IF;

  SELECT * INTO v_existing FROM employee_devices
    WHERE employee_id = v_employee_id AND device_id = p_device_id;

  IF FOUND THEN
    UPDATE employee_devices
      SET last_seen_at = now(), device_label = COALESCE(p_device_label, device_label)
      WHERE id = v_existing.id;
    RETURN QUERY SELECT (CASE WHEN v_existing.is_active THEN 'active' ELSE 'pending' END), v_existing.is_active;
    RETURN;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM employee_devices WHERE employee_id = v_employee_id AND is_active = true
  ) INTO v_has_active;
  v_new_active := NOT v_has_active;

  INSERT INTO employee_devices (employee_id, device_id, device_label, is_active)
  VALUES (v_employee_id, p_device_id, p_device_label, v_new_active);

  RETURN QUERY SELECT (CASE WHEN v_new_active THEN 'active' ELSE 'pending' END), v_new_active;
END;
$$;

-- ── 출근: attendance_check_in ────────────────────────────────────────────
-- 승인된 기기 + 셀피 경로가 있어야만 기록을 만든다. 좌표 판정(geofence)은 기존
-- trg_attendance_geofence 트리거가 insert 시 그대로 채운다(002_attendance_geofence_trigger.sql).
CREATE OR REPLACE FUNCTION attendance_check_in(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_device_id text,
  p_selfie_path text
) RETURNS attendance
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_device      employee_devices;
  v_row         attendance;
BEGIN
  SELECT id INTO v_employee_id FROM employees WHERE user_id = auth.uid();
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'attendance_check_in: 연결된 직원 정보가 없습니다';
  END IF;

  IF p_selfie_path IS NULL OR length(trim(p_selfie_path)) = 0 THEN
    RAISE EXCEPTION '셀피 촬영 없이는 출근할 수 없습니다';
  END IF;

  SELECT * INTO v_device FROM employee_devices
    WHERE employee_id = v_employee_id AND device_id = p_device_id;
  IF NOT FOUND OR NOT v_device.is_active THEN
    RAISE EXCEPTION '등록되지 않았거나 승인 대기 중인 기기입니다 — 관리자 승인이 필요합니다';
  END IF;

  IF EXISTS (
    SELECT 1 FROM attendance
    WHERE employee_id = v_employee_id AND check_type = 'check_in'
      AND (check_time AT TIME ZONE 'Asia/Jakarta')::date = (now() AT TIME ZONE 'Asia/Jakarta')::date
  ) THEN
    RAISE EXCEPTION '오늘 이미 출근 기록이 있습니다';
  END IF;

  INSERT INTO attendance (employee_id, check_type, latitude, longitude, device_id, selfie_url, device_info)
  VALUES (
    v_employee_id, 'check_in', p_lat, p_lon, p_device_id, p_selfie_path,
    jsonb_build_object('device_id', p_device_id, 'label', v_device.device_label)
  )
  RETURNING * INTO v_row;

  UPDATE employee_devices SET last_seen_at = now() WHERE id = v_device.id;

  RETURN v_row;
END;
$$;

-- ── 퇴근: attendance_check_out ───────────────────────────────────────────
-- 당일 출근 기록이 있고 아직 퇴근 전이어야만 허용한다.
CREATE OR REPLACE FUNCTION attendance_check_out(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_device_id text,
  p_selfie_path text
) RETURNS attendance
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_device      employee_devices;
  v_row         attendance;
BEGIN
  SELECT id INTO v_employee_id FROM employees WHERE user_id = auth.uid();
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'attendance_check_out: 연결된 직원 정보가 없습니다';
  END IF;

  IF p_selfie_path IS NULL OR length(trim(p_selfie_path)) = 0 THEN
    RAISE EXCEPTION '셀피 촬영 없이는 퇴근할 수 없습니다';
  END IF;

  SELECT * INTO v_device FROM employee_devices
    WHERE employee_id = v_employee_id AND device_id = p_device_id;
  IF NOT FOUND OR NOT v_device.is_active THEN
    RAISE EXCEPTION '등록되지 않았거나 승인 대기 중인 기기입니다 — 관리자 승인이 필요합니다';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM attendance
    WHERE employee_id = v_employee_id AND check_type = 'check_in'
      AND (check_time AT TIME ZONE 'Asia/Jakarta')::date = (now() AT TIME ZONE 'Asia/Jakarta')::date
  ) THEN
    RAISE EXCEPTION '오늘 출근 기록이 없어 퇴근할 수 없습니다';
  END IF;

  IF EXISTS (
    SELECT 1 FROM attendance
    WHERE employee_id = v_employee_id AND check_type = 'check_out'
      AND (check_time AT TIME ZONE 'Asia/Jakarta')::date = (now() AT TIME ZONE 'Asia/Jakarta')::date
  ) THEN
    RAISE EXCEPTION '오늘 이미 퇴근 기록이 있습니다';
  END IF;

  INSERT INTO attendance (employee_id, check_type, latitude, longitude, device_id, selfie_url, device_info)
  VALUES (
    v_employee_id, 'check_out', p_lat, p_lon, p_device_id, p_selfie_path,
    jsonb_build_object('device_id', p_device_id, 'label', v_device.device_label)
  )
  RETURNING * INTO v_row;

  UPDATE employee_devices SET last_seen_at = now() WHERE id = v_device.id;

  RETURN v_row;
END;
$$;

-- ── 지오펜스 이탈/재진입 감지: attendance_report_geofence_exit (요건 4) ────
-- 프론트(Phase 3)가 근무 중 주기적으로 좌표를 보내 호출한다. 상태 전이(안→밖, 밖→안)가 있을 때만
-- geofence_alerts 에 기록해 스팸을 막는다. 오늘 출근했고 아직 퇴근 전인 직원만 대상으로 한다.
CREATE OR REPLACE FUNCTION attendance_report_geofence_exit(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_geo         RECORD;
  v_last_type   text;
BEGIN
  SELECT id INTO v_employee_id FROM employees WHERE user_id = auth.uid();
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'attendance_report_geofence_exit: 연결된 직원 정보가 없습니다';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM attendance a
    WHERE a.employee_id = v_employee_id AND a.check_type = 'check_in'
      AND (a.check_time AT TIME ZONE 'Asia/Jakarta')::date = (now() AT TIME ZONE 'Asia/Jakarta')::date
      AND NOT EXISTS (
        SELECT 1 FROM attendance o
        WHERE o.employee_id = a.employee_id AND o.check_type = 'check_out'
          AND (o.check_time AT TIME ZONE 'Asia/Jakarta')::date = (a.check_time AT TIME ZONE 'Asia/Jakarta')::date
      )
  ) THEN
    RETURN 'not_clocked_in';
  END IF;

  SELECT * INTO v_geo FROM check_geofence(p_lat, p_lon);

  SELECT alert_type INTO v_last_type FROM geofence_alerts
    WHERE employee_id = v_employee_id ORDER BY created_at DESC LIMIT 1;

  IF v_geo.within THEN
    IF v_last_type = 'exit' THEN
      INSERT INTO geofence_alerts (employee_id, geofence_zone_id, latitude, longitude, distance_meters, alert_type)
        VALUES (v_employee_id, v_geo.zone_id, p_lat, p_lon, v_geo.distance, 'reenter');
      RETURN 'reenter_logged';
    END IF;
    RETURN 'no_change';
  ELSE
    IF v_last_type IS DISTINCT FROM 'exit' THEN
      INSERT INTO geofence_alerts (employee_id, geofence_zone_id, latitude, longitude, distance_meters, alert_type)
        VALUES (v_employee_id, v_geo.zone_id, p_lat, p_lon, v_geo.distance, 'exit');
      RETURN 'exit_logged';
    END IF;
    RETURN 'no_change';
  END IF;
END;
$$;

-- ── HR 수기 보정: attendance_correct (요건 7) ──────────────────────────────
-- super_admin 전용. 최초 원본 시각은 original_check_time 에 한 번만 보존한다(이미 보정된 건을
-- 다시 보정해도 최초 원본값이 덮어써지지 않도록 COALESCE).
CREATE OR REPLACE FUNCTION attendance_correct(
  p_attendance_id uuid,
  p_new_check_time TIMESTAMPTZ,
  p_reason text
) RETURNS attendance
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
  v_row      attendance;
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') <> 'super_admin' THEN
    RAISE EXCEPTION 'attendance_correct: 관리자만 근태 기록을 정정할 수 있습니다';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'attendance_correct: 정정 사유는 필수입니다';
  END IF;

  SELECT id INTO v_admin_id FROM employees WHERE user_id = auth.uid();

  UPDATE attendance
  SET original_check_time = COALESCE(original_check_time, check_time),
      check_time          = p_new_check_time,
      status               = 'corrected',
      corrected_by         = v_admin_id,
      corrected_at         = now(),
      correction_reason    = p_reason
  WHERE id = p_attendance_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'attendance_correct: 대상 근태 기록을 찾을 수 없습니다: %', p_attendance_id;
  END IF;

  RETURN v_row;
END;
$$;

-- ── 함수 권한: anon 차단, 로그인 사용자만 호출 ─────────────────────────────
REVOKE ALL ON FUNCTION attendance_register_device(text, text)                       FROM public, anon;
REVOKE ALL ON FUNCTION attendance_check_in(double precision, double precision, text, text)  FROM public, anon;
REVOKE ALL ON FUNCTION attendance_check_out(double precision, double precision, text, text) FROM public, anon;
REVOKE ALL ON FUNCTION attendance_report_geofence_exit(double precision, double precision)  FROM public, anon;
REVOKE ALL ON FUNCTION attendance_correct(uuid, timestamptz, text)                   FROM public, anon;

GRANT EXECUTE ON FUNCTION attendance_register_device(text, text)                       TO authenticated;
GRANT EXECUTE ON FUNCTION attendance_check_in(double precision, double precision, text, text)  TO authenticated;
GRANT EXECUTE ON FUNCTION attendance_check_out(double precision, double precision, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION attendance_report_geofence_exit(double precision, double precision)  TO authenticated;
GRANT EXECUTE ON FUNCTION attendance_correct(uuid, timestamptz, text)                   TO authenticated;

-- ── RLS 강화: 직접 insert 우회 경로 제거 ────────────────────────────────────
-- attendance/employee_devices 는 이제 위 RPC(SECURITY DEFINER)를 통해서만 값이 들어가야 한다.
-- 기존 emp_insert_own_att(001_create_attendance_schema.sql)·emp_insert_own_device(Phase 1) 는
-- employee_id 소유권만 검사할 뿐 기기 승인·셀피 필수 여부를 강제하지 않아, 이 정책이 남아있으면
-- 클라이언트가 RPC를 건너뛰고 REST로 직접 insert 해 대리출석 방지 로직 전체를 무력화할 수 있다.
DROP POLICY IF EXISTS emp_insert_own_att    ON attendance;
DROP POLICY IF EXISTS emp_insert_own_device ON employee_devices;
