<script setup lang="ts">
import { ref, watch, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import {
  Search as SearchIcon, SlidersHorizontal, X, ExternalLink,
  ChevronDown, ChevronUp, ChevronLeft, ChevronRight,
  Zap, AlignLeft, Tag, ArrowUpDown, Clock, TrendingUp,
} from 'lucide-vue-next';
import Input from '@/components/ui/Input.vue';
import Button from '@/components/ui/Button.vue';
import Badge from '@/components/ui/Badge.vue';
import { Card, CardContent } from '@/components/ui/card';
import Separator from '@/components/ui/Separator.vue';
import SourceIcon from '@/components/icons/SourceIcon.vue';
import type { SearchResult } from '@/data';
import { cn, previewContent } from '@/lib/utils';
import { API_BASE, IS_HOST, ensureApiRunning } from '@/lib/api';
import { SOURCE_COLOR as sourceColor, SOURCE_LABEL as sourceLabel } from '@/lib/sources';
import { useSortMode } from '@/composables/useSortMode';

type SourceType = 'notion' | 'upnote' | 'gmail' | 'drive' | 'calendar' | 'obsidian' | 'band';

interface SourceFilter {
  id: SourceType | 'all';
  label: string;
  color: string;
  planned?: boolean;   // 개발예정 — 비활성 표시
}

const sourceFilters: SourceFilter[] = [
  { id: 'all',      label: '전체',            color: '#818cf8' },
  { id: 'notion',   label: 'Notion',          color: sourceColor.notion },
  { id: 'upnote',   label: 'UpNote',          color: sourceColor.upnote },
  { id: 'gmail',    label: 'Gmail',           color: sourceColor.gmail },
  { id: 'drive',    label: 'Google Drive',    color: sourceColor.drive },
  { id: 'calendar', label: 'Google Calendar', color: sourceColor.calendar },
  { id: 'band',     label: 'Naver Band',      color: sourceColor.band,      planned: true },
  { id: 'obsidian', label: 'Obsidian',        color: sourceColor.obsidian,  planned: true },
];

const query = ref('');
const activeSource = ref<SourceType | 'all'>('all');
const results = ref<SearchResult[]>([]);
const searching = ref(false);
const searched = ref(false);
const offline = ref(false);   // 검색 API(8000) 연결 실패 여부
const starting = ref(false);  // 자동 기동 재시도 중
// 개발예정 소스는 기본으로 접어 둔다(상시 공간 차지 방지)
const showPlanned = ref(false);
const visibleFilters = computed(() => sourceFilters.filter(f => !f.planned || showPlanned.value));
const plannedCount = sourceFilters.filter(f => f.planned).length;
const inputRef = ref<{ focus: () => void } | null>(null);

const expandedMap = ref<Record<string, boolean>>({});
function toggleExpand(id: string) {
  expandedMap.value[id] = !expandedMap.value[id];
}

/** 검색 1회 실행. 성공하면 true, 연결·응답 실패면 false(결과는 비운다). */
async function runQuery(): Promise<boolean> {
  // 호스트 PC 가 아니면 요청 자체를 만들지 않는다(HTTPS→http://localhost = mixed content).
  // offline 안내는 아래 템플릿의 non-host 분기가 그대로 보여준다.
  if (!IS_HOST) return false;

  try {
    const params = new URLSearchParams({ q: query.value.trim(), limit: '50' });
    if (activeSource.value !== 'all') params.set('source', activeSource.value);

    const res  = await fetch(`${API_BASE}/search?${params}`, { signal: AbortSignal.timeout(20000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    results.value = (data.results ?? []).map((r: Record<string, unknown>) => ({
      id:          String(r.id),
      source:      String(r.source) as SourceType,
      title:       String(r.title ?? '(제목 없음)'),
      content:     String(r.content ?? ''),
      sourceUrl:   String(r.source_url ?? '#'),
      tags:        Array.isArray((r.metadata as Record<string, unknown>)?.tags)
                     ? ((r.metadata as Record<string, unknown>).tags as string[])
                     : [],
      date:        String((r.metadata as Record<string, unknown>)?.date ?? r.id).slice(0, 10),
      vectorScore: Number(r.vector_score ?? 0),
      ftsScore:    Number(r.fts_score    ?? 0),
      rrfScore:    Number(r.rrf_score    ?? 0),
      chunkType:   String(r.chunk_type   ?? 'section') as 'section' | 'paragraph',
    }));
    return true;
  } catch {
    results.value = [];
    return false;
  }
}

// 실패 시 사용자가 인프라를 만지지 않아도 되도록, 앱이 직접 API 를 깨우고 1회 자동 재시도한다.
async function handleSearch() {
  if (!query.value.trim()) return;
  searching.value = true;
  searched.value = false;
  offline.value = false;

  let ok = await runQuery();
  if (!ok && IS_HOST) {
    starting.value = true;
    if (await ensureApiRunning()) ok = await runQuery();   // 런처가 유휴 종료시킨 경우 여기서 살아난다
    starting.value = false;
  }

  offline.value   = !ok;
  searching.value = false;
  searched.value  = true;
}

function onKeyDown(e: KeyboardEvent) {
  if (e.key === 'Enter') void handleSearch();
}

watch(activeSource, () => {
  if (searched.value && query.value.trim()) void handleSearch();
});

function clearSearch() {
  query.value = '';
  results.value = [];
  searched.value = false;
  inputRef.value?.focus();
}

// 홈 빠른검색·딥링크: /search?q=... 진입 시 자동 실행
const route = useRoute();
onMounted(() => {
  const initial = (route.query.q as string | undefined)?.trim();
  if (initial) { query.value = initial; void handleSearch(); }
  else inputRef.value?.focus();
});

const { sortMode, cycleSortMode, sortLabel, sorted: sortedResults } = useSortMode(results);

const PAGE_SIZE = 10;
const currentPage = ref(1);

watch([searched, sortMode, activeSource], () => { currentPage.value = 1; });

const totalPages = computed(() => Math.ceil(sortedResults.value.length / PAGE_SIZE));

const pagedResults = computed(() => {
  const start = (currentPage.value - 1) * PAGE_SIZE;
  return sortedResults.value.slice(start, start + PAGE_SIZE);
});

const pageNumbers = computed<(number | '...')[]>(() => {
  const total = totalPages.value;
  const cur   = currentPage.value;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const pages: (number | '...')[] = [1];
  if (cur > 3) pages.push('...');
  for (let i = Math.max(2, cur - 1); i <= Math.min(total - 1, cur + 1); i++) pages.push(i);
  if (cur < total - 2) pages.push('...');
  pages.push(total);
  return pages;
});
</script>

<template>
  <div
    v-motion
    :initial="{ opacity: 0, y: 16 }"
    :enter="{ opacity: 1, y: 0, transition: { duration: 320 } }"
    class="p-4 md:p-6 max-w-3xl mx-auto space-y-5"
  >
    <!-- Header -->
    <div>
      <h2 class="text-xl font-bold">로컬 검색</h2>
      <p class="text-sm text-muted-foreground mt-0.5">
        FTS + Vector (RRF) · Notion · UpNote · Gmail · Google Drive
      </p>
    </div>

    <!-- Search Box -->
    <div class="space-y-3">
      <div class="relative">
        <SearchIcon
          :size="16"
          class="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none"
        />
        <label for="local-search" class="sr-only">검색어</label>
        <Input
          id="local-search"
          ref="inputRef"
          v-model="query"
          placeholder="질문을 입력하세요… 예: AGR 4월 마진 분석, 인도네시아 세관 규정"
          class="pl-10 pr-20 h-11 text-sm bg-card border-border/60 focus:border-primary/50"
          @keydown="onKeyDown"
        />
        <button
          v-if="query"
          class="absolute right-12 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
          @click="clearSearch"
        >
          <X :size="14" />
        </button>
        <!-- 이 화면의 주요 CTA — solid 는 화면당 1개(가이드 2항) -->
        <Button
          variant="solid"
          :disabled="!query.trim() || searching"
          size="sm"
          class="absolute right-1.5 top-1/2 -translate-y-1/2 h-8 px-3 text-xs"
          @click="handleSearch"
        >
          {{ searching ? '검색 중…' : '검색' }}
        </Button>
      </div>

      <!-- Source Filter -->
      <div class="flex items-center gap-2 flex-wrap">
        <SlidersHorizontal :size="13" class="text-muted-foreground shrink-0" />
        <button
          v-for="sf in visibleFilters"
          :key="sf.id"
          :disabled="sf.planned"
          :title="sf.planned ? '개발예정 — 수집기 연동 준비 중' : ''"
          :class="cn(
            'text-xs px-2.5 py-1 rounded-full border transition-all duration-150',
            sf.planned
              ? 'border-dashed border-border/40 text-muted-foreground/40 cursor-not-allowed'
              : activeSource === sf.id
                ? 'border-transparent text-background font-medium'
                : 'border-border/50 text-muted-foreground hover:border-border',
          )"
          :style="!sf.planned && activeSource === sf.id ? { background: sf.color } : {}"
          @click="!sf.planned && (activeSource = sf.id)"
        >
          {{ sf.label }}{{ sf.planned ? ' (개발예정)' : '' }}
        </button>
        <!-- 개발예정 소스는 접어 두고 필요할 때만 펼친다 -->
        <button
          v-if="plannedCount"
          class="text-[11px] px-2 py-1 rounded-full border border-dashed border-border/50 text-muted-foreground/70 hover:text-foreground hover:border-border transition-colors"
          :aria-expanded="showPlanned"
          @click="showPlanned = !showPlanned"
        >
          {{ showPlanned ? '개발예정 접기' : `개발예정 ${plannedCount}` }}
        </button>
      </div>
    </div>

    <!-- How it works (pre-search) -->
    <div v-if="!searched && !searching" class="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-4">
      <div
        v-for="card in [
          { icon: AlignLeft, label: 'FTS',     desc: '전문 텍스트 검색\n키워드 정확도 기반', color: '#4ade80' },
          { icon: Zap,       label: 'Vector',  desc: '의미론적 벡터 검색\n문맥/개념 유사도 기반', color: '#818cf8' },
          { icon: SearchIcon,label: 'RRF 결합', desc: 'Reciprocal Rank Fusion\n두 점수 통합 순위화', color: '#60a5fa' },
        ]"
        :key="card.label"
        class="p-3 rounded-lg bg-muted/20 border border-border/40 text-center"
      >
        <div
          class="w-8 h-8 rounded-lg mx-auto mb-2 flex items-center justify-center"
          :style="{ background: card.color + '18' }"
        >
          <component :is="card.icon" :size="15" :style="{ color: card.color }" />
        </div>
        <div class="text-xs font-semibold text-foreground">{{ card.label }}</div>
        <div class="text-[10px] text-muted-foreground mt-1 whitespace-pre-line leading-relaxed">
          {{ card.desc }}
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="searching" class="flex flex-col items-center py-12 gap-3">
      <div class="relative w-10 h-10">
        <div class="absolute inset-0 rounded-full border-2 border-primary/20" />
        <div class="absolute inset-0 rounded-full border-2 border-transparent border-t-primary animate-spin" />
      </div>
      <div class="text-sm text-muted-foreground">하이브리드 검색 중…</div>
    </div>

    <!-- 검색 API 오프라인 안내 (0개 결과로 위장되지 않도록) -->
    <div v-if="searched && !searching && offline"
      class="mt-4 rounded-xl border border-amber-300 bg-amber-50/60 p-5 text-sm text-amber-800">
      <template v-if="IS_HOST">
        <p>검색 백엔드(API)에 연결하지 못했습니다. 자동 기동을 시도했지만 응답이 없습니다.</p>
        <button
          :disabled="searching"
          class="mt-2 inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg border border-amber-400/60 bg-amber-100/60 hover:bg-amber-100 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          @click="handleSearch"
        >
          {{ starting ? '기동 중…' : '다시 시도' }}
        </button>
      </template>
      <template v-else>
        <b>로컬 검색·AI 지식 Q&A</b>는 데이터가 있는 <b>호스트 PC에서만</b> 동작합니다(원격 미지원).
        다른 컴퓨터에서는 KPI·마진·지점·수입·DB·견적 등 나머지 기능을 이용하세요.
      </template>
    </div>

    <!-- Results -->
    <Transition
      enter-active-class="transition-opacity duration-300"
      enter-from-class="opacity-0"
    >
      <div v-if="searched && !searching && !offline" class="space-y-3">
        <div class="flex items-center justify-between">
          <div class="text-sm text-muted-foreground">
            <span class="text-foreground font-semibold">{{ results.length }}개</span> 결과
            <span v-if="totalPages > 1" class="text-muted-foreground/60 text-xs ml-1">
              ({{ (currentPage - 1) * PAGE_SIZE + 1 }}–{{ Math.min(currentPage * PAGE_SIZE, results.length) }})
            </span>
          </div>
          <div v-if="results.length > 0" class="flex items-center gap-2">
            <div class="flex items-center gap-1.5 text-[10px] text-muted-foreground">
              <span class="w-2 h-2 rounded-full bg-violet-400/70" /> Vector
              <span class="w-2 h-2 rounded-full bg-green-400/70 ml-1" /> FTS
            </div>
            <button
              :class="cn(
                'flex items-center gap-1 text-[11px] px-2 py-1 rounded-md border transition-all',
                sortMode !== 'rrf'
                  ? 'border-primary/40 text-primary bg-primary/8'
                  : 'border-border/50 text-muted-foreground hover:border-border hover:text-foreground',
              )"
              @click="cycleSortMode"
            >
              <Clock v-if="sortMode === 'date_desc'" :size="11" />
              <TrendingUp v-else-if="sortMode === 'rrf'" :size="11" />
              <ArrowUpDown v-else :size="11" />
              {{ sortLabel }}
            </button>
          </div>
        </div>
        <Separator class="border-border/40" />
        <div v-if="results.length === 0" class="text-center py-12 text-sm text-muted-foreground">
          검색 결과가 없습니다.
        </div>
        <div v-else class="space-y-3">
          <div v-for="r in pagedResults" :key="r.id">
            <Card
              class="border-border/50 hover:border-border transition-colors group"
              style="box-shadow: 0 2px 12px color-mix(in srgb, var(--primary) 4%, transparent);"
            >
              <CardContent class="p-4">
                <div class="flex items-start gap-2 mb-2">
                  <div
                    class="w-6 h-6 rounded flex items-center justify-center shrink-0 mt-0.5"
                    :style="{ background: sourceColor[r.source] + '18', color: sourceColor[r.source] }"
                  >
                    <SourceIcon :source="r.source" :size="13" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-start gap-2">
                      <h3 class="text-sm font-semibold text-foreground leading-snug flex-1">
                        {{ r.title }}
                      </h3>
                      <a
                        v-if="r.sourceUrl && r.sourceUrl !== '#'"
                        :href="r.sourceUrl"
                        :target="r.sourceUrl.startsWith('http') ? '_blank' : '_self'"
                        rel="noopener noreferrer"
                        class="opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                      >
                        <ExternalLink :size="12" class="text-muted-foreground" />
                      </a>
                    </div>
                    <div class="flex items-center gap-2 mt-1 flex-wrap">
                      <Badge
                        variant="outline"
                        class="text-[9px] px-1.5 py-0 h-4"
                        :style="{ borderColor: sourceColor[r.source] + '60', color: sourceColor[r.source] }"
                      >
                        {{ sourceLabel[r.source] }}
                      </Badge>
                      <span class="text-[10px] text-muted-foreground">{{ r.date }}</span>
                      <span class="text-[10px] text-muted-foreground capitalize bg-muted/40 px-1.5 rounded">
                        {{ r.chunkType }}
                      </span>
                    </div>
                  </div>
                </div>

                <div
                  :class="cn(
                    'text-xs text-muted-foreground leading-relaxed ml-8',
                    !expandedMap[r.id] && 'line-clamp-2',
                  )"
                >
                  {{ expandedMap[r.id] ? r.content : previewContent(r.content) + (r.content.length > 180 ? '…' : '') }}
                </div>

                <div v-if="r.tags.length > 0" class="flex items-center gap-1.5 mt-2.5 ml-8 flex-wrap">
                  <Tag :size="10" class="text-muted-foreground/50" />
                  <span
                    v-for="t in r.tags"
                    :key="t"
                    class="text-[10px] bg-muted/50 text-muted-foreground px-1.5 py-0.5 rounded"
                  >
                    {{ t }}
                  </span>
                </div>

                <div class="mt-3 ml-8 pt-2.5 border-t border-border/40 flex items-center gap-4 flex-wrap">
                  <div class="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                    <Zap :size="9" class="text-primary/70" />
                    <span>RRF</span>
                    <div class="h-1 rounded-full bg-muted/50 overflow-hidden w-16">
                      <div
                        class="h-full rounded-full transition-all"
                        :style="{ width: (r.rrfScore * 100) + '%', background: '#818cf8' }"
                      />
                    </div>
                    <span class="font-mono text-primary/80">{{ r.rrfScore.toFixed(2) }}</span>
                  </div>
                  <div class="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                    <span>Vector</span>
                    <div class="h-1 rounded-full bg-muted/50 overflow-hidden w-16">
                      <div
                        class="h-full rounded-full transition-all"
                        :style="{ width: (r.vectorScore * 100) + '%', background: '#60a5fa' }"
                      />
                    </div>
                    <span class="font-mono">{{ r.vectorScore.toFixed(2) }}</span>
                  </div>
                  <div class="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                    <span>FTS</span>
                    <div class="h-1 rounded-full bg-muted/50 overflow-hidden w-16">
                      <div
                        class="h-full rounded-full transition-all"
                        :style="{ width: (r.ftsScore * 100) + '%', background: '#4ade80' }"
                      />
                    </div>
                    <span class="font-mono">{{ r.ftsScore.toFixed(2) }}</span>
                  </div>
                  <button
                    class="ml-auto text-[10px] text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
                    @click="toggleExpand(r.id)"
                  >
                    <template v-if="expandedMap[r.id]">
                      <ChevronUp :size="10" /> 접기
                    </template>
                    <template v-else>
                      <ChevronDown :size="10" /> 더 보기
                    </template>
                  </button>
                </div>
              </CardContent>
            </Card>
          </div>
        </div>

        <!-- Pagination -->
        <div v-if="totalPages > 1" class="flex items-center justify-center gap-1 pt-2">
          <button
            :disabled="currentPage === 1"
            :class="cn(
              'w-7 h-7 flex items-center justify-center rounded-md border text-xs transition-all',
              currentPage === 1
                ? 'border-border/30 text-muted-foreground/30 cursor-not-allowed'
                : 'border-border/50 text-muted-foreground hover:border-border hover:text-foreground',
            )"
            @click="currentPage--"
          >
            <ChevronLeft :size="13" />
          </button>

          <template v-for="p in pageNumbers" :key="String(p) + '_' + pageNumbers.indexOf(p)">
            <span
              v-if="p === '...'"
              class="w-7 h-7 flex items-center justify-center text-xs text-muted-foreground/50"
            >…</span>
            <button
              v-else
              :class="cn(
                'w-7 h-7 flex items-center justify-center rounded-md border text-xs transition-all',
                currentPage === p
                  ? 'bg-primary text-primary-foreground border-primary font-semibold'
                  : 'border-border/50 text-muted-foreground hover:border-border hover:text-foreground',
              )"
              @click="currentPage = p as number"
            >
              {{ p }}
            </button>
          </template>

          <button
            :disabled="currentPage === totalPages"
            :class="cn(
              'w-7 h-7 flex items-center justify-center rounded-md border text-xs transition-all',
              currentPage === totalPages
                ? 'border-border/30 text-muted-foreground/30 cursor-not-allowed'
                : 'border-border/50 text-muted-foreground hover:border-border hover:text-foreground',
            )"
            @click="currentPage++"
          >
            <ChevronRight :size="13" />
          </button>
        </div>
      </div>
    </Transition>
  </div>
</template>
