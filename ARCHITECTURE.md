# ARCHITECTURE

AsuraDB 의 구조와 데이터가 흐르는 경로. 화면 목록·실행 방법은 [README.md](README.md),
작업 규칙은 [CONTRIBUTING.md](CONTRIBUTING.md) 를 본다.

---

## 1. 전체 그림

```
┌───────────────────────┐      ┌───────────────────────┐
│  대시보드 (Vue 3 SPA) │      │  직원용 PWA (Vue 3)   │
│  /asuraDB/            │      │  /asuraDB/pwa/        │
│  관리자·직원 (PC)     │      │  전 직원 (휴대폰)     │
└───────────┬───────────┘      └───────────┬───────────┘
            │  anon 키 + 사용자 JWT        │
            └──────────────┬───────────────┘
                           ▼
        ┌──────────────────────────────────────┐
        │            Supabase                  │
        │  Auth · Postgres(RLS) · Storage      │
        │  Edge Functions · pg_cron · pg_net   │
        └───────┬──────────────────────┬───────┘
                │ service_role         │ service_role
                ▼                      ▼
      ┌──────────────────┐   ┌────────────────────┐
      │ 수집기 (Python)  │   │ FastAPI (호스트 PC)│
      │ collectors/      │   │ api/search.py      │
      │ LaunchAgent 스케줄│   │ 로컬 검색·AI Q&A   │
      └──────────────────┘   └────────────────────┘
```

세 종류의 클라이언트가 있고, **브라우저에서 도는 둘은 anon 키만** 쓴다.
service_role 키는 수집기와 Edge Function 등 서버 쪽에만 존재한다.

---

## 2. 대시보드 (`src/`)

```
src/
├── main.ts                엔트리 (Pinia · Router · Motion)
├── App.vue                루트 (Toaster · RouterView)
├── style.css              Tailwind v4 + 라이트 테마 시맨틱 토큰
├── router/index.ts        해시 라우팅 + 인증/역할 가드
├── components/
│   ├── Layout.vue         사이드바(5그룹) · 탑바 · 모바일 내비
│   ├── CommandPalette.vue 전역 검색 팔레트
│   ├── charts/ icons/ ui/ 차트 · 아이콘 · shadcn-vue 패턴 컴포넌트
│   └── ...                KpiEntryModal · StaffPayrollTable · TubeSpecTable 등
├── views/                 화면 21개 (README §3)
├── lib/                   supabase · auth · attendance · loginHistory · csv · xlsx · format · recent
├── stores/                Pinia (UI 상태)
└── composables/           재사용 로직
```

**라우팅** — `createWebHashHistory()`. GitHub Pages 하위 경로 배포에서 새로고침 404 가
나지 않게 하기 위한 선택이다. 라우트 `meta.title`/`meta.desc` 로 문서 제목과
`<meta name="description">` 을 매 이동마다 갱신한다.

**뷰는 전부 지연 로딩**(`() => import(...)`)이라 첫 진입 번들이 화면 수만큼 커지지 않는다.

---

## 3. 인증 · 권한

3중 구조다. 브라우저 쪽 값은 전부 표시용이고, 실제 강제는 DB 에서 한다.

```
1. Supabase Auth 세션 (JWT)        ← 로그인 상태의 근거
2. app_metadata.role               ← 권한의 원본(SSOT). 4역할 모델
3. sessionStorage.asura_auth       ← 화면 표시·라우터 게이팅용 캐시
```

| 역할 | 접근 범위 |
|---|---|
| `super_admin` | 전체 + 근태 정정/취소/수기 추가, 기기 승인 |
| `staff` | 전체 (관리자 전용 RPC 는 제외) |
| `distributor` · `end_user` | `/quote` · `/price-compare` 만 |

- **라우터 가드**(`src/router/index.ts`) — 세션 없으면 `/login`, 역할이 맞지 않으면 허용 경로로 되돌린다.
- **RLS** — 모든 테이블은 `to authenticated` 정책으로 보호된다. 라우터 가드를 우회한
  임의 클라이언트도 데이터를 못 가져간다.
- **SECURITY DEFINER RPC** — 관리자 전용 동작은 RPC 안에서 역할을 다시 검사한다.
  반드시 `IS DISTINCT FROM` 을 쓴다(`<>` 는 role 이 NULL 일 때 통과하는 fail-open).
  자세한 규칙은 [개발 지침서 §11-6](docs/AsuraDB_Development_Guide.md).

