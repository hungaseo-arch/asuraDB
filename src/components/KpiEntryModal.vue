<script setup lang="ts">
/**
 * KPI 월별 실적/목표 입력창.
 *
 * ⚠ SSOT 주의 (CLAUDE.md §데이터 SSOT):
 *   `data/kpi/<YYYY>.csv` → kpi_importer.py → kpi_monthly 가 진실원천이라,
 *   브라우저에서 DB 에만 쓰면 importer 재실행 시 입력값이 되돌아간다.
 *   그래서 여기서 저장한 행은 source='manual' 로 표시하고 kpi_importer 가 해당 행을 건너뛴다.
 *   (CSV 를 다시 진실원천으로 삼으려면 그 행 source 를 'csv' 로 바꾸고 importer 재실행)
 */
import { ref, computed, watch } from 'vue';
import { X, Loader2, Lock } from 'lucide-vue-next';
import { sbGetAll, sbPost } from '@/lib/supabase';

interface KpiMetric {
  id: string; grp: string; product: string | null; kind: string;
  name_ko: string; unit: string | null; sort_order: number;
}
interface Row {
  metric_id: string; year_month: string;
  target: number | null; actual: number | null; source?: string;
}

const props = defineProps<{ metrics: KpiMetric[]; year: number }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'saved'): void }>();

const MONTHS = Array.from({ length: 12 }, (_, i) => i + 1);
const month = ref<number>(new Date().getMonth() + 1);
const loading = ref(false);
const saving = ref(false);
const msg = ref('');
const rows = ref<Record<string, { target: string; actual: string; source: string }>>({});

const ym = computed(() => `${props.year}-${String(month.value).padStart(2, '0')}`);
const orderedMetrics = computed(() => [...props.metrics].sort((a, b) => a.sort_order - b.sort_order));
const lockedCount = computed(() => Object.values(rows.value).filter(r => r.source === 'manual').length);

const toNum = (s: string): number | null => {
  const t = (s ?? '').trim().replace(/,/g, '');
  if (!t) return null;
  const n = Number(t);
  return isNaN(n) ? null : n;
};
const fmt = (n: number | null | undefined) => (n === null || n === undefined ? '' : String(n));

async function load() {
  loading.value = true; msg.value = '';
  try {
    const data = await sbGetAll<Row>(
      `kpi_monthly?select=metric_id,year_month,target,actual,source&year_month=eq.${ym.value}`,
    );
    const byId = new Map(data.map(d => [d.metric_id, d]));
    const next: typeof rows.value = {};
    for (const m of props.metrics) {
      const d = byId.get(m.id);
      next[m.id] = { target: fmt(d?.target), actual: fmt(d?.actual), source: d?.source ?? 'csv' };
    }
    rows.value = next;
  } catch (e) {
    msg.value = `불러오기 실패: ${(e as Error).message}`;
  } finally {
    loading.value = false;
  }
}
watch([month, () => props.year], load, { immediate: true });

