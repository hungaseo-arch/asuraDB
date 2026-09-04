-- 출퇴근 기록 저장 시 지오펜싱 판정을 서버에서 채운다.
--
-- 배경: PWA 의 checkIn()/checkOut() 은 employee_id·check_type·좌표만 POST 한다.
--       geofence_zone_id / is_within_geofence / distance_meters 를 채우는 곳이 어디에도 없어
--       (클라이언트도, 트리거도 없음) 모든 실제 출퇴근이 컬럼 기본값대로
--       is_within_geofence = false, distance_meters = NULL 로 저장됐다.
--       즉 근무지 안에서 찍어도 항상 "영역 밖" 이었고 check_geofence() 는 호출되지 않는 죽은 코드였다.
--
-- 판정을 클라이언트가 보내게 하지 않고 서버에서 계산하는 이유: 클라이언트가 보내는 값은
-- 위조할 수 있다(is_within_geofence: true 를 그냥 넣으면 그만). 좌표만 받고 판정은 DB 가 한다.

CREATE OR REPLACE FUNCTION attendance_apply_geofence()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  g RECORD;
BEGIN
  SELECT * INTO g FROM check_geofence(NEW.latitude, NEW.longitude);

  IF FOUND THEN
    NEW.geofence_zone_id    := CASE WHEN g.within THEN g.zone_id ELSE NULL END;
    NEW.is_within_geofence  := g.within;
    NEW.distance_meters     := g.distance;   -- 영역 밖이어도 가장 가까운 근무지까지의 거리를 남긴다
  ELSE
    -- 활성 근무지가 하나도 없으면 판정 불가
    NEW.geofence_zone_id    := NULL;
    NEW.is_within_geofence  := false;
    NEW.distance_meters     := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_attendance_geofence ON attendance;
CREATE TRIGGER trg_attendance_geofence
  BEFORE INSERT ON attendance
  FOR EACH ROW EXECUTE FUNCTION attendance_apply_geofence();
