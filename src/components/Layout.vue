<script setup lang="ts">
import { computed, ref, watch, nextTick, onMounted, onUnmounted } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';
import {
  Home, Search, BrainCircuit, ClipboardList, BarChart3, Ship, Percent, Store,
  FolderOpen, Package, RefreshCw, LogOut, Scale, Gauge, BookMarked, Wallet, ScanSearch, Menu,
} from 'lucide-vue-next';
import { signOut } from '@/lib/auth';
import AsuraLogo from '@/components/icons/AsuraLogo.vue';
import { cn } from '@/lib/utils';
import { API_BASE, LAUNCHER_BASE, IS_HOST } from '@/lib/api';
import { SB_URL, sbHeaders } from '@/lib/supabase';

interface NavItem {
  to?: string;
  href?: string;
  icon: typeof Search;
  label: string;
  short?: string;
  badge: string | null;
  exact?: boolean;
}

const router = useRouter();
const auth = sessionStorage.getItem('asura_auth');
// 4역할 모델: super_admin/staff = 권한 풀, distributor/end_user = 견적서만
const isPrivileged = auth === 'super_admin' || auth === 'staff';
const isQuoteOnly  = !isPrivileged;

// 역할 뱃지 라벨
const roleLabel =
  auth === 'super_admin' ? 'Admin'
  : auth === 'staff'        ? 'Staff'
  : auth === 'distributor'  ? 'Distributor'
  : 'Customer';

async function handleLogout() {
  await signOut();
  router.replace('/login');
}

// ── 3그룹 재분류: 경영·성과 / 영업·견적 / 운영·데이터 (3그룹 × 3페이지) ──────
interface NavGroup { key: string; label: string; items: NavItem[] }
const NAV_GROUPS: NavGroup[] = [
  {
    key: 'perf', label: '경영·성과',
    items: [
      { to: '/monitor',      icon: BarChart3, label: 'KPI — 핵심성과', short: 'KPI', badge: null },
      { to: '/margin',       icon: Percent,   label: '마진 — 마진분석',    short: '마진', badge: null },
      { to: '/branch-sales', icon: Store,     label: '지점 — 지점실적',    short: '지점', badge: null },
      { to: '/labor-cost',   icon: Wallet,    label: '인건비 — 인건비현황', short: '인건비', badge: null },
    ],
  },
  {
    key: 'sales', label: '영업·견적',
    items: [
      { to: '/quote',         icon: ClipboardList, label: '견적 — 견적서',        short: '견적', badge: null },
      { to: '/price-compare', icon: Scale,         label: '가격비교 - 경쟁제품',             short: '가격비교', badge: null },
      { to: '/databases',     icon: Package,       label: 'DB — 데이터베이스',    short: 'DB', badge: null },
    ],
  },
  {
    key: 'ref', label: '조회·검토',
    items: [
      { to: '/tools/dot-lookup', icon: ScanSearch, label: 'DOT 조회 — 공장코드', short: 'DOT', badge: null },
      { to: '/tire-import',      icon: Ship,       label: '수입 조회 — BPS자료',    short: '수입', badge: null },
      { to: '/load-calc',        icon: Gauge,      label: '하중 조회 — 차량하중',    short: '하중', badge: null },
    ],
  },
  {
    key: 'docs', label: '자료·문서',
    items: [
      { to: '/docs',     icon: FolderOpen, label: '회사자료 — 주요문서', short: 'ASC', badge: null },
      { to: '/seo-docs', icon: BookMarked, label: '개인자료 — 관심사항', short: 'SEO', badge: null },
    ],
  },
];

// 고객 전용(distributor/end_user)은 견적서 + 가격비교만 평면 노출 (그룹 없음)
const quoteOnlyItems: NavItem[] = [
  { to: '/quote',         icon: ClipboardList, label: '견적서 작성', short: '견적', badge: null },
  { to: '/price-compare', icon: Scale,         label: '가격비교',    short: '가격비교', badge: null },
];

