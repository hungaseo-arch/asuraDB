<script setup lang="ts">
import { TrendingUp, TrendingDown, Search as SearchIcon, RefreshCw, Bot } from 'lucide-vue-next';
import Badge from '@/components/ui/Badge.vue';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import SourceIcon from '@/components/icons/SourceIcon.vue';
import NotionIcon from '@/components/icons/NotionIcon.vue';
import GmailIcon from '@/components/icons/GmailIcon.vue';
import GoogleDriveIcon from '@/components/icons/GoogleDriveIcon.vue';
import SearchVolumeChart from '@/components/charts/SearchVolumeChart.vue';
import SourceDistributionChart from '@/components/charts/SourceDistributionChart.vue';
import {
  kpiData, sourceStats, recentActivity, sourceDistribution, totalDocs,
} from '@/data';
import { cn } from '@/lib/utils';

// Framer-motion stagger replaced with @vueuse/motion directives (`v-motion-*`).
// CSS classes/animations stay identical to the React version.

function activityColor(type: string): string {
  if (type === 'search') return 'text-primary bg-primary/10';
  if (type === 'sync')   return 'text-green-400 bg-green-400/10';
  if (type === 'agent')  return 'text-yellow-400 bg-yellow-400/10';
  return 'text-muted-foreground bg-muted';
}

const statusBadge: Record<string, { label: string; className: string }> = {
  synced:  { label: '동기화', className: 'border-green-500/30 text-green-400 bg-green-400/5' },
  syncing: { label: '동기 중', className: 'border-yellow-500/30 text-yellow-400 bg-yellow-400/5 animate-pulse' },
  error:   { label: '오류',    className: 'border-red-500/30 text-red-400' },
  planned: { label: '예정',    className: 'border-violet-500/30 text-violet-400 bg-violet-400/5' },
};
</script>

<template>
  <div
    v-motion
    :initial="{ opacity: 0, y: 16 }"
    :enter="{ opacity: 1, y: 0, transition: { duration: 350 } }"
    class="p-4 md:p-6 space-y-6"
  >
    <!-- Page title -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-xl font-bold text-foreground">대시보드</h1>
        <p class="text-sm text-muted-foreground mt-0.5">
          총 <span class="text-foreground font-semibold">{{ totalDocs.toLocaleString() }}</span>개 청크 · 4개 소스 통합
        </p>
      </div>
      <Badge variant="outline" class="text-xs gap-1 border-primary/30 text-primary">
        마지막 업데이트 5분 전
      </Badge>
    </div>

    <!-- KPI Cards -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
      <div v-for="kpi in kpiData" :key="kpi.label">
        <Card
          class="border-border/60"
          style="box-shadow: 0 4px 20px color-mix(in srgb, var(--primary) 6%, transparent);"
        >
          <CardContent class="p-4">
            <div class="text-xs text-muted-foreground mb-1">{{ kpi.label }}</div>
            <div class="text-2xl font-bold text-foreground">{{ kpi.value }}</div>
            <div
              :class="cn(
                'text-xs mt-1 flex items-center gap-1',
                kpi.deltaDir === 'up' ? 'text-green-400' : 'text-red-400',
              )"
            >
              <TrendingUp v-if="kpi.deltaDir === 'up'" :size="11" />
              <TrendingDown v-else :size="11" />
              {{ kpi.delta }} 오늘
            </div>
          </CardContent>
        </Card>
      </div>
    </div>

    <!-- Charts Row -->
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <!-- Search Volume -->
      <div class="lg:col-span-2">
        <Card class="border-border/60 h-full">
          <CardHeader class="pb-2">
            <CardTitle class="text-sm font-semibold">소스별 검색량 (최근 7일)</CardTitle>
          </CardHeader>
          <CardContent>
            <SearchVolumeChart />
          </CardContent>
        </Card>
      </div>

      <!-- Source Distribution -->
      <div>
        <Card class="border-border/60 h-full">
          <CardHeader class="pb-2">
            <CardTitle class="text-sm font-semibold">문서 소스 분포</CardTitle>
          </CardHeader>
          <CardContent>
            <SourceDistributionChart />
            <div class="space-y-1.5 mt-1">
              <div
                v-for="s in sourceDistribution"
                :key="s.name"
                class="flex items-center justify-between text-xs"
              >
                <div class="flex items-center gap-1.5">
                  <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ background: s.fill }" />
                  <span class="text-muted-foreground">{{ s.name }}</span>
                </div>
                <span class="font-mono text-foreground/80">{{ s.value.toLocaleString() }}</span>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>

    <!-- Sources + Activity -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <!-- Source Status -->
      <div>
        <Card class="border-border/60">
          <CardHeader class="pb-2">
            <CardTitle class="text-sm font-semibold">데이터 소스 현황</CardTitle>
          </CardHeader>
          <CardContent class="space-y-2">
            <div
              v-for="s in sourceStats"
              :key="s.source"
              class="flex items-center gap-3 p-2.5 rounded-lg bg-muted/30 hover:bg-muted/50 transition-colors"
            >
              <div
                class="w-7 h-7 rounded-md flex items-center justify-center text-sm flex-shrink-0"
                :style="{ background: s.color + '18', color: s.color }"
              >
                <NotionIcon v-if="s.source === 'notion'" :size="14" />
                <span v-else-if="s.source === 'upnote'" class="text-[10px] font-bold">UN</span>
                <GmailIcon v-else-if="s.source === 'gmail'" :size="14" />
                <GoogleDriveIcon v-else-if="s.source === 'drive'" :size="14" />
                <span v-else-if="s.source === 'obsidian'" class="text-[10px] font-bold">OB</span>
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-foreground">{{ s.label }}</span>
                  <Badge
                    variant="outline"
                    :class="cn('text-[9px] px-1.5 py-0 h-4', statusBadge[s.status].className)"
                  >
                    {{ statusBadge[s.status].label }}
                  </Badge>
                </div>
                <div class="text-xs text-muted-foreground">
                  {{ s.count > 0 ? `${s.count.toLocaleString()}개 청크` : '미연동' }} · {{ s.lastSync }}
                </div>
              </div>
              <div v-if="s.count > 0" class="text-right flex-shrink-0">
                <div class="text-sm font-semibold text-foreground">
                  {{ Math.round((s.count / totalDocs) * 100) }}%
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <!-- Recent Activity -->
      <div>
        <Card class="border-border/60">
          <CardHeader class="pb-2">
            <CardTitle class="text-sm font-semibold">최근 활동</CardTitle>
          </CardHeader>
          <CardContent class="space-y-2">
            <div
              v-for="act in recentActivity"
              :key="act.id"
              class="flex items-start gap-2.5 p-2 rounded-lg hover:bg-muted/30 transition-colors"
            >
              <div
                :class="cn(
                  'w-6 h-6 rounded-md flex items-center justify-center flex-shrink-0 mt-0.5',
                  activityColor(act.type),
                )"
              >
                <SearchIcon v-if="act.type === 'search'" :size="12" />
                <RefreshCw v-else-if="act.type === 'sync'" :size="12" />
                <Bot v-else-if="act.type === 'agent'" :size="12" />
              </div>
              <div class="flex-1 min-w-0">
                <div class="text-xs text-foreground/80 leading-relaxed">{{ act.message }}</div>
                <div class="flex items-center gap-1.5 mt-0.5">
                  <span v-if="act.source" class="text-muted-foreground/60">
                    <SourceIcon :source="act.source" :size="12" />
                  </span>
                  <span class="text-[10px] text-muted-foreground/50">{{ act.time }}</span>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  </div>
</template>
