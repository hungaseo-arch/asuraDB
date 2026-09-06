import { supabase, sbHeaders, sbRpc } from './supabase';
import { jakartaDate, jakartaDayRange } from './date';

const SB_URL = import.meta.env.VITE_SB_URL as string;
const SELFIE_BUCKET = 'attendance-selfies';

export interface Employee {
  id: string;
  user_id: string;
  name: string;
  employee_code: string;
  department: string;
  position: string;
  annual_leave_total: number;
  annual_leave_used: number;
}

export type AttendanceStatus = 'normal' | 'belum_checkout' | 'corrected' | 'voided';

export interface AttendanceRecord {
  id: string;
  check_type: 'check_in' | 'check_out';
  check_time: string;
  is_within_geofence: boolean;
  distance_meters: number | null;
  status: AttendanceStatus;
  device_id: string | null;
  correction_reason: string | null;
  original_check_time: string | null;
  geofence_zone?: { name: string } | null;
}

export interface LeaveRequest {
  id: string;
  leave_type: string;
  start_date: string;
  end_date: string;
  days_count: number;
  reason: string | null;
  status: 'pending' | 'approved' | 'rejected' | 'cancelled';
  created_at: string;
}

// ── 공통 fetch — PostgREST 오류(RLS 거부·트리거 예외 등)를 삼키지 않고 메시지로 던진다 ──
async function sbFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    ...init,
    headers: { ...(await sbHeaders()), ...(init.headers as Record<string, string> | undefined) },
  });
  if (!res.ok) {
    let message = `요청 실패 (${res.status})`;
    try {
      const body = await res.json();
      if (body?.message) message = body.message;
    } catch { /* 본문이 JSON 이 아니면 기본 메시지 */ }
    throw new Error(message);
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

// ── 직원 정보 (세션당 1회 조회 후 캐시) ──
let employeeCache: { userId: string; employee: Employee | null } | null = null;

export async function fetchEmployee(force = false): Promise<Employee | null> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) { employeeCache = null; return null; }
  if (!force && employeeCache && employeeCache.userId === user.id) return employeeCache.employee;
  const rows = await sbFetch<Employee[]>(`employees?select=*&user_id=eq.${user.id}&limit=1`);
  const employee = rows[0] ?? null;
  employeeCache = { userId: user.id, employee };
  return employee;
}

export function clearEmployeeCache() { employeeCache = null; }

// ── 기기 등록/검증 ──
// attendance_antifraud_phase2_1.sql 의 attendance_register_device RPC(반환 컬럼 o_status/o_is_active).
// 최초 1대는 자동 승인, 이후 새 device_id 는 승인 대기로 등록된다(관리자가 메인 대시보드에서 승인).
// employee_id 는 서버가 auth.uid() 로 직접 찾으므로 클라이언트가 보낼 필요가 없다.
export interface DeviceStatus { status: 'active' | 'pending'; is_active: boolean }

export async function registerDevice(deviceId: string, label: string): Promise<DeviceStatus> {
  const rows = await sbRpc<Array<{ o_status: 'active' | 'pending'; o_is_active: boolean }>>(
    'attendance_register_device',
    { p_device_id: deviceId, p_device_label: label }
  );
  const row = rows[0];
  if (!row) throw new Error('기기 등록 응답이 비어 있습니다');
  return { status: row.o_status, is_active: row.o_is_active };
}

// ── 셀피 업로드 ──
// attendance-selfies 버킷(private)에 <employee_id>/<check_type>-<timestamp>.jpg 로 저장한다.
// RLS(attendance_selfies_self_insert, phase1)가 첫 폴더 세그먼트를 본인 employee_id 로 제한하고,
// 서버 RPC(attendance_assert_selfie, phase2.1)는 15분 내 업로드된 본인 객체만 인정한다.
export async function uploadSelfie(employeeId: string, checkType: 'check_in' | 'check_out', blob: Blob): Promise<string> {
  const path = `${employeeId}/${checkType}-${Date.now()}.jpg`;
  const { error } = await supabase.storage.from(SELFIE_BUCKET).upload(path, blob, {
    contentType: 'image/jpeg',
    upsert: false,
  });
  if (error) throw new Error(`셀피 업로드 실패: ${error.message}`);
  return path;
}

