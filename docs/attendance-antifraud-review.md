# 근태 대리출석 방지 모듈 — 코드 전체 검토 및 개선안 (2026-09-06)

검토 범위: `supabase/migrations/001_create_attendance_schema.sql` · `002_attendance_geofence_trigger.sql` ·
`attendance_antifraud_phase1.sql` · `attendance_antifraud_phase2.sql` · `supabase/functions/attendance-selfie-cleanup/` ·
`employee-pwa/src/**` · `src/lib/attendance.ts` · `src/views/Attendance.vue` · `src/views/AttendanceReport.vue` · `docs/근태관리기능.md`.
DB 사실관계는 프로덕션(`subatvlyfglztdmyexfl`)을 읽기 전용으로 조회해 확인했다.

현재 상태 요약: attendance 522건(그중 `belum_checkout` 20건), employee_devices 0건, geofence_alerts 0건,
auth 연결 직원 2/14명, 활성 존 4곳(Semarang 100m · Surabaya 100m · Karawang 150m · ASCENDO 150m, HOME 비활성),
pg_cron 2건(`attendance-flag-missing-checkout`·`attendance-selfie-cleanup`) 2026-09-05 정상 실행.
**미커밋 작업 중 상태**: `employee-pwa/src/lib/attendance.ts` 는 RPC 시그니처로 바뀌었으나
`employee-pwa/src/views/CheckIn.vue` 는 옛 시그니처(`checkIn(employee.id, lat, lon)`)를 그대로 호출해 **현재 PWA 는 빌드가 깨진 상태**다(Phase 3 완료 전까지).

우선순위: **S = 보안/데이터 무결성(즉시)** · **A = 기능 오류(Phase 3 전 수정)** · **B = 품질/UX** · **C = 문서**

---

## S. 보안 · 무결성 (즉시 수정 권고 → Phase 2.1 SQL)

### S1. `attendance_correct` 역할 검사가 NULL 에 대해 열려 있음 — **프로덕션에서 재현 확인**
- `IF (auth.jwt()->'app_metadata'->>'role') <> 'super_admin'` 은 role 클레임이 **없으면** NULL 비교가 되어 조건이 false → 예외 없이 통과한다.
- 프로브(트랜잭션 롤백)로 확인: `app_metadata` 가 빈 사용자가 호출하자 `status=corrected` 로 **정정이 성공**했다.
- 근태관리기능.md §9 체크리스트가 "새 직원 계정에 role 을 명시"하라고 하는 만큼, 누락된 계정이 하나라도 생기면 그 직원이 **모든 직원의 근태 시각을 임의 변경**할 수 있다.
- **수정**: `IF (auth.jwt()->'app_metadata'->>'role') IS DISTINCT FROM 'super_admin' THEN RAISE ...`.
  같은 패턴을 쓰는 다른 RPC 는 없음(확인).

### S2. 셀피 경로를 검증하지 않음 — 셀피 필수 요건이 문자열 하나로 우회됨
- `attendance_check_in/out` 은 `p_selfie_path` 가 **비어 있지 않은지만** 본다. `"x"` 를 보내도 통과한다.
- **수정**: RPC 안에서 `p_selfie_path LIKE v_employee_id::text || '/%'` 이고
  `EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='attendance-selfies' AND name=p_selfie_path AND created_at > now()-interval '10 minutes')` 을 요구(SECURITY DEFINER 라 조회 가능). 재사용 방지로 같은 경로가 이미 attendance.selfie_url 에 있으면 거부.
- 버킷 자체에도 `file_size_limit`(예 2MB)·`allowed_mime_types`(`image/jpeg`) 를 설정해 임의 파일 적재를 막는다.

### S3. 출퇴근 중복 생성 경쟁(더블탭·재시도)
- 중복 검사가 `EXISTS → INSERT` 두 단계라 동시 호출 2건이 모두 통과할 수 있다. Jakarta 일자 기준 유니크 인덱스는 `AT TIME ZONE` 이 IMMUTABLE 이 아니라 만들 수 없다.
- **수정**: 두 RPC 첫 줄에 `PERFORM pg_advisory_xact_lock(hashtext(v_employee_id::text));` 를 넣어 직원 단위로 직렬화.

### S4. 관리자가 RPC 를 거치지 않고 attendance 를 직접 UPDATE/DELETE 할 수 있음
- `admin_all` 정책(ALL) 때문에 super_admin 은 PostgREST PATCH 로 `check_time` 을 바꿔도 `original_check_time`·`corrected_by`·`correction_reason` 이 남지 않는다(감사 추적 구멍).
- **수정**: attendance 의 `admin_all` 을 SELECT 전용으로 좁히고, 수정은 `attendance_correct` 만 허용. 삭제가 필요하면 별도 `attendance_void(p_id, p_reason)` RPC 로 `status='voided'` 처리(물리 삭제 금지).

