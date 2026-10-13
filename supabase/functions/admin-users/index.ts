// 관리자 전용 사용자 관리 — 목록·등록·삭제·비밀번호 재설정.
// service_role 키는 이 함수(서버)에서만 쓰고 브라우저에는 노출하지 않는다.
// 호출자는 반드시 로그인한 super_admin (app_metadata.role) 이어야 한다.
//
// Secrets: DEFAULT_USER_PASSWORD (기본 비밀번호 — 저장소에 두지 않는다)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const ROLES = ['super_admin', 'staff', 'distributor', 'end_user'] as const;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PW = 8;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  // 레거시 JWT 비밀값 폐기(2026-10-13) 대응 — 신규 secret key 사용, verify_jwt=false(아래에서 직접 검증)
  const secretKeys: Record<string, string> = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}');
  const admin = createClient(url, secretKeys['default'] ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 호출자 검증 — JWT 를 서버에서 다시 확인하고 app_metadata.role 만 신뢰한다
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: caller, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !caller.user) return json({ error: '로그인이 필요합니다' }, 401);
  if (caller.user.app_metadata?.role !== 'super_admin') return json({ error: '관리자만 사용할 수 있습니다' }, 403);

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return json({ error: '잘못된 요청' }, 400); }

  try {
    switch (body.action) {
      case 'list': {
        const { data, error } = await admin.auth.admin.listUsers({ perPage: 200 });
        if (error) throw error;
        return json({
          users: data.users.map(u => ({
            id: u.id, email: u.email, role: u.app_metadata?.role ?? null,
            created_at: u.created_at, last_sign_in_at: u.last_sign_in_at ?? null,
          })),
        });
      }

      case 'create': {
        const email = String(body.email ?? '').trim().toLowerCase();
        const role = body.role;
        if (!EMAIL_RE.test(email)) return json({ error: '이메일 형식이 올바르지 않습니다' }, 400);
        if (!ROLES.includes(role)) return json({ error: '역할이 올바르지 않습니다' }, 400);
        const password = String(body.password || Deno.env.get('DEFAULT_USER_PASSWORD') || '');
        if (password.length < MIN_PW) return json({ error: `비밀번호는 ${MIN_PW}자 이상이어야 합니다 (기본 비밀번호 시크릿 확인)` }, 400);
        const { data, error } = await admin.auth.admin.createUser({
          email, password, email_confirm: true, app_metadata: { role },
        });
        if (error) return json({ error: error.message }, 400);
        return json({ id: data.user.id, email });
      }

      case 'set_password': {
        const password = String(body.password || Deno.env.get('DEFAULT_USER_PASSWORD') || '');
        if (password.length < MIN_PW) return json({ error: `비밀번호는 ${MIN_PW}자 이상이어야 합니다` }, 400);
        const { error } = await admin.auth.admin.updateUserById(String(body.id), { password });
        if (error) return json({ error: error.message }, 400);
        // 기존 세션 무효화 — 재설정 후 이전 로그인이 남지 않게 한다
        await admin.auth.admin.signOut(String(body.id), 'global').catch(() => {});
        return json({ ok: true });
      }

      case 'delete': {
        const id = String(body.id);
        if (id === caller.user.id) return json({ error: '본인 계정은 삭제할 수 없습니다' }, 400);
        const { error } = await admin.auth.admin.deleteUser(id);
        if (error) return json({ error: error.message }, 400);
        return json({ ok: true });
      }

      default:
        return json({ error: '알 수 없는 action' }, 400);
    }
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
