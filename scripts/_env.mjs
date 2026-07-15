// 공유 .env 로더 — Node 스크립트(ingest-bps-file·create_auth_users 등)에서 재사용.
// dotenv 의존 없이 루트 .env 를 정규식으로 읽는다(따옴표 제거).
import { readFileSync } from 'node:fs';

const envText = (() => {
  try {
    return readFileSync(new URL('../.env', import.meta.url), 'utf8');
  } catch {
    return '';   // .env 없을 때(예: process.env 만 사용) 빈 문자열
  }
})();

/** .env 에서 키 값 읽기 (없으면 ''). 앞뒤 공백·감싼 따옴표 제거. */
export const pick = (k) =>
  (envText.match(new RegExp(`^${k}=(.+)$`, 'm'))?.[1] ?? '').trim().replace(/^"|"$/g, '');

/**
 * service_role 자격 (서버/수집기 전용). URL 은 SUPABASE_URL 우선(없으면 VITE_SB_URL),
 * 키는 환경변수 SUPABASE_SERVICE_ROLE_KEY 우선(없으면 .env SUPABASE_SERVICE_KEY).
 * @returns {{ url: string, key: string }}
 */
export function serviceCreds() {
  return {
    url: pick('SUPABASE_URL') || pick('VITE_SB_URL'),
    key: process.env.SUPABASE_SERVICE_ROLE_KEY || pick('SUPABASE_SERVICE_KEY'),
  };
}
