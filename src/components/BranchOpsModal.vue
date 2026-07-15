<script setup lang="ts">
/**
 * 지점 인원·인건비·Petty 입력창 (branch_ops_monthly).
 *
 * 이 값들은 지점 판매 CSV 에서 도출되지 않는다(거래행에 없는 정보) → 여기서 직접 입력한다.
 * 판매 수치(branch_sales_rows)와 달리 업로드로 갱신되지 않으므로 덮어쓰기 충돌이 없다.
 */
import { ref, watch } from 'vue';
import { X, Loader2 } from 'lucide-vue-next';
import { sbGetAll, sbPost } from '@/lib/supabase';

interface OpsRow {
  branch: string; year: number; month: number;
  sales_hc: number | null; admin_hc: number | null; deliv_hc: number | null;
  salary: number | null; petty: number | null;
}

const props = defineProps<{ branch: string; branchLabel: string; year: number }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'saved'): void }>();

const FIELDS = [
  { key: 'sales_hc', label: 'Sales (영업)',        unit: '명' },
  { key: 'admin_hc', label: 'Admin (관리)',        unit: '명' },
  { key: 'deliv_hc', label: 'Delivery (배송)',     unit: '명' },
  { key: 'salary',   label: 'Salary Total',        unit: 'M.IDR' },
  { key: 'petty',    label: 'Petty Cost',          unit: 'M.IDR' },
] as const;
type FieldKey = (typeof FIELDS)[number]['key'];

const MONTHS = Array.from({ length: 12 }, (_, i) => i + 1);
const loading = ref(false);
const saving = ref(false);
const msg = ref('');
// month -> field -> 입력문자열
const grid = ref<Record<number, Record<string, string>>>({});

const toNum = (s: string): number | null => {
  const t = (s ?? '').trim().replace(/,/g, '');
  if (!t) return null;
  const n = Number(t);
  return isNaN(n) ? null : n;
};

async function load() {
  loading.value = true; msg.value = '';
  try {
    const rows = await sbGetAll<OpsRow>(
      `branch_ops_monthly?select=*&branch=eq.${props.branch}&year=eq.${props.year}`,
    );
    const byMonth = new Map(rows.map(r => [r.month, r]));
    const next: typeof grid.value = {};
    for (const m of MONTHS) {
      const r = byMonth.get(m);
      next[m] = {};
      for (const f of FIELDS) {
        const v = r ? (r[f.key as FieldKey] as number | null) : null;
        next[m][f.key] = v === null || v === undefined ? '' : String(v);
      }
    }
    grid.value = next;
  } catch (e) {
    msg.value = `불러오기 실패: ${(e as Error).message}`;
  } finally {
    loading.value = false;
  }
}
watch([() => props.branch, () => props.year], load, { immediate: true });

async function save() {
  saving.value = true; msg.value = '';
  try {
    // 전 항목이 빈 달은 저장하지 않는다(빈 행 양산 방지)
    const payload = MONTHS
      .filter(m => FIELDS.some(f => (grid.value[m]?.[f.key] ?? '').trim() !== ''))
      .map(m => ({
        branch: props.branch, year: props.year, month: m,
        sales_hc: toNum(grid.value[m].sales_hc), admin_hc: toNum(grid.value[m].admin_hc),
        deliv_hc: toNum(grid.value[m].deliv_hc), salary: toNum(grid.value[m].salary),
        petty: toNum(grid.value[m].petty),
      }));
    if (!payload.length) { msg.value = '입력된 값이 없습니다.'; return; }
    await sbPost('branch_ops_monthly', payload, { onConflict: 'branch,year,month' });
    msg.value = `${props.branchLabel} ${props.year}년 ${payload.length}개월 저장 완료`;
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
      <div class="flex items-center justify-between px-5 py-3 border-b border-border">
        <div class="flex items-center gap-3">
          <h2 class="text-sm font-semibold text-foreground">인원 · 인건비 · Petty 입력</h2>
          <span class="text-xs text-muted-foreground tabular-nums">{{ branchLabel }} · {{ year }}년</span>
        </div>
        <button class="text-muted-foreground hover:text-foreground" @click="emit('close')"><X :size="18" /></button>
      </div>

      <div class="flex-1 overflow-auto px-5 py-3">
        <p v-if="loading" class="text-xs text-muted-foreground py-8 text-center">불러오는 중…</p>
        <table v-else class="w-full text-sm whitespace-nowrap">
          <thead>
            <tr class="border-b border-border text-xs text-muted-foreground">
              <th class="text-left font-semibold py-2 pr-2">월</th>
              <th v-for="f in FIELDS" :key="f.key" class="text-right font-semibold py-2 px-1">
                {{ f.label }}<span class="text-[10px] text-muted-foreground/60"> ({{ f.unit }})</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in MONTHS" :key="m" class="border-b border-border/40 last:border-b-0">
              <td class="py-1.5 pr-2 text-xs text-muted-foreground tabular-nums">{{ m }}월</td>
              <td v-for="f in FIELDS" :key="f.key" class="py-1.5 px-1">
                <input
                  v-model="grid[m][f.key]" type="text" inputmode="decimal" placeholder="—"
                  class="w-full h-8 rounded border border-input bg-background px-2 text-xs text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-teal-400"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="px-5 py-3 border-t border-border space-y-2">
        <p class="text-[11px] text-muted-foreground">
          빈칸은 미입력(–)으로 저장됩니다. Total(인원) 행은 Sales+Admin+Delivery 로 자동 계산됩니다.
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
            {{ saving ? '저장 중…' : '저장' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
