// ⚠️  VITE_SB_KEY는 Vite 빌드에 포함되어 브라우저에 노출됩니다.
// 반드시 Supabase Dashboard → Settings → API → anon public 키를 사용하세요.
// service_role 키는 Edge Function (서버) 전용입니다.
//
// RLS는 `to authenticated`로 좁혀져 있어, 비로그인(anon 키만) 요청은 차단됩니다.
// 로그인 시 Supabase Auth가 발급한 사용자 JWT를 Authorization 헤더로 보내야 데이터에 접근됩니다.

import { createClient } from '@supabase/supabase-js';

const SB_URL = import.meta.env.VITE_SB_URL as string;
const SB_KEY = import.meta.env.VITE_SB_KEY as string;

export { SB_URL };

// 인증 세션 관리 전용 클라이언트 (세션은 localStorage에 보관·자동 갱신)
// detectSessionInUrl=false: 해시 라우터(createWebHashHistory) 사용 + OAuth 콜백 미사용이라
//                           URL 해시를 auth 콜백으로 파싱하는 기본 동작을 꺼서 충돌 방지.
export const supabase = createClient(SB_URL, SB_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});

// 현재 세션 토큰 기반 헤더. 로그인 시 사용자 JWT, 아니면 anon 키로 폴백.
export async function sbHeaders(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token ?? SB_KEY;
  return {
    apikey:        SB_KEY,
    Authorization: `Bearer ${token}`,
  };
}

export async function sbGet<T>(path: string): Promise<T> {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, { headers: await sbHeaders() });
  if (!res.ok) throw new Error(`GET ${path}: ${res.status}`);
  return res.json() as Promise<T>;
}

// max-rows cap(기본 1000) 우회 — Range 헤더로 페이지네이션해 전체 행 수집
export async function sbGetAll<T>(path: string, pageSize = 1000): Promise<T[]> {
  const all: T[] = [];
  let from = 0;
  const headers = await sbHeaders();
  while (true) {
    const to  = from + pageSize - 1;
    const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
      headers: { ...headers, Range: `${from}-${to}` },
    });
    // 200 = 전체 반환 / 206 = Partial Content (더 있음). 둘 다 정상.
    if (res.status !== 200 && res.status !== 206) {
      throw new Error(`GET ${path}: ${res.status}`);
    }
    const chunk = (await res.json()) as T[];
    all.push(...chunk);
    if (chunk.length < pageSize) break;
    from += pageSize;
  }
  return all;
}

// onConflict 지정 시 upsert(중복 병합) — UNIQUE 제약 있는 테이블에 재삽입해도 409 대신 갱신.
export async function sbPost<T>(path: string, body: unknown, opts?: { onConflict?: string }): Promise<T> {
  const prefer = opts?.onConflict
    ? 'return=representation,resolution=merge-duplicates'
    : 'return=representation';
  const url = opts?.onConflict
    ? `${SB_URL}/rest/v1/${path}${path.includes('?') ? '&' : '?'}on_conflict=${opts.onConflict}`
    : `${SB_URL}/rest/v1/${path}`;
  const res = await fetch(url, {
    method:  'POST',
    headers: { ...(await sbHeaders()), 'Content-Type': 'application/json', Prefer: prefer },
    body:    JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`POST ${path}: ${res.status}`);
  return res.json() as Promise<T>;
}

export async function sbPatch(path: string, body: unknown): Promise<void> {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method:  'PATCH',
    headers: { ...(await sbHeaders()), 'Content-Type': 'application/json' },
    body:    JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`PATCH ${path}: ${res.status}`);
}

export async function sbDelete(path: string): Promise<void> {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method:  'DELETE',
    headers: await sbHeaders(),
  });
  if (!res.ok) throw new Error(`DELETE ${path}: ${res.status}`);
}

export async function sbRpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method:  'POST',
    headers: { ...(await sbHeaders()), 'Content-Type': 'application/json' },
    body:    JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`RPC ${fn}: ${res.status}`);
  return res.json() as Promise<T>;
}