### S5. `attendance_register_device` — OUT 컬럼명 충돌 (**높은 확률의 런타임 오류, 미검증**)
- `RETURNS TABLE(status text, is_active boolean)` 의 `is_active` 는 plpgsql 변수이므로 본문의
  `WHERE employee_id = v_employee_id AND is_active = true` 가 `column reference "is_active" is ambiguous` 로 실패할 수 있다(기본 `plpgsql.variable_conflict = error`). 이 경로는 **모든 직원의 첫 기기 등록**이라 Phase 3 첫 실사용에서 바로 터진다.
- 프로브 실행이 분류기에 막혀 실측하지 못했다. **수정**: OUT 컬럼을 `o_status`·`o_is_active` 로 바꾸거나 `employee_devices.is_active = true` 로 한정. 프론트(`registerDevice`)의 반환 타입도 함께 변경.

### S6. Supabase 보안 어드바이저 (근태 외 항목 포함, 참고)
- `handle_new_user()`·`sync_role_to_auth()` 가 **anon 에도 EXECUTE** 된 SECURITY DEFINER 함수 → `REVOKE EXECUTE ... FROM anon, authenticated` (트리거 전용).
- SECURITY DEFINER 뷰 6건(`v_dot_lookup`·`products_sell`·`v_weekly_highlights` 등) ERROR 등급, `search_path` 미설정 함수 11건 WARN. 근태 5종 RPC 는 `SET search_path = public` 이 있어 해당 없음.

---

## A. 기능 오류 (Phase 3 에서 함께 수정)

### A1. "오늘" 기준이 서버(Asia/Jakarta)와 프론트(UTC)로 갈라짐
- 서버 RPC·cron 은 `(check_time AT TIME ZONE 'Asia/Jakarta')::date`. 프론트는 모두 `toISOString().slice(0,10)`(UTC):
  PWA `fetchTodayStatus`(attendance.ts:98) · History 월/일 그룹(History.vue:12,33) · 대시보드 `fetchTodayAttendance`/`fetchAttendanceByDate`(src/lib/attendance.ts:102,108).
- 결과: Jakarta 00:00~07:00 사이엔 어제가 "오늘"로 보여 출근 버튼이 잠기거나, 06:30 출근이 History 에서 전날로 묶인다.
- **수정**: 공용 `jakartaDate(d)`/`jakartaDayRange(date)` 헬퍼(`Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Jakarta'})`)를 두 앱에 추가하고 쿼리 경계를 `+07:00` 오프셋으로 보낸다. 더 단순하게는 `attendance_today_status()` RPC 를 추가해 "오늘" 판정을 서버로 일원화.

### A2. 지오펜스 이탈 판정이 날짜에 묶이지 않음
- `attendance_report_geofence_exit` 의 마지막 알림 조회가 `employee_id` 만으로 최신 1건을 본다. 어제 퇴근 전 'exit' 로 끝났으면 오늘 첫 이탈이 "이미 exit 상태"로 묻힌다.
- **수정**: 조회에 `AND (created_at AT TIME ZONE 'Asia/Jakarta')::date = 오늘` 추가. 존이 하나도 없을 때 `v_geo.within` 이 NULL 이면 exit 로 기록되는 것도 `COALESCE(v_geo.within,true)` 로 방어.

### A3. `belum_checkout` 이 영구 상태
- cron 이 `status='belum_checkout'` 을 찍은 뒤 다음날 HR 이 퇴근을 보정해도 되돌릴 경로가 없다(이미 20건). `attendance_correct` 는 **기존 행만** 수정하고 **누락 퇴근을 추가**하지 못한다(요건 7 미충족).
- **수정**: `attendance_add_manual(p_employee_id, p_check_type, p_check_time, p_reason)` RPC(super_admin, `status='corrected'`, `device_id='manual'`) 추가 + 수기 퇴근 추가 시 같은 날 check_in 의 `belum_checkout` 을 `normal` 로 해제.

### A4. 기기 잠금 시 자활 불가 · 관리 UI 부재
- 기기를 전부 비활성화하면 직원이 새 기기를 등록해도 영원히 pending. `employee_devices` 를 다룰 화면이 대시보드에 없다(현재 0건이라 아직 표면화 안 됨).
- **수정(Phase 3 범위)**: `Attendance.vue` 에 "기기 승인" 섹션(pending 목록 → 승인/폐기, `isSuperAdmin` 게이트), 활성 기기 0대면 다음 등록을 자동 승인하는 규칙은 이미 있으므로 "폐기 = is_active=false" 만 하면 재등록 시 자동 승인됨을 문서화.

