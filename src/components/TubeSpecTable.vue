<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';
import { Search, Package, Download } from 'lucide-vue-next';
import { TUBE_SPECS, type TubeSpec } from '@/data/tubeSpecs';
import { sbGet } from '@/lib/supabase';
import { exportCsv } from '@/lib/csv';
import TableState from '@/components/ui/TableState.vue';

// 스펙은 전부 TUBE 분류 → 가격 탭과 동일하게 [전체, TUBE]
const CATS = ['전체', 'TUBE'] as const;
const query = ref('');
const category = ref<(typeof CATS)[number]>('전체');

// DB(specs_tube) 우선, 미적용 시 정적 데이터 폴백
const specs = ref<TubeSpec[]>([]);
const loading = ref(true);
interface TubeRow { no: number; category: string; article: string | null; description: string | null; size: string; valve: string; w_std: number | null; w_min: number | null; w_max: number | null; lebar: number | null; tebal: number | null; packaging: string; qty: number | null }
onMounted(async () => {
  try {
    const rows = await sbGet<TubeRow[]>('specs_tube?select=*&order=no.asc');
    specs.value = rows?.length
      ? rows.map(r => ({ no: r.no, category: r.category as TubeSpec['category'], article: r.article ?? '', description: r.description ?? '', size: r.size, valve: r.valve, wStd: r.w_std, wMin: r.w_min, wMax: r.w_max, lebar: r.lebar, tebal: r.tebal, packaging: r.packaging as TubeSpec['packaging'], qty: r.qty }))
      : TUBE_SPECS;
  } catch {
    // 정적 제원(TUBE_SPECS)이 있으니 실패를 노출하지 않고 폴백한다 — 표가 비는 경우는 없다
    specs.value = TUBE_SPECS;
  }
  loading.value = false;
});

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase();
  return specs.value.filter((s: TubeSpec) => {
    // 모든 스펙의 분류는 TUBE — '전체'/'TUBE' 모두 전량 표시
    if (category.value !== '전체' && category.value !== 'TUBE') return false;
    if (!q) return true;
    return [s.size, s.valve, s.article, s.description].some(v => (v ?? '').toLowerCase().includes(q));
  });
});

const PAGE_SIZE = 20;
const page = ref(1);
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / PAGE_SIZE)));
const paged = computed(() => filtered.value.slice((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE));
watch([query, category], () => { page.value = 1; });

const w = (n: number | null) => (n == null ? '—' : n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }));

function downloadCsv() {
  const headers = ['No.', '아이템', '제품', 'Article', 'Size', 'Valve', 'Std', 'Min', 'Max', 'Lebar', 'Tebal', 'Packaging', 'Qty/Pkg'];
  const rows = filtered.value.map((s: TubeSpec) => [
    s.no, 'TUBE', s.description ?? '', s.article ?? '', s.size, s.valve ?? '',
    s.wStd ?? '', s.wMin ?? '', s.wMax ?? '', s.lebar ?? '', s.tebal ?? '', s.packaging, s.qty ?? '',
  ]);
  exportCsv(`스펙_튜브_${new Date().toISOString().slice(0, 10)}`, headers, rows);
}
</script>

