# AsuraDB

PT Ascendo International 타이어 사업 사내 대시보드.
경영 KPI·마진·지점 실적·인건비, 영업 견적·가격비교, 근태 관리, 사내 자료 게시판을 한 앱에서 다룬다.

**Vue 3 + TailwindCSS v4 + Supabase**. 대시보드는 GitHub Pages(`/asuraDB/`)에,
직원용 근태 PWA 는 그 하위 경로(`/asuraDB/pwa/`)에 배포된다.

> 사내 전용 · 비공개 저장소. 검색엔진 색인 대상이 아니다(`noindex`).

---

## 1. 빠른 시작

```bash
npm install                       # 의존성 설치
cp .env.example .env              # 환경변수 채우기 (§5)
npm run dev                       # 개발 서버 → http://localhost:5173/asuraDB/
npm run build                     # 타입 검사 + 프로덕션 빌드
npm run type-check                # 타입 검사만
```

Python 수집기·검색 백엔드는 별도로 띄운다.

```bash
uv sync                                   # 수집기 의존성 (pyproject.toml)
uv run python scripts/launcher.py         # 수집기 데몬 (일간/주간/월간 스케줄)
uv run uvicorn api.search:app --port 8000 # 로컬 검색·AI Q&A 백엔드 (호스트 PC 전용)
```

---

## 2. 구성

| 파트 | 위치 | 내용 |
|---|---|---|
| **대시보드 (메인 앱)** | [src/](src/) | Vue 3 SPA. 해시 라우팅, 21개 화면 |
| **직원용 근태 PWA** | [employee-pwa/](employee-pwa/) | 별도 Vue 3 프로젝트. 휴대폰 설치용 출퇴근 앱 |
| **DB · 서버 로직** | [supabase/](supabase/) | 마이그레이션 101개 + Edge Function 3종 |
| **수집기** | [collectors/](collectors/) | 외부 지표·문서 수집 (Python) |
| **검색 백엔드** | [api/search.py](api/search.py) | FastAPI. 하이브리드 검색 + AI Q&A (로컬 전용) |
| **운영 스크립트** | [scripts/](scripts/) | 데이터 적재·계정 생성·LaunchAgent plist |
| **E2E 테스트** | [tests/e2e/](tests/e2e/) | Playwright 스모크 (전 라우트 렌더 + 콘솔 에러 0건) |

구조와 데이터 흐름은 [ARCHITECTURE.md](ARCHITECTURE.md) 참조.

---

## 3. 화면

사이드바 5개 그룹으로 묶여 있다. 경로는 모두 해시 라우팅(`#/home`).

| 그룹 | 경로 | 화면 |
|---|---|---|
| **경영·성과** | `/monitor` · `/margin` · `/branch-sales` · `/labor-cost` | KPI 모니터링 · 마진 분석 · 지점 실적 · 인건비 |
| **근태** | `/attendance` · `/leave-management` · `/attendance-report` | 출퇴근 현황 · 휴가/초과근무 승인 · 근태 집계 |
| **영업·견적** | `/quote` · `/price-compare` · `/databases` | 견적서 작성 · 가격 비교 · 회사 DB |
| **조회·검토** | `/tools/dot-lookup` · `/tire-import` · `/load-calc` · `/login-history` | DOT 공장코드 · BPS 수입통계 · 하중 계산 · 로그인 이력 |
| **자료·문서** | `/docs` · `/seo-docs` | 회사 자료 · 개인 자료 게시판 |
| 그 외 | `/home` · `/search` · `/ai-search` · `/login` | 홈 · 로컬 검색 · AI Q&A · 로그인 |

`/search`·`/ai-search` 는 호스트 PC 의 FastAPI 백엔드가 떠 있어야 동작한다.

**역할 게이팅** — `super_admin`·`staff` 는 전 경로, `distributor`·`end_user` 는 `/quote` 와
`/price-compare` 만 접근된다. 역할은 `auth.jwt().app_metadata.role` 이 원본이고
세션 캐시(`sessionStorage.asura_auth`)는 화면 표시용이다.

