-- ─────────────────────────────────────────────────────────────────────────────
-- 근태 화면 구성용 임시(데모) 데이터 — 2026-08-01 ~ 2026-09-02
--
--  * 실제 운영 데이터가 아니다. 직원용 PWA 가 붙어 실제 기록이 쌓이기 전까지
--    출퇴근/휴가/근태보고서 3개 화면을 확인하기 위한 임시 데이터다.
--  * 직원 명단·사번(employee_code)은 실제 `staff` 테이블의 Jakarta 인원 12명을
--    NIK 기준으로 가져왔다(나중에 실제 연동 시 NIK 로 매칭됨).
--    반면 부서(department)·연차 사용일수·출퇴근/휴가/초과근무 기록은 전부 임시값이다.
--  * employees.user_id 는 아직 auth.users 와 연결하지 않았다(NULL).
--  * 승인권자: LeaveManagement.vue 가 `position = 'admin'` 인 직원을 승인자로 찾으므로
--    총괄(I GEDE KOMANG SUDIARTA)의 position 을 'admin' 으로 둔다. 화면에는 표시되지 않는다.
--  * 시간대: 모든 check_time 은 자카르타 현지시각(Asia/Jakarta, UTC+7) 기준으로 저장한다.
--  * 재실행 가능(idempotent): 같은 범위의 기존 데모 데이터를 지우고 다시 넣는다.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 1) 직원 12명 (사번 = staff.nik) ────────────────────────────────────────────
INSERT INTO employees (employee_code, name, department, position, annual_leave_total, annual_leave_used, is_active) VALUES
  ('20150001',  'I GEDE KOMANG SUDIARTA', '경영지원', 'admin',              12, 4, true),
  ('20220708',  'ERI SUHENDRI',           '영업부',   'GENERAL MANAGER',    12, 6, true),
  ('20201001',  'HERY',                   '관리부',   'MANAGER',            12, 3, true),
  ('20200703',  'ACHMAD RIZKI FIRDAUS',   '영업부',   'SENIOR SUPERVISOR',  12, 5, true),
  ('20190202',  'ANNA SISKA',             '관리부',   'SENIOR SUPERVISOR',  12, 8, true),
  ('20260103',  'DANY ISMAIL PERDANA',    '영업부',   'SUPERVISOR',         12, 1, true),
  ('20230903',  'HANIF ABDULLOH MAHDI',   '물류부',   'JUNIOR SUPERVISOR',  12, 2, true),
  ('20210302',  'ALYA AISYA ROHAYA',      '관리부',   'TEAM LEADER',        12, 7, true),
  ('20191101',  'MERRY MAHARANI',         '영업부',   'TEAM LEADER',        12, 9, true),
  ('20240801',  'LISA AMALIA',            '관리부',   'STAFF',              12, 2, true),
  ('20240705',  'JULMI ARDIANSYAH',       '영업부',   'STAFF',              12, 0, true),
  ('220180012', 'HARY YANTO',             '물류부',   'SOPIR',              12, 5, true)
ON CONFLICT (employee_code) DO UPDATE SET
  name               = EXCLUDED.name,
  department         = EXCLUDED.department,
  position           = EXCLUDED.position,
  annual_leave_total = EXCLUDED.annual_leave_total,
  annual_leave_used  = EXCLUDED.annual_leave_used,
  is_active          = EXCLUDED.is_active,
  updated_at         = now();

-- 2) 지오펜싱 영역 ───────────────────────────────────────────────────────────
--    본사(PT. ASCENDO INTERNASIONAL)는 이미 등록되어 있어 건드리지 않는다.
--    아래 2곳은 좌표가 임시값이므로 실제 위치로 교체해야 한다.
INSERT INTO geofence_zones (name, description, latitude, longitude, radius_meters, is_active)
SELECT v.name, v.descr, v.lat, v.lon, v.r, true
FROM (VALUES
  ('Gudang Karawang',  '임시 좌표 — 실제 창고 위치로 교체 필요', -6.322700, 107.337600, 150),
  ('Cabang Surabaya',  '임시 좌표 — 실제 지점 위치로 교체 필요', -7.257500, 112.752100, 100)
) AS v(name, descr, lat, lon, r)
WHERE NOT EXISTS (SELECT 1 FROM geofence_zones g WHERE g.name = v.name);

