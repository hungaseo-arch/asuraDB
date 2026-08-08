import { test as setup, expect } from '@playwright/test';

// 로그인 1회 → 세션(storageState) 저장. 스모크 테스트는 이 상태를 재사용한다.
// 계정은 반드시 환경변수로 준다(저장소에 자격증명을 넣지 않는다).
const AUTH_FILE = 'tests/e2e/.auth/user.json';

setup('로그인', async ({ page }) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  if (!email || !password) {
    throw new Error('E2E_EMAIL / E2E_PASSWORD 환경변수가 필요합니다. 예) E2E_EMAIL=... E2E_PASSWORD=... npm run test:e2e');
  }

  await page.goto('#/login');
  await page.fill('#login-email', email);
  await page.fill('#login-password', password);
  await page.click('button[type="submit"]');

  // 로그인 성공 → 홈(또는 견적)으로 이동. 실패하면 화면의 사유를 그대로 보여준다
  // (URL 타임아웃만 나면 '왜 실패했는지'를 알 수 없어서)
  const loginError = page.getByTestId('login-error');
  await Promise.race([
    page.waitForURL(/#\/(home|quote)/, { timeout: 20_000 }).catch(() => {}),
    loginError.waitFor({ state: 'visible', timeout: 20_000 }).catch(() => {}),
  ]);
  if (await loginError.isVisible()) {
    throw new Error(
      `로그인 실패 — 앱 메시지: "${(await loginError.innerText()).trim()}"\n` +
      'E2E_EMAIL / E2E_PASSWORD 를 확인하세요. 비밀번호에 특수문자가 있으면 작은따옴표로 감싸야 합니다.',
    );
  }
  await expect(page).toHaveURL(/#\/(home|quote)/, { timeout: 20_000 });
  await page.context().storageState({ path: AUTH_FILE });
});
