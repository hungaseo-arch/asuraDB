<script setup lang="ts">
import { CheckCircle2, Circle, Clock, Zap } from 'lucide-vue-next';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import Badge from '@/components/ui/Badge.vue';
import { roadmapPhases, type RoadmapPhase } from '@/data';
import { cn } from '@/lib/utils';

interface ArchNode {
  id: string;
  label: string;
  sub: string;
  color: string;
  col: number;
}

const archNodes: ArchNode[] = [
  { id: 'sources',  label: 'SOURCES',       sub: 'Notion · UpNote · Gmail · Drive\n(향후: Obsidian)', color: '#818cf8', col: 0 },
  { id: 'pipeline', label: 'INGESTION',     sub: 'MD Parse → Chunking\nMetadata → Embedding',         color: '#60a5fa', col: 1 },
  { id: 'supabase', label: 'SUPABASE',      sub: 'PostgreSQL + pgvector\n+ Storage',                  color: '#4ade80', col: 2 },
  { id: 'search',   label: 'HYBRID SEARCH', sub: 'FTS + Vector + Metadata\n→ RRF 결합',               color: '#f59e0b', col: 3 },
  { id: 'agent',    label: 'MCP AGENT',     sub: 'Ollama + 5개 도구\n질의응답 · 이메일 초안',          color: '#f87171', col: 4 },
];

type PhaseStatus = RoadmapPhase['status'];
const phaseStatus: Record<PhaseStatus, { label: string; className: string }> = {
  completed:     { label: '완료',    className: 'border-green-500/30 text-green-400 bg-green-400/8' },
  'in-progress': { label: '진행 중', className: 'border-yellow-500/30 text-yellow-400 bg-yellow-400/8 animate-pulse' },
  pending:       { label: '대기',    className: 'border-blue-500/30 text-blue-400 bg-blue-400/8' },
  planned:       { label: '계획',    className: 'border-violet-500/30 text-violet-400 bg-violet-400/8' },
};

const stackLabels = [
  { label: '임베딩 모델', value: 'paraphrase-multilingual-MiniLM-L12-v2 (384dim)' },
  { label: 'AI 검색',      value: 'Ollama qwen3:8b' },
  { label: 'AI Agent',   value: 'Ollama qwen3:8b (MCP)' },
  { label: '검색 방식',   value: 'FTS + Vector → RRF Fusion' },
];

function phaseBgColor(status: PhaseStatus): string {
  if (status === 'completed')   return 'bg-green-400/15 text-green-400';
  if (status === 'in-progress') return 'bg-yellow-400/15 text-yellow-400';
  if (status === 'pending')     return 'bg-blue-400/15 text-blue-400';
  return 'bg-violet-400/15 text-violet-400';
}
</script>

<template>
  <div
    v-motion
    :initial="{ opacity: 0, y: 16 }"
    :enter="{ opacity: 1, y: 0, transition: { duration: 320 } }"
    class="p-4 md:p-6 space-y-6"
  >
    <div>
      <h1 class="text-xl font-bold">시스템 아키텍처 &amp; 로드맵</h1>
      <p class="text-sm text-muted-foreground mt-0.5">
        AsuraDB TO-BE 목표 아키텍처 및 개발 단계별 진행 현황
      </p>
    </div>

    <!-- Architecture Diagram -->
    <Card class="border-border/60">
      <CardHeader class="pb-3">
        <CardTitle class="text-sm font-semibold flex items-center gap-2">
          <Zap :size="14" class="text-primary" /> 시스템 흐름도
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div class="relative overflow-x-auto">
          <div class="flex items-center gap-0 min-w-150 py-4">
            <template v-for="(node, idx) in archNodes" :key="node.id">
              <div class="flex items-center flex-1 min-w-0">
                <div class="flex-1 flex flex-col items-center">
                  <div
                    class="w-full max-w-30 rounded-xl p-3 text-center border transition-all hover:scale-105"
                    :style="{
                      background: node.color + '12',
                      borderColor: node.color + '40',
                      boxShadow: '0 4px 16px ' + node.color + '20',
                    }"
                  >
                    <div
                      class="text-[10px] font-bold uppercase tracking-wider mb-1"
                      :style="{ color: node.color }"
                    >
                      {{ node.label }}
                    </div>
                    <div class="text-[9px] text-muted-foreground whitespace-pre-line leading-relaxed">
                      {{ node.sub }}
                    </div>
                  </div>
                </div>
                <div v-if="idx < archNodes.length - 1" class="shrink-0 px-1">
                  <div class="flex flex-col items-center gap-0.5">
                    <div class="w-6 h-px bg-border/60" />
                    <div class="w-0 h-0 border-l-4 border-y-[3px] border-y-transparent border-l-border/60" />
                  </div>
                </div>
              </div>
            </template>
          </div>
        </div>

        <!-- Stack Labels -->
        <div class="mt-4 pt-4 border-t border-border/40 grid grid-cols-2 md:grid-cols-4 gap-3">
          <div
            v-for="s in stackLabels"
            :key="s.label"
            class="p-2.5 rounded-lg bg-muted/20 border border-border/40"
          >
            <div class="text-[10px] text-muted-foreground">{{ s.label }}</div>
            <div class="text-xs font-medium text-foreground mt-0.5 leading-snug">{{ s.value }}</div>
          </div>
        </div>
      </CardContent>
    </Card>

    <!-- Roadmap -->
    <div>
      <h2 class="text-base font-semibold mb-3">개발 로드맵</h2>
      <div class="space-y-3">
        <Card
          v-for="phase in roadmapPhases"
          :key="phase.phase"
          :class="cn(
            'border-border/50 transition-all',
            phase.status === 'in-progress' && 'border-yellow-500/30',
            phase.status === 'completed' && 'border-green-500/20',
          )"
        >
          <CardContent class="p-4">
            <div class="flex items-start gap-3">
              <!-- Phase Number -->
              <div
                :class="cn(
                  'w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold shrink-0',
                  phaseBgColor(phase.status),
                )"
              >
                {{ phase.phase }}
              </div>

              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <h3 class="text-sm font-semibold text-foreground">
                    Phase {{ phase.phase }} — {{ phase.title }}
                  </h3>
                  <Badge
                    variant="outline"
                    :class="cn('text-[9px] px-1.5 py-0 h-4', phaseStatus[phase.status].className)"
                  >
                    {{ phaseStatus[phase.status].label }}
                  </Badge>
                  <span class="text-[10px] text-muted-foreground ml-auto">
                    <Clock :size="9" class="inline mr-0.5" />{{ phase.duration }}
                  </span>
                </div>

                <ul class="mt-2.5 grid grid-cols-1 md:grid-cols-2 gap-1">
                  <li
                    v-for="(item, i) in phase.items"
                    :key="i"
                    class="flex items-start gap-1.5 text-xs text-muted-foreground"
                  >
                    <CheckCircle2
                      v-if="phase.status === 'completed'"
                      :size="12"
                      class="text-green-400 shrink-0 mt-0.5"
                    />
                    <Circle
                      v-else
                      :size="12"
                      :class="cn(
                        'shrink-0 mt-0.5',
                        phase.status === 'in-progress' ? 'text-yellow-400/70' : 'text-muted-foreground/40',
                      )"
                    />
                    {{ item }}
                  </li>
                </ul>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  </div>
</template>
