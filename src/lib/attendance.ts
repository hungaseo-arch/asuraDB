import { supabase, sbGet, sbGetAll, sbPost, sbPatch, sbRpc } from './supabase';

// ── 타입 정의 ──
export interface Employee {
  id: string;
  user_id: string;
  name: string;
  employee_code: string;
  department: string;
  position: string;
  phone: string;
  annual_leave_total: number;
  annual_leave_used: number;
  is_active: boolean;
}

export interface GeofenceZone {
  id: string;
  name: string;
  description: string;
  latitude: number;
  longitude: number;
  radius_meters: number;
  is_active: boolean;
}

// attendance.status — 서버 CHECK 제약과 동일 (attendance_antifraud_phase2_1.sql)
export type AttendanceStatus = 'normal' | 'belum_checkout' | 'corrected' | 'voided';

export interface AttendanceRecord {
  id: string;
  employee_id: string;
  employee?: Pick<Employee, 'name' | 'department' | 'position'> | null;
  check_type: 'check_in' | 'check_out';
  latitude: number | null;   // HR 수기 추가(device_id='manual') 행은 좌표가 없다
  longitude: number | null;
  geofence_zone_id: string | null;
  geofence_zone?: Pick<GeofenceZone, 'name'> | null;
  is_within_geofence: boolean;
  distance_meters: number | null;
  device_info: any;
  check_time: string;
  // ── 대리출석 방지(Phase 1~2.1) 컬럼 ──
  selfie_url: string | null;          // private 버킷 attendance-selfies 의 객체 경로(URL 아님) — signed URL 로 열람
  device_id: string | null;           // 'manual' = HR 수기 추가
  status: AttendanceStatus;
  corrected_by: string | null;        // employees.id
  corrected_at: string | null;
  correction_reason: string | null;
  original_check_time: string | null; // 최초 정정 전 시각(한 번만 보존)
  corrector?: Pick<Employee, 'name'> | null;
}

export interface EmployeeDevice {
  id: string;
  employee_id: string;
  device_id: string;
  device_label: string | null;
  is_active: boolean;          // false = 승인 대기(또는 폐기)
  registered_at: string | null;
  last_seen_at: string | null;
  employee?: Pick<Employee, 'name' | 'department'> | null;
}

export interface GeofenceAlert {
  id: string;
  employee_id: string;
  geofence_zone_id: string | null;
  latitude: number;
  longitude: number;
  distance_meters: number | null;
  alert_type: 'exit' | 'reenter';
  acknowledged: boolean;
  acknowledged_by: string | null;
  acknowledged_at: string | null;
  created_at: string;
  employee?: Pick<Employee, 'name' | 'department'> | null;
  geofence_zone?: Pick<GeofenceZone, 'name'> | null;
}

export interface LeaveRequest {
  id: string;
  employee_id: string;
  employee?: Employee;
  leave_type: 'annual' | 'sick' | 'personal' | 'other';
  start_date: string;
  end_date: string;
  days_count: number;
  reason: string;
  status: 'pending' | 'approved' | 'rejected' | 'cancelled';
  approved_by: string | null;
  approver?: Employee;
  approved_at: string | null;
  created_at: string;
}

export interface OvertimeRecord {
  id: string;
  employee_id: string;
  employee?: Employee;
  overtime_date: string;
  start_time: string;
  end_time: string;
  hours: number;
  reason: string;
  status: 'pending' | 'approved' | 'rejected' | 'cancelled';
  approved_by: string | null;
  approver?: Employee;
  approved_at: string | null;
}

// ── Asia/Jakarta 날짜·시각 helper ──
// 서버(RPC·배치)는 모두 (check_time AT TIME ZONE 'Asia/Jakarta')::date 로 하루를 자른다.
// 관리자 브라우저가 한국(UTC+9)이어도 같은 하루를 보도록 화면도 자카르타 기준으로 맞춘다.
const JAKARTA_TZ = 'Asia/Jakarta';

/** 자카르타 기준 'YYYY-MM-DD' */
export function jakartaDate(d: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: JAKARTA_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d);
}

/** 자카르타 하루의 [from, to] ISO 경계. PostgREST 쿼리에 넣을 때는 반드시 encodeURIComponent (+ → %2B). */
export function jakartaDayRange(date: string): { from: string; to: string } {
  return { from: `${date}T00:00:00+07:00`, to: `${date}T23:59:59.999+07:00` };
}

