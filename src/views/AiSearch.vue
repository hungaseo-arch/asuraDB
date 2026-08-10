<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import {
  BrainCircuit, Send, X, ExternalLink,
  ChevronDown, ChevronUp, Zap, Tag,
  ArrowUpDown, Clock, TrendingUp,
} from 'lucide-vue-next';
import PageHeader from '@/components/PageHeader.vue';
import Input from '@/components/ui/Input.vue';
import Button from '@/components/ui/Button.vue';
import Badge from '@/components/ui/Badge.vue';
import { Card, CardContent } from '@/components/ui/card';
import Separator from '@/components/ui/Separator.vue';
import SourceIcon from '@/components/icons/SourceIcon.vue';
import { cn, previewContent } from '@/lib/utils';
import { API_BASE, IS_HOST } from '@/lib/api';
import { SOURCE_COLOR as sourceColor, SOURCE_LABEL as sourceLabel } from '@/lib/sources';
import { useSortMode } from '@/composables/useSortMode';

interface AiSource {
  id:           string;
  source:       string;
  title:        string;
  content:      string;
  source_url:   string;
  rrf_score:    number;
  vector_score: number;
  fts_score:    number;
  chunk_type:   string;
  tags:         string[];
  metadata:     Record<string, unknown>;
  date:         string;
}

const query       = ref('');
const answer      = ref('');
const sources     = ref<AiSource[]>([]);
const loading     = ref(false);
const done        = ref(false);
const expandedMap = ref<Record<string, boolean>>({});

const { sortMode, cycleSortMode, sortLabel, sorted: sortedSources } = useSortMode(sources);

function toggleExpand(id: string) {
  expandedMap.value[id] = !expandedMap.value[id];
}

function extractDate(meta: Record<string, unknown>): string {
  const d = meta?.date ?? meta?.updated_at ?? meta?.start ?? '';
  return String(d).slice(0, 10);
}

async function handleSearch() {
  if (!query.value.trim() || loading.value) return;

  // 호스트 PC 가 아니면 localhost 요청을 만들지 않고 곧바로 안내만 보여준다
  // (HTTPS 배포본에서 http://localhost 호출은 mixed content 로 차단된다)
  if (!IS_HOST) {
    answer.value  = 'AI 지식 Q&A와 로컬 검색은 데이터가 있는 호스트 PC에서만 동작합니다(원격 미지원). 다른 컴퓨터에서는 KPI·마진·지점·수입·DB·견적 등 나머지 기능을 이용하세요.';
    sources.value = [];
    done.value    = true;
    return;
  }

  loading.value = true;
  done.value    = false;
  answer.value  = '';
  sources.value = [];
  expandedMap.value = {};

  try {
    const res = await fetch(`${API_BASE}/ai-search`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ q: query.value.trim(), limit: 30 }),
    });

    if (!res.ok || !res.body) throw new Error('API 오류');

    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let   buffer  = '';

    while (true) {
      const { done: streamDone, value } = await reader.read();
      if (streamDone) break;
      buffer += decoder.decode(value, { stream: true });

      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const json = line.slice(6).trim();
        if (json === '[DONE]') { done.value = true; continue; }
        try {
          const obj = JSON.parse(json) as {
            type: string;
            text?: string;
            sources?: Record<string, unknown>[];
          };
          if (obj.type === 'text') {
            answer.value += obj.text ?? '';
          }
          if (obj.type === 'sources') {
            sources.value = (obj.sources ?? []).map(s => ({
              id:           String(s.id),
              source:       String(s.source),
              title:        String(s.title ?? '(제목 없음)'),
              content:      String(s.content ?? ''),
              source_url:   String(s.source_url ?? '#'),
              rrf_score:    Number(s.rrf_score    ?? 0),
              vector_score: Number(s.vector_score ?? 0),
              fts_score:    Number(s.fts_score    ?? 0),
              chunk_type:   String(s.chunk_type   ?? 'section'),
              tags:         Array.isArray(s.tags) ? (s.tags as string[]) : [],
              metadata:     (s.metadata as Record<string, unknown>) ?? {},
              date:         extractDate((s.metadata as Record<string, unknown>) ?? {}),
            }));
          }
        } catch { /**/ }
      }
    }
  } catch (e) {
    const msg = String(e);
    const connFailed = e instanceof TypeError || msg.includes('Failed to fetch');
    if (connFailed && !IS_HOST) {
      answer.value = 'AI 지식 Q&A와 로컬 검색은 데이터가 있는 호스트 PC에서만 동작합니다(원격 미지원). 다른 컴퓨터에서는 KPI·마진·지점·수입·DB·견적 등 나머지 기능을 이용하세요.';
    } else if (connFailed) {
      answer.value = 'AI 검색 백엔드(localhost:8000)에 연결할 수 없습니다. 런처(scripts/launcher.py)가 실행 중인지 확인하세요 — 실행 중이면 백엔드 첫 기동에 ~20초가 걸립니다.';
    } else {
      answer.value = `오류: ${msg}`;
    }
  }

  loading.value = false;
  done.value    = true;
}

function onKeyDown(e: KeyboardEvent) {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void handleSearch(); }
}

// 홈 AI Q&A 박스·딥링크: /ai-search?q=... 진입 시 자동 질문
const route = useRoute();
onMounted(() => {
  const initial = (route.query.q as string | undefined)?.trim();
  if (initial) { query.value = initial; void handleSearch(); }
});

function clearAll() {
  query.value       = '';
  answer.value      = '';
  sources.value     = [];
  done.value        = false;
  expandedMap.value = {};
}
</script>

