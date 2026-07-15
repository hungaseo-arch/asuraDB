<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { Line, Bar } from 'vue-chartjs';
import type { ChartData, ChartOptions } from 'chart.js';
import { X, LineChart, BarChart3 } from 'lucide-vue-next';
import '@/components/charts/chartSetup';

// 카드 클릭 시 열리는 추이 모달 — 월간(선택 연도 12개월) / 연간(연도별 합계) 탭.
// 분모(denom: 매출) 시계열이 있으면 금액/비율(매출 대비 %) 토글 제공.

export interface TrendSeries {
  label: string;
  unit: string;                  // 'pcs' | 'USD'
  months: string[];              // 전체 기간 'YYYY-MM' (정렬됨, 다년도)
  target: (number | null)[];
  actual: (number | null)[];
  denomTarget?: (number | null)[]; // 비율 모드용 분모(매출) 목표
  denomActual?: (number | null)[]; // 비율 모드용 분모(매출) 실적
  ratioLabel?: string;             // 비율 모드 부제 (예: '매출 대비')
}

const props = defineProps<{
  open: boolean;
  title: string;
  subtitle?: string;
  info?: string;              // 지표 간략 설명 (있으면 본문 상단에 표시)
  source?: string;            // 데이터 출처 (있으면 표시)
  series: TrendSeries[];
  year: number;
  years: number[];
}>();

const emit = defineEmits<{ (e: 'close'): void }>();

const chartType = ref<'line' | 'bar'>('line');
const period    = ref<'month' | 'year'>('month');
const valueMode = ref<'amount' | 'ratio'>('amount');

const hasDenom = computed(() => props.series.some(s => !!s.denomActual || !!s.denomTarget));
// 목표 시계열 유무 — 산업 지표(수집값만)는 목표가 없어 목표 관련 UI를 숨긴다
const hasTarget = computed(() => props.series.some(s => (s.target ?? []).some(v => v !== null && v !== undefined)));

watch(period, p => { chartType.value = p === 'year' ? 'bar' : 'line'; });
// 열릴 때 초기화 — 분모가 있으면 '비율'을 기본으로
watch(() => props.open, (o) => {
  if (o) {
    period.value = 'month';
    chartType.value = 'line';
    valueMode.value = hasDenom.value ? 'ratio' : 'amount';
  }
});

const TARGET_COLOR = '#94a3b8';
const ACTUAL_COLOR = '#3b82f6';

function fmt(v: number | null, unit: string): string {
  if (v === null || v === undefined || Number.isNaN(v)) return '—';
  if (unit === '%')   return v.toFixed(1);
  if (unit === 'pcs') return Math.round(v).toLocaleString('en-US');
  return v.toLocaleString('en-US', { maximumFractionDigits: 0 });
}
function unitSuffix(unit: string): string {
  return unit === '%' ? '%' : unit === 'pcs' ? ' pcs' : ' $';
}
function unitFor(s: TrendSeries): string {
  return valueMode.value === 'ratio' ? '%' : s.unit;
}

// ── 집계 ───────────────────────────────────────────────────────────────────────

function monthIdx(s: TrendSeries, year: number): number[] {
  const out: number[] = [];
  s.months.forEach((m, i) => { if (m.slice(0, 4) === String(year)) out.push(i); });
  return out;
}
function sumIdx(arr: (number | null)[] | undefined, idx: number[]): number | null {
  if (!arr) return null;
  const f = idx.filter(i => arr[i] !== null && arr[i] !== undefined);
  return f.length ? f.reduce((a, i) => a + (arr[i] as number), 0) : null;
}

// 비율 모드: 값 = 분자/분모*100 (분모 없으면 null)
function toDisplay(num: (number | null)[], den: (number | null)[]): (number | null)[] {
  if (valueMode.value !== 'ratio') return num;
  return num.map((n, i) => {
    const d = den[i];
    return (n !== null && n !== undefined && d !== null && d !== undefined && d !== 0) ? (n / d) * 100 : null;
  });
}

function periodData(s: TrendSeries) {
  if (period.value === 'month') {
    const idx = monthIdx(s, props.year);
    return {
      labels: idx.map(i => s.months[i].slice(5)),
      tNum: idx.map(i => s.target[i]),
      tDen: idx.map(i => s.denomTarget?.[i] ?? null),
      aNum: idx.map(i => s.actual[i]),
      aDen: idx.map(i => s.denomActual?.[i] ?? null),
    };
  }
  return {
    labels: props.years.map(String),
    tNum: props.years.map(y => sumIdx(s.target, monthIdx(s, y))),
    tDen: props.years.map(y => sumIdx(s.denomTarget, monthIdx(s, y))),
    aNum: props.years.map(y => sumIdx(s.actual, monthIdx(s, y))),
    aDen: props.years.map(y => sumIdx(s.denomActual, monthIdx(s, y))),
  };
}

