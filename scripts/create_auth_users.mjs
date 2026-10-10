// Supabase Auth 계정 생성/갱신 — 4역할 모델 (이메일 + 비밀번호)
//
// 가이드: AsuraDB RLS 보안 점검 (app_metadata.role 사용)
//   super_admin · staff · distributor · end_user
//
// ⚠ 역할은 반드시 app_metadata 에 저장 (user_metadata 는 사용자가 self-update 가능)
//
// 실행:
//   node scripts/create_auth_users.mjs
//
// 계정 정의 (비밀번호는 코드에 두지 않는다 — public 저장소):
//   - JSON 파일:   node scripts/create_auth_users.mjs [accounts.json]   (기본 경로: 저장소 루트 accounts.json, .gitignore 됨)
//   - 환경변수:    ACCOUNTS_JSON='[{"email":"...","password":"...","role":"staff"}]' node scripts/create_auth_users.mjs
//   형식: [{ "email": "...", "password": "...", "role": "staff" }, ...]
//
// service_role 키는 .env 의 SUPABASE_SERVICE_KEY 또는 SUPABASE_SERVICE_ROLE_KEY 환경변수에서 읽음.

import { readFileSync } from 'node:fs';
import { serviceCreds } from './_env.mjs';

const { url: SB_URL, key: SERVICE_KEY } = serviceCreds();

if (!SB_URL)      { console.error('✗ .env에 VITE_SB_URL / SUPABASE_URL 이 없습니다.'); process.exit(1); }
if (!SERVICE_KEY) { console.error('✗ service_role 키 없음 (.env SUPABASE_SERVICE_KEY 또는 환경변수 SUPABASE_SERVICE_ROLE_KEY).'); process.exit(1); }

const ALLOWED_ROLES = ['super_admin', 'staff', 'distributor', 'end_user'];

// 계정 목록 — 파일 인자 > ACCOUNTS_JSON 환경변수 > 루트 accounts.json 순. 어느 쪽도 없으면 중단.
let accounts;
try {
  const raw = process.env.ACCOUNTS_JSON
    ? process.env.ACCOUNTS_JSON
    : readFileSync(process.argv[2] ?? new URL('../accounts.json', import.meta.url), 'utf8');
  accounts = JSON.parse(raw);
  if (!Array.isArray(accounts)) throw new Error('JSON 최상단은 배열이어야 합니다.');
} catch (e) {
  console.error('✗ 계정 정의를 읽지 못했습니다 (accounts.json 또는 ACCOUNTS_JSON):', e.message);
  process.exit(1);
}

// 검증
for (const a of accounts) {
  if (!a.email || !a.password || !ALLOWED_ROLES.includes(a.role)) {
    console.error(`✗ 잘못된 계정 정의: ${JSON.stringify(a)} (role은 ${ALLOWED_ROLES.join('/')} 중 하나)`);
    process.exit(1);
  }
}

const headers = {
  apikey:        SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
};

async function findUserByEmail(email) {
  const res = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=200`, { headers });
  if (!res.ok) throw new Error(`목록 조회 실패: ${res.status} ${await res.text()}`);
  const data  = await res.json();
  const users = data.users ?? data;
  return users.find((u) => u.email === email) ?? null;
}

for (const acc of accounts) {
  try {
    const existing = await findUserByEmail(acc.email);
    // ⚠ 가이드 핵심: role은 app_metadata 로 저장 (self-update 불가).
    //   user_metadata 는 비워서 이전 흔적 제거.
    const body = JSON.stringify({
      email:         acc.email,
      password:      acc.password,
      email_confirm: true,
      app_metadata:  { role: acc.role },
      user_metadata: {},
    });
    const res = existing
      ? await fetch(`${SB_URL}/auth/v1/admin/users/${existing.id}`, { method: 'PUT',  headers, body })
      : await fetch(`${SB_URL}/auth/v1/admin/users`,                { method: 'POST', headers, body });

    const verb = existing ? '갱신' : '생성';
    console.log(res.ok
      ? `✓ ${acc.email} ${verb}됨 (app_metadata.role=${acc.role})`
      : `✗ ${acc.email} ${verb} 실패 ${res.status}: ${await res.text()}`,
    );
  } catch (e) {
    console.error(`✗ ${acc.email} 오류:`, e.message);
  }
}
