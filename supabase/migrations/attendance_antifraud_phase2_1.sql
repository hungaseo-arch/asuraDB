-- 근태 관리 — 대리출석 방지 Phase 2.1 (코드 검토 후속: 보안·무결성 수정)
--
-- 근거: docs/attendance-antifraud-review.md (2026-09-06). Phase 2(attendance_antifraud_phase2.sql) 적용 후
--       전체 검토에서 나온 S1~S6·A2·A3 항목을 한 파일로 묶었다. 순서대로 실행해야 한다.
--
-- ⚠ RLS 정책 변경·storage.buckets UPDATE 를 포함하므로 apply_migration 이 auto-mode 분류기에 차단될 수
--    있다 — Supabase SQL Editor 에서 직접 실행한다. 전체가 한 트랜잭션은 아니므로 중간에 실패하면
--    실패 지점부터 다시 실행한다(모든 문장은 재실행 안전: OR REPLACE / IF EXISTS / UPDATE).
--
-- 변경 요약
--   S1  attendance_correct 역할 검사 `<>` → `IS DISTINCT FROM` (role 클레임 없는 사용자 통과 버그, 재현 확인)
--   S2  셀피 경로 검증 helper attendance_assert_selfie(): 본인 폴더 + storage.objects 실존(15분 이내) + 재사용 금지
--       + attendance-selfies 버킷 file_size_limit 2MB / image/jpeg 만 허용
--   S3  출퇴근 RPC 에 직원 단위 advisory lock → 더블탭/동시 호출 중복 차단
--   S4  attendance 의 admin_all(ALL) → admin_read(SELECT) 로 축소. 수정은 attendance_correct, 추가는
--       attendance_add_manual, 취소는 attendance_void 로만 가능(감사 추적 강제)
--   S5  attendance_register_device 반환 컬럼 status/is_active → o_status/o_is_active (컬럼명 충돌 제거)
--   S6  handle_new_user()/sync_role_to_auth() 트리거 함수 EXECUTE 를 anon·authenticated 에서 회수(어드바이저 0028/0029)
--   A2  attendance_report_geofence_exit: 마지막 알림 조회를 오늘(Asia/Jakarta)로 한정, 존 없음(NULL) 방어
--   A3  attendance_add_manual(): HR 수기 추가(누락 퇴근 등) + 같은 날 check_in 의 belum_checkout 해제
--       attendance_void(): 잘못된 기록 취소(status='voided', 물리 삭제 없음). status CHECK 에 'voided' 추가.
--       수기 추가 행은 좌표가 없으므로 latitude/longitude NOT NULL 해제 + 지오펜스 트리거 NULL 가드.

-- ═══════════════════════════════════════════════════════════════════════════
-- 0. 스키마 보강: status 'voided', 좌표 nullable, 트리거 NULL 가드
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE attendance DROP CONSTRAINT IF EXISTS attendance_status_check;
ALTER TABLE attendance ADD CONSTRAINT attendance_status_check
  CHECK (status IN ('normal', 'belum_checkout', 'corrected', 'voided'));

ALTER TABLE attendance ALTER COLUMN latitude  DROP NOT NULL;
ALTER TABLE attendance ALTER COLUMN longitude DROP NOT NULL;

