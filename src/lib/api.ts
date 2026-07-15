export const API_BASE      = 'http://localhost:8000';
export const LAUNCHER_BASE = 'http://localhost:8001';

// 로컬 검색·AI 검색 백엔드(FastAPI)는 호스트 PC의 localhost 에서만 동작한다.
// 배포본(GitHub Pages 등)에서 접속하면 이 두 기능은 쓸 수 없으므로 안내 문구를 분기한다.
// (KPI·마진·지점·수입·DB·견적 등은 Supabase 직결이라 원격에서도 정상)
export const IS_HOST = /^(localhost|127\.0\.0\.1)$/.test(
  typeof location !== 'undefined' ? location.hostname : '',
);
