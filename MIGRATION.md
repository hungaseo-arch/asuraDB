# AsuraDB · React → Vue 3 마이그레이션 노트

> 마이그레이션 일자: 2026-05-17
> 원본: `asuradb_current/` (React 18 + TSX + shadcn/ui)
> 산출물: `asuradb_vue/` (Vue 3 + SFC + shadcn-vue 패턴)

---

## 1. 의존성 매핑 (Library mapping / Pemetaan pustaka)

| 영역 | React (AS-IS) | Vue (TO-BE) | 비고 |
|------|---------------|-------------|------|
| 프레임워크 | `react@18` + `react-dom` | `vue@3.5` | Composition API + `<script setup>` |
| 빌드 | `@vitejs/plugin-react-swc` | `@vitejs/plugin-vue` | Vite 5 공통 |
| 라우터 | `react-router-dom@6` (HashRouter) | `vue-router@4` (`createWebHashHistory`) | URL 패턴 동일 (`#/`) |
| 상태 | `zustand@5`, lifted `useState` | `pinia@2` (`useUiStore`) | 사이드바 상태 |
| 폼 (예정) | `react-hook-form` + `zod` | `vee-validate` + `zod` | 현재 페이지 사용 없음 |
| 데이터 패칭 (예정) | `@tanstack/react-query` | `@tanstack/vue-query` | 향후 Search API 연결 시 |
| UI 기반 | Radix UI + shadcn/ui | `reka-ui` (= Radix Vue) + 자체 shadcn-vue 패턴 | 핵심 6개 컴포넌트만 포팅 |
| 차트 | `recharts@2` (AreaChart, PieChart) | `vue-chartjs@5` + `chart.js@4` (Line+Fill, Doughnut) | RRF 시각화 컬러 동일 |
| 애니메이션 | `framer-motion@11` | `@vueuse/motion@2` + Vue `<Transition>` | stagger 효과는 단순화 |
| 아이콘(범용) | `lucide-react` | `lucide-vue-next` | API 동일 |
| 아이콘(브랜드) | `react-icons/si` (`SiNotion` 등) | 인라인 SVG 컴포넌트 (`components/icons/`) | 의존성 감소 |
| 토스트 | `sonner` | `vue-sonner` | API 거의 동일 |
| 유틸 | `clsx` + `tailwind-merge` | 동일 | `cn()` 그대로 유지 |
| 스타일 | TailwindCSS v4 + `tw-animate-css` | 동일 | 디자인 토큰 1:1 보존 |

---

## 2. 파일별 매핑 (File mapping)

| React (`asuradb_current/`) | Vue (`asuradb_vue/`) | 변경 사항 |
|---------------------------|---------------------|----------|
| `src/main.tsx` | `src/main.ts` | `createApp` + Pinia + Router + MotionPlugin |
| `src/App.tsx` | `src/App.vue` | `HashRouter`/`TooltipProvider`/`Toaster` → `reka-ui` `TooltipProvider` + `vue-sonner` |
| `src/index.css` | `src/style.css` | 100% 보존 (디자인 토큰 / `@theme inline` / `@layer base`) |
| `src/lib/utils.ts` | `src/lib/utils.ts` | 그대로 |
| `src/data/index.ts` | `src/data/index.ts` | 그대로 + `KpiItem`, `RoadmapPhase` 타입 명시 |
| `src/components/Layout.tsx` (242줄) | `src/components/Layout.vue` | `useState` → Pinia 스토어 / `NavLink` → `RouterLink` / `motion.aside` → CSS transition + Vue `<Transition>` |
| `src/pages/Dashboard.tsx` (246줄) | `src/views/Dashboard.vue` | `recharts` 차트 두 개 → `components/charts/` 분리 / `motion.div`(stagger) → `v-motion` |
| `src/pages/Search.tsx` (289줄) | `src/views/Search.vue` | `useState` × 5 → `ref` × 5 / `ResultCard` 인라인화 / per-card 상태 → `expandedMap` 객체 |
| `src/pages/Arch.tsx` (166줄) | `src/views/Arch.vue` | framer stagger 제거 / `cn()` 조건부 클래스 패턴 유지 |
| `src/pages/SettingsPage.tsx` (104줄) | `src/views/Settings.vue` | `Separator` (reka-ui 기반) 그대로 |
| `src/pages/not-found/Index.tsx` | `src/views/NotFound.vue` | `useLocation()` → `useRoute()` |
| `src/hooks/use-mobile.tsx`, `use-toast.ts` | (미포팅) | `@vueuse/core` `useMediaQuery` / `vue-sonner` 로 대체 가능 — 현재 사용처 없음 |
| `src/lib/react-router-dom-proxy.tsx` | (제거) | React 전용 — Vue Router는 표준 사용 |
| `src/lib/motion.ts` | (제거) | `@vueuse/motion` 디렉티브로 대체 |
| `src/components/ui/*` (40+ shadcn 컴포넌트) | `src/components/ui/{Badge,Button,Input,Separator,card,tooltip}` | **실제 사용한 6종만 포팅** (나머지 미사용) |
| `vite.config.ts` (커스텀 CDN 플러그인) | `vite.config.ts` (단순화) | `cdnPrefixImages()` 제거 — §6 참조 |
| `supabase/edge_function/**` | (그대로 복사 권장) | Deno 기반이라 프론트 마이그레이션과 무관 |