### A5. PWA 화면이 실제로 스타일되지 않음
- `employee-pwa/package.json` 에 tailwind·postcss 가 없고 CSS import 도 없는데 모든 뷰가 Tailwind 클래스로 작성돼 있다 → 배포본은 **무스타일**로 렌더된다(기존 결함, Phase 이전부터).
- **수정**: `@tailwindcss/vite` 추가 + `src/style.css` 에 `@import "tailwindcss"` 와 메인 앱과 같은 라이트 토큰. 최소 대안은 scoped CSS 로 3개 뷰를 다시 쓰는 것.

### A6. 대시보드 `src/lib/attendance.ts` 잔존 코드
- `checkIn`/`checkOut`(120~139행, 직접 insert → Phase 2 이후 42501 로 항상 실패)·`checkGeofenceRpc`(179행) 는 호출처가 없다 → 삭제.
- `AttendanceRecord` 타입에 `status`·`selfie_url`·`device_id`·`corrected_by/at`·`correction_reason`·`original_check_time` 이 없어 화면이 새 컬럼을 표시할 수 없다.

---

## B. 품질 · UX

- **B1 오류 삼킴**: PWA `History.vue`·`LeaveRequest.vue` 의 `catch { /* ignore */ }`, `fetch` 뒤 `res.ok` 미확인(`fetchEmployee` 등은 오류 JSON 을 데이터로 취급). `sbRpc` 처럼 실패를 던지고 화면에 배너로 보여줄 것.
- **B2 중복 조회**: `fetchMyAttendance`·`fetchMyLeaveRequests` 가 매번 `employees` 를 다시 찾는다. 로그인 시 employee 를 한 번 받아 store(`ref`)에 두고 재사용.
- **B3 라우트 가드 없음**: `/#/history`·`/#/leave` 는 세션 없이도 진입해 빈 화면이 된다. `router.beforeEach` 에서 세션 확인 후 `/` 로.
- **B4 휴가 일수**: `days_count` 가 달력일 계산이라 주말이 포함되고, 잔여 연차 검증이 클라이언트에만 있다. 서버 트리거(또는 `leave_request_create` RPC)에서 근무일 계산·잔여 검증.
- **B5 이벤트 리스너 누수**: `Attendance.vue:98` 의 `asura:refresh` 리스너를 `onUnmounted` 에서 제거.
- **B6 관리 화면 표시 누락**: 오늘 현황·일별 보고서(`AttendanceReport.vue`)·CSV 에 `status`(belum_checkout/corrected)·보정 사유·기기 라벨·셀피(서명 URL 60초) 를 노출. `geofence_alerts` 는 어디에도 표시되지 않고 `acknowledged` 도 쓰이지 않는다 → "이탈 알림" 카드 + 확인 처리.
- **B7 반경 표준화 미완**: Phase 1 D1 배경대로라면 존 반경이 통일돼야 하는데 Semarang·Surabaya 100m / Karawang·ASCENDO 150m 로 섞여 있다. 기준값을 정해 `geofence_zones.radius_meters` 를 맞추거나, 의도된 차이면 문서에 근거를 남긴다.
- **B8 Edge Function**: `storage.remove()` 는 없는 파일에도 오류를 내지 않아 `deleted` 카운트가 과대 계산될 수 있다. 반환 배열 길이로 세고, 삭제 후 `attendance.selfie_url` 을 NULL 로 갱신해 UI 가 깨진 링크를 만들지 않게 한다.
- **B9 device.ts**: `crypto.randomUUID()` 는 HTTPS 전용(개발 http 에서 예외). `getDeviceLabel` 은 iPadOS Safari 를 'Mac' 으로 인식하므로 `navigator.maxTouchPoints` 보강.

---

## C. 문서

- `docs/근태관리기능.md` §3(PWA 흐름)·§4(지오펜싱)·§5(RLS) 가 Phase 1/2 를 반영하지 않는다: 기기 승인, 셀피 필수·90일 보관, 5종 RPC, 직접 insert 차단, `geofence_alerts`, `status` 값, cron 2건. Phase 3 완료 시 함께 갱신.
- 개발 가이드 §11 보안 절에 "SECURITY DEFINER RPC 는 반드시 `IS DISTINCT FROM` 으로 역할 검사" 규칙을 추가.

---

## 제안 실행 순서

1. **Phase 2.1 SQL**(사용자가 SQL Editor 에서 실행): S1 · S2 · S3 · S5 · A2 · A3(수기 추가 RPC) · S4(admin_all 축소) · S6(anon REVOKE 2건).
2. **Phase 3 프론트**: CheckIn.vue RPC 전환 + 카메라 셀피 + 주기적 이탈 보고, Tailwind 배선(A5), 날짜 헬퍼(A1), 대시보드 기기 승인·HR 보정·알림 UI(A4·B6), 잔존 코드 정리(A6), B1~B5·B9.
3. **문서**: C 항목, 변경이력.
