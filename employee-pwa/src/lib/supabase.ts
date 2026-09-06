import { createClient } from '@supabase/supabase-js';

const SB_URL = import.meta.env.VITE_SB_URL as string;
const SB_KEY = import.meta.env.VITE_SB_KEY as string;

export { SB_URL };

export const supabase = createClient(SB_URL, SB_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});

export async function sbHeaders(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token ?? SB_KEY;
  return { apikey: SB_KEY, Authorization: `Bearer ${token}` };
}

// RPC 호출 — 서버 RAISE EXCEPTION 메시지(한글, 사용자에게 그대로 보여줄 문구)를 최대한 살려서 던진다.
export async function sbRpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method:  'POST',
    headers: { ...(await sbHeaders()), 'Content-Type': 'application/json' },
    body:    JSON.stringify(args),
  });
  if (!res.ok) {
    let message = `RPC ${fn}: ${res.status}`;
    try {
      const body = await res.json();
      if (body?.message) message = body.message;
    } catch { /* 응답이 JSON이 아니면 기본 메시지 사용 */ }
    throw new Error(message);
  }
  return res.json() as Promise<T>;
}
