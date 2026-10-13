import { supabase } from './supabase';
import type { Role } from './auth';

// 관리자 전용 사용자 관리 — Edge Function `admin-users` 를 호출한다.
// 계정 생성·삭제·비밀번호 재설정은 service_role 이 필요하므로 브라우저에서 직접 하지 않고,
// 함수가 호출자의 JWT(app_metadata.role = super_admin)를 검증한 뒤 서버에서 처리한다.
// 비밀번호를 비워 보내면 함수 시크릿 DEFAULT_USER_PASSWORD(기본 비밀번호)가 쓰인다.

export interface AdminUser {
  id: string;
  email: string | null;
  role: Role | string | null;
  created_at: string;
  last_sign_in_at: string | null;
}

async function call<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('admin-users', { body });
  if (error) {
    // FunctionsHttpError 는 응답 본문에 서버 메시지가 있다
    const msg = await (error as any).context?.json?.().then((j: any) => j?.error).catch(() => null);
    throw new Error(msg || error.message);
  }
  return data as T;
}

export async function listUsers(): Promise<AdminUser[]> {
  return (await call<{ users: AdminUser[] }>({ action: 'list' })).users;
}

export function createUser(email: string, role: Role, password?: string) {
  return call<{ id: string; email: string }>({ action: 'create', email, role, password: password || undefined });
}

export function setUserPassword(id: string, password?: string) {
  return call<{ ok: true }>({ action: 'set_password', id, password: password || undefined });
}

export function deleteUser(id: string) {
  return call<{ ok: true }>({ action: 'delete', id });
}
