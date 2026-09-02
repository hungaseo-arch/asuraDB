import { supabase, sbHeaders, sbGet, sbGetAll, sbPost, sbPatch, sbRpc, SB_URL } from './supabase';

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

export interface AttendanceRecord {
  id: string;
  employee_id: string;
  employee?: Employee;
  check_type: 'check_in' | 'check_out';
  latitude: number;
  longitude: number;
  geofence_zone_id: string | null;
  geofence_zone?: GeofenceZone;
  is_within_geofence: boolean;
  distance_meters: number;
  device_info: any;
  check_time: string;
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

// ── 출퇴근 기록 ──
export async function fetchTodayAttendance(): Promise<AttendanceRecord[]> {
  const today = new Date().toISOString().slice(0, 10);
  return sbGetAll<AttendanceRecord>(
    `attendance?select=*,employee:employees(name,department,position)&check_time=gte.${today}T00:00:00&order=check_time.desc`
  );
}

export async function fetchAttendanceByDate(date: string): Promise<AttendanceRecord[]> {
  return sbGetAll<AttendanceRecord>(
    `attendance?select=*,employee:employees(name,department,position)&check_time=gte.${date}T00:00:00&check_time=lte.${date}T23:59:59&order=check_time.desc`
  );
}

export async function fetchEmployeeAttendance(employeeId: string, from: string, to: string): Promise<AttendanceRecord[]> {
  return sbGetAll<AttendanceRecord>(
    `attendance?select=*,employee:employees(name,department,position)&employee_id=eq.${employeeId}&check_time=gte.${from}&check_time=lte.${to}&order=check_time.desc`
  );
}

export async function checkIn(employeeId: string, lat: number, lon: number, deviceInfo?: any) {
  return sbPost<AttendanceRecord>('attendance', {
    employee_id: employeeId,
    check_type: 'check_in',
    latitude: lat,
    longitude: lon,
    device_info: deviceInfo ?? {},
  });
}

export async function checkOut(employeeId: string, lat: number, lon: number, deviceInfo?: any) {
  return sbPost<AttendanceRecord>('attendance', {
    employee_id: employeeId,
    check_type: 'check_out',
    latitude: lat,
    longitude: lon,
    device_info: deviceInfo ?? {},
  });
}

// ── 휴가/연차 ──
export async function fetchLeaveRequests(status?: string): Promise<LeaveRequest[]> {
  let path = 'leave_requests?select=*,employee:employees(name,department),approver:employees!leave_requests_approved_by_fkey(name)&order=created_at.desc';
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
  let path = 'overtime?select=*,employee:employees(name,department),approver:employees!overtime_approved_by_fkey(name)&order=created_at.desc';
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

// ── 지오펜싱 체크 (Supabase RPC) ──
export async function checkGeofenceRpc(lat: number, lon: number): Promise<{
  zone_id: string | null;
  zone_name: string | null;
  distance: number;
  within: boolean;
}> {
  const result = await sbRpc<Array<{
    zone_id: string | null;
    zone_name: string | null;
    distance: number;
    within: boolean;
  }>>('check_geofence', { p_lat: lat, p_lon: lon });
  return result[0] ?? { zone_id: null, zone_name: null, distance: 0, within: false };
}