---

## 4. 배포

```bash
npm run deploy        # 대시보드 + PWA 를 함께 gh-pages 로 (dist/ + dist/pwa/)
npm run deploy:pwa    # 직원용 PWA 만 → /asuraDB/pwa/
```

- 대시보드: `https://<계정>.github.io/asuraDB/`
- 직원용 PWA: `https://<계정>.github.io/asuraDB/pwa/`

> **순서 주의** — PWA 가 새 RPC 시그니처에 의존할 때는 반드시 **Supabase 마이그레이션을 먼저**
> 적용한 뒤 PWA 를 배포한다. 반대로 하면 출퇴근이 막힌다.

Edge Function 은 별도다.

```bash
supabase functions deploy <function-name> --project-ref <project-ref>
```

---

## 5. 환경변수

[.env.example](.env.example) 을 `.env` 로 복사해 채운다. PWA 는 [employee-pwa/.env.example](employee-pwa/.env.example) 을 따로 쓴다.

```bash
VITE_SB_URL=https://<project-ref>.supabase.co
VITE_SB_KEY=sb_publishable_xxxx      # 브라우저 노출 O — publishable/anon 키만
SUPABASE_SERVICE_KEY=eyJ...          # 브라우저 노출 X — 서버·수집기 전용
```

**`VITE_` 접두사가 붙은 값은 빌드 결과에 그대로 들어가 브라우저에 노출된다.**
service_role 키·API 비밀키에는 절대 붙이지 않는다. 데이터 보호는 노출된 anon 키가 아니라
RLS(`to authenticated`) + 사용자 JWT 로 한다. 자세한 항목은 `.env.example` 주석과
[개발 지침서 §9·§11](docs/AsuraDB_Development_Guide.md) 참조.

---

## 6. 기술 스택

| 레이어 | 사용 |
|---|---|
| 프레임워크 | Vue 3.5 (`<script setup lang="ts">`) · Vite 5 · TypeScript 5.5 |
| 스타일 | TailwindCSS v4 (`@tailwindcss/vite`) · 시맨틱 토큰 라이트 테마 |
| UI | `reka-ui` + shadcn-vue 패턴 자체 구현 · `lucide-vue-next` · `vue-sonner` |
| 라우팅·상태 | `vue-router` 4 (해시) · `pinia` 2 |
| 시각화 | `chart.js` 4 + `vue-chartjs` · `leaflet`(지오펜싱 지도) |
| 백엔드 | Supabase (Postgres · Auth · Storage · Edge Functions · pg_cron) |
| 수집기 | Python 3.11+ · `uv` · FastAPI · `sentence-transformers` |
| 테스트·배포 | Playwright · `gh-pages` |

---

## 7. 문서

| 문서 | 내용 |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 시스템 구조 · 데이터 흐름 · 인증/권한 모델 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 작업 규칙 · 코드 컨벤션 · 마이그레이션 적용 절차 |
| [CHANGELOG.md](CHANGELOG.md) | 릴리스 단위 요약 |
| [CLAUDE.md](CLAUDE.md) | AI 어시스턴트용 작업 지침(필수 규칙 요약) |
| [docs/AsuraDB_Development_Guide.md](docs/AsuraDB_Development_Guide.md) | 아키텍처·스키마·환경변수·보안(§11)·로드맵 |
| [docs/웹사이트_운영_변경이력.md](docs/웹사이트_운영_변경이력.md) | **변경이력 SSOT** — 모든 변경의 상세 기록 |
| [docs/근태관리기능.md](docs/근태관리기능.md) | 근태 3화면 · PWA · 지오펜싱 · 대리출석 방지 |
| [docs/AsuraDB_지표수집_가이드.md](docs/AsuraDB_지표수집_가이드.md) | 외부 거시·시장 지표 24종 수집 |
| [docs/학습덱_HTML_제작지침.md](docs/학습덱_HTML_제작지침.md) | `public/docs/` 학습용 정적 HTML 덱 규격 |

---

*PT Ascendo International · 사내 전용*