// 드롭다운 열림 상태
const openGroup = ref<string | null>(null);

// 키보드 조작용 DOM 조회 — 그룹 래퍼에 data-navgroup="<key>" 를 달아 두고 그 안에서 찾는다
function menuItems(key: string): HTMLElement[] {
  const menu = document.querySelector(`[data-navgroup="${key}"] [role="menu"]`);
  return Array.from(menu?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? []);
}
function groupTrigger(key: string): HTMLElement | null {
  return document.querySelector<HTMLElement>(`[data-navgroup="${key}"] > button`);
}

async function toggleGroup(key: string) {
  const opening = openGroup.value !== key;
  openGroup.value = opening ? key : null;
  // 열면 첫 항목으로 포커스를 옮긴다 — 키보드만으로 메뉴 진입이 가능해진다
  if (opening) { await nextTick(); menuItems(key)[0]?.focus(); }
}

function closeGroups() { openGroup.value = null; mobileNavOpen.value = false; }

// Escape·포커스 이탈로 닫을 때는 열었던 트리거로 포커스를 되돌린다(포커스 유실 방지).
// closeGroups 는 RouterLink @click 핸들러로도 쓰여 이벤트 객체를 받으므로 별 함수로 분리.
function closeGroupsAndRestore() {
  const key = openGroup.value;
  closeGroups();
  if (key) groupTrigger(key)?.focus();
}

function onWindowClick(e: MouseEvent) {
  if (!(e.target as HTMLElement).closest?.('[data-navgroup]')) openGroup.value = null;
}

// Escape 로도 닫는다(외부 클릭·라우트 이동과 함께 3경로 모두 차단).
// 메뉴가 열려 있으면 ↑/↓ 로 항목 이동, Tab 은 메뉴 안에 가둔다(포커스 트랩 — 탈출은 Esc).
function onWindowKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') { closeGroupsAndRestore(); return; }

  const key = openGroup.value;
  if (!key || !['ArrowDown', 'ArrowUp', 'Tab'].includes(e.key)) return;
  const items = menuItems(key);
  if (!items.length) return;

  const cur = items.indexOf(document.activeElement as HTMLElement);
  e.preventDefault();
  const forward = e.key === 'ArrowDown' || (e.key === 'Tab' && !e.shiftKey);
  const next = forward
    ? (cur + 1) % items.length
    : (cur <= 0 ? items.length - 1 : cur - 1);
  items[next].focus();
}
function groupActive(g: NavGroup): boolean { return g.items.some(it => isActive(it.to!, it.exact)); }

// 모바일(<md) 네비게이션 드로어 — 좁은 폭에서 헤더 메뉴가 겹치지 않도록 분리
const mobileNavOpen = ref(false);

const isRefreshing = ref(false);
const apiOnline = ref<boolean | null>(null);
// 데이터 백엔드(Supabase) 상태 — KPI·마진·DB·견적 등 대부분의 화면이 여기에 의존한다.
// 검색 API(8000)와 별개라 하나만 죽어도 '일부 지연'으로 구분해 알린다.
const dbOnline = ref<boolean | null>(null);

// 이하 검색 API(8000)·런처(8001) 관련 함수는 모두 호스트 PC 에서만 실제 요청을 보낸다.
// 배포본(HTTPS)에서 http://localhost 를 호출하면 mixed content 로 차단되고,
// 하트비트가 7초마다 무한 재시도해 콘솔 에러·불필요한 트래픽만 남는다.
async function checkApiOnline() {
  if (!IS_HOST) { apiOnline.value = null; return; }
  try {
    const res = await fetch(`${API_BASE}/health`, { signal: AbortSignal.timeout(3000) });
    apiOnline.value = res.ok;
  } catch {
    apiOnline.value = false;
  }
}