CREATE OR REPLACE FUNCTION attendance_apply_geofence()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  g RECORD;
BEGIN
  -- HR 수기 추가(attendance_add_manual)는 좌표가 없다 — 판정 불가로 남긴다.
  IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
    NEW.geofence_zone_id   := NULL;
    NEW.is_within_geofence := false;
    NEW.distance_meters    := NULL;
    RETURN NEW;
  END IF;

  SELECT * INTO g FROM check_geofence(NEW.latitude, NEW.longitude);

  IF FOUND THEN
    NEW.geofence_zone_id    := CASE WHEN g.within THEN g.zone_id ELSE NULL END;
    NEW.is_within_geofence  := COALESCE(g.within, false);
    NEW.distance_meters     := g.distance;
  ELSE
    NEW.geofence_zone_id    := NULL;
    NEW.is_within_geofence  := false;
    NEW.distance_meters     := NULL;
  END IF;

  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- S2. 셀피 경로 검증 helper (RPC 내부 전용 — 외부 호출 권한 없음)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION attendance_assert_selfie(
  p_employee_id uuid,
  p_selfie_path text,
  p_check_type  text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_selfie_path IS NULL OR length(trim(p_selfie_path)) = 0 THEN
    RAISE EXCEPTION '셀피 촬영 없이는 %할 수 없습니다', CASE WHEN p_check_type = 'check_in' THEN '출근' ELSE '퇴근' END;
  END IF;
  -- 경로 규약: <employee_id>/<check_type>-<timestamp>.jpg — 첫 세그먼트가 본인 employee_id 여야 한다
  IF p_selfie_path NOT LIKE p_employee_id::text || '/%' THEN
    RAISE EXCEPTION '셀피 경로가 본인 폴더가 아닙니다';
  END IF;
  -- 실제로 업로드된 파일이어야 한다(15분 이내). 임의 문자열로 셀피 요건을 우회하는 것을 막는다.
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'attendance-selfies'
      AND name = p_selfie_path
      AND created_at > now() - interval '15 minutes'
  ) THEN
    RAISE EXCEPTION '셀피 파일을 찾을 수 없거나 오래된 파일입니다 — 다시 촬영해 주세요';
  END IF;
  -- 한 장의 셀피를 여러 기록에 재사용하지 못하게 한다
  IF EXISTS (SELECT 1 FROM attendance WHERE selfie_url = p_selfie_path) THEN
    RAISE EXCEPTION '이미 사용된 셀피입니다 — 다시 촬영해 주세요';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION attendance_assert_selfie(uuid, text, text) FROM public, anon, authenticated;

-- 버킷 자체 제한: 2MB 이하 JPEG 만 (RLS 는 폴더만 제한하므로 임의 파일 적재 방지)
UPDATE storage.buckets
   SET file_size_limit = 2097152,
       allowed_mime_types = ARRAY['image/jpeg']
 WHERE id = 'attendance-selfies';

-- ═══════════════════════════════════════════════════════════════════════════
-- S5. attendance_register_device — 반환 컬럼명 충돌 제거
--     RETURNS TABLE 의 컬럼은 plpgsql OUT 변수라 본문의 `WHERE ... is_active = true` 와 충돌
--     (column reference "is_active" is ambiguous). 반환 타입이 바뀌므로 DROP 후 재생성.
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS attendance_register_device(text, text);
CREATE FUNCTION attendance_register_device(
  p_device_id text,
  p_device_label text DEFAULT NULL
) RETURNS TABLE(o_status text, o_is_active boolean)
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
  SELECT e.id INTO v_employee_id FROM employees e WHERE e.user_id = auth.uid();
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'attendance_register_device: 연결된 직원 정보가 없습니다';
  END IF;
  IF p_device_id IS NULL OR length(trim(p_device_id)) = 0 THEN
    RAISE EXCEPTION 'attendance_register_device: device_id 는 필수입니다';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('employee_devices:' || v_employee_id::text));

  SELECT d.* INTO v_existing FROM employee_devices d
    WHERE d.employee_id = v_employee_id AND d.device_id = p_device_id;

  IF FOUND THEN
    UPDATE employee_devices d
      SET last_seen_at = now(), device_label = COALESCE(p_device_label, d.device_label)
      WHERE d.id = v_existing.id;
    RETURN QUERY SELECT (CASE WHEN v_existing.is_active THEN 'active' ELSE 'pending' END)::text, v_existing.is_active;
    RETURN;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM employee_devices d WHERE d.employee_id = v_employee_id AND d.is_active = true
  ) INTO v_has_active;
  v_new_active := NOT v_has_active;

  INSERT INTO employee_devices (employee_id, device_id, device_label, is_active)
  VALUES (v_employee_id, p_device_id, p_device_label, v_new_active);

  RETURN QUERY SELECT (CASE WHEN v_new_active THEN 'active' ELSE 'pending' END)::text, v_new_active;
