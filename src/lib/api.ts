export const API_BASE      = 'http://localhost:8000';
export const LAUNCHER_BASE = 'http://localhost:8001';

// 로컬 검색·AI 검색 백엔드(FastAPI)는 호스트 PC의 localhost 에서만 동작한다.
// 배포본(GitHub Pages 등)에서 접속하면 이 두 기능은 쓸 수 없으므로 안내 문구를 분기한다.
// (KPI·마진·지점·수입·DB·견적 등은 Supabase 직결이라 원격에서도 정상)
export const IS_HOST = /^(localhost|127\.0\.0\.1)$/.test(
  typeof location !== 'undefined' ? location.hostname : '',
);

/**
 * API(8000)가 떠 있도록 보장한다. 런처(8001)는 유휴 시 API 를 자동 종료하므로,
 * :8000 을 직접 호출하기 전 반드시 먼저 깨워야 한다.
 *   1) /health 로 이미 살아 있으면 즉시 true
 *   2) 아니면 런처 /start 로 기동 요청 후 최대 ~15초 health 폴링
 * 런처 자체가 없으면(호스트 아님·미실행) false 를 반환한다.
 */
export async function ensureApiRunning(): Promise<boolean> {
  // 호스트 PC 가 아니면 localhost 로 나갈 요청을 아예 만들지 않는다.
  // (HTTPS 배포본에서 http://localhost 호출은 mixed content 로 차단되며 콘솔 에러만 쌓인다)
  if (!IS_HOST) return false;

  try {
    const res = await fetch(`${API_BASE}/health`, { signal: AbortSignal.timeout(2000) });
    if (res.ok) return true;
  } catch { /* 아래에서 기동 시도 */ }

  try {
    await fetch(`${LAUNCHER_BASE}/start`, { method: 'POST', signal: AbortSignal.timeout(3000) });
  } catch {
    return false;   // 런처 미실행 → 기동 불가
  }

  for (let i = 0; i < 15; i++) {
    await new Promise(r => setTimeout(r, 1000));
    try {
      const res = await fetch(`${API_BASE}/health`, { signal: AbortSignal.timeout(2000) });
      if (res.ok) return true;
    } catch { /* 기동 대기 중 */ }
  }
  return false;
}