-- 3) 출퇴근 기록 ─────────────────────────────────────────────────────────────
WITH demo AS (
  SELECT id FROM employees WHERE employee_code IN
    ('20150001','20220708','20201001','20200703','20190202','20260103',
     '20230903','20210302','20191101','20240801','20240705','220180012')
)
DELETE FROM attendance
WHERE employee_id IN (SELECT id FROM demo)
  AND check_time >= (DATE '2026-08-01')::timestamp AT TIME ZONE 'Asia/Jakarta'
  AND check_time <  (DATE '2026-09-03')::timestamp AT TIME ZONE 'Asia/Jakarta';

WITH hq AS (
  SELECT id, latitude, longitude
  FROM geofence_zones WHERE name = 'PT. ASCENDO INTERNASIONAL' LIMIT 1
),
emp AS (
  SELECT id, employee_code FROM employees WHERE employee_code IN
    ('20150001','20220708','20201001','20200703','20190202','20260103',
     '20230903','20210302','20191101','20240801','20240705','220180012')
),
days AS (
  -- 평일만. 2026-08-17 은 인도네시아 독립기념일이라 제외.
  SELECT gs::date AS day
  FROM generate_series(DATE '2026-08-01', DATE '2026-09-02', INTERVAL '1 day') gs
  WHERE EXTRACT(ISODOW FROM gs) < 6
    AND gs::date <> DATE '2026-08-17'
),
grid AS (
  SELECT
    e.id AS employee_id,
    d.day,
    -- 결정적 의사난수 (같은 직원·같은 날짜면 항상 같은 값)
    ('x' || substr(md5(e.employee_code || d.day::text || 'a'), 1, 7))::bit(28)::int AS r1,
    ('x' || substr(md5(e.employee_code || d.day::text || 'b'), 1, 7))::bit(28)::int AS r2,
    ('x' || substr(md5(e.employee_code || d.day::text || 'c'), 1, 7))::bit(28)::int AS r3
  FROM emp e CROSS JOIN days d
),
plan AS (
  SELECT
    g.*,
    -- 출근 시각(분): 07:45 기준, 8% 는 지각(+35~65분)
    465 + (g.r1 % 35) + CASE WHEN g.r2 % 100 >= 92 THEN 35 + (g.r3 % 30) ELSE 0 END AS in_min,
    -- 퇴근 시각(분): 17:00 ~ 18:29
    1020 + (g.r2 % 90) AS out_min,
    (g.r3 % 100) < 88  AS inside      -- 12% 는 외근 등 영역 밖
  FROM grid g
  WHERE g.r1 % 100 >= 6               -- 6% 는 결근/휴가 → 기록 없음
),
rows AS (
  -- 출근
  SELECT p.employee_id, 'check_in' AS check_type, p.day, p.in_min AS mins, p.inside, p.r1 AS rr
  FROM plan p
  UNION ALL
  -- 퇴근 (오늘(2026-09-02)은 아직 진행 중이라 일부만, 그 외 날은 4% 미체크)
  SELECT p.employee_id, 'check_out', p.day, p.out_min, p.inside, p.r2
  FROM plan p
  WHERE CASE WHEN p.day = DATE '2026-09-02' THEN p.r2 % 100 < 25 ELSE p.r3 % 100 >= 4 END
)
INSERT INTO attendance (employee_id, check_type, latitude, longitude, geofence_zone_id, is_within_geofence, distance_meters, device_info, check_time)
SELECT
  r.employee_id,
  r.check_type,
  hq.latitude  + CASE WHEN r.inside THEN (r.rr % 21 - 10) * 0.000018 ELSE (r.rr % 61 - 30) * 0.00035 END,
  hq.longitude + CASE WHEN r.inside THEN (r.rr % 17 -  8) * 0.000018 ELSE (r.rr % 53 - 26) * 0.00035 END,
  hq.id,
  r.inside,
  CASE WHEN r.inside THEN 3 + (r.rr % 25) ELSE 260 + (r.rr % 40) * 115 END,
  jsonb_build_object('source', 'seed', 'platform', CASE WHEN r.rr % 3 = 0 THEN 'iOS' ELSE 'Android' END),
  (r.day + make_interval(mins => r.mins)) AT TIME ZONE 'Asia/Jakarta'
FROM rows r CROSS JOIN hq;

-- 4) 휴가·연차 신청 ──────────────────────────────────────────────────────────
DELETE FROM leave_requests
WHERE start_date BETWEEN DATE '2026-08-01' AND DATE '2026-09-30';

INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days_count, reason, status, approved_by, approved_at, created_at)
SELECT e.id, v.ltype, v.sd, v.ed, v.dc, v.reason, v.status,
       CASE WHEN v.status IN ('approved','rejected') THEN a.id END,
       CASE WHEN v.status IN ('approved','rejected') THEN (v.sd - 3) + TIME '10:20' END,
       (v.sd - v.lead) + TIME '09:10'
FROM (VALUES
  ('20191101',  'annual',   DATE '2026-08-05', DATE '2026-08-07', 3.0, '가족 행사 참석',            'approved',  7),
  ('20190202',  'annual',   DATE '2026-08-10', DATE '2026-08-14', 5.0, '연차 소진 (장기 휴가)',      'approved', 14),
  ('220180012', 'sick',     DATE '2026-08-11', DATE '2026-08-11', 1.0, '몸살 — 병원 진료',           'approved',  1),
  ('20210302',  'annual',   DATE '2026-08-18', DATE '2026-08-18', 1.0, '독립기념일 연휴 연장',        'approved',  6),
  ('20240801',  'personal', DATE '2026-08-19', DATE '2026-08-20', 2.0, '개인 사유',                  'rejected',  5),
  ('20200703',  'annual',   DATE '2026-08-24', DATE '2026-08-26', 3.0, '휴식',                      'approved',  9),
  ('20230903',  'sick',     DATE '2026-08-27', DATE '2026-08-28', 2.0, '치과 시술 및 회복',           'approved',  4),
  ('20220708',  'annual',   DATE '2026-09-07', DATE '2026-09-11', 5.0, '본사 출장 후 휴가',           'pending',   8),
  ('20260103',  'personal', DATE '2026-09-08', DATE '2026-09-08', 1.0, '자녀 학교 행사',             'pending',   6),
  ('20240705',  'annual',   DATE '2026-09-14', DATE '2026-09-15', 2.0, '지방 방문',                  'pending',  10),
  ('20201001',  'other',    DATE '2026-09-21', DATE '2026-09-22', 2.0, '자격 시험 응시',             'pending',   4)
) AS v(code, ltype, sd, ed, dc, reason, status, lead)
JOIN employees e ON e.employee_code = v.code
CROSS JOIN (SELECT id FROM employees WHERE employee_code = '20150001') a;

-- 5) 초과근무 신청 ───────────────────────────────────────────────────────────
DELETE FROM overtime
WHERE overtime_date BETWEEN DATE '2026-08-01' AND DATE '2026-09-30';

INSERT INTO overtime (employee_id, overtime_date, start_time, end_time, hours, reason, status, approved_by, approved_at, created_at)
SELECT e.id, v.od, v.st, v.et, v.hrs, v.reason, v.status,
       CASE WHEN v.status IN ('approved','rejected') THEN a.id END,
       CASE WHEN v.status IN ('approved','rejected') THEN (v.od + 1) + TIME '09:40' END,
       v.od + TIME '17:30'
FROM (VALUES
  ('20230903',  DATE '2026-08-04', TIME '18:00', TIME '21:00', 3.0, '컨테이너 입고 검수',        'approved'),
  ('220180012', DATE '2026-08-06', TIME '18:30', TIME '22:00', 3.5, '거래처 긴급 배송',          'approved'),
  ('20240705',  DATE '2026-08-12', TIME '18:00', TIME '20:30', 2.5, '월간 견적 마감 작업',        'approved'),
  ('20190202',  DATE '2026-08-13', TIME '18:00', TIME '21:30', 3.5, '7월 마감 결산',             'approved'),
  ('20200703',  DATE '2026-08-20', TIME '18:00', TIME '20:00', 2.0, '입찰 제안서 작성',           'rejected'),
  ('20240801',  DATE '2026-08-25', TIME '18:00', TIME '21:00', 3.0, '재고 실사',                 'approved'),
  ('20230903',  DATE '2026-08-28', TIME '18:30', TIME '22:30', 4.0, '창고 재배치 작업',           'approved'),
  ('20260103',  DATE '2026-09-01', TIME '18:00', TIME '20:30', 2.5, '신규 거래처 자료 준비',       'pending'),
  ('20240705',  DATE '2026-09-02', TIME '18:00', TIME '21:00', 3.0, '9월 판매 계획 수립',         'pending'),
  ('20210302',  DATE '2026-09-02', TIME '18:00', TIME '20:00', 2.0, '급여 자료 정리',             'pending')
) AS v(code, od, st, et, hrs, reason, status)
JOIN employees e ON e.employee_code = v.code
CROSS JOIN (SELECT id FROM employees WHERE employee_code = '20150001') a;

COMMIT;
