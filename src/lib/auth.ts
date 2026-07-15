import { supabase } from '@/lib/supabase';

// 4역할 모델 — 가이드(RLS 보안 점검) 기준
//   super_admin : 전체 접근 + 쓰기 (관리자)
//   staff       : 원가 포함 조회 (직원, read-only)
//   distributor : 판매가만 조회 (대리점)
//   end_user    : 판매가만 조회 (최종 고객)
//
// 역할은 반드시 app_metadata.role 에만 저장 — user_metadata 는 사용자가
// supabase.auth.updateUser({data:{...}}) 로 self-update 가능하므로 신뢰 불가.
export type Role = 'super_admin' | 'staff' | 'distributor' | 'end_user';

const ALLOWED_ROLES: readonly Role[] = ['super_admin', 'staff', 'distributor', 'end_user'];

function isRole(v: unknown): v is Role {
  return typeof v === 'string' && (ALLOWED_ROLES as readonly string[]).includes(v);
}

// 이메일 + 비밀번호 로그인. 성공 시 app_metadata.role 반환 (없으면 null).
// 실패 시 메시지를 그대로 throw (PinLogin에서 표시).
export async function signIn(email: string, password: string): Promise<Role | null> {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new Error(error.message);

  const claim = (data.session?.user.app_metadata as Record<string, unknown> | undefined)?.role;
  const role  = isRole(claim) ? claim : null;
  if (role) sessionStorage.setItem('asura_auth', role);
  else      sessionStorage.removeItem('asura_auth');
  return role;
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
  sessionStorage.removeItem('asura_auth');
}

// 세션은 살아있지만 sessionStorage 역할이 비어있는 경우(탭 재오픈 등) 복원.
// 가이드 §보안: app_metadata 만 읽는다 (user_metadata 는 self-update 가능해 신뢰 불가).
export async function syncRoleFromSession(): Promise<Role | null> {
  const { data } = await supabase.auth.getSession();
  const claim = (data.session?.user.app_metadata as Record<string, unknown> | undefined)?.role;
  const role  = isRole(claim) ? claim : null;
  if (role) sessionStorage.setItem('asura_auth', role);
  return role;
}