// ── 출근/퇴근 ──
// attendance_check_in/check_out RPC. 승인된 기기 + 유효한 셀피 경로가 없으면 서버가 예외로 거부한다
// (attendance 테이블 직접 insert 는 Phase 2 에서 RLS 로 막혔다).
export async function checkIn(lat: number, lon: number, deviceId: string, selfiePath: string) {
  return sbRpc<AttendanceRecord>('attendance_check_in', {
    p_lat: lat, p_lon: lon, p_device_id: deviceId, p_selfie_path: selfiePath,
  });
}

export async function checkOut(lat: number, lon: number, deviceId: string, selfiePath: string) {
  return sbRpc<AttendanceRecord>('attendance_check_out', {
    p_lat: lat, p_lon: lon, p_device_id: deviceId, p_selfie_path: selfiePath,
  });
}

// ── 근무 중 지오펜스 이탈 감지 ──
// 출근 후 주기적으로 좌표를 보내 이탈/재진입 상태 전이를 서버에 기록한다(요건 4).
// 반환: 'exit' | 'reenter' | 'no_change' | 'not_checked_in' | 'no_position' | 'no_zone'
export async function reportGeofenceExit(lat: number, lon: number): Promise<string> {
  return sbRpc<string>('attendance_report_geofence_exit', { p_lat: lat, p_lon: lon });
}

// ── 조회 ──
export async function fetchMyAttendance(from: string, to: string): Promise<AttendanceRecord[]> {
  const emp = await fetchEmployee();
  if (!emp) return [];
  const q = `attendance?select=id,check_type,check_time,is_within_geofence,distance_meters,status,device_id,correction_reason,original_check_time,geofence_zone:geofence_zones(name)`
    + `&employee_id=eq.${emp.id}&check_time=gte.${encodeURIComponent(from)}&check_time=lte.${encodeURIComponent(to)}&order=check_time.desc`;
  return sbFetch<AttendanceRecord[]>(q);
}

export interface TodayStatus {
  lastCheckIn: string | null;
  lastCheckOut: string | null;
  records: AttendanceRecord[];
}

/** 오늘(자카르타 기준) 출퇴근 상태. 취소(voided)된 기록은 없는 것으로 본다. */
export async function fetchTodayStatus(): Promise<TodayStatus> {
  const { from, to } = jakartaDayRange(jakartaDate());
  const records = (await fetchMyAttendance(from, to)).filter(r => r.status !== 'voided');
  const lastCheckIn = records.find(r => r.check_type === 'check_in')?.check_time ?? null;
  const lastCheckOut = records.find(r => r.check_type === 'check_out')?.check_time ?? null;
  return { lastCheckIn, lastCheckOut, records };
}

// ── 휴가 ──
export async function createLeaveRequest(body: {
  employee_id: string;
  leave_type: string;
  start_date: string;
  end_date: string;
  days_count: number;
  reason: string;
}): Promise<LeaveRequest> {
  // 서버 트리거(leave_requests_validate, phase2.1)가 기간·일수·잔여 연차를 검증하고 위반 시 예외를 던진다.
  const rows = await sbFetch<LeaveRequest[]>('leave_requests', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify(body),
  });
  return rows[0];
}

export async function fetchMyLeaveRequests(): Promise<{ requests: LeaveRequest[]; employee: Employee | null }> {
  const employee = await fetchEmployee(true); // 잔여 연차는 승인 시 바뀌므로 매번 새로 읽는다
  if (!employee) return { requests: [], employee: null };
  const requests = await sbFetch<LeaveRequest[]>(
    `leave_requests?select=*&employee_id=eq.${employee.id}&order=created_at.desc`
  );
  return { requests, employee };
}
