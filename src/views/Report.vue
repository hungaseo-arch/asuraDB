<script setup lang="ts">
import { ref } from 'vue';
import { FileBarChart2, RefreshCw, Clock, ChevronDown, ChevronUp } from 'lucide-vue-next';
import Button from '@/components/ui/Button.vue';
import { Card, CardContent } from '@/components/ui/card';
import { API_BASE } from '@/lib/api';

interface Report {
  generated_at: string;
  topic: string;
  content: string;
}

const report    = ref<Report | null>(null);
const loading   = ref(false);
const streaming = ref(false);
const content   = ref('');
const sections  = ref<{ title: string; body: string }[]>([]);
const expanded  = ref<Record<number, boolean>>({});

function parseSection(raw: string) {
  const lines = raw.split('\n');
  const result: { title: string; body: string }[] = [];
  let cur: { title: string; body: string[] } | null = null;
  for (const line of lines) {
    if (line.startsWith('## ')) {
      if (cur) result.push({ title: cur.title, body: cur.body.join('\n').trim() });
      cur = { title: line.slice(3).trim(), body: [] };
    } else if (line.startsWith('# ')) {
      // skip top-level title
    } else if (cur) {
      cur.body.push(line);
    }
  }
  if (cur) result.push({ title: cur.title, body: cur.body.join('\n').trim() });
  return result;
}

async function generate() {
  loading.value   = true;
  streaming.value = true;
  content.value   = '';
  sections.value  = [];
  report.value    = null;

  try {
    const res = await fetch(`${API_BASE}/report/generate`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ topic: '인도네시아 타이어 시장 동향' }),
    });

    if (!res.ok || !res.body) throw new Error('API 오류');

    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let   buffer  = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const json = line.slice(6).trim();
        if (json === '[DONE]') {
          streaming.value = false;
          sections.value  = parseSection(content.value);
          report.value    = {
            generated_at: new Date().toISOString(),
            topic:        '인도네시아 타이어 시장 동향',
            content:      content.value,
          };
          continue;
        }
        try {
          const obj = JSON.parse(json) as { text?: string };
          if (obj.text) content.value += obj.text;
        } catch { /**/ }
      }
    }
  } catch (e) {
    content.value   = `오류: ${String(e)}`;
    streaming.value = false;
  }

  loading.value = false;
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
    <div class="flex items-start justify-between">
      <div>
        <h1 class="text-xl font-bold flex items-center gap-2">
          <FileBarChart2 :size="20" class="text-primary" />
          자동화 레포트
        </h1>
        <p class="text-sm text-muted-foreground mt-0.5">
          DB 전체를 AI가 분석해 인사이트를 제공합니다
        </p>
      </div>
      <Button
        size="sm"
        class="gap-1.5 text-xs h-8 px-3"
        :disabled="loading"
        @click="generate"
      >
        <RefreshCw :size="12" :class="loading && 'animate-spin'" />
        {{ loading ? '생성 중…' : '지금 생성' }}
      </Button>
    </div>

    <!-- 준비 화면 (생성 전) -->
    <div v-if="!loading && !report" class="space-y-3">
      <!-- 예정 레포트 목록 -->
      <div class="grid grid-cols-1 gap-3">
        <Card
          class="border-border/50 cursor-pointer hover:border-primary/40 transition-colors"
          @click="generate"
        >
          <CardContent class="p-4 flex items-center gap-3">
            <div class="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
              <FileBarChart2 :size="16" class="text-primary" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-sm font-semibold">인도네시아 타이어 시장 동향</div>
              <div class="text-xs text-muted-foreground mt-0.5">
                AGR · OTR · TBR 시장 현황 및 주요 고객사 동향 분석
              </div>
            </div>
            <div class="text-xs text-muted-foreground shrink-0">매일 09:00</div>
          </CardContent>
        </Card>

        <!-- 향후 추가 예정 -->
        <Card class="border-border/30 opacity-50">
          <CardContent class="p-4 flex items-center gap-3">
            <div class="w-9 h-9 rounded-lg bg-muted/40 flex items-center justify-center shrink-0">
              <FileBarChart2 :size="16" class="text-muted-foreground" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-sm font-semibold text-muted-foreground">주간 영업 요약</div>
              <div class="text-xs text-muted-foreground mt-0.5">준비 중</div>
            </div>
            <div class="text-xs text-muted-foreground shrink-0 border border-border/40 rounded px-1.5 py-0.5">예정</div>
          </CardContent>
        </Card>

        <Card class="border-border/30 opacity-50">
          <CardContent class="p-4 flex items-center gap-3">
            <div class="w-9 h-9 rounded-lg bg-muted/40 flex items-center justify-center shrink-0">
              <FileBarChart2 :size="16" class="text-muted-foreground" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-sm font-semibold text-muted-foreground">경쟁사 동향 분석</div>
              <div class="text-xs text-muted-foreground mt-0.5">준비 중</div>
            </div>
            <div class="text-xs text-muted-foreground shrink-0 border border-border/40 rounded px-1.5 py-0.5">예정</div>
          </CardContent>
        </Card>
      </div>
    </div>

    <!-- 스트리밍 중 -->
    <div v-if="loading && !sections.length" class="space-y-3">
      <div class="flex items-center gap-2 text-sm text-muted-foreground">
        <div class="w-4 h-4 rounded-full border-2 border-transparent border-t-primary animate-spin" />
        DB 검색 및 레포트 생성 중…
      </div>
      <Card class="border-primary/20 bg-primary/5">
        <CardContent class="p-4">
          <div class="text-sm text-foreground leading-relaxed whitespace-pre-wrap">
            {{ content }}<span class="inline-block w-1.5 h-4 bg-primary/60 animate-pulse ml-0.5 align-middle" />
          </div>
        </CardContent>
      </Card>
    </div>

    <!-- 완성된 레포트 -->
    <div v-if="report && sections.length" class="space-y-4">
      <!-- 메타 -->
      <div class="flex items-center gap-2 text-xs text-muted-foreground">
        <Clock :size="12" />
        {{ new Date(report.generated_at).toLocaleString('ko-KR') }} 생성
        <span class="ml-auto text-[10px] bg-primary/10 text-primary px-2 py-0.5 rounded-full">{{ report.topic }}</span>
      </div>

      <!-- 섹션별 카드 -->
      <div v-for="(sec, i) in sections" :key="i">
        <Card class="border-border/50">
          <CardContent class="p-4">
            <button
              class="w-full flex items-center justify-between text-left"
              @click="expanded[i] = !expanded[i]"
            >
              <span class="text-sm font-semibold">{{ sec.title }}</span>
              <component :is="expanded[i] ? ChevronUp : ChevronDown" :size="14" class="text-muted-foreground shrink-0" />
            </button>
            <div v-if="expanded[i] !== false" class="mt-3 text-sm text-muted-foreground leading-relaxed whitespace-pre-wrap">
              {{ sec.body }}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  </div>
</template>