---

## 3. 패턴 변환 치트시트 (Pattern cheat sheet)

### 3-1. State

```tsx
// React
const [open, setOpen] = useState(false);
const toggle = () => setOpen(o => !o);
```

```vue
<!-- Vue (script setup) -->
const open = ref(false);
function toggle() { open.value = !open.value; }
```

### 3-2. Conditional classes

```tsx
className={cn('base', isActive && 'bg-primary')}
```

```vue
:class="cn('base', isActive && 'bg-primary')"
```

`cn()` 함수는 동일 (`src/lib/utils.ts`).

### 3-3. Event handler

```tsx
<button onClick={handleSearch}>검색</button>
```

```vue
<button @click="handleSearch">검색</button>
```

### 3-4. Conditional rendering

```tsx
{searching && <Spinner />}
{searched ? <Results /> : <Empty />}
```

```vue
<Spinner v-if="searching" />
<Results v-if="searched" />
<Empty v-else />
```

### 3-5. Two-way binding

```tsx
<input value={query} onChange={e => setQuery(e.target.value)} />
```

```vue
<Input v-model="query" />
```

### 3-6. Animation (framer-motion → @vueuse/motion)

```tsx
<motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }}>...</motion.div>
```

```vue
<div v-motion :initial="{ opacity: 0, y: 16 }" :enter="{ opacity: 1, y: 0 }">...</div>
```

> stagger 효과는 `@vueuse/motion` 단독으로는 약하므로, 필요 시 `<TransitionGroup>` + `transition-delay` 인덱스 계산 패턴으로 강화 권장.

### 3-7. Charts

| Recharts | vue-chartjs | 메모 |
|----------|-------------|------|
| `<AreaChart>` + 4× `<Area>` (stacked-like) | `<Line>` with `fill: true` × 4 dataset | 4개 dataset = 4개 영역 |
| `<linearGradient>` defs | `backgroundColor: color + '4D'` | 단색 알파로 단순화 |
| `<PieChart>` + `innerRadius={36} outerRadius={56}` | `<Doughnut>` + `cutout: '60%'` | 시각적 동일 |
| `<Tooltip contentStyle={...}>` | `options.plugins.tooltip` | 옵션 객체 형태 |
| `<ResponsiveContainer>` | wrapper div + `height` 인라인 | Chart.js는 부모 크기 따름 |

### 3-8. Routing

```tsx
<NavLink to="/search" end>검색</NavLink>
const navigate = useNavigate();
const location = useLocation();
```

```vue
<RouterLink to="/search">검색</RouterLink>
<script setup>
import { useRouter, useRoute } from 'vue-router';
const router = useRouter();
const route  = useRoute();
</script>
```

---

## 4. 디자인 토큰 / Tailwind 설정

- `src/style.css` 의 CSS 변수(`--background`, `--primary`, `--chart-1` 등)와 `@theme inline` 매핑은 React 버전과 **100% 동일**.
- 라이트/다크 토큰, 사이드바 토큰, 폰트 feature settings, 스크롤바 스타일 모두 보존.
- 다크 모드: `<html class="dark">` 로 강제 (현재). 시스템 모드 토글이 필요하면 `useDark()` from `@vueuse/core` 권장.

---

## 5. 미포팅 / 의도적 제외 (Not migrated)

| 항목 | 이유 | 대응 |
|------|------|------|
| 40+ shadcn/ui 컴포넌트 (Accordion, Dialog, Menubar, …) | 실제 사용처 없음 | 필요 시 shadcn-vue CLI 로 추가 — `npx shadcn-vue@latest add dialog` |
| `lovable-tagger` Vite 플러그인 | 외부 빌더 전용 | 제거 |
| `cdnPrefixImages()` 커스텀 플러그인 (vite.config.ts) | `public/images/**` 자산 없음 | §6 참조. 필요 시 복원 |
| `react-router-dom-proxy.tsx` + `__ROUTE_MESSAGING_ENABLED__` flag | React Router 내부 후킹 전용 | 제거 |
| `examples/third-party-integrations/stripe/` | 예제 (.tsx) | 신규 Stripe 통합 시 Vue 패턴으로 재작성 |
| `uploaded_files/**` | 빌드 산출물과 무관 | 제외 |
| `next-themes`, `embla-carousel-react`, `cmdk` 등 미사용 의존성 | 페이지에서 import 없음 | 의존성 제거 (clean install 시 자동) |

