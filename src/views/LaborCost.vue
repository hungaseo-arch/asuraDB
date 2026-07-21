<script setup lang="ts">
// 경영·성과 › 인건비 — 지점별·월별 인원/인건비(Gross)/평균 인건비
// 데이터: src/data/payrollMonthly.ts (정적 SSOT). 라이트(화이트) 테마 · 기존 뷰(Margin/Monitor) 컨벤션 준수.
import { ref, computed } from 'vue';
import { Users, Wallet, Coins, CalendarRange } from 'lucide-vue-next';
import { Bar } from 'vue-chartjs';
import type { ChartData, ChartDataset, ChartOptions } from 'chart.js';
import '@/components/charts/chartSetup'; // Chart.js 1회 등록(Line/Bar/Point 포함)
import PageHeader from '@/components/PageHeader.vue';
import { PAYROLL_TABS, PAYROLL_MONTHS_2026, PAYROLL_UPDATED } from '@/data/payrollMonthly';

const cur = ref(0);
const tab = computed(() => PAYROLL_TABS[cur.value]);

const fmt = (n: number, d = 1) =>
  Number(n).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
const pct = (c: number, base: number) => (base ? ((c - base) / base) * 100 : null);
const deltaClass = (v: number | null) =>
  v == null ? 'text-muted-foreground' : v > 0 ? 'text-emerald-600' : v < 0 ? 'text-red-500' : 'text-muted-foreground';
const deltaText = (v: number | null) =>
  v == null ? '—' : `${v > 0 ? '▲' : v < 0 ? '▼' : '■'} ${Math.abs(v).toFixed(1)}%`;

// KPI(최신월=7월) → 2025 평균 대비 증감
const kpis = computed(() => {
  const t = tab.value;
  const i = t.total.m2026.length - 1;
  return [
    { icon: Users,  label: '인원 (최신월)',     value: fmt(t.total.m2026[i], 0),  unit: '명',
      delta: pct(t.total.m2026[i], t.total.avg2025), foot: 'vs 2025평균' },
    { icon: Wallet, label: '인건비 Gross (최신월)', value: fmt(t.salary.m2026[i], 1), unit: '백만IDR',
      delta: pct(t.salary.m2026[i], t.salary.avg2025), foot: 'vs 2025평균' },
    { icon: Coins,  label: '평균 인건비 (최신월)',   value: fmt(t.avgcost.m2026[i], 1), unit: '백만IDR/인',
      delta: pct(t.avgcost.m2026[i], t.avgcost.avg2025), foot: 'vs 2025평균' },
    { icon: CalendarRange, label: '2026 평균 인건비', value: fmt(t.salary.avg2026, 1), unit: '백만IDR/월',
      delta: null, foot: `2025평균 ${fmt(t.salary.avg2025, 1)}` },
  ];
});

// `var(--foo)` → 런타임 실제 색(라이트 테마). Chart.js canvas 는 CSS 변수를 못 읽어 직접 해석.
function cssVar(name: string, fallback: string): string {
  if (typeof document === 'undefined') return fallback;
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback;
}
const axisColor = cssVar('--muted-foreground', '#64748b');
const gridColor = 'rgba(15,23,42,.08)';   // 라이트 테마용 옅은 그리드
const BAR_BLUE = '#3b82f6';                // 마진 뷰 ASCENDO 색과 통일
const LINE_GREEN = '#10b981';

// 월별 추이 차트 (인건비 막대 + 인원 선, 이중 축)
const chartData = computed<ChartData<'bar'>>(() => ({
  labels: PAYROLL_MONTHS_2026,
  datasets: [
    { label: '인건비 (백만IDR)', data: tab.value.salary.m2026,
      backgroundColor: 'rgba(59,130,246,.5)', borderColor: BAR_BLUE, borderWidth: 1, yAxisID: 'y', order: 2 },
    // 혼합 차트: 인원 선(line) 데이터셋을 bar 차트에 얹음 (vue-chartjs 타입 한계로 캐스팅)
    ({ type: 'line', label: '인원 (명)', data: tab.value.total.m2026,
      borderColor: LINE_GREEN, backgroundColor: LINE_GREEN, tension: 0.3, pointRadius: 3, yAxisID: 'y1', order: 1
    } as unknown as ChartDataset<'bar'>),
  ],
}));
const chartOptions: ChartOptions<'bar'> = {
  responsive: true, maintainAspectRatio: false,
  interaction: { mode: 'index' as const, intersect: false },
  plugins: { legend: { labels: { color: axisColor, boxWidth: 12, font: { size: 11 } } } },
  scales: {
    x:  { ticks: { color: axisColor }, grid: { color: gridColor } },
    y:  { position: 'left' as const, title: { display: true, text: '인건비(백만IDR)', color: axisColor, font: { size: 10 } },
          ticks: { color: axisColor }, grid: { color: gridColor } },
    y1: { position: 'right' as const, beginAtZero: true, title: { display: true, text: '인원(명)', color: axisColor, font: { size: 10 } },
          ticks: { color: axisColor }, grid: { drawOnChartArea: false } },
  },
};