END;
$$;
REVOKE ALL ON FUNCTION attendance_register_device(text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION attendance_register_device(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- S2+S3. attendance_check_in / attendance_check_out — advisory lock + 셀피 검증 + voided 제외
-- ═══════════════════════════════════════════════════════════════════════════
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
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION '위치 정보가 없어 출근할 수 없습니다';
  END IF;

  -- 같은 직원의 동시 호출(더블탭·재시도)을 직렬화한다 — 트랜잭션 종료 시 자동 해제
  PERFORM pg_advisory_xact_lock(hashtext('attendance:' || v_employee_id::text));

  PERFORM attendance_assert_selfie(v_employee_id, p_selfie_path, 'check_in');

  SELECT * INTO v_device FROM employee_devices
    WHERE employee_id = v_employee_id AND device_id = p_device_id;
  IF NOT FOUND OR NOT v_device.is_active THEN
    RAISE EXCEPTION '등록되지 않았거나 승인 대기 중인 기기입니다 — 관리자 승인이 필요합니다';
  END IF;

  IF EXISTS (
    SELECT 1 FROM attendance
    WHERE employee_id = v_employee_id AND check_type = 'check_in' AND status <> 'voided'
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
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION '위치 정보가 없어 퇴근할 수 없습니다';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('attendance:' || v_employee_id::text));

  PERFORM attendance_assert_selfie(v_employee_id, p_selfie_path, 'check_out');

  SELECT * INTO v_device FROM employee_devices
    WHERE employee_id = v_employee_id AND device_id = p_device_id;
  IF NOT FOUND OR NOT v_device.is_active THEN
    RAISE EXCEPTION '등록되지 않았거나 승인 대기 중인 기기입니다 — 관리자 승인이 필요합니다';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM attendance
    WHERE employee_id = v_employee_id AND check_type = 'check_in' AND status <> 'voided'
      AND (check_time AT TIME ZONE 'Asia/Jakarta')::date = (now() AT TIME ZONE 'Asia/Jakarta')::date
  ) THEN
    RAISE EXCEPTION '오늘 출근 기록이 없어 퇴근할 수 없습니다';
  END IF;

  IF EXISTS (
    SELECT 1 FROM attendance
    WHERE employee_id = v_employee_id AND check_type = 'check_out' AND status <> 'voided'
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

-- ═══════════════════════════════════════════════════════════════════════════
-- A2. attendance_report_geofence_exit — 오늘 기준 상태 전이, 존 없음 방어
-- ═══════════════════════════════════════════════════════════════════════════
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
  v_today       date := (now() AT TIME ZONE 'Asia/Jakarta')::date;
BEGIN
  SELECT id INTO v_employee_id FROM employees WHERE user_id = auth.uid();
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'attendance_report_geofence_exit: 연결된 직원 정보가 없습니다';
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RETURN 'no_position';
  END IF;

  -- 오늘 출근했고 아직 퇴근 전인 직원만 대상 (취소된 기록 제외)
  IF NOT EXISTS (
    SELECT 1 FROM attendance a
    WHERE a.employee_id = v_employee_id AND a.check_type = 'check_in' AND a.status <> 'voided'
      AND (a.check_time AT TIME ZONE 'Asia/Jakarta')::date = v_today
      AND NOT EXISTS (
        SELECT 1 FROM attendance o
        WHERE o.employee_id = a.employee_id AND o.check_type = 'check_out' AND o.status <> 'voided'
          AND (o.check_time AT TIME ZONE 'Asia/Jakarta')::date = v_today
      )
  ) THEN
    RETURN 'not_clocked_in';
  END IF;

  SELECT * INTO v_geo FROM check_geofence(p_lat, p_lon);
  IF NOT FOUND OR v_geo.within IS NULL THEN
    RETURN 'no_zone';   -- 활성 근무지가 없으면 판정하지 않는다(거짓 이탈 알림 방지)
  END IF;

  -- 어제의 'exit' 로 끝난 상태가 오늘 첫 이탈을 가리지 않도록 오늘 알림만 본다
  SELECT alert_type INTO v_last_type FROM geofence_alerts
    WHERE employee_id = v_employee_id
      AND (created_at AT TIME ZONE 'Asia/Jakarta')::date = v_today
    ORDER BY created_at DESC LIMIT 1;

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

-- ═══════════════════════════════════════════════════════════════════════════
-- S1. attendance_correct — 역할 검사 fail-open 수정
-- ═══════════════════════════════════════════════════════════════════════════
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
  -- `<>` 는 role 클레임이 없을 때 NULL 이 되어 통과한다(검토 S1, 프로덕션 재현). 반드시 IS DISTINCT FROM.
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'attendance_correct: 관리자만 근태 기록을 정정할 수 있습니다';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'attendance_correct: 정정 사유는 필수입니다';
  END IF;
  IF p_new_check_time IS NULL THEN
    RAISE EXCEPTION 'attendance_correct: 정정 시각은 필수입니다';
  END IF;

  SELECT id INTO v_admin_id FROM employees WHERE user_id = auth.uid();

  UPDATE attendance
  SET original_check_time = COALESCE(original_check_time, check_time),
      check_time          = p_new_check_time,
      status               = 'corrected',
      corrected_by         = v_admin_id,
      corrected_at         = now(),
      correction_reason    = p_reason
  WHERE id = p_attendance_id AND status <> 'voided'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'attendance_correct: 대상 근태 기록을 찾을 수 없거나 취소된 기록입니다: %', p_attendance_id;
  END IF;

  RETURN v_row;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- A3. attendance_add_manual — HR 수기 추가 (누락 퇴근 등). 좌표 없음, status='corrected'.
--     수기 퇴근을 넣으면 같은 날 check_in 의 belum_checkout 표시를 normal 로 되돌린다
--     (감사 추적은 수기 행의 corrected_by/correction_reason 에 남는다).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION attendance_add_manual(
  p_employee_id uuid,
  p_check_type  text,
  p_check_time  TIMESTAMPTZ,
  p_reason      text
) RETURNS attendance
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
  v_row      attendance;
  v_day      date;
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'attendance_add_manual: 관리자만 근태 기록을 추가할 수 있습니다';
  END IF;
  IF p_check_type NOT IN ('check_in', 'check_out') THEN
    RAISE EXCEPTION 'attendance_add_manual: check_type 은 check_in / check_out 만 가능합니다';
  END IF;
  IF p_check_time IS NULL THEN
    RAISE EXCEPTION 'attendance_add_manual: 시각은 필수입니다';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'attendance_add_manual: 사유는 필수입니다';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'attendance_add_manual: 직원을 찾을 수 없습니다: %', p_employee_id;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('attendance:' || p_employee_id::text));

  v_day := (p_check_time AT TIME ZONE 'Asia/Jakarta')::date;

  IF EXISTS (
    SELECT 1 FROM attendance
    WHERE employee_id = p_employee_id AND check_type = p_check_type AND status <> 'voided'
      AND (check_time AT TIME ZONE 'Asia/Jakarta')::date = v_day
  ) THEN
    RAISE EXCEPTION '해당 날짜에 이미 % 기록이 있습니다 — 정정(attendance_correct)을 사용하세요',
      CASE WHEN p_check_type = 'check_in' THEN '출근' ELSE '퇴근' END;
  END IF;

  SELECT id INTO v_admin_id FROM employees WHERE user_id = auth.uid();

  INSERT INTO attendance (employee_id, check_type, latitude, longitude, device_id, check_time,
                          status, corrected_by, corrected_at, correction_reason, device_info)
  VALUES (p_employee_id, p_check_type, NULL, NULL, 'manual', p_check_time,
          'corrected', v_admin_id, now(), p_reason, jsonb_build_object('manual', true))
  RETURNING * INTO v_row;

  -- 누락 퇴근을 채웠으면 같은 날 출근의 belum_checkout 표시를 해제
  IF p_check_type = 'check_out' THEN
    UPDATE attendance
    SET status = 'normal'
    WHERE employee_id = p_employee_id AND check_type = 'check_in' AND status = 'belum_checkout'
      AND (check_time AT TIME ZONE 'Asia/Jakarta')::date = v_day;
  END IF;

  RETURN v_row;
END;
$$;

-- attendance_void — 잘못된 기록 취소. 물리 삭제 대신 status='voided' 로 남긴다(감사 추적).
CREATE OR REPLACE FUNCTION attendance_void(
  p_attendance_id uuid,
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
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'attendance_void: 관리자만 근태 기록을 취소할 수 있습니다';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'attendance_void: 취소 사유는 필수입니다';
  END IF;

  SELECT id INTO v_admin_id FROM employees WHERE user_id = auth.uid();

  UPDATE attendance
  SET status            = 'voided',
      corrected_by      = v_admin_id,
      corrected_at      = now(),
      correction_reason = p_reason
  WHERE id = p_attendance_id AND status <> 'voided'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'attendance_void: 대상 근태 기록을 찾을 수 없거나 이미 취소된 기록입니다: %', p_attendance_id;
  END IF;

  RETURN v_row;
END;
$$;

-- belum_checkout 배치도 취소된 기록을 무시하도록 갱신
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
        AND o.status <> 'voided'
        AND (o.check_time AT TIME ZONE 'Asia/Jakarta')::date = (a.check_time AT TIME ZONE 'Asia/Jakarta')::date
    );
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 함수 권한
-- ═══════════════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION attendance_add_manual(uuid, text, timestamptz, text) FROM public, anon;
REVOKE ALL ON FUNCTION attendance_void(uuid, text)                          FROM public, anon;
GRANT EXECUTE ON FUNCTION attendance_add_manual(uuid, text, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION attendance_void(uuid, text)                          TO authenticated;

-- S6. 트리거 전용 SECURITY DEFINER 함수를 REST(/rpc) 로 호출하지 못하게 한다(어드바이저 0028/0029).
--     트리거 실행은 EXECUTE 권한과 무관하므로 auth.users / 역할 동기화 트리거에는 영향 없다.
--     ⚠ 이 두 함수의 EXECUTE 는 anon/authenticated 에 직접 부여된 게 아니라 PUBLIC 기본 권한(ACL `=X/...`)이다.
--       `FROM anon, authenticated` 만 쓰면 아무것도 회수되지 않는다(2026-09-06 프로덕션에서 확인) — PUBLIC 을 함께 회수한다.
REVOKE EXECUTE ON FUNCTION public.handle_new_user()   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_role_to_auth() FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- S4. attendance RLS: 관리자 직접 UPDATE/DELETE 차단 → 읽기만. 쓰기는 위 RPC 로만.
-- ═══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS admin_all ON attendance;
CREATE POLICY admin_read ON attendance FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');

-- ═══════════════════════════════════════════════════════════════════════════
-- B4. 휴가 신청 서버측 검증 — 기간·일수·연차 잔여를 클라이언트가 아닌 DB 가 확인한다
--     (근무일 계산 규칙은 회사마다 달라 서버는 상한/하한만 검증하고 일수 산정은 클라이언트에 둔다)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION leave_requests_validate()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_total int;
  v_used  int;
  v_span  int;
BEGIN
  IF NEW.end_date < NEW.start_date THEN
    RAISE EXCEPTION '종료일이 시작일보다 앞설 수 없습니다';
  END IF;
  v_span := (NEW.end_date - NEW.start_date) + 1;
  IF NEW.days_count IS NULL OR NEW.days_count < 1 OR NEW.days_count > v_span THEN
    RAISE EXCEPTION '휴가 일수(%)가 기간(%일)과 맞지 않습니다', NEW.days_count, v_span;
  END IF;
  -- 신규 신청(pending)일 때만 잔여 연차를 검사한다 (승인/거절 상태 변경은 검사하지 않음)
  IF NEW.leave_type = 'annual' AND NEW.status = 'pending' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'pending') THEN
    SELECT annual_leave_total, annual_leave_used INTO v_total, v_used FROM employees WHERE id = NEW.employee_id;
    IF v_total IS NOT NULL AND NEW.days_count > (v_total - COALESCE(v_used, 0)) THEN
      RAISE EXCEPTION '잔여 연차(%일)를 초과하는 신청입니다', v_total - COALESCE(v_used, 0);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_leave_requests_validate ON leave_requests;
CREATE TRIGGER trg_leave_requests_validate
  BEFORE INSERT OR UPDATE ON leave_requests
  FOR EACH ROW EXECUTE FUNCTION leave_requests_validate();

-- ═══════════════════════════════════════════════════════════════════════════
-- 반영 확인 쿼리 (실행 후 눈으로 확인)
-- ═══════════════════════════════════════════════════════════════════════════
-- SELECT proname, prosecdef FROM pg_proc WHERE proname LIKE 'attendance\_%' ORDER BY 1;
-- SELECT polname, polcmd FROM pg_policy WHERE polrelid = 'public.attendance'::regclass;   -- admin_read(r) staff_read(r) emp_read_own_att(r)
-- SELECT file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'attendance-selfies';
