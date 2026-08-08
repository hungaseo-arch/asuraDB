import { defineConfig, devices } from '@playwright/test';

// E2E 스모크 — 빌드 결과(dist)를 vite preview 로 띄워 실제 배포본과 같은 번들을 검사한다.
// 로그인 계정은 저장소에 넣지 않고 환경변수로만 받는다:
//   E2E_EMAIL=... E2E_PASSWORD=... npm run test:e2e
const PORT = Number(process.env.E2E_PORT ?? 4173);
// vite base 가 '/asuraDB/' 라 preview 도 이 경로 아래에 뜬다 (vite.config.ts 의 base 와 같아야 함)
const BASE_PATH = '/asuraDB/';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,          // 같은 세션(로그인 상태)을 공유하므로 순차 실행
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: `http://localhost:${PORT}${BASE_PATH}`,
    trace: 'retain-on-failure',
    ...devices['Desktop Chrome'],
  },
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.ts/ },
    {
      name: 'smoke',
      dependencies: ['setup'],
      use: { storageState: 'tests/e2e/.auth/user.json' },
    },
  ],
  webServer: {
    command: `npm run build && npm run preview -- --port ${PORT} --strictPort`,
    url: `http://localhost:${PORT}${BASE_PATH}`,
    timeout: 180_000,
    reuseExistingServer: !process.env.CI,
  },
});