async function checkDbOnline() {
  try {
    // 가장 가벼운 호출 — 행을 받지 않고 응답 코드만 본다
    const res = await fetch(`${SB_URL}/rest/v1/products?select=id&limit=1`, {
      headers: await sbHeaders(), signal: AbortSignal.timeout(4000),
    });
    dbOnline.value = res.ok;
  } catch {
    dbOnline.value = false;
  }
}

// 배포본(호스트 PC 아님)에서는 검색 API 가 원래 닿지 않으므로 장애로 세지 않는다.
const apiCounts = computed(() => IS_HOST);
const downServices = computed(() => {
  const down: string[] = [];
  if (apiCounts.value && apiOnline.value === false) down.push('검색 API');
  if (dbOnline.value === false) down.push('데이터(Supabase)');
  return down;
});
const statusTone = computed<'ok' | 'partial' | 'down'>(() => {
  const total = (apiCounts.value ? 1 : 0) + 1;
  if (!downServices.value.length) return 'ok';
  return downServices.value.length >= total ? 'down' : 'partial';
});
const statusLabel = computed(() =>
  statusTone.value === 'ok' ? '시스템 정상'
  : statusTone.value === 'down' ? '시스템 오프라인'
  : `일부 지연 · ${downServices.value.join('·')}`,
);
const statusTitle = computed(() =>
  statusTone.value === 'ok'
    ? `시스템 정상 — ${apiCounts.value ? '검색 API · ' : ''}데이터(Supabase) 응답 확인 · 클릭하여 새로고침`
    : `연결 실패: ${downServices.value.join(', ')} · 클릭하여 기동·새로고침`,
);

async function startApi() {
  if (!IS_HOST) return;
  if (isRefreshing.value) return;
  isRefreshing.value = true;
  try {
    await fetch(`${LAUNCHER_BASE}/start`, { method: 'POST', signal: AbortSignal.timeout(3000) });
  } catch { /* 런처 미실행 시 무시 */ }
  for (let i = 0; i < 15; i++) {
    await new Promise(r => setTimeout(r, 1000));
    try {
      const res = await fetch(`${API_BASE}/health`, { signal: AbortSignal.timeout(2000) });
      if (res.ok) { isRefreshing.value = false; return; }
    } catch { /* 기동 대기 중 */ }
  }
  isRefreshing.value = false;
}

// 상태 배지 = 새로고침 버튼: 페이지 데이터 새로고침 + 의존 서비스 상태 갱신(API 오프라인이면 기동)
async function refreshAll() {
  window.dispatchEvent(new CustomEvent('asura:refresh'));
  void checkDbOnline();
  if (apiCounts.value && apiOnline.value === false) { await startApi(); return; }
  if (isRefreshing.value) return;
  isRefreshing.value = true;
  await checkApiOnline();
  isRefreshing.value = false;
}

// ── API 자동 기동/유지 (런처 8001 경유) ──────────────────────────────────────
// 앱이 열려 있는 동안 하트비트로 API(8000)를 살려두고,
// 탭을 닫으면 하트비트가 끊겨 런처가 유휴 타임아웃 후 자동 종료한다.
let hbTimer: number | undefined;
let alive = true;  // 언마운트 후 폴링 루프가 죽은 컴포넌트의 ref를 건드리지 않도록

async function ensureApiRunning() {
  if (!IS_HOST) return;
  try {
    await fetch(`${LAUNCHER_BASE}/start`, { method: 'POST', signal: AbortSignal.timeout(3000) });
  } catch { /* 런처 미실행 시 무시 */ }
  for (let i = 0; i < 15 && alive; i++) {
    await new Promise(r => setTimeout(r, 1000));
    if (!alive) return;
    await checkApiOnline();
    if (apiOnline.value) return;
  }
}

function startHeartbeat() {
  if (!IS_HOST) return;
  if (hbTimer !== undefined) return;
  hbTimer = window.setInterval(() => {
    fetch(`${LAUNCHER_BASE}/heartbeat`, { method: 'POST', keepalive: true }).catch(() => {});
  }, 7000);
}

function stopHeartbeat() {
  if (hbTimer !== undefined) { clearInterval(hbTimer); hbTimer = undefined; }
}

