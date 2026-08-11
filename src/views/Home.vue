<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import {
  Search, BrainCircuit, ClipboardList, BarChart3, Ship, Percent, Store,
  ArrowRight, ExternalLink,
} from 'lucide-vue-next';
import PageHeader from '@/components/PageHeader.vue';
import SourceIcon from '@/components/icons/SourceIcon.vue';
import { sbGet } from '@/lib/supabase';

const router = useRouter();

// ── 로컬 검색 / AI Q&A ───────────────────────────────────────────────────────
const q = ref('');
function runSearch() {
  const t = q.value.trim();
  router.push(t ? { path: '/search', query: { q: t } } : { path: '/search' });
}
const aq = ref('');
function runAsk() {
  const t = aq.value.trim();
  router.push(t ? { path: '/ai-search', query: { q: t } } : { path: '/ai-search' });
}

// ── 도구 바로가기 ────────────────────────────────────────────────────────────
const TOOLS = [
  { to: '/monitor',      icon: BarChart3,     label: 'KPI 모니터링', desc: '시장·재무 대시보드' },
  { to: '/margin',       icon: Percent,       label: '마진 분석',       desc: '월별 마진 추이' },
  { to: '/branch-sales', icon: Store,         label: '지점 판매 현황',   desc: '지점 매출·운영 손익' },
  { to: '/tire-import',  icon: Ship,          label: '연간 타이어 수입량', desc: '인니 수입 통계' },
  { to: '/quote',        icon: ClipboardList, label: '견적서 작성',     desc: '거래처 견적 작성·관리' },

] as const;

// ── 데이터 소스 현황 ─────────────────────────────────────────────────────────
type Src = { key: string; label: string; status: 'synced' | 'stale' | 'none' | 'planned'; last: string | null };
const SOURCE_DEFS = [
  { key: 'notion',   label: 'Notion' },
  { key: 'upnote',   label: 'UpNote' },
  { key: 'gmail',    label: 'Gmail' },
  { key: 'drive',    label: 'Google Drive' },
  { key: 'calendar', label: 'Google Calendar' },
  { key: 'band',     label: 'Naver Band' },
  { key: 'obsidian', label: 'Obsidian' },
];
const sources = ref<Src[]>([]);
const loadingSources = ref(true);

