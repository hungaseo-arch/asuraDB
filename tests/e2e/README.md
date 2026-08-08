# E2E 스모크 테스트 (Playwright)

전 라우트가 로그인 상태에서 정상 렌더되고 **콘솔 에러가 0건**인지 확인한다.
(라우트 15개 + 404 페이지 = 16건, 앞단에 로그인 setup 1건)

## 실행

```bash
# 최초 1회 — 브라우저 다운로드
npx playwright install chromium

# 실행 (계정은 환경변수로만 준다 — 저장소에 자격증명을 넣지 않는다)
E2E_EMAIL='you@example.com' E2E_PASSWORD='••••' npm run test:e2e
```

- `playwright.config.ts` 의 `webServer` 가 `npm run build && npm run preview` 를 자동으로 띄운다
  (기본 포트 4173, `E2E_PORT` 로 변경 가능). 이미 preview 가 떠 있으면 그대로 재사용한다.
- vite `base` 가 `/asuraDB/` 라 `baseURL` 도 `http://localhost:4173/asuraDB/` 이며,
  테스트에서는 `#/home` 처럼 해시 경로만 쓴다.
- 로그인 세션은 `tests/e2e/.auth/user.json` 에 저장해 재사용한다 (gitignore 대상).

## 판정 기준

- 각 라우트: `/login` 으로 튕기지 않을 것 · `document.title` 이 라우트 제목일 것 ·
  `<main>` 이 보일 것 · 콘솔 에러 0건.
- 로컬 전용 기능(로컬 검색 · AI 지식 Q&A)은 호스트 PC의 FastAPI(`localhost:8000/8001`)가 있어야
  동작하므로, 백엔드 미기동 시의 연결 실패 로그는 `smoke.spec.ts` 의 `IGNORED` 에서 제외한다.