// 선택 연도 YTD 요약 (금액 + 비율 둘 다 산출)
function annual(s: TrendSeries) {
  const idx = monthIdx(s, props.year);
  let lastActual = -1;
  idx.forEach((i, k) => { if (s.actual[i] !== null && s.actual[i] !== undefined) lastActual = k; });
  let aNum = 0, aDen = 0, tNum = 0, tDen = 0, ftNum = 0, ftDen = 0;
  idx.forEach((i, k) => {
    if (s.actual[i] !== null && s.actual[i] !== undefined) {
      aNum += s.actual[i]!; aDen += s.denomActual?.[i] ?? 0;
    }
    if (s.target[i] !== null && s.target[i] !== undefined) {
      ftNum += s.target[i]!; ftDen += s.denomTarget?.[i] ?? 0;
      if (k <= lastActual) { tNum += s.target[i]!; tDen += s.denomTarget?.[i] ?? 0; }
    }
  });
  const ratio = (n: number, d: number) => (d > 0 ? (n / d) * 100 : null);
  return {
    ytdMonths: lastActual + 1,
    // 금액
    actualSum: aNum, targetToDate: tNum, fullTarget: ftNum,
    achv: tNum > 0 ? (aNum / tNum) * 100 : null,
    // 비율 (매출 대비)
    actualRatio: ratio(aNum, aDen), targetRatio: ratio(tNum, tDen), fullTargetRatio: ratio(ftNum, ftDen),
  };
}

const annuals = computed(() => props.series.map(annual));

function chartDataFor(s: TrendSeries): ChartData<'line' | 'bar'> {
  const pd = periodData(s);
  const target = toDisplay(pd.tNum, pd.tDen);
  const actual = toDisplay(pd.aNum, pd.aDen);
  const targetDataset = {
    label: '목표',
    data: target as number[],
    borderColor: TARGET_COLOR,
    backgroundColor: chartType.value === 'bar' ? TARGET_COLOR + '88' : TARGET_COLOR + '22',
    borderWidth: 1.5,
    borderDash: chartType.value === 'line' ? [5, 4] : undefined,
    tension: 0.3,
    pointRadius: chartType.value === 'line' ? 2 : 0,
    pointHoverRadius: 4,
    fill: false,
    spanGaps: true,
  };
  return {
    labels: pd.labels,
    datasets: [
      // 목표 시계열이 있을 때만 목표 데이터셋 포함
      ...(hasTarget.value ? [targetDataset] : []),
      {
        label: '실적',
        data: actual as number[],
        borderColor: ACTUAL_COLOR,
        backgroundColor: chartType.value === 'bar' ? ACTUAL_COLOR + 'cc' : ACTUAL_COLOR + '33',
        borderWidth: 2,
        tension: 0.3,
        pointRadius: chartType.value === 'line' ? 2.5 : 0,
        pointHoverRadius: 5,
        fill: chartType.value === 'line',
        spanGaps: true,
      },
    ],
  };
}

function optionsFor(unit: string): ChartOptions<'line' | 'bar'> {
  const ratioMode = valueMode.value === 'ratio';
  return {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: {
        position: 'top',
        align: 'end',
        labels: { boxWidth: 10, boxHeight: 10, font: { size: 11 }, usePointStyle: true, color: 'rgba(180,180,200,0.85)' },
      },
      tooltip: {
        backgroundColor: 'rgba(20,20,30,0.95)',
        borderColor: 'rgba(255,255,255,0.08)',
        borderWidth: 1,
        callbacks: {
          label: (ctx) => `${ctx.dataset.label}: ${fmt(ctx.parsed.y, unit)}${unitSuffix(unit)}`,
          // 금액 모드에서만 달성률(실적/목표) 표시
          footer: (items) => {
            if (ratioMode) return '';
            const t = items.find(i => i.dataset.label === '목표')?.parsed.y;
            const a = items.find(i => i.dataset.label === '실적')?.parsed.y;
            if (t == null || a == null || t === 0) return '';
            return `달성률: ${(a / t * 100).toFixed(1)}%`;
          },
        },
      },
    },
    scales: {
      x: {
        grid: { color: 'rgba(255,255,255,0.05)' },
        ticks: { font: { size: 10 }, color: 'rgba(180,180,200,0.6)' },
        border: { display: false },
      },
      y: {
        grid: { color: 'rgba(255,255,255,0.05)' },
        ticks: { font: { size: 10 }, color: 'rgba(180,180,200,0.6)', callback: (v) => fmt(Number(v), unit) },
        border: { display: false },
      },
    },
  };
}
</script>