---

## 6. Custom Vite plugins — `cdnPrefixImages` 복원 가이드

React 프로젝트는 빌드 시 `/images/**` 참조를 `CDN_IMG_PREFIX` 환경변수로 다시 쓰는 자체 Babel 플러그인이 있었음. Vue 측에서 동일 기능이 필요하면:

1. Vue SFC AST는 `@vue/compiler-sfc` 의 `parse()` 결과를 사용.
2. `template` 블록의 `src`/`href`/`srcset` 속성, `style` 블록의 `url(...)`, `<script>` 내부 문자열 리터럴을 각각 처리.
3. Babel 기반 React 플러그인을 Vue 환경에 그대로 옮길 수 없으므로, 별도 PostCSS 플러그인 + Vue 트랜스폼 훅으로 분할 권장.

현재는 `public/images/**` 자산이 없어 **기본 비활성**.

---

## 7. Post-migration TODO

### 즉시 해야 할 일

- [ ] `npm install` → `npm run build` 로컬 검증
- [ ] 의존성 lockfile 커밋 (`package-lock.json`)
- [ ] CI 워크플로의 `npm run lint` / `test` 단계 Vue 기준으로 재작성
- [ ] `index.html` 의 `<html class="dark">` 디자인팀과 협의 (라이트 모드 토글 필요 여부)

### Phase 2 — 실데이터 연동

- [ ] `src/lib/supabase.ts` 신규 (`createClient(VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY)`)
- [ ] `views/Search.vue` 의 `mockResults` → `supabase.rpc('hybrid_search', { query_text, query_embedding, source_filter, match_count })` 호출
- [ ] 검색 디바운스 (`@vueuse/core` `useDebounceFn`) 적용
- [ ] 로딩/오류/빈 상태 일관화

### Phase 3 — Gmail 연동 UI

- [ ] `views/Mail.vue` 신규 — 초안 작성 (Gmail 라벨 PKDB)
- [ ] OAuth 콜백 페이지 (`/oauth/callback`) 라우트 추가
- [ ] 사이드바 `navItems` 에 Gmail 항목 추가

### Phase 4 — 타이어 판매 대시보드

- [ ] `views/Tire.vue` 신규 — `tire_sales` 테이블 조회 (지점/브랜드/기간 필터)
- [ ] `components/charts/SalesByBrand.vue` (AGR vs ASCENDO 마진 비교)
- [ ] `components/charts/MonthlyRevenue.vue` (Surabaya / Semarang 비교)
- [ ] 모바일 반응형 점검 (테이블 → 카드 fallback)

### Phase 5 — PWA / 다국어

- [ ] `vite-plugin-pwa` 도입 + 매니페스트
- [ ] `vue-i18n` 도입 — 한국어/인도네시아어 (Bahasa Indonesia) 토글
- [ ] 검색 캐시 (`IndexedDB`)

---

## 8. 알려진 차이/주의 (Known differences)

1. **Stagger 애니메이션** — framer-motion `variants={stagger}` 는 단일 부모로 자식들을 순차 페이드인 시켰음. `@vueuse/motion` 만으로는 동일 효과 미지원이라 현재 단순 fade-up 만 적용. 필요 시 `TransitionGroup` + 인덱스 기반 `transition-delay` 패턴 추가 권장.
2. **Chart hover tooltip 스타일** — Chart.js 의 기본 tooltip 은 Recharts 와 색감이 약간 다름. 디자인팀 OK 받기 전까지는 디폴트 어두운 배경 사용.
3. **`asChild` prop** — React `Slot` 패턴은 Vue 에서 `as-child` prop 으로 대체되며, `reka-ui` 가 자동 처리. 단, `<RouterLink>` 안에 다중 자식이 있을 때는 명시적으로 `<RouterLink custom v-slot="{ ... }">` 패턴이 필요할 수 있음.
4. **Tailwind v4 `@apply` 와 SFC `<style scoped>`** — 가급적 `class` 인라인 사용 권장. SFC scoped 안에서 `@apply` 는 동작하지만 빌드 시간이 늘어남.
5. **다크 모드** — 현재 `<html class="dark">` 하드코딩. `index.html` 에서 제어. 동적 토글 미구현.

---

*문의 사항은 `README.md` §6 또는 `AsuraDB_Development_Guide.md` 참고.*
