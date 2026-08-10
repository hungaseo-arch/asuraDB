<script setup lang="ts">
import { computed } from 'vue';
import { Line } from 'vue-chartjs';
import type { ChartData, ChartOptions } from 'chart.js';
import { chartColor } from '@/components/charts/chartSetup';
import { searchVolumeData } from '@/data';

// React equivalent: recharts <AreaChart> with 4 stacked Areas + linearGradient defs.
// Here we use vue-chartjs <Line> with `fill: true` + per-dataset gradients (via colors).
type SourceKey = 'notion' | 'upnote' | 'gmail' | 'drive';

// chart-N 매핑은 SourceDistributionChart(src/data sourceDistribution)와 동일한
// 순서(Notion/UpNote/Gmail/Drive)로 맞춰 두 차트에서 같은 소스가 같은 색을 쓴다.
const sourceMeta: Record<SourceKey, { label: string; color: string }> = {
  notion: { label: 'Notion',       color: chartColor(1) },
  upnote: { label: 'UpNote',       color: chartColor(2) },
  gmail:  { label: 'Gmail',        color: chartColor(3) },
  drive:  { label: 'Google Drive', color: chartColor(4) },
};

const chartData = computed<ChartData<'line'>>(() => ({
  labels: searchVolumeData.map((d) => d.date),
  datasets: (Object.keys(sourceMeta) as SourceKey[]).map((key) => {
    const { label, color } = sourceMeta[key];
    return {
      label,
      data: searchVolumeData.map((d) => d[key]),
      borderColor: color,
      backgroundColor: color + '4D', // ~30% alpha — fills the area below the line.
      borderWidth: 1.5,
      fill: true,
      tension: 0.35,
      pointRadius: 0,
      pointHoverRadius: 4,
    };
  }),
}));

const options: ChartOptions<'line'> = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: {
      position: 'bottom',
      labels: { boxWidth: 8, boxHeight: 8, font: { size: 11 }, usePointStyle: true },
    },
    tooltip: {
      backgroundColor: 'rgba(20,20,30,0.95)',
      borderColor: 'rgba(255,255,255,0.08)',
      borderWidth: 1,
      titleFont: { size: 12 },
      bodyFont: { size: 11 },
    },
  },
  scales: {
    x: {
      grid: { color: 'rgba(255,255,255,0.06)' },
      ticks: { font: { size: 11 }, color: 'rgba(180,180,200,0.7)' },
      border: { display: false },
    },
    y: {
      grid: { color: 'rgba(255,255,255,0.06)' },
      ticks: { font: { size: 11 }, color: 'rgba(180,180,200,0.7)' },
      border: { display: false },
      beginAtZero: true,
    },
  },
};
</script>

<template>
  <div class="relative w-full" style="height: 200px;">
    <Line :data="chartData" :options="options" />
  </div>
</template>
