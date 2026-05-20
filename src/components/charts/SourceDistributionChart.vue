<script setup lang="ts">
import { computed } from 'vue';
import { Doughnut } from 'vue-chartjs';
import type { ChartData, ChartOptions } from 'chart.js';
import '@/components/charts/chartSetup';
import { sourceDistribution } from '@/data';

// React: recharts <PieChart><Pie innerRadius={36} outerRadius={56} /></PieChart>.
// Vue: Chart.js Doughnut with matching cutout ratio.

// `var(--color-chart-N)` is resolved at runtime via getComputedStyle.
function resolveCssVar(value: string): string {
  const match = value.match(/var\((--[^)]+)\)/);
  if (!match) return value;
  if (typeof document === 'undefined') return value;
  return getComputedStyle(document.documentElement).getPropertyValue(match[1]).trim() || value;
}

const chartData = computed<ChartData<'doughnut'>>(() => ({
  labels: sourceDistribution.map((s) => s.name),
  datasets: [
    {
      data: sourceDistribution.map((s) => s.value),
      backgroundColor: sourceDistribution.map((s) => resolveCssVar(s.fill)),
      borderWidth: 0,
      hoverOffset: 4,
    },
  ],
}));

const options: ChartOptions<'doughnut'> = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '60%',
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(20,20,30,0.95)',
      borderColor: 'rgba(255,255,255,0.08)',
      borderWidth: 1,
      callbacks: {
        label: (ctx) => `${ctx.parsed.toLocaleString()}건`,
      },
    },
  },
};
</script>

<template>
  <div class="relative w-full" style="height: 130px;">
    <Doughnut :data="chartData" :options="options" />
  </div>
</template>
