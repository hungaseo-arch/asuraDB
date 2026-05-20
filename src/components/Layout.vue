<script setup lang="ts">
import { computed, ref, onMounted } from 'vue';
import { RouterLink, RouterView, useRoute } from 'vue-router';
import {
  Search, BrainCircuit, FileBarChart2, ClipboardList,
  ChevronLeft, Menu, Circle, ExternalLink, RefreshCw,
} from 'lucide-vue-next';
import AsuraLogo from '@/components/icons/AsuraLogo.vue';
import { storeToRefs } from 'pinia';
import { useUiStore } from '@/stores/ui';
import Badge from '@/components/ui/Badge.vue';
import { Tooltip, TooltipTrigger, TooltipContent } from '@/components/ui/tooltip';
import NotionIcon from '@/components/icons/NotionIcon.vue';
import GmailIcon from '@/components/icons/GmailIcon.vue';
import GoogleDriveIcon from '@/components/icons/GoogleDriveIcon.vue';
import UpNoteIcon from '@/components/icons/UpNoteIcon.vue';
import ObsidianIcon from '@/components/icons/ObsidianIcon.vue';
import GoogleCalendarIcon from '@/components/icons/GoogleCalendarIcon.vue';
import NaverBandIcon from '@/components/icons/NaverBandIcon.vue';
import { cn } from '@/lib/utils';
import { API_BASE, LAUNCHER_BASE } from '@/lib/api';

type SourceStatus = 'synced' | 'syncing' | 'error' | 'planned';

interface NavItem {
  to?: string;
  href?: string;
  icon: typeof Search;
  label: string;
  badge: string | null;
  exact?: boolean;
}

interface SourceItem {
  icon: object;
  label: string;
  color: string;
  key: string;
  status: SourceStatus;
  lastSynced: string | null;
}

const isQuoteOnly = sessionStorage.getItem('asura_auth') === 'quote';

const allNavItems: NavItem[] = [
  { to: '/search',    icon: Search,          label: '통합 자료 검색', badge: null },
  { to: '/ai-search', icon: BrainCircuit,    label: 'AI 지식 Q&A',  badge: null },
  { to: '/report',    icon: FileBarChart2,   label: '자동화 레포트',   badge: null },
  { to: '/quote',     icon: ClipboardList,   label: '견적서 생성',     badge: null },
  { href: 'http://localhost:3000', icon: ExternalLink, label: 'Open WebUI', badge: null },
];

const navItems = isQuoteOnly
  ? allNavItems.filter(item => item.to === '/quote')
  : allNavItems;

const sourceItems = ref<SourceItem[]>([
  { icon: NotionIcon,         label: 'Notion',          color: '#e5e5e5', key: 'notion',   status: 'syncing', lastSynced: null },
  { icon: UpNoteIcon,         label: 'UpNote',          color: '#4ade80', key: 'upnote',   status: 'syncing', lastSynced: null },
  { icon: GmailIcon,          label: 'Gmail',           color: '#f87171', key: 'gmail',    status: 'syncing', lastSynced: null },
  { icon: GoogleDriveIcon,    label: 'Google Drive',    color: '#60a5fa', key: 'drive',    status: 'syncing', lastSynced: null },
  { icon: GoogleCalendarIcon, label: 'Google Calendar', color: '#4285F4', key: 'calendar', status: 'syncing', lastSynced: null },
  { icon: ObsidianIcon,       label: 'Obsidian',        color: '#a78bfa', key: 'obsidian', status: 'planned', lastSynced: null },
  { icon: NaverBandIcon,      label: 'Naver Band',      color: '#1DB446', key: 'band',     status: 'syncing', lastSynced: null },
]);

const statusDot: Record<string, string> = {
  synced:  'bg-green-400',
  syncing: 'bg-yellow-400 animate-pulse',
  error:   'bg-red-400',
  planned: 'bg-muted-foreground/40',
};

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

