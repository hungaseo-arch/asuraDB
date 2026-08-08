import { test, expect, type ConsoleMessage, type Page } from '@playwright/test';

// 스모크 — 전 라우트가 로그인 상태에서 뜨고, 콘솔 에러가 0건인지 확인한다.
// (auth.setup.ts 가 저장한 세션을 재사용)

const ROUTES: { path: string; title: string }[] = [
  { path: '#/home',             title: '홈' },
  { path: '#/search',           title: '로컬 검색' },
  { path: '#/ai-search',        title: 'AI 지식 Q&A' },
  { path: '#/quote',            title: '견적서 작성' },
  { path: '#/price-compare',    title: '가격비교' },
  { path: '#/load-calc',        title: '하중계산' },
  { path: '#/monitor',          title: 'KPI 모니터링' },
  { path: '#/tire-import',      title: '인도네시아 타이어 수입량' },
  { path: '#/margin',           title: '마진 분석' },
  { path: '#/branch-sales',     title: '지점 판매 현황' },
  { path: '#/labor-cost',       title: '인건비' },
  { path: '#/docs',             title: 'ASCENDO자료' },
  { path: '#/seo-docs',         title: 'SEO자료' },
  { path: '#/databases',        title: '회사 DB' },
  { path: '#/tools/dot-lookup', title: 'DOT 공장코드 조회' },
];

// 호스트 PC 전용 기능(로컬 검색·AI 검색)은 FastAPI(localhost:8000/8001)가 떠 있어야 동작한다.
// 백엔드가 없는 환경에서 나는 연결 실패는 앱 결함이 아니므로 스모크 판정에서 제외한다.
const IGNORED = [/localhost:800[01]/, /ERR_CONNECTION_REFUSED/, /Failed to load resource/];

function watchConsole(page: Page): string[] {
  const errors: string[] = [];
  page.on('console', (m: ConsoleMessage) => {
    if (m.type() !== 'error') return;
    const text = m.text();
    if (IGNORED.some(re => re.test(text))) return;
    errors.push(text);
  });
  page.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
  return errors;
}

for (const r of ROUTES) {
  test(`${r.path} — 렌더 + 콘솔 에러 0건`, async ({ page }) => {
    const errors = watchConsole(page);
    await page.goto(r.path);
    // 라우트 가드가 /login 으로 튕기지 않았는지 = 세션 유효
    await expect(page).toHaveURL(new RegExp(r.path.replace('/#', '#').replace(/\//g, '\\/')));
    await expect(page).toHaveTitle(new RegExp(`${r.title}`));
    // 앱 셸이 그려졌는지(빈 화면·크래시 감지)
    await expect(page.locator('main')).toBeVisible();
    await page.waitForLoadState('networkidle');
    expect(errors, `콘솔 에러:\n${errors.join('\n')}`).toEqual([]);
  });
}

test('없는 경로 → 404 페이지', async ({ page }) => {
  const errors = watchConsole(page);
  await page.goto('#/no-such-page');
  await expect(page.getByText('404')).toBeVisible();
  expect(errors, `콘솔 에러:\n${errors.join('\n')}`).toEqual([]);
});