30분 미조작 시 자동 로그아웃되며, 로그인·로그아웃 이력은 `login_history` 에 남는다.

---

## 4. 데이터 흐름 — SSOT

화면에 보이는 숫자마다 "원본이 어디인가"가 정해져 있다. SQL 만 DB 에 적용하고 원본
파일을 안 고치면 importer 재실행 때 되돌아가므로, **원본과 DB 를 함께** 갱신한다.

| 도메인 | 원본(SSOT) | 경로 | 도착 테이블 → 화면 |
|---|---|---|---|
| 시장·경쟁·재무 KPI | `data/kpi/<YYYY>.csv` | `collectors/kpi_importer.py` | `kpi_monthly` → `Monitor.vue` |
| 마진 분석 | `sales analysis report_<YYYY-MM>.pdf` | `seed_margin_<YYYY-MM>.sql` | `margin_records` → `Margin.vue` |
| 지점 실적 | 지점 보고 파일 | `scripts/ingest_branch_sales.py` | `branch_sales` → `BranchSales.vue` |
| 외부 거시·시장 지표 | 외부 API (BPS · yfinance 등) | `collectors/indicator_collector.py` · Edge Function `collect-indicators` | `indicators` → `Monitor.vue` |
| 타이어 수입통계 | BPS WebAPI (dataexim) | `collectors/bps_import_collector.py` | `tire_imports` → `TireImport.vue` |
| 근태 | 직원 PWA 실시간 입력 | `attendance_check_in/out` RPC | `attendance` → 근태 3화면 |

---

## 5. 수집기 (`collectors/`)

Python 3.11+ / `uv`. 주기별 러너가 개별 수집기를 호출하는 구조다.

```
scripts/launcher.py            상시 데몬. 아래 러너를 스케줄에 맞춰 실행
├── daily_collector.py         일간 — 환율·유가·상품가 등
├── weekly_collector.py        주간 — 경쟁사·시장 자료 + 모니터링 리포트
└── monthly_collector.py       월간 — CPI·수입통계 등
```

개별 수집기는 `bps_collector`(CPI) · `bps_import_collector`(수입통계) ·
`indicator_collector`(지표 24종) · `gmail_collector` · `drive_collector` ·
`notion_collector` · `calendar_collector` · `upnote_collector` · `band_collector` ·
`kpi_importer`(CSV→DB) 등이 있다.

- **자동 실행** — macOS LaunchAgent (`scripts/com.asuradb.*.plist`).
- **상태 확인** — 각 수집기가 `collector_heartbeat` 에 `last_run` 을 남긴다.
  홈 화면 사이드바의 소스 stale 표시가 이 값을 본다.
- **클라우드 이관분** — 호스트 PC 가 꺼져 있어도 도는 것들은 Edge Function +
  pg_cron 으로 옮겼다(`collect-indicators`).

---

## 6. Supabase

### 6.1 Edge Functions

| 함수 | 트리거 | 하는 일 |
|---|---|---|
| `collect-indicators` | pg_cron | 외부 지표 수집(호스트 PC 독립) |
| `attendance-selfie-cleanup` | pg_cron (UTC 18:30 = 자카르타 01:30) | 출퇴근 셀피 90일 경과분 Storage 삭제 + `selfie_url` NULL 처리 |
| `summarize-meeting` | 수동 호출 | 회의록 요약 |

pg_cron → `pg_net` POST(`Authorization: service_role`) → Edge Function 패턴을 쓴다.
Storage 객체 삭제는 Storage API 를 거쳐야 실제 파일까지 지워지므로 SQL 만으로 처리하지 않는다.

### 6.2 마이그레이션

`supabase/migrations/` 에 101개. 파일명이 곧 이력이라 순번과 날짜 접두사가 섞여 있다.
적용은 **Supabase SQL Editor 에서 직접 실행**하는 방식을 쓴다(자세한 절차는 CONTRIBUTING §4).

### 6.3 저장소(Storage)

| 버킷 | 공개 | 제한 |
|---|---|---|
| `attendance-selfies` | 비공개 | 2 MB · `image/jpeg` 만. 경로 `<employee_id>/<check_type>-<timestamp>.jpg` |

비공개 버킷이라 대시보드는 `createSignedUrl(path, 60)` 로 잠깐만 열어 본다.

---

## 7. 근태 모듈