<template>
  <div class="space-y-3">
    <div class="flex items-center justify-between gap-2 flex-wrap">
      <p class="text-[11px] text-muted-foreground">
        총 {{ filtered.length }}종 · Weight(kg) Std/Min/Max · Lebar=폭(mm) · Tebal=두께(mm)
      </p>
      <div class="flex items-center gap-2">
        <div class="inline-flex items-center gap-1.5 bg-card rounded-lg border border-border pl-3 pr-1 focus-within:ring-1 focus-within:ring-teal-400">
          <span class="text-[11px] font-semibold text-muted-foreground shrink-0">아이템</span>
          <select v-model="category" class="text-xs font-semibold bg-transparent text-foreground py-2 pr-6 focus:outline-none cursor-pointer">
            <option v-for="c in CATS" :key="c" :value="c">{{ c }}</option>
          </select>
        </div>
        <div class="relative">
          <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            v-model="query" type="text" placeholder="사이즈·밸브 검색…"
            class="w-48 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-teal-400"
          />
        </div>
        <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadCsv">
          <Download :size="14" /> 엑셀
        </button>
      </div>
    </div>

    <div class="rounded-xl border border-border bg-card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full text-sm whitespace-nowrap">
          <caption class="sr-only">튜브 제원 목록</caption>
          <thead>
            <tr class="border-b border-border bg-muted/20 text-xs text-muted-foreground">
              <th scope="col" class="w-12 text-center font-semibold px-3 py-2.5">No.</th>
              <th scope="col" class="text-left font-semibold px-3 py-2.5">아이템</th>
              <th scope="col" class="text-left font-semibold px-3 py-2.5">제품</th>
              <th scope="col" class="text-left font-semibold px-3 py-2.5">Size</th>
              <th scope="col" class="text-left font-semibold px-3 py-2.5">Valve</th>
              <th scope="col" class="text-right font-semibold px-3 py-2.5">Std</th>
              <th scope="col" class="text-right font-semibold px-3 py-2.5">Min</th>
              <th scope="col" class="text-right font-semibold px-3 py-2.5">Max</th>
              <th scope="col" class="text-right font-semibold px-3 py-2.5">Lebar</th>
              <th scope="col" class="text-right font-semibold px-3 py-2.5">Tebal</th>
              <th scope="col" class="text-left font-semibold px-3 py-2.5">Packaging</th>
              <th scope="col" class="text-right font-semibold px-3 py-2.5">Qty/Pkg</th>
            </tr>
          </thead>
          <tbody>
            <TableState
              v-if="loading || !paged.length"
              :colspan="12" :loading="loading" :skeleton-rows="6"
              empty-text="검색 결과가 없습니다."
            />
            <tr
              v-for="s in paged" v-else :key="s.no"
              class="border-b border-border/50 last:border-b-0 hover:bg-accent/40 transition-colors"
            >
              <td class="text-center text-muted-foreground tabular-nums px-3 py-2.5">{{ s.no }}</td>
              <td class="px-3 py-2.5">
                <span class="inline-block px-1.5 py-0.5 rounded bg-muted text-[11px] text-foreground/80">TUBE</span>
              </td>
              <td class="px-3 py-2.5">
                <div class="flex items-center gap-2 min-w-0">
                  <Package :size="14" class="text-teal-600 shrink-0" />
                  <div class="min-w-0">
                    <div class="font-medium text-foreground">{{ s.description || '—' }}</div>
                    <div v-if="s.article" class="text-[11px] text-muted-foreground tabular-nums">{{ s.article }}</div>
                  </div>
                </div>
              </td>
              <td class="px-3 py-2.5 font-medium text-foreground">{{ s.size }}</td>
              <td class="px-3 py-2.5 text-muted-foreground">{{ s.valve || '—' }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums font-medium">{{ w(s.wStd) }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ w(s.wMin) }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ w(s.wMax) }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ s.lebar ?? '—' }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ w(s.tebal) }}</td>
              <td class="px-3 py-2.5 text-muted-foreground">{{ s.packaging }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums">{{ s.qty ?? '—' }}</td>
            </tr>
            <tr v-if="!paged.length">
              <td colspan="12" class="text-center text-muted-foreground py-10">검색 결과가 없습니다.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="totalPages > 1" class="flex items-center justify-center gap-1 py-3 border-t border-border">
        <button :disabled="page <= 1" class="inline-flex items-center justify-center h-8 w-8 rounded-md border border-border text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page--">‹</button>
        <button
          v-for="n in totalPages" :key="n"
          :class="['h-8 min-w-8 px-2 rounded-md text-sm border transition-colors',
            n === page ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
          @click="page = n"
        >{{ n }}</button>
        <button :disabled="page >= totalPages" class="inline-flex items-center justify-center h-8 w-8 rounded-md border border-border text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page++">›</button>
      </div>
    </div>
  </div>
</template>
