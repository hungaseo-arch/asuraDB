import { supabase, sbHeaders } from './supabase';

const SB_URL = import.meta.env.VITE_SB_URL as string;

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

export interface AttendanceRecord {
  id: string;
  check_type: 'check_in' | 'check_out';
  check_time: string;
  is_within_geofence: boolean;
  distance_meters: number;
  geofence_zone?: { name: string } | null;
}

export async function fetchEmployee(): Promise<Employee | null> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const res = await fetch(`${SB_URL}/rest/v1/employees?select=*&user_id=eq.${user.id}&limit=1`, {
    headers: await sbHeaders(),
  });
  const data = await res.json();
  return data[0] ?? null;
}

export async function checkIn(employeeId: string, lat: number, lon: number) {
  const res = await fetch(`${SB_URL}/rest/v1/attendance`, {
    method: 'POST',
    headers: { ...(await sbHeaders()), 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify({ employee_id: employeeId, check_type: 'check_in', latitude: lat, longitude: lon, device_info: {} }),
  });
  return res.json();
}

export async function checkOut(employeeId: string, lat: number, lon: number) {
  const res = await fetch(`${SB_URL}/rest/v1/attendance`, {
    method: 'POST',
    headers: { ...(await sbHeaders()), 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify({ employee_id: employeeId, check_type: 'check_out', latitude: lat, longitude: lon, device_info: {} }),
  });
  return res.json();
}

export async function fetchMyAttendance(from: string, to: string): Promise<AttendanceRecord[]> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const empRes = await fetch(`${SB_URL}/rest/v1/employees?select=id&user_id=eq.${user.id}&limit=1`, {
    headers: await sbHeaders(),
  });
  const emp = (await empRes.json())[0];
  if (!emp) return [];
  const res = await fetch(
    `${SB_URL}/rest/v1/attendance?select=*,geofence_zone:geofence_zones(name)&employee_id=eq.${emp.id}&check_time=gte.${from}&check_time=lte.${to}&order=check_time.desc`,
    { headers: await sbHeaders() }
  );
  return res.json();
}

export async function fetchTodayStatus(): Promise<{ lastCheckIn: string | null; lastCheckOut: string | null }> {
  const today = new Date().toISOString().slice(0, 10);
  const records = await fetchMyAttendance(`${today}T00:00:00`, `${today}T23:59:59`);
  const lastCheckIn = records.find(r => r.check_type === 'check_in')?.check_time ?? null;
  const lastCheckOut = records.find(r => r.check_type === 'check_out')?.check_time ?? null;
  return { lastCheckIn, lastCheckOut };
}

export async function createLeaveRequest(body: {
  employee_id: string;
  leave_type: string;
  start_date: string;
  end_date: string;
  days_count: number;
  reason: string;
}) {
  const res = await fetch(`${SB_URL}/rest/v1/leave_requests`, {
    method: 'POST',
    headers: { ...(await sbHeaders()), 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify(body),
  });
  return res.json();
}

export async function fetchMyLeaveRequests() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const empRes = await fetch(`${SB_URL}/rest/v1/employees?select=id,annual_leave_total,annual_leave_used&user_id=eq.${user.id}&limit=1`, {
    headers: await sbHeaders(),
  });
  const emp = (await empRes.json())[0];
  if (!emp) return { requests: [], employee: null };
  const res = await fetch(
    `${SB_URL}/rest/v1/leave_requests?select=*&employee_id=eq.${emp.id}&order=created_at.desc`,
    { headers: await sbHeaders() }
  );
  return { requests: await res.json(), employee: emp };
}