// 하루 1회: 로그인/앱 진입 시점 기준으로 수집기를 돌려 비어있는 이전 자료까지 catch-up.
// (yfinance 환율·브렌트/파생 KRW·IDR + 스크래퍼 매크로. 수동 전용 원자재는 소스 없어 제외)
async function maybeDailyCollect() {
  if (!IS_HOST) return;   // 수집기는 호스트 PC 의 로컬 백엔드에만 있다
  const today = new Date().toISOString().slice(0, 10);
  if (localStorage.getItem('asura_last_collect') === today) return;
  localStorage.setItem('asura_last_collect', today);
  try {
    await ensureApiRunning();  // 런처/ API 기동 보장 후 수집 트리거
    void fetch(`${LAUNCHER_BASE}/collect`, { method: 'POST', keepalive: true }).catch(() => {});
  } catch { /* 런처 미가동 시 조용히 무시 */ }
}

onMounted(() => {
  void checkApiOnline();
  void checkDbOnline();
  void ensureApiRunning();
  startHeartbeat();
  void maybeDailyCollect();
  window.addEventListener('click', onWindowClick);
  window.addEventListener('keydown', onWindowKeydown);
});

onUnmounted(() => {
  alive = false;
  stopHeartbeat();
  window.removeEventListener('click', onWindowClick);
  window.removeEventListener('keydown', onWindowKeydown);
});

const route = useRoute();

// 라우트가 바뀌면 ① 열린 메뉴를 닫고 ② 본문 스크롤을 맨 위로 되돌린다.
// 스크롤 컨테이너가 window 가 아니라 <main> 이라 라우터 scrollBehavior 로는 처리되지 않는다.
const mainEl = ref<HTMLElement | null>(null);
watch(() => route.fullPath, () => {
  closeGroups();
  mainEl.value?.scrollTo({ top: 0 });
});

function isActive(to: string, exact?: boolean): boolean {
  return exact ? route.path === to : route.path === to || route.path.startsWith(`${to}/`);
}

// 상단 브랜드 우측에 표시할 현재 상세페이지 제목 (홈에서는 숨김)
const pageTitle = computed(() =>
  route.path === '/home' ? '홈' : ((route.meta?.title as string | undefined) ?? ''),
);
</script>