async function save() {
  saving.value = true; msg.value = '';
  try {
    const payload = props.metrics.map(m => ({
      metric_id: m.id,
      year_month: ym.value,
      target: toNum(rows.value[m.id]?.target ?? ''),
      actual: toNum(rows.value[m.id]?.actual ?? ''),
      source: 'manual',
      updated_at: new Date().toISOString(),
    }));
    await sbPost('kpi_monthly', payload, { onConflict: 'metric_id,year_month' });
    msg.value = `${ym.value} 저장 완료 — 이 달은 이제 입력창이 우선이며 importer 가 덮어쓰지 않습니다.`;
    await load();
    emit('saved');
  } catch (e) {
    msg.value = `저장 실패: ${(e as Error).message}`;
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" @click.self="emit('close')">
    <div class="bg-card border border-border rounded-xl shadow-xl w-full max-w-3xl max-h-[88vh] flex flex-col">
      <!-- 헤더 -->
      <div class="flex items-center justify-between px-5 py-3 border-b border-border">
        <div class="flex items-center gap-3">
          <h2 class="text-sm font-semibold text-foreground">KPI 실적 입력</h2>
          <span class="text-xs text-muted-foreground tabular-nums">{{ ym }}</span>
          <span v-if="lockedCount" class="inline-flex items-center gap-1 text-[11px] text-amber-700 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
            <Lock :size="10" /> 입력창 우선 {{ lockedCount }}건
          </span>
        </div>
        <button class="text-muted-foreground hover:text-foreground" @click="emit('close')"><X :size="18" /></button>
      </div>

      <!-- 월 선택 -->
      <div class="px-5 py-3 border-b border-border flex items-center gap-2 flex-wrap">
        <span class="text-[11px] font-semibold text-muted-foreground">월</span>
        <select v-model.number="month" class="text-xs font-semibold bg-background border border-border rounded-lg px-2 py-1.5 focus:outline-none focus:ring-1 focus:ring-teal-400 cursor-pointer">
          <option v-for="m in MONTHS" :key="m" :value="m">{{ props.year }}년 {{ m }}월</option>
        </select>
        <p class="text-[11px] text-muted-foreground ml-2">
          빈칸은 미입력(NULL)으로 저장됩니다.
        </p>
      </div>

      <!-- 입력 표 -->
      <div class="flex-1 overflow-y-auto px-5 py-3">
        <p v-if="loading" class="text-xs text-muted-foreground py-8 text-center">불러오는 중…</p>
        <table v-else class="w-full text-sm">
          <caption class="sr-only">KPI 월별 입력 표</caption>
          <thead>
            <tr class="border-b border-border text-xs text-muted-foreground">
              <th scope="col" class="text-left font-semibold py-2">지표</th>
              <th scope="col" class="text-left font-semibold py-2 w-16">단위</th>
              <th scope="col" class="text-right font-semibold py-2 w-32">목표</th>
              <th scope="col" class="text-right font-semibold py-2 w-32">실적</th>
              <th scope="col" class="w-8" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in orderedMetrics" :key="m.id" class="border-b border-border/40 last:border-b-0">
              <td class="py-1.5 text-foreground">{{ m.name_ko }}</td>
              <td class="py-1.5 text-[11px] text-muted-foreground">{{ m.unit || '—' }}</td>
              <td class="py-1.5">
                <input
                  v-model="rows[m.id].target" type="text" inputmode="decimal" placeholder="—"
                  class="w-full h-8 rounded border border-input bg-background px-2 text-xs text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-teal-400"
                />
              </td>
              <td class="py-1.5">
                <input
                  v-model="rows[m.id].actual" type="text" inputmode="decimal" placeholder="—"
                  class="w-full h-8 rounded border border-input bg-background px-2 text-xs text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-teal-400"
                />
              </td>
              <td class="py-1.5 text-center">
                <Lock v-if="rows[m.id].source === 'manual'" :size="11" class="text-amber-600 inline" />
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 푸터 -->
      <div class="px-5 py-3 border-t border-border space-y-2">
        <p class="text-[11px] text-amber-800 bg-amber-50/70 border border-amber-200 rounded-lg px-2.5 py-1.5">
          저장하면 이 달은 <b>입력창 값이 우선</b>이 되어 <code>kpi_importer</code> 재실행 시 CSV 로 덮어쓰지 않습니다.
          CSV(<code>data/kpi/{{ props.year }}.csv</code>)를 다시 기준으로 삼으려면 해당 행의 <code>source</code> 를 <code>csv</code> 로 바꾸고 importer 를 재실행하세요.
        </p>
        <p v-if="msg" class="text-[11px] rounded-lg px-2.5 py-1.5 border"
           :class="msg.includes('실패') ? 'text-red-700 bg-red-50/60 border-red-200' : 'text-emerald-700 bg-emerald-50/60 border-emerald-200'">
          {{ msg }}
        </p>
        <div class="flex justify-end gap-2">
          <button class="text-xs px-3 py-2 rounded-lg border border-border text-muted-foreground hover:bg-accent" @click="emit('close')">닫기</button>
          <button
            :disabled="saving || loading"
            class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg bg-primary/15 text-primary border border-primary/30 font-semibold hover:bg-primary/25 disabled:opacity-50"
            @click="save"
          >
            <Loader2 v-if="saving" :size="13" class="animate-spin" />
            {{ saving ? '저장 중…' : `${ym} 저장` }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