/** HH:mm (자카르타 벽시계) */
export function formatJakartaTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('ko-KR', { timeZone: JAKARTA_TZ, hour: '2-digit', minute: '2-digit' });
}

/** YYYY. MM. DD. HH:mm (자카르타 벽시계) */
export function formatJakartaDateTime(iso: string): string {
  return new Date(iso).toLocaleString('ko-KR', {
    timeZone: JAKARTA_TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  });
}

/** ISO → <input type="datetime-local"> 값('YYYY-MM-DDTHH:mm', 자카르타 벽시계) */
export function toJakartaLocalInput(iso: string | Date): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: JAKARTA_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(iso));
  const get = (t: string) => parts.find(p => p.type === t)?.value ?? '00';
  return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}`;
}

/** datetime-local 값('YYYY-MM-DDTHH:mm')을 자카르타 시각으로 해석한 ISO 문자열 */
export function fromJakartaLocalInput(value: string): string {
  return `${value}:00+07:00`;
}

// ── 직원 ──
export async function fetchEmployees(): Promise<Employee[]> {
  return sbGetAll<Employee>('employees?select=*&is_active=eq.true&order=name');
}

export async function fetchEmployeeByUserId(userId: string): Promise<Employee | null> {
  const data = await sbGet<Employee[]>(`employees?select=*&user_id=eq.${userId}&limit=1`);
  return data[0] ?? null;
}

// ── 지오펜싱 영역 ──
export async function fetchGeofenceZones(): Promise<GeofenceZone[]> {
  return sbGetAll<GeofenceZone>('geofence_zones?select=*&is_active=eq.true&order=name');
}

export async function createGeofenceZone(zone: Partial<GeofenceZone>): Promise<GeofenceZone> {
  return sbPost<GeofenceZone>('geofence_zones', zone);
}

export async function updateGeofenceZone(id: string, zone: Partial<GeofenceZone>): Promise<void> {
  await sbPatch(`geofence_zones?id=eq.${id}`, zone);
}

export async function deleteGeofenceZone(id: string): Promise<void> {
  await sbPatch(`geofence_zones?id=eq.${id}`, { is_active: false });
}

// ── 출퇴근 기록 (관리자는 REST 로 읽기만 가능 — 쓰기는 아래 RPC 3종) ──
// attendance 는 employees 로 가는 FK 가 둘(employee_id, corrected_by)이라 embed 에 FK 힌트가 필수다.
const ATTENDANCE_SELECT =
  'select=*,employee:employees!attendance_employee_id_fkey(name,department,position),' +
  'geofence_zone:geofence_zones(name),corrector:employees!attendance_corrected_by_fkey(name)';

function checkTimeRange(from: string, to: string): string {
  return `check_time=gte.${encodeURIComponent(from)}&check_time=lte.${encodeURIComponent(to)}`;
}

export async function fetchTodayAttendance(): Promise<AttendanceRecord[]> {
  return fetchAttendanceByDate(jakartaDate());
}

/** @param date 'YYYY-MM-DD' (자카르타 기준 하루) */
export async function fetchAttendanceByDate(date: string): Promise<AttendanceRecord[]> {
  const { from, to } = jakartaDayRange(date);
  return sbGetAll<AttendanceRecord>(
    `attendance?${ATTENDANCE_SELECT}&${checkTimeRange(from, to)}&order=check_time.desc`
  );
}

/** @param from,to 'YYYY-MM-DD' (자카르타 기준, 양끝 포함) */
export async function fetchEmployeeAttendance(employeeId: string, from: string, to: string): Promise<AttendanceRecord[]> {
  const range = checkTimeRange(jakartaDayRange(from).from, jakartaDayRange(to).to);
  return sbGetAll<AttendanceRecord>(
    `attendance?${ATTENDANCE_SELECT}&employee_id=eq.${employeeId}&${range}&order=check_time.desc`
  );
}

// ── HR 보정 RPC (SECURITY DEFINER, super_admin 전용 — 실패 시 서버의 한국어 메시지가 Error.message 로 온다) ──
export async function correctAttendance(id: string, newCheckTimeIso: string, reason: string): Promise<AttendanceRecord> {
  return sbRpc<AttendanceRecord>('attendance_correct', {
    p_attendance_id: id, p_new_check_time: newCheckTimeIso, p_reason: reason,
  });
}

export async function addManualAttendance(
  employeeId: string, checkType: 'check_in' | 'check_out', checkTimeIso: string, reason: string,
): Promise<AttendanceRecord> {
  return sbRpc<AttendanceRecord>('attendance_add_manual', {
    p_employee_id: employeeId, p_check_type: checkType, p_check_time: checkTimeIso, p_reason: reason,
  });
}

export async function voidAttendance(id: string, reason: string): Promise<AttendanceRecord> {
  return sbRpc<AttendanceRecord>('attendance_void', { p_attendance_id: id, p_reason: reason });
}

// ── 셀피 (private 버킷 → 60초 signed URL) ──
export async function getSelfieSignedUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage.from('attendance-selfies').createSignedUrl(path, 60);
  if (error) throw new Error(error.message);
  if (!data?.signedUrl) throw new Error('셀피 URL 을 발급받지 못했습니다');
  return data.signedUrl;
}

// ── 기기 승인 (employee_devices — super_admin 은 admin_all 정책으로 PATCH 가능) ──
export async function fetchEmployeeDevices(): Promise<EmployeeDevice[]> {
  return sbGetAll<EmployeeDevice>(
    'employee_devices?select=*,employee:employees(name,department)&order=registered_at.desc'
  );
}

export async function approveDevice(id: string): Promise<void> {
  await sbPatch(`employee_devices?id=eq.${id}`, { is_active: true });
}

export async function revokeDevice(id: string): Promise<void> {
  await sbPatch(`employee_devices?id=eq.${id}`, { is_active: false });
}

// ── 지오펜스 이탈 알림 ──
// geofence_alerts 도 employees FK 가 둘(employee_id, acknowledged_by) — 힌트 필수.
/** @param date 'YYYY-MM-DD' (자카르타 기준 하루, created_at 기준) */
export async function fetchGeofenceAlerts(date: string): Promise<GeofenceAlert[]> {
  const { from, to } = jakartaDayRange(date);
  return sbGetAll<GeofenceAlert>(
    'geofence_alerts?select=*,employee:employees!geofence_alerts_employee_id_fkey(name,department),geofence_zone:geofence_zones(name)' +
    `&created_at=gte.${encodeURIComponent(from)}&created_at=lte.${encodeURIComponent(to)}&order=created_at.desc`
  );
}

export async function acknowledgeAlert(id: string, adminEmployeeId: string | null): Promise<void> {
  await sbPatch(`geofence_alerts?id=eq.${id}`, {
    acknowledged: true,
    acknowledged_by: adminEmployeeId,
    acknowledged_at: new Date().toISOString(),
  });
}

// ── 휴가/연차 ──
export async function fetchLeaveRequests(status?: string): Promise<LeaveRequest[]> {
  let path = 'leave_requests?select=*,employee:employees!leave_requests_employee_id_fkey(name,department),approver:employees!leave_requests_approved_by_fkey(name)&order=created_at.desc';
  if (status) path += `&status=eq.${status}`;
  return sbGetAll<LeaveRequest>(path);
}

export async function createLeaveRequest(req: Partial<LeaveRequest>): Promise<LeaveRequest> {
  return sbPost<LeaveRequest>('leave_requests', req);
}

export async function updateLeaveStatus(id: string, status: string, approverId: string): Promise<void> {
  await sbPatch(`leave_requests?id=eq.${id}`, {
    status,
    approved_by: approverId,
    approved_at: new Date().toISOString(),
  });
}

// ── 초과근무 ──
export async function fetchOvertimeRecords(status?: string): Promise<OvertimeRecord[]> {
  let path = 'overtime?select=*,employee:employees!overtime_employee_id_fkey(name,department),approver:employees!overtime_approved_by_fkey(name)&order=created_at.desc';
  if (status) path += `&status=eq.${status}`;
  return sbGetAll<OvertimeRecord>(path);
}

export async function createOvertimeRequest(req: Partial<OvertimeRecord>): Promise<OvertimeRecord> {
  return sbPost<OvertimeRecord>('overtime', req);
}

export async function updateOvertimeStatus(id: string, status: string, approverId: string): Promise<void> {
  await sbPatch(`overtime?id=eq.${id}`, {
    status,
    approved_by: approverId,
    approved_at: new Date().toISOString(),
  });
}