function todayStr(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
function localDate(iso: string): string {
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
function relTime(iso: string | null): string {
  if (!iso) return '기록 없음';
  const diff = Date.now() - new Date(iso).getTime();
  const h = Math.floor(diff / 3.6e6);
  if (h < 1) return '방금';
  if (h < 24) return `${h}시간 전`;
  return `${Math.floor(h / 24)}일 전`;
}

const STATUS_DOT: Record<Src['status'], string> = {
  synced: 'bg-success', stale: 'bg-destructive', none: 'bg-destructive', planned: 'bg-muted-foreground/40',
};
const STATUS_LABEL: Record<Src['status'], string> = {
  synced: '최신', stale: '지연', none: '미수집', planned: '예정',
};

// ── 최근 자료 ────────────────────────────────────────────────────────────────
type Doc = { source: string; title: string; source_url: string | null; updated_at: string };
const recent = ref<Doc[]>([]);
const loadingRecent = ref(true);

async function loadAll() {
  loadingSources.value = true; loadingRecent.value = true;
  const today = todayStr();
  // 소스 상태 (heartbeat)
  try {
    const hb = await sbGet<{ source: string; last_run: string }[]>('collector_heartbeat?select=source,last_run');
    const map: Record<string, string> = {};
    for (const r of hb) map[r.source] = r.last_run;
    sources.value = SOURCE_DEFS.map(d => {
      const last = map[d.key] ?? null;
      let status: Src['status'];
      if (d.key === 'obsidian') status = 'planned';
      else if (!last) status = 'none';
      else status = localDate(last) === today ? 'synced' : 'stale';
      return { ...d, status, last };
    });
  } catch { sources.value = SOURCE_DEFS.map(d => ({ ...d, status: 'none', last: null })); }
  loadingSources.value = false;

  // 최근 자료 (문서 1행/건 = chunk_index 0)
  try {
    recent.value = await sbGet<Doc[]>(
      'documents?select=source,title,source_url,updated_at&chunk_index=eq.0&order=updated_at.desc&limit=8',
    );
  } catch { recent.value = []; }
  loadingRecent.value = false;
}

// 상단 상태 버튼의 새로고침 이벤트에 반응해 대시보드 재로드
function onRefresh() { void loadAll(); }
onMounted(() => {
  void loadAll();
  window.addEventListener('asura:refresh', onRefresh);
});
onUnmounted(() => window.removeEventListener('asura:refresh', onRefresh));
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">
    <PageHeader>
      <template #subtitle>
        <p class="text-xs text-muted-foreground">회사 자료를 한곳에서 — 검색·분석·관리 (상단 '시스템 정상' 버튼으로 새로고침)</p>
      </template>
    </PageHeader>

    <!-- 로컬 검색 · AI Q&A (가로 2분할) -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
      <!-- 로컬 검색 -->
      <div class="rounded-xl border border-border bg-card p-5 shadow-sm">
        <div class="flex items-center gap-2 text-sm font-semibold text-foreground mb-3">
          <Search :size="16" class="text-primary" /> 로컬 검색
        </div>
        <div class="flex gap-2">
          <div class="relative flex-1">
            <Search :size="16" class="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <label for="home-search" class="sr-only">로컬 검색어</label>
            <input
              id="home-search"
              v-model="q"
              type="search"
              placeholder="문서·메일·노트 전체에서 검색…"
              class="w-full bg-muted/50 border border-border rounded-xl pl-9 pr-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
              @keydown.enter="runSearch"
            />
          </div>
          <button
            class="inline-flex items-center gap-1.5 bg-primary text-primary-foreground text-sm font-semibold rounded-xl px-5 py-2.5 hover:bg-primary/90 transition-colors shrink-0"
            @click="runSearch"
          >
            검색 <ArrowRight :size="16" />
          </button>
        </div>
      </div>

      <!-- AI 지식 Q&A -->
      <div class="rounded-xl border border-border bg-card p-5 shadow-sm">
        <div class="flex items-center gap-2 text-sm font-semibold text-foreground mb-3">
          <BrainCircuit :size="16" class="text-primary" /> AI 지식 Q&A
        </div>
        <div class="flex gap-2">
          <div class="relative flex-1">
            <BrainCircuit :size="16" class="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <label for="home-ask" class="sr-only">AI 지식 Q&A 질문</label>
            <input
              id="home-ask"
              v-model="aq"
              type="text"
              placeholder="질문하면 Claude가 DB 기반으로 답합니다…"
              class="w-full bg-muted/50 border border-border rounded-xl pl-9 pr-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
              @keydown.enter="runAsk"
            />
          </div>
          <button
            class="inline-flex items-center gap-1.5 bg-primary text-primary-foreground text-sm font-semibold rounded-xl px-5 py-2.5 hover:bg-primary/90 transition-colors shrink-0"
            @click="runAsk"
          >
            질문 <ArrowRight :size="16" />
          </button>
        </div>
      </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
      <!-- 데이터 소스 현황 -->
      <div class="rounded-xl border border-border bg-card p-4">
        <h2 class="text-sm font-bold text-foreground mb-3">데이터 소스</h2>
        <div v-if="loadingSources" class="space-y-2">
          <div v-for="i in 5" :key="i" class="h-9 rounded-lg bg-muted animate-pulse" />
        </div>
        <ul v-else class="space-y-1">
          <li v-for="s in sources" :key="s.key" class="flex items-center gap-3 py-1.5">
            <SourceIcon :source="s.key" :size="18" class="shrink-0" />
            <span class="text-sm text-foreground flex-1 truncate">{{ s.label }}</span>
            <span class="text-[11px] text-muted-foreground tabular-nums">{{ relTime(s.last) }}</span>
            <span class="inline-flex items-center gap-1.5 text-[11px] font-medium w-12 justify-end"
                  :class="s.status === 'synced' ? 'text-success' : s.status === 'planned' ? 'text-muted-foreground' : 'text-destructive'">
              <span class="h-2 w-2 rounded-full" :class="STATUS_DOT[s.status]" />
              {{ STATUS_LABEL[s.status] }}
            </span>
          </li>
        </ul>
      </div>

      <!-- 최근 자료 -->
      <div class="rounded-xl border border-border bg-card p-4">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-sm font-bold text-foreground">최근 자료</h2>
          <RouterLink to="/search" class="text-[11px] text-primary hover:text-primary/80 font-medium inline-flex items-center gap-0.5">
            전체 검색 <ArrowRight :size="12" />
          </RouterLink>
        </div>
        <div v-if="loadingRecent" class="space-y-2">
          <div v-for="i in 6" :key="i" class="h-9 rounded-lg bg-muted animate-pulse" />
        </div>
        <p v-else-if="!recent.length" class="text-xs text-muted-foreground py-4 text-center">최근 자료가 없습니다.</p>
        <ul v-else class="divide-y divide-border/60">
          <li v-for="(d, i) in recent" :key="i">
            <!-- 원본 링크가 없는 자료는 링크로 만들지 않는다(빈 링크 방지) -->
            <component
              :is="d.source_url ? 'a' : 'div'"
              :href="d.source_url || undefined"
              :target="d.source_url ? '_blank' : undefined"
              :rel="d.source_url ? 'noopener noreferrer' : undefined"
              :aria-label="d.source_url ? `${d.title || '(제목 없음)'} — 원본 열기` : undefined"
              :title="d.title || '(제목 없음)'"
              class="flex items-center gap-3 py-2 group"
            >
              <SourceIcon :source="d.source" :size="16" class="shrink-0" />
              <span class="text-sm text-foreground/90 flex-1 truncate group-hover:text-primary transition-colors">{{ d.title || '(제목 없음)' }}</span>
              <span class="text-[11px] text-muted-foreground tabular-nums shrink-0">{{ localDate(d.updated_at).slice(5) }}</span>
              <ExternalLink v-if="d.source_url" :size="13" class="text-muted-foreground/50 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity" />
            </component>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
