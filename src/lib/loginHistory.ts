import { sbGet, sbPost } from './supabase';
import type { Role } from './auth';

export interface LoginHistoryRecord {
  id: string;
  user_id: string | null;
  email: string | null;
  role: string | null;
  event_type: 'login' | 'logout';
  user_agent: string | null;
  created_at: string;
}

// 로그인/로그아웃 이벤트 기록. 실패해도 인증 흐름을 막지 않는다(로깅은 부가 기능).
export async function recordLoginEvent(
  eventType: 'login' | 'logout',
  userId: string,
  email: string | null,
  role: Role | null,
): Promise<void> {
  try {
    await sbPost('login_history', {
      user_id: userId,
      email,
      role,
      event_type: eventType,
      user_agent: navigator.userAgent,
    });
  } catch {
    // 로그 기록 실패는 무시
  }
}

export async function fetchLoginHistory(params: { from?: string; to?: string; limit?: number } = {}): Promise<LoginHistoryRecord[]> {
  const filters = ['select=*', 'order=created_at.desc'];
  if (params.from) filters.push(`created_at=gte.${params.from}`);
  if (params.to)   filters.push(`created_at=lte.${params.to}`);
  filters.push(`limit=${params.limit ?? 500}`);
  return sbGet<LoginHistoryRecord[]>(`login_history?${filters.join('&')}`);
}