const notes = computed(() => {
  const t = tab.value;
  const n = [
    '인건비 = TOTAL GAJI GROSS(기본급+수당+회사부담 BPJS, 세전). 구분 = 원본 월시트 Section(Divisi) 그대로. 평균 인건비 = 인건비 ÷ 인원(천 단위).',
    '2025 평균 = 2025년 월별 평균, 2026 Avg = 1~7월 평균.',
  ];
  if (t.key === 'Semarang' || t.key === 'company')
    n.push('스마랑 2025년 10월 개소 → 지점 2025평균은 10~12월(3개월), 전사 탭의 스마랑 행은 연간 12개월 기준.');
  if (t.key === 'HQ Jakarta')
    n.push('HQ 2025.11 조직개편 · SALES ADMIN → SALES FINANCE&ADMIN/PURCHASING 분리, LOCAL SALES·EXIM 통합(원본 명칭 유지).');
  if (t.key === 'Cikarang/Karawang WH')
    n.push('창고 2025 Cikarang → 2026 Karawang 이전분 동일 지점으로 연속 집계.');
  return n;
});
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">
    <PageHeader
      title="인건비"
      :subtitle="`지점별·월별 인원 / 인건비(Gross) / 평균 인건비 · 단위: 인원=명, 인건비=백만 IDR(Juta) · 기준 ${PAYROLL_UPDATED}`"
    >
      <template #controls>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="(t, i) in PAYROLL_TABS" :key="t.key"
            class="px-3 py-1.5 rounded-lg border text-xs font-semibold transition-colors"
            :class="i === cur
              ? 'bg-primary/15 border-primary/40 text-primary'
              : 'bg-card border-border text-foreground/80 hover:bg-accent'"
            @click="cur = i"
          >{{ t.name }}</button>
        </div>
      </template>
    </PageHeader>

    <!-- KPI 카드 -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div v-for="k in kpis" :key="k.label" class="rounded-xl border border-border bg-card p-4">
        <div class="flex items-center gap-1.5 text-[11.5px] text-muted-foreground mb-1.5">
          <component :is="k.icon" :size="14" /> {{ k.label }}
        </div>
        <p class="text-2xl font-extrabold tabular-nums">
          {{ k.value }} <span class="text-xs text-muted-foreground font-semibold">{{ k.unit }}</span>
        </p>
        <p class="text-[11.5px] mt-1 tabular-nums" :class="deltaClass(k.delta)">
          {{ deltaText(k.delta) }} <span class="text-muted-foreground">{{ k.foot }}</span>
        </p>
      </div>
    </div>

    <!-- 월별 추이 차트 -->
    <div class="rounded-xl border border-border bg-card p-4">
      <h2 class="text-sm font-semibold mb-3">2026년 월별 추이 — 인건비(막대) · 인원(선)</h2>
      <div class="relative h-75">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
    </div>

    <!-- 피벗 표 -->
    <div class="rounded-xl border border-border bg-card p-4">
      <h2 class="text-sm font-semibold mb-3">{{ tab.name }} — 월별 상세</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-xs tabular-nums whitespace-nowrap border-collapse">
          <thead>
            <tr class="text-muted-foreground">
              <th rowspan="2" class="text-left font-semibold px-2 py-2 border-b border-border">구분 (Kategori)</th>
              <th rowspan="2" class="px-2 py-2 border-b border-border bg-muted/40">2025<br>평균</th>
              <th :colspan="PAYROLL_MONTHS_2026.length" class="px-2 py-1 border-b border-border">2026</th>
              <th rowspan="2" class="px-2 py-2 border-b border-border bg-primary/10 text-primary">2026<br>Avg</th>
            </tr>
            <tr class="text-muted-foreground">
              <th v-for="m in PAYROLL_MONTHS_2026" :key="m" class="px-2 py-1.5 border-b border-border font-semibold">{{ m }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in tab.rows" :key="r.label" class="border-b border-border/50">
              <td class="text-left px-2 py-2 text-foreground/90">{{ r.label }}</td>
              <td class="text-center px-2 py-2 bg-muted/20">{{ fmt(r.avg2025, 1) }}</td>
              <td v-for="(v, i) in r.m2026" :key="i" class="text-center px-2 py-2">{{ fmt(v, 0) }}</td>
              <td class="text-center px-2 py-2 bg-primary/5">{{ fmt(r.avg2026, 1) }}</td>
            </tr>
            <tr class="border-b border-border bg-muted/40 font-bold">
              <td class="text-left px-2 py-2">인원 합계 (명)</td>
              <td class="text-center px-2 py-2">{{ fmt(tab.total.avg2025, 1) }}</td>
              <td v-for="(v, i) in tab.total.m2026" :key="i" class="text-center px-2 py-2">{{ fmt(v, 0) }}</td>
              <td class="text-center px-2 py-2">{{ fmt(tab.total.avg2026, 1) }}</td>
            </tr>
            <tr class="border-b border-border bg-primary/10 font-bold text-primary">
              <td class="text-left px-2 py-2">인건비 Gross (백만IDR)</td>
              <td class="text-center px-2 py-2">{{ fmt(tab.salary.avg2025, 1) }}</td>
              <td v-for="(v, i) in tab.salary.m2026" :key="i" class="text-center px-2 py-2">{{ fmt(v, 1) }}</td>
              <td class="text-center px-2 py-2">{{ fmt(tab.salary.avg2026, 1) }}</td>
            </tr>
            <tr class="bg-muted/20">
              <td class="text-left px-2 py-2">평균 인건비 (백만IDR/인)</td>
              <td class="text-center px-2 py-2">{{ fmt(tab.avgcost.avg2025, 1) }}</td>
              <td v-for="(v, i) in tab.avgcost.m2026" :key="i" class="text-center px-2 py-2">{{ fmt(v, 1) }}</td>
              <td class="text-center px-2 py-2">{{ fmt(tab.avgcost.avg2026, 1) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <ul class="mt-3 space-y-1 text-[11px] text-muted-foreground list-disc pl-4">
        <li v-for="(nt, i) in notes" :key="i">{{ nt }}</li>
      </ul>
    </div>
  </div>
</template>