앱에서 가장 서버 강제가 강한 부분이라 따로 적는다. 전체 설명은 [docs/근태관리기능.md](docs/근태관리기능.md).

```
직원 PWA                        Supabase                       대시보드
────────                        ────────                       ────────
로그인                     →  employees.user_id 로 본인 특정
기기 등록                  →  attendance_register_device       기기 승인/폐기
셀피 촬영 → Storage 업로드 →  attendance_assert_selfie(검증)
GPS 취득 → 출근/퇴근       →  attendance_check_in/out          당일 현황·정정·취소·수기추가
근무 중 5분 간격 좌표 보고 →  attendance_report_geofence_exit  이탈 알림 확인
```

- **직접 INSERT 불가** — `attendance` 에 클라이언트용 INSERT 정책이 없다. 출퇴근은
  SECURITY DEFINER RPC 가 유일한 쓰기 경로다. 관리자도 `admin_read`(SELECT)만 있어
  정정·취소·수기 추가는 전부 RPC 를 거치며 감사 기록이 남는다.
- **셀피 검증** — 본인 폴더 · 15분 이내 업로드 · 미사용 객체일 때만 출퇴근이 성립한다.
- **동시 요청** — `pg_advisory_xact_lock` 으로 직원 단위 직렬화(더블탭 중복 방지).
- **날짜 기준** — 서버는 `(check_time AT TIME ZONE 'Asia/Jakarta')::date`,
  클라이언트는 `Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' })`.
  자카르타 하루 경계를 양쪽이 똑같이 본다.
- **상태값** — `normal` · `belum_checkout` · `corrected` · `voided`.
  취소는 물리 삭제가 아니라 `voided` 로 남긴다.

---

## 8. 검색 백엔드 (`api/search.py`)

FastAPI. **호스트 PC 에서만** 동작하며 클라우드에 배포되지 않는다(`localhost:8000/8001`).

```
질의 → 임베딩(sentence-transformers) ┐
                                     ├→ hybrid_search RPC (FTS + vector, RRF) → 상위 청크
질의 → 전문 검색(FTS)                ┘                                            ↓
                                                              Claude API 로 답변 생성 (/ai-search)
```

문서는 `pipeline/chunker.py` 로 청크화해 임베딩과 함께 적재한다.
백엔드가 꺼져 있으면 `/search`·`/ai-search` 두 화면만 동작하지 않고 나머지는 정상이다.

---

## 9. 배포 경로

```
npm run build      → dist/            대시보드
npm run build:pwa  → employee-pwa/dist/
npm run bundle:pwa → dist/pwa/        PWA 를 대시보드 산출물 안으로 복사
npm run deploy     → gh-pages 브랜치  둘 다 한 번에
npm run deploy:pwa → gh-pages/pwa     PWA 만 (--dest pwa)
```

`vite.config.ts` 의 `base: '/asuraDB/'`, PWA 는 `base: '/asuraDB/pwa/'`.
해시 라우팅이라 하위 경로에서도 새로고침이 깨지지 않는다.

---

## 10. 설계상 정해둔 것들

- **라이트 테마 고정** (2026-07-29 확정). `src/style.css` 의 `:root` 라이트 토큰만 쓰고
  `.dark` 는 쓰지 않는다. 하드코딩 색 대신 시맨틱 토큰을 쓴다.
- **마진은 항상 판매가 기준** — `마진 = (판매가 − 원가) ÷ 판매가`. 역산은
  `판매가 = 원가 ÷ (1 − 마진)`. 원가 기준 산식은 어느 화면·문서에도 쓰지 않는다.
- **VAT** — 대리점가(`dist_price_pcs`·`dist_price_set`)는 VAT 포함가, 그 외 가격은 미포함가.
  인니 PPN 11% 기준으로 환산해 넣고 화면·CSV 에 포함 여부를 병기한다.
- **제원 표기는 영문·약어 통일** — `PAT` · `Size` · `PR` · `LI` · `SS` · `OD (mm)` ·
  `TD (mm)` · `Single (kg)` 처럼 단위까지 붙인다.
- **변경이력 기록이 작업의 일부** — 의미 있는 변경은 `docs/웹사이트_운영_변경이력.md` 에 남긴다.

근거와 세부 규칙은 [CLAUDE.md](CLAUDE.md) 와 [docs/AsuraDB_Development_Guide.md](docs/AsuraDB_Development_Guide.md) 에 있다.
