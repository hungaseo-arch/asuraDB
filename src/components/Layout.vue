<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';
import {
  Home, Search, BrainCircuit, ClipboardList, BarChart3, Ship, Percent, Store,
  FolderOpen, Package, RefreshCw, LogOut, Scale, Gauge,
} from 'lucide-vue-next';
import { signOut } from '@/lib/auth';
import AsuraLogo from '@/components/icons/AsuraLogo.vue';
import { cn } from '@/lib/utils';
import { API_BASE, LAUNCHER_BASE } from '@/lib/api';

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
      { to: '/monitor',      icon: BarChart3, label: 'KPI — 핵심성과지표', short: 'KPI', badge: null },
      { to: '/margin',       icon: Percent,   label: '마진 — 마진분석',    short: '마진', badge: null },
      { to: '/branch-sales', icon: Store,     label: '지점 — 지점실적',    short: '지점', badge: null },
    ],
  },
  {
    key: 'sales', label: '영업·견적',
    items: [
      { to: '/quote',         icon: ClipboardList, label: '견적 — 견적서',        short: '견적', badge: null },
      { to: '/price-compare', icon: Scale,         label: '가격비교',             short: '가격비교', badge: null },
      { to: '/load-calc',     icon: Gauge,         label: '하중 — 하중·규격 조회', short: '하중', badge: null },
    ],
  },
  {
    key: 'ops', label: '운영·데이터',
    items: [
      { to: '/tire-import', icon: Ship,       label: '수입 — 수입관리',   short: '수입', badge: null },
      { to: '/databases',   icon: Package,    label: 'DB — 데이터베이스', short: 'DB', badge: null },
      { to: '/docs',        icon: FolderOpen, label: '정리 — 데이터 정리', short: '정리', badge: null },
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
function toggleGroup(key: string) { openGroup.value = openGroup.value === key ? null : key; }
function closeGroups() { openGroup.value = null; }
function onWindowClick(e: MouseEvent) {
  if (!(e.target as HTMLElement).closest?.('[data-navgroup]')) closeGroups();
}
function groupActive(g: NavGroup): boolean { return g.items.some(it => isActive(it.to!, it.exact)); }

const isRefreshing = ref(false);
const apiOnline = ref<boolean | null>(null);

async function checkApiOnline() {
  try {
    const res = await fetch(`${API_BASE}/health`, { signal: AbortSignal.timeout(3000) });
    apiOnline.value = res.ok;
  } catch {
    apiOnline.value = false;
  }
}

async function startApi() {
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

// 상태 배지 = 새로고침 버튼: 페이지 데이터 새로고침 + API 상태 갱신(오프라인이면 기동)
async function refreshAll() {
  window.dispatchEvent(new CustomEvent('asura:refresh'));
  if (apiOnline.value === false) { await startApi(); return; }
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
  void ensureApiRunning();
  startHeartbeat();
  void maybeDailyCollect();
  window.addEventListener('click', onWindowClick);
});

onUnmounted(() => {
  alive = false;
  stopHeartbeat();
  window.removeEventListener('click', onWindowClick);
});

const route = useRoute();

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
      <!-- ② 메뉴바(가운데) — 3그룹 드롭다운 (경영·성과 / 영업·견적 / 운영·데이터) -->
      <!-- 드롭다운이 잘리지 않도록 overflow 없음 (그룹 3개는 좁은 화면에서도 수용) -->
      <nav v-if="!isQuoteOnly" class="shrink-0 flex items-center justify-center gap-1 px-1">
        <div v-for="g in NAV_GROUPS" :key="g.key" class="relative" data-navgroup>
          <button
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
            <div v-if="openGroup === g.key" class="absolute left-1/2 -translate-x-1/2 top-full mt-1.5 z-50 min-w-48 rounded-xl border border-border bg-card shadow-xl p-1.5">
              <RouterLink
                v-for="item in g.items" :key="item.to" :to="item.to!" :title="item.label"
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
          <!-- 상태 + 새로고침 통합 버튼 -->
          <button
            :disabled="isRefreshing"
            class="inline-flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-md border transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            :class="apiOnline === false
              ? 'border-red-500/30 text-red-600 hover:bg-red-400/10'
              : 'border-green-500/30 text-green-600 hover:bg-green-500/10'"
            :title="apiOnline === false ? 'API 오프라인 · 클릭하여 기동·새로고침' : '시스템 정상 · 클릭하여 새로고침'"
            @click="refreshAll"
          >
            <RefreshCw :size="11" :class="isRefreshing && 'animate-spin'" />
            {{ apiOnline === false ? 'API 오프라인' : '시스템 정상' }}
          </button>
          <div class="h-7 px-2.5 rounded-full bg-primary/20 flex items-center justify-center text-xs font-bold text-primary whitespace-nowrap">
            {{ roleLabel }}
          </div>
          <button
            class="h-7 w-7 rounded-full flex items-center justify-center text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
            title="로그아웃"
            @click="handleLogout"
          >
            <LogOut :size="14" />
          </button>
        </div>
      </header>

      <!-- Page Content -->
      <main class="flex-1 overflow-y-auto">
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