<template>
  <div
    v-motion
    :initial="{ opacity: 0, y: 16 }"
    :enter="{ opacity: 1, y: 0, transition: { duration: 320 } }"
    class="p-4 md:p-6 max-w-3xl mx-auto space-y-5"
  >
    <!-- Header -->
    <PageHeader title="AI 지식 Q&A" subtitle="질문하면 DB 전체에서 관련 문서를 찾아 Claude Haiku가 답변합니다">
      <template #icon><BrainCircuit :size="20" class="text-primary" /></template>
      <template #actions>
        <button
          v-if="done"
          class="text-muted-foreground hover:text-foreground transition-colors"
          @click="clearAll"
        >
          <X :size="16" />
        </button>
      </template>
    </PageHeader>

    <!-- Input -->
    <div class="relative">
      <Input
        v-model="query"
        placeholder="예: 인도네시아 AGR 타이어 시장 현황은? / 4월 마진이 가장 높은 제품은?"
        class="pr-24 h-11 text-sm bg-card border-border/60 focus:border-primary/50"
        :disabled="loading"
        @keydown="onKeyDown"
      />
      <!-- 이 화면의 주요 CTA — solid 는 화면당 1개(가이드 2항) -->
      <Button
        variant="solid"
        :disabled="!query.trim() || loading"
        size="sm"
        class="absolute right-1.5 top-1/2 -translate-y-1/2 h-8 px-3 text-xs gap-1.5"
        @click="handleSearch"
      >
        <Send :size="11" />
        {{ loading ? '검색 중…' : '질문' }}
      </Button>
    </div>

    <!-- 예시 질문 -->
    <div v-if="!done && !loading" class="flex flex-wrap gap-2">
      <button
        v-for="ex in [
          '인도네시아 AGR 타이어 시장 동향',
          '최근 미팅에서 논의된 주요 고객사',
          '러버트랙 주요 사이즈별 수요 현황',
          'MAXAM 브랜드 경쟁 현황',
        ]"
        :key="ex"
        class="text-[11px] px-2.5 py-1 rounded-full border border-border/50 text-muted-foreground hover:border-primary/40 hover:text-foreground transition-all"
        @click="query = ex; void handleSearch()"
      >
        {{ ex }}
      </button>
    </div>

    <!-- Loading -->
    <div v-if="loading && !answer" class="flex flex-col items-center py-10 gap-3">
      <div class="relative w-9 h-9">
        <div class="absolute inset-0 rounded-full border-2 border-primary/20" />
        <div class="absolute inset-0 rounded-full border-2 border-transparent border-t-primary animate-spin" />
      </div>
      <p class="text-sm text-muted-foreground">문서 검색 및 답변 생성 중…</p>
    </div>

    <!-- Answer -->
    <div v-if="answer" class="space-y-4">
      <Card class="border-primary/20 bg-primary/5">
        <CardContent class="p-4">
          <div class="flex items-center gap-2 mb-3 text-xs font-semibold text-primary">
            <BrainCircuit :size="13" />
            Claude Haiku 답변
          </div>
          <div class="text-sm text-foreground leading-relaxed whitespace-pre-wrap">
            {{ answer }}<span
              v-if="loading"
              class="inline-block w-1.5 h-4 bg-primary/60 animate-pulse ml-0.5 align-middle"
            />
          </div>
        </CardContent>
      </Card>

      <!-- Sources -->
      <div v-if="sources.length > 0" class="space-y-3">
        <div class="flex items-center justify-between">
          <div class="text-sm text-muted-foreground">
            참조 문서 <span class="text-foreground font-semibold">{{ sources.length }}개</span>
          </div>
          <div class="flex items-center gap-2">
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

        <div class="space-y-3">
          <div v-for="r in sortedSources" :key="r.id">
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
                        v-if="r.source_url && r.source_url !== '#'"
                        :href="r.source_url"
                        :target="r.source_url.startsWith('http') ? '_blank' : '_self'"
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
                        {{ sourceLabel[r.source] ?? r.source }}
                      </Badge>
                      <span v-if="r.date" class="text-[10px] text-muted-foreground">{{ r.date }}</span>
                      <span class="text-[10px] text-muted-foreground capitalize bg-muted/40 px-1.5 rounded">
                        {{ r.chunk_type }}
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
                  >{{ t }}</span>
                </div>

                <div class="mt-3 ml-8 pt-2.5 border-t border-border/40 flex items-center gap-4 flex-wrap">
                  <div class="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                    <Zap :size="9" class="text-primary/70" />
                    <span>RRF</span>
                    <div class="h-1 rounded-full bg-muted/50 overflow-hidden w-16">
                      <div
                        class="h-full rounded-full transition-all"
                        :style="{ width: (r.rrf_score * 100) + '%', background: '#818cf8' }"
                      />
                    </div>
                    <span class="font-mono text-primary/80">{{ r.rrf_score.toFixed(2) }}</span>
                  </div>
                  <div class="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                    <span>Vector</span>
                    <div class="h-1 rounded-full bg-muted/50 overflow-hidden w-16">
                      <div
                        class="h-full rounded-full transition-all"
                        :style="{ width: (r.vector_score * 100) + '%', background: '#60a5fa' }"
                      />
                    </div>
                    <span class="font-mono">{{ r.vector_score.toFixed(2) }}</span>
                  </div>
                  <div class="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                    <span>FTS</span>
                    <div class="h-1 rounded-full bg-muted/50 overflow-hidden w-16">
                      <div
                        class="h-full rounded-full transition-all"
                        :style="{ width: (r.fts_score * 100) + '%', background: '#4ade80' }"
                      />
                    </div>
                    <span class="font-mono">{{ r.fts_score.toFixed(2) }}</span>
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
      </div>
    </div>
  </div>
</template>