const SB_URL = import.meta.env.VITE_SB_URL as string;
const SB_KEY = import.meta.env.VITE_SB_KEY as string;
const SB_HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` };

async function sbGet<T>(table: string, qs: string): Promise<T[]> {
  const res = await fetch(`${SB_URL}/rest/v1/${table}?${qs}`, { headers: SB_HEADERS });
  if (!res.ok) throw new Error(`${table} ${res.status}`);
  return res.json() as Promise<T[]>;
}

function formatLocal(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function localDateStr(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

async function fetchSourceStatuses() {
  try {
    const now = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');
    const today = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;

    const hbRows = await sbGet<{ source: string; last_run: string }>(
      'collector_heartbeat', 'select=source,last_run',
    );

    const heartbeats: Record<string, string> = {};
    for (const row of hbRows) heartbeats[row.source] = row.last_run;

    for (const item of sourceItems.value) {
      if (item.key === 'obsidian') continue;

      let lastUpdated = heartbeats[item.key] ?? null;

      if (!lastUpdated) {
        const rows = await sbGet<{ updated_at: string }>(
          'documents',
          `select=updated_at&source=eq.${item.key}&order=updated_at.desc&limit=1`,
        );
        lastUpdated = rows[0]?.updated_at ?? null;
      }

      item.lastSynced = lastUpdated;
      item.status = !lastUpdated ? 'error' : localDateStr(lastUpdated) === today ? 'synced' : 'error';
    }

  } catch (e) {
    console.error('[fetchSourceStatuses]', e);
  }
}

async function refreshSources() {
  if (isRefreshing.value) return;
  isRefreshing.value = true;
  sourceItems.value.forEach(item => {
    if (item.key !== 'obsidian') item.status = 'syncing';
  });
  await fetchSourceStatuses();
  isRefreshing.value = false;
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
      if (res.ok) { await fetchSourceStatuses(); isRefreshing.value = false; return; }
    } catch { /* 기동 대기 중 */ }
  }
  await fetchSourceStatuses();
  isRefreshing.value = false;
}

onMounted(() => {
  void fetchSourceStatuses();
  void checkApiOnline();
});

const ui = useUiStore();
const { sidebarCollapsed, mobileSidebarOpen } = storeToRefs(ui);
const route = useRoute();

function isActive(to: string, exact?: boolean): boolean {
  return exact ? route.path === to : route.path === to || route.path.startsWith(`${to}/`);
}

const asideWidthStyle = computed(() => ({
  width: sidebarCollapsed.value ? '64px' : '220px',
  transition: 'width 280ms cubic-bezier(.34,1.56,.64,1)',
  boxShadow: '4px 0 24px color-mix(in srgb, var(--primary) 8%, transparent)',
}));
</script>

<template>
  <div class="flex h-screen w-full overflow-hidden bg-background text-foreground">
    <!-- Mobile overlay -->
    <Transition
      enter-active-class="transition-opacity duration-200"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-200"
      leave-to-class="opacity-0"
    >
      <div
        v-if="mobileSidebarOpen"
        class="fixed inset-0 z-30 bg-black/60 md:hidden"
        @click="ui.closeMobileSidebar()"
      />
    </Transition>

    <!-- Desktop Sidebar -->
    <aside
      :style="asideWidthStyle"
      class="hidden md:flex flex-col h-full z-40 border-r border-border shrink-0 bg-card overflow-hidden relative"
    >
      <!-- Sidebar Content -->
      <!-- Logo -->
      <div class="flex items-center gap-2.5 h-14 px-4 border-b border-border shrink-0">
        <AsuraLogo :size="28" class="shrink-0" style="filter: drop-shadow(0 0 8px rgba(38,126,255,0.5));" />
        <Transition
          enter-active-class="transition-all duration-150"
          enter-from-class="opacity-0 -translate-x-2"
          leave-active-class="transition-all duration-150"
          leave-to-class="opacity-0 -translate-x-2"
        >
          <div v-if="!sidebarCollapsed" class="overflow-hidden">
            <div class="font-bold text-sm leading-tight text-foreground">AsuraDB</div>
            <div class="text-[10px] text-muted-foreground leading-tight">v1.0</div>
          </div>
        </Transition>
        <button
          class="ml-auto p-1 rounded-md hover:bg-accent transition-colors shrink-0"
          @click="ui.toggleSidebar()"
        >
          <Menu v-if="sidebarCollapsed" :size="14" />
          <ChevronLeft v-else :size="14" />
        </button>
      </div>

      <!-- Nav -->
      <nav class="flex-1 p-2 space-y-0.5 overflow-y-auto">
        <Tooltip v-for="item in navItems" :key="item.to ?? item.href" :delay-duration="0">
          <TooltipTrigger :as-child="true">
            <a
              v-if="item.href"
              :href="item.href"
              target="_blank"
              rel="noopener noreferrer"
              :class="cn(
                'flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm transition-all duration-150',
                'hover:bg-accent hover:text-accent-foreground text-muted-foreground',
                sidebarCollapsed && 'justify-center',
              )"
            >
              <component :is="item.icon" :size="16" class="shrink-0" />
              <span v-if="!sidebarCollapsed" class="overflow-hidden whitespace-nowrap flex-1">
                {{ item.label }}
              </span>
            </a>
            <RouterLink
              v-else
              :to="item.to!"
              :class="cn(
                'flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm transition-all duration-150',
                'hover:bg-accent hover:text-accent-foreground',
                isActive(item.to!, item.exact)
                  ? 'bg-primary/15 text-primary font-medium'
                  : 'text-muted-foreground',
                sidebarCollapsed && 'justify-center',
              )"
            >
              <component :is="item.icon" :size="16" class="shrink-0" />
              <span v-if="!sidebarCollapsed" class="overflow-hidden whitespace-nowrap flex-1">
                {{ item.label }}
              </span>
              <Badge
                v-if="item.badge && !sidebarCollapsed"
                class="text-[9px] px-1 py-0 h-4 bg-primary/20 text-primary border-0"
              >
                {{ item.badge }}
              </Badge>
            </RouterLink>
          </TooltipTrigger>
          <TooltipContent v-if="sidebarCollapsed" side="right">
            {{ item.label }}
          </TooltipContent>
        </Tooltip>

        <!-- Source section -->
        <div class="pt-3 pb-1">
          <div
            v-if="!sidebarCollapsed"
            class="px-2.5 mb-1.5 flex items-center justify-between"
          >
            <span class="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground/50">
              데이터 소스
            </span>
            <button
              class="p-0.5 rounded hover:bg-accent transition-colors text-muted-foreground/50 hover:text-muted-foreground"
              :class="{ 'animate-spin': isRefreshing }"
              :disabled="isRefreshing"
              @click="refreshSources"
            >
              <RefreshCw :size="10" />
            </button>
          </div>
          <Tooltip v-for="src in sourceItems" :key="src.label" :delay-duration="0">
            <TooltipTrigger :as-child="true">
              <div
                :class="cn(
                  'flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg text-xs cursor-default',
                  'text-muted-foreground/70',
                  sidebarCollapsed && 'justify-center',
                )"
              >
                <component :is="src.icon" :size="14" :style="{ color: src.color }" class="shrink-0" />
                <div
                  v-if="!sidebarCollapsed"
                  class="flex-1 flex items-center justify-between min-w-0 gap-1"
                >
                  <div class="flex flex-col min-w-0">
                    <span class="truncate leading-tight">{{ src.label }}</span>
                    <span class="text-[9px] text-muted-foreground/40 leading-tight truncate">
                      {{ src.lastSynced
                        ? formatLocal(src.lastSynced)
                        : src.status === 'planned' ? '연동 예정' : '수집기록없음' }}
                    </span>
                  </div>
                  <span :class="cn('w-1.5 h-1.5 rounded-full shrink-0', statusDot[src.status])" />
                </div>
              </div>
            </TooltipTrigger>
            <TooltipContent v-if="sidebarCollapsed" side="right">
              {{ src.label }}
            </TooltipContent>
          </Tooltip>
        </div>
      </nav>

      <!-- Footer -->
      <div v-if="!sidebarCollapsed" class="p-3 border-t border-border">
        <div class="text-[10px] text-muted-foreground/40 text-center">
          Ollama qwen3:8b · pgvector
        </div>
      </div>
    </aside>

    <!-- Mobile Sidebar -->
    <Transition
      enter-active-class="transition-transform duration-300 ease-out"
      enter-from-class="-translate-x-full"
      leave-active-class="transition-transform duration-300 ease-out"
      leave-to-class="-translate-x-full"
    >
      <aside
        v-if="mobileSidebarOpen"
        class="fixed left-0 top-0 h-full w-55 z-40 flex flex-col bg-card border-r border-border md:hidden"
      >
        <div class="flex items-center gap-2.5 h-14 px-4 border-b border-border shrink-0">
          <AsuraLogo :size="28" class="shrink-0" />
          <div class="overflow-hidden">
            <div class="font-bold text-sm leading-tight text-foreground">AsuraDB</div>
            <div class="text-[10px] text-muted-foreground leading-tight">PKDB v2.0</div>
          </div>
          <button
            class="ml-auto p-1 rounded-md hover:bg-accent transition-colors shrink-0"
            @click="ui.closeMobileSidebar()"
          >
            <ChevronLeft :size="14" />
          </button>
        </div>
        <nav class="flex-1 p-2 space-y-0.5 overflow-y-auto">
          <template v-for="item in navItems" :key="item.to ?? item.href">
            <a
              v-if="item.href"
              :href="item.href"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm transition-all duration-150 hover:bg-accent hover:text-accent-foreground text-muted-foreground"
              @click="ui.closeMobileSidebar()"
            >
              <component :is="item.icon" :size="16" class="shrink-0" />
              <span class="overflow-hidden whitespace-nowrap flex-1">{{ item.label }}</span>
            </a>
            <RouterLink
              v-else
              :to="item.to!"
              :class="cn(
                'flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm transition-all duration-150',
                'hover:bg-accent hover:text-accent-foreground',
                isActive(item.to!, item.exact)
                  ? 'bg-primary/15 text-primary font-medium'
                  : 'text-muted-foreground',
              )"
              @click="ui.closeMobileSidebar()"
            >
              <component :is="item.icon" :size="16" class="shrink-0" />
              <span class="overflow-hidden whitespace-nowrap flex-1">{{ item.label }}</span>
              <Badge
                v-if="item.badge"
                class="text-[9px] px-1 py-0 h-4 bg-primary/20 text-primary border-0"
              >
                {{ item.badge }}
              </Badge>
            </RouterLink>
          </template>
        </nav>
      </aside>
    </Transition>

    <!-- Main -->
    <div class="flex-1 flex flex-col h-full overflow-hidden">
      <!-- Topbar -->
      <header class="flex items-center gap-3 h-14 px-4 border-b border-border bg-card/50 shrink-0">
        <button
          class="md:hidden p-1.5 rounded-md hover:bg-accent transition-colors"
          @click="ui.openMobileSidebar()"
        >
          <Menu :size="18" />
        </button>
        <AsuraLogo :size="20" class="hidden md:block" />
        <span class="text-sm text-muted-foreground hidden md:block">
          AsuraDB <span class="text-muted-foreground/50 mx-1">/</span>
          <span class="text-foreground/80">개인 지식 DB 검색 시스템</span>
        </span>
        <div class="ml-auto flex items-center gap-2">
          <button
            v-if="apiOnline === false"
            :disabled="isRefreshing"
            class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-md border border-red-500/30 text-red-400 hover:bg-red-400/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            @click="startApi"
          >
            <RefreshCw :size="10" :class="isRefreshing && 'animate-spin'" />
            API 오프라인
          </button>
          <Badge
            v-else
            variant="outline"
            class="text-xs gap-1 border-green-500/30 text-green-400"
          >
            <Circle :size="6" class="fill-green-400" />
            시스템 정상
          </Badge>
          <div class="w-7 h-7 rounded-full bg-primary/20 flex items-center justify-center text-xs font-semibold text-primary">
            A
          </div>
        </div>
      </header>

      <!-- Page Content -->
      <main class="flex-1 overflow-y-auto">
        <RouterView />
      </main>
    </div>
  </div>
</template>