<template>
  <div class="flex flex-col h-screen w-full overflow-hidden bg-background text-foreground">
    <!-- 키보드 사용자용 본문 바로가기 — 포커스를 받을 때만 나타난다 -->
    <a href="#main-content"
       class="sr-only focus:not-sr-only focus:absolute focus:z-100 focus:top-2 focus:left-2 focus:px-3 focus:py-2 focus:rounded-lg focus:bg-card focus:border focus:border-primary focus:text-sm focus:font-semibold focus:text-primary focus:shadow-lg">
      본문 바로가기
    </a>
    <!-- Top navigation bar -->
    <header class="flex items-center gap-2 h-14 px-3 sm:px-4 border-b border-border bg-card shrink-0 print:hidden">
      <!-- ① 브랜드 + 현재 상세페이지 제목(좌) -->
      <div class="flex-1 min-w-0 flex items-center gap-2.5">
        <RouterLink to="/home" class="flex items-center gap-2 shrink-0" title="홈">
          <AsuraLogo :size="30" class="shrink-0" style="filter: drop-shadow(0 0 8px rgba(38,126,255,0.5));" />
          <span class="font-bold text-xl text-foreground hidden sm:inline">AsuraDB</span>
        </RouterLink>
        <template v-if="pageTitle">
          <span class="h-6 w-px bg-border shrink-0 hidden sm:block" />
          <span class="text-sm font-semibold text-foreground truncate">{{ pageTitle }}</span>
        </template>
      </div>
      <!-- ② 메뉴바(가운데) — 그룹 드롭다운 (경영·성과 / 영업·견적 / 운영·데이터 / SEO자료) -->
      <!-- 드롭다운이 잘리지 않도록 overflow 없음. 좁은 폭(<lg)에서는 아래 햄버거 드로어로 대체 -->
      <nav v-if="!isQuoteOnly" class="shrink-0 hidden lg:flex items-center justify-center gap-1 px-1">
        <div v-for="g in NAV_GROUPS" :key="g.key" class="relative" :data-navgroup="g.key">
          <!-- 항목이 하나뿐인 그룹은 드롭다운 없이 바로 이동 (2번 클릭 방지) -->
          <RouterLink
            v-if="g.items.length === 1"
            :to="g.items[0].to!"
            :title="g.items[0].label"
            :class="cn(
              'flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap transition-colors',
              groupActive(g)
                ? 'bg-primary/15 text-primary font-semibold'
                : 'text-foreground/80 hover:bg-accent hover:text-accent-foreground',
            )"
            @click="closeGroups"
          >
            {{ g.label }}
          </RouterLink>
          <button
            v-else
            :aria-expanded="openGroup === g.key"
            aria-haspopup="menu"
            :class="cn(
              'flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap transition-colors',
              groupActive(g) || openGroup === g.key
                ? 'bg-primary/15 text-primary font-semibold'
                : 'text-foreground/80 hover:bg-accent hover:text-accent-foreground',
            )"
            @click="toggleGroup(g.key)"
          >
            {{ g.label }}
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" class="transition-transform" :class="openGroup === g.key && 'rotate-180'"><path d="m6 9 6 6 6-6"/></svg>
          </button>
          <transition enter-active-class="transition-opacity duration-100" enter-from-class="opacity-0" leave-active-class="transition-opacity duration-100" leave-to-class="opacity-0">
            <div v-if="openGroup === g.key" role="menu" class="absolute left-1/2 -translate-x-1/2 top-full mt-1.5 z-50 min-w-48 rounded-xl border border-border bg-card shadow-xl p-1.5">
              <RouterLink
                v-for="item in g.items" :key="item.to" :to="item.to!" :title="item.label"
                role="menuitem"
                :class="cn(
                  'flex items-center gap-2 px-2.5 py-2 rounded-lg text-sm whitespace-nowrap transition-colors',
                  isActive(item.to!, item.exact)
                    ? 'bg-primary/15 text-primary font-semibold'
                    : 'text-foreground/80 hover:bg-accent hover:text-accent-foreground',
                )"
                @click="closeGroups"
              >
                <component :is="item.icon" :size="15" class="shrink-0" />
                {{ item.label }}
              </RouterLink>
            </div>
          </transition>
        </div>
      </nav>
      <!-- 고객 전용: 견적서·가격비교 평면 메뉴 -->
      <nav v-else class="shrink-0 flex items-center justify-center gap-1 px-1 overflow-x-auto max-w-full">
        <RouterLink
          v-for="item in quoteOnlyItems" :key="item.to" :to="item.to!" :title="item.label"
          :class="cn(
            'flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap transition-colors',
            isActive(item.to!, item.exact)
              ? 'bg-primary/15 text-primary font-semibold'
              : 'text-foreground/80 hover:bg-accent hover:text-accent-foreground',
          )"
        >
          <component :is="item.icon" :size="15" class="shrink-0" />
          <span class="hidden md:inline">{{ item.short ?? item.label }}</span>
        </RouterLink>
      </nav>
      <!-- ③ 상태·역할·로그아웃(우) -->
      <div class="flex-1 min-w-0 flex items-center justify-end gap-2">
          <!-- 상태 + 새로고침 통합 버튼. 좁은 폭에서는 아이콘만(라벨은 title 로) -->
          <button
            :disabled="isRefreshing"
            class="inline-flex items-center gap-1.5 text-xs px-2 sm:px-2.5 py-1 rounded-md border transition-colors disabled:opacity-50 disabled:cursor-not-allowed whitespace-nowrap"
            :class="statusTone === 'down'
              ? 'border-red-500/30 text-red-600 hover:bg-red-400/10'
              : statusTone === 'partial'
                ? 'border-amber-500/40 text-amber-600 hover:bg-amber-400/10'
                : 'border-green-500/30 text-green-600 hover:bg-green-500/10'"
            :title="statusTitle"
            :aria-label="statusTitle"
            @click="refreshAll"
          >
            <RefreshCw :size="11" :class="isRefreshing && 'animate-spin'" />
            <span class="hidden sm:inline">{{ statusLabel }}</span>
          </button>
          <div class="h-7 px-2.5 rounded-full bg-primary/20 hidden sm:flex items-center justify-center text-xs font-bold text-primary whitespace-nowrap">
            {{ roleLabel }}
          </div>
          <button
            class="h-7 w-7 rounded-full flex items-center justify-center text-muted-foreground hover:text-foreground hover:bg-accent transition-colors shrink-0"
            title="로그아웃"
            aria-label="로그아웃"
            @click="handleLogout"
          >
            <LogOut :size="14" />
          </button>
          <!-- 햄버거 — 좁은 폭 전용 메뉴 드로어 토글 -->
          <button
            v-if="!isQuoteOnly"
            class="lg:hidden h-7 w-7 rounded-md flex items-center justify-center text-foreground/80 hover:bg-accent transition-colors shrink-0"
            :aria-expanded="mobileNavOpen"
            aria-controls="mobile-nav"
            :aria-label="mobileNavOpen ? '메뉴 닫기' : '메뉴 열기'"
            data-navgroup="mobile"
            @click="mobileNavOpen = !mobileNavOpen"
          >
            <Menu :size="18" />
          </button>
        </div>
      </header>

      <!-- 모바일 네비게이션 드로어 (<lg) — 그룹별 전체 메뉴를 세로로 펼친다 -->
      <div v-if="mobileNavOpen && !isQuoteOnly" id="mobile-nav" data-navgroup
           class="lg:hidden border-b border-border bg-card shadow-lg max-h-[70vh] overflow-y-auto px-3 py-2 print:hidden">
        <div v-for="g in NAV_GROUPS" :key="g.key" class="py-1.5">
          <p class="px-1 pb-1 text-[11px] font-semibold text-muted-foreground">{{ g.label }}</p>
          <div class="grid grid-cols-2 gap-1">
            <RouterLink
              v-for="item in g.items" :key="item.to" :to="item.to!"
              :class="cn(
                'flex items-center gap-2 px-2.5 py-2 rounded-lg text-sm transition-colors',
                isActive(item.to!, item.exact)
                  ? 'bg-primary/15 text-primary font-semibold'
                  : 'text-foreground/80 hover:bg-accent hover:text-accent-foreground',
              )"
              @click="closeGroups"
            >
              <component :is="item.icon" :size="15" class="shrink-0" />
              <span class="truncate">{{ item.short ?? item.label }}</span>
            </RouterLink>
          </div>
        </div>
      </div>

      <!-- Page Content -->
      <main id="main-content" ref="mainEl" class="flex-1 overflow-y-auto">
        <!-- 각 화면의 대표 제목(h1). 화면 디자인은 그대로 두고 heading 계층만 세운다
             (h1 = 페이지 제목 → 화면 안의 섹션 제목은 h2) -->
        <h1 class="sr-only">{{ pageTitle || 'AsuraDB' }}</h1>
        <RouterView />
    </main>
  </div>
</template>

<style>
/* 인쇄 시: 앱셸의 h-screen + overflow-hidden + main의 overflow-y-auto가
   콘텐츠를 1페이지에 잘라버리므로, 자연스럽게 흐르도록 해제 */
@media print {
  html, body { height: auto !important; overflow: visible !important; background: #fff !important; }
  body > * { height: auto !important; overflow: visible !important; }
  .h-screen,
  .h-full { height: auto !important; }
  .overflow-hidden,
  .overflow-y-auto { overflow: visible !important; }
}
</style>
