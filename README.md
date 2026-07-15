# AsuraDB — Vue 3 + TailwindCSS

> Personal Knowledge DB 검색 시스템 — React 18 → Vue 3 마이그레이션 완료본
> Sumber kode (Source code) / 소스 코드: Vue 3 + Vite + TypeScript + TailwindCSS v4 + shadcn-vue 패턴

---

## 1. 빠른 시작 (Quick start / Mulai cepat)

```bash
# 1) 의존성 설치
npm install

# 2) 개발 서버 (포트 8080)
npm run dev

# 3) 프로덕션 빌드
npm run build

# 4) 빌드 결과 미리보기
npm run preview

# 5) 타입 검사만 별도 실행
npm run type-check
```

브라우저: `http://localhost:8080`

---

## 2. 기술 스택 (Stack / Tumpukan)

| 레이어 | 라이브러리 | 메모 |
|--------|----------|------|
| Framework | Vue 3.5 (`<script setup lang="ts">`) | Composition API 전용 |
| 빌드 도구 | Vite 5 + `@vitejs/plugin-vue` | React SWC 대체 |
| 언어 | TypeScript 5.5 + `vue-tsc` | 타입 검사 |
| 스타일 | TailwindCSS v4 + `@tailwindcss/vite` + `tw-animate-css` | React 버전과 동일 토큰 |
| UI 컴포넌트 | `reka-ui` (Tooltip, Separator) + shadcn-vue 패턴 자체 작성 | Card · Badge · Button · Input |
| 라우터 | `vue-router` 4 + `createWebHashHistory` | React `HashRouter` 대체 |
| 상태 관리 | `pinia` 2 | React `useState` 리프트 대체 |
| 차트 | `chart.js` 4 + `vue-chartjs` 5 | recharts 대체 |
| 애니메이션 | `@vueuse/motion` + Vue Transition | `framer-motion` 대체 |
| 아이콘 | `lucide-vue-next` + 인라인 SVG (Notion/Gmail/Drive) | `react-icons` 대체 |
| 토스트 | `vue-sonner` | `sonner` Vue 포팅 |
| 유틸 | `clsx` + `tailwind-merge` | `cn()` 유지 |

---

## 3. 폴더 구조 (Struktur folder)

```
asuradb_vue/
├── index.html
├── package.json
├── vite.config.ts
├── tsconfig*.json
├── README.md              ← 본 문서
├── docs/                  ← 프로젝트 문서 (개발 지침 · 가이드 · 운영이력)
│   ├── AsuraDB_Development_Guide.md   ← 아키텍처·스키마·연결/보안(§11)·로드맵·부록 A(마이그레이션)
│   ├── AsuraDB_지표수집_가이드.md      ← 외부 거시·시장 지표 24종 수집
│   └── 웹사이트_운영_변경이력.md       ← 월간 비즈니스 데이터 갱신 절차 + 변경이력
└── src/
    ├── main.ts                              엔트리 (Pinia + Router + MotionPlugin)
    ├── App.vue                              루트 (TooltipProvider, Toaster, RouterView)
    ├── style.css                            Tailwind v4 + design tokens
    ├── env.d.ts
    ├── router/index.ts                      Hash routing
    ├── stores/ui.ts                         Pinia (사이드바 상태)
    ├── data/index.ts                        Mock 데이터 (1:1 포팅)
    ├── lib/utils.ts                         cn() 헬퍼
    ├── components/
    │   ├── Layout.vue                       사이드바 + 탑바
    │   ├── icons/                           Notion · Gmail · Drive · SourceIcon
    │   ├── charts/                          SearchVolume · SourceDistribution
    │   └── ui/                              Badge · Button · Input · Separator
    │       ├── card/                        Card, CardHeader, CardTitle, CardContent
    │       └── tooltip/                     Tooltip, TooltipTrigger, TooltipContent
    └── views/
        ├── Dashboard.vue                    `/`
        ├── Search.vue                       `/search`
        ├── Arch.vue                         `/arch`
        ├── Settings.vue                     `/settings`
        └── NotFound.vue                     404
```

---

## 4. 라우트 (Routes)

| 경로 | 컴포넌트 | 설명 |
|------|---------|------|
| `#/`         | `views/Dashboard.vue` | KPI · 검색량 차트 · 소스 분포 · 최근 활동 |
| `#/search`   | `views/Search.vue`    | FTS + Vector (RRF) 하이브리드 검색 |
| `#/arch`     | `views/Arch.vue`      | 시스템 흐름도 + 5단계 로드맵 |
| `#/settings` | `views/Settings.vue`  | 데이터 소스 / API 키 / 동기화 주기 / 검색 설정 |

---

## 5. 환경변수 (.env)

`docs/AsuraDB_Development_Guide.md` §9 참조. Vue 환경에서는 모든 클라이언트 노출용 키에 `VITE_` 접두사 필수.

```bash
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJ...
# 서버사이드 전용 키는 절대 VITE_ 접두사 금지
SUPABASE_SERVICE_KEY=eyJ...
ANTHROPIC_API_KEY=sk-ant-...
```

---

## 6. 다음 작업 (Next steps / Langkah berikutnya)

`docs/AsuraDB_Development_Guide.md` §7 로드맵 / §13 구현현황을 따라 진행. 핵심:

1. `@supabase/supabase-js` 클라이언트 초기화 (`src/lib/supabase.ts`)
2. `mockResults` → `hybrid_search` RPC 실제 호출 전환 (`views/Search.vue`)
3. Pinia 스토어 추가 (검색 기록 / 소스 필터 영속화)
4. Phase 4 — 타이어 판매 대시보드 (`/tire`) 신규 페이지
5. PWA 매니페스트 + 서비스 워커 (Phase 5)

---

*마이그레이션 일자: 2026-05-17 · 작업자: ASURA (PT Ascendo International)*
# asuradb
# asuradb
# asuradb
# asuraDB