<template>
  <transition
    enter-active-class="transition-opacity duration-150"
    enter-from-class="opacity-0"
    leave-active-class="transition-opacity duration-150"
    leave-to-class="opacity-0"
  >
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="emit('close')"
    >
      <div class="bg-card border border-border rounded-2xl w-full max-w-3xl shadow-2xl max-h-[90vh] overflow-y-auto">
        <!-- Header -->
        <div class="flex items-start justify-between p-5 border-b border-border sticky top-0 bg-card z-10">
          <div>
            <h3 class="font-semibold text-base text-foreground">{{ title }}</h3>
            <p v-if="subtitle" class="text-xs text-muted-foreground mt-0.5">{{ subtitle }}</p>
          </div>
          <div class="flex items-center gap-2 flex-wrap justify-end">
            <!-- 금액 / 비율 (분모 있을 때만) -->
            <div v-if="hasDenom" class="flex rounded-lg border border-border overflow-hidden text-xs">
              <button
                :class="['px-2.5 py-1 transition-colors', valueMode === 'amount' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-accent']"
                @click="valueMode = 'amount'"
              >금액</button>
              <button
                :class="['px-2.5 py-1 transition-colors', valueMode === 'ratio' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-accent']"
                @click="valueMode = 'ratio'"
              >비율</button>
            </div>
            <!-- 월간 / 연간 -->
            <div class="flex rounded-lg border border-border overflow-hidden text-xs">
              <button
                :class="['px-2.5 py-1 transition-colors', period === 'month' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-accent']"
                @click="period = 'month'"
              >월간</button>
              <button
                :class="['px-2.5 py-1 transition-colors', period === 'year' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-accent']"
                @click="period = 'year'"
              >연간</button>
            </div>
            <!-- Line / Bar -->
            <div class="flex rounded-lg border border-border overflow-hidden">
              <button
                :class="['p-1.5 transition-colors', chartType === 'line' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-accent']"
                title="라인 차트"
                @click="chartType = 'line'"
              ><LineChart :size="14" /></button>
              <button
                :class="['p-1.5 transition-colors', chartType === 'bar' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-accent']"
                title="바 차트"
                @click="chartType = 'bar'"
              ><BarChart3 :size="14" /></button>
            </div>
            <button class="p-1.5 rounded-lg hover:bg-accent text-muted-foreground" @click="emit('close')">
              <X :size="16" />
            </button>
          </div>
        </div>

        <!-- Series -->
        <div class="p-5 space-y-6">
          <!-- 지표 간략 설명 -->
          <p v-if="info" class="text-xs leading-relaxed text-muted-foreground bg-muted/40 border border-border rounded-lg px-3.5 py-2.5">
            {{ info }}
          </p>

          <!-- 데이터 출처 -->
          <p v-if="source" class="text-[11px] text-muted-foreground">
            <span class="font-semibold">출처</span> · {{ source }}
          </p>

          <div v-for="(s, i) in series" :key="s.label" class="space-y-3">
            <div class="flex items-center justify-between flex-wrap gap-2">
              <h4 class="text-sm font-medium text-foreground">
                {{ s.label }}
                <span v-if="valueMode === 'ratio'" class="text-muted-foreground font-normal">· {{ s.ratioLabel ?? '매출 대비' }} 비율</span>
                <span class="text-xs text-muted-foreground font-normal">({{ unitFor(s) }})</span>
              </h4>
              <!-- YTD 요약 -->
              <div v-if="valueMode === 'ratio'" class="flex items-center gap-3 text-xs">
                <span class="text-muted-foreground">
                  {{ year }} YTD <span class="font-semibold text-foreground tabular-nums">{{ fmt(annuals[i].actualRatio, '%') }}%</span>
                </span>
                <span class="text-muted-foreground">
                  / 목표 <span class="font-semibold text-foreground tabular-nums">{{ fmt(annuals[i].targetRatio, '%') }}%</span>
                </span>
              </div>
              <!-- 목표가 있는 지표만 YTD/목표/달성률 요약 표시 (산업 지표는 목표 없음 → 숨김) -->
              <div v-else-if="hasTarget" class="flex items-center gap-3 text-xs">
                <span class="text-muted-foreground">
                  {{ year }} YTD <span class="font-semibold text-foreground tabular-nums">{{ fmt(annuals[i].actualSum, s.unit) }}</span>
                </span>
                <span class="text-muted-foreground">
                  / 목표 <span class="font-semibold text-foreground tabular-nums">{{ fmt(annuals[i].targetToDate, s.unit) }}</span>
                </span>
                <span
                  v-if="annuals[i].achv !== null"
                  :class="['px-1.5 py-0.5 rounded font-semibold tabular-nums', annuals[i].achv! >= 100 ? 'bg-blue-500/15 text-blue-400' : 'bg-amber-500/15 text-amber-600']"
                >{{ annuals[i].achv!.toFixed(0) }}%</span>
              </div>
            </div>

            <div class="relative w-full" style="height: 240px;">
              <Bar  v-if="chartType === 'bar'" :data="(chartDataFor(s) as any)" :options="(optionsFor(unitFor(s)) as any)" />
              <Line v-else                      :data="(chartDataFor(s) as any)" :options="(optionsFor(unitFor(s)) as any)" />
            </div>

            <p class="text-[11px] text-muted-foreground">
              {{ period === 'month' ? `${year}년 월별` : '연도별 합계' }}
              <template v-if="valueMode === 'ratio'">
                · {{ year }} 연간 목표 비율 <span class="tabular-nums text-foreground/80">{{ fmt(annuals[i].fullTargetRatio, '%') }}%</span>
              </template>
              <template v-else-if="hasTarget">
                · {{ year }} 연간 목표 <span class="tabular-nums text-foreground/80">{{ fmt(annuals[i].fullTarget, s.unit) }}</span>
              </template>
            </p>
          </div>
        </div>
      </div>
    </div>
  </transition>
</template>
