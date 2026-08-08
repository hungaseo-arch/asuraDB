<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';
import { Search, Download } from 'lucide-vue-next';
import { sbGetAll } from '@/lib/supabase';
import { exportCsv } from '@/lib/csv';
import { errMsg } from '@/lib/utils';
import DataState from '@/components/ui/DataState.vue';
import TableState from '@/components/ui/TableState.vue';

interface Payroll {
  nik: string; npwp: string | null; no_rek: string | null;
  kode_ter: string | null; ter_pct: number | null;
  gaji_pokok: number | null; tunj_jabatan: number | null;
  total_tunj_tetap: number | null; total_tunj_tidak_tetap: number | null;
  total_bpjs_perusahaan: number | null; total_gaji_gross: number | null;
  total_potongan: number | null; take_home_pay: number | null;
  periode: string;
}

const rows = ref<Payroll[]>([]);
const loading = ref(true);
const missing = ref(false);              // 테이블 자체가 없음(마이그레이션 미적용)
const loadError = ref<string | null>(null);   // 권한·네트워크 등 그 외 실패 → 재시도 UI

// staff 마스터(nik → 성명·직급). position 컬럼은 마이그레이션 후 존재(없으면 undefined → —)
interface StaffRow { nik: string; name: string | null; grade?: string | null; position?: string | null }
const staffMap = ref<Map<string, StaffRow>>(new Map());
const nameOf  = (nik: string) => staffMap.value.get(nik)?.name || '—';
const gradeOf = (nik: string) => staffMap.value.get(nik)?.grade || '—';
const posOf   = (nik: string) => staffMap.value.get(nik)?.position || '—';

async function load() {
  loading.value = true; missing.value = false; loadError.value = null;
  try {
    const [pay, staff] = await Promise.all([
      sbGetAll<Payroll>('staff_payroll?select=*&order=periode.desc,nik.asc'),
      sbGetAll<StaffRow>('staff?select=*').catch(() => [] as StaffRow[]),
    ]);
    rows.value = pay;
    staffMap.value = new Map(staff.map(s => [s.nik, s]));
    // 기본 조회는 '최신월' — '전체'면 같은 사람이 월마다 중복 나열돼 목록이 길고 합계도 오해를 부른다.
    // (추이가 필요하면 기간 드롭다운에서 '전체'나 다른 월을 고르면 된다)
    const latest = pay.map(r => r.periode).sort().at(-1);
    if (latest) periode.value = latest;
  } catch (e) {
    rows.value = [];
    // 404 = 관계 없음(마이그레이션 미적용) → 안내문. 그 외(401·5xx·네트워크)는 사유 + 재시도.
    const raw = e instanceof Error ? e.message : String(e);
    if (/:\s*404\b/.test(raw)) missing.value = true;
    else loadError.value = errMsg(e);
  }
  loading.value = false;
}
onMounted(load);

const periods = computed(() => ['전체', ...Array.from(new Set(rows.value.map(r => r.periode))).sort().reverse()]);
const periode = ref('전체');
const query = ref('');

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase();
  return rows.value.filter(r => {
    if (periode.value !== '전체' && r.periode !== periode.value) return false;
    if (!q) return true;
    return [nameOf(r.nik), r.nik, gradeOf(r.nik), posOf(r.nik)].some(v => (v ?? '').toLowerCase().includes(q));
  });
});

// 정렬 (헤더 클릭 토글)
const STAFF_COLS: { key: string; label: string; num?: boolean; center?: boolean; right?: boolean }[] = [
  { key: 'name', label: '성명' },
  { key: 'nik', label: 'NIK' },
  { key: 'grade', label: '레벨' },
  { key: 'position', label: '직급' },
  { key: 'gaji_pokok', label: '기본급', num: true, right: true },
  { key: 'tunj_jabatan', label: '직책수당', num: true, right: true },
  { key: 'total_tunj_tetap', label: '고정수당', num: true, right: true },
  { key: 'total_tunj_tidak_tetap', label: '변동수당', num: true, right: true },
  { key: 'total_gaji_gross', label: 'Gross', num: true, right: true },
  { key: 'periode', label: '기간', center: true },
];
function staffVal(r: Payroll, key: string): string | number {
  if (key === 'name') return nameOf(r.nik);
  if (key === 'grade') return gradeOf(r.nik);
  if (key === 'position') return posOf(r.nik);
  const v = r[key as keyof Payroll];
  return typeof v === 'number' ? v : String(v ?? '');
}
const sort = ref<{ key: string; dir: 1 | -1 }>({ key: 'name', dir: 1 });
function sortBy(key: string) {
  if (sort.value.key === key) sort.value.dir = sort.value.dir === 1 ? -1 : 1;
  else sort.value = { key, dir: 1 };
  page.value = 1;
}
const sorted = computed(() => {
  const { key, dir } = sort.value;
  return [...filtered.value].sort((a, b) => {
    const av = staffVal(a, key), bv = staffVal(b, key);
    if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
    return String(av).localeCompare(String(bv), 'ko', { numeric: true }) * dir;
  });
});

const PAGE_SIZE = 20;
const page = ref(1);
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / PAGE_SIZE)));
const paged = computed(() => sorted.value.slice((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE));
watch([query, periode], () => { page.value = 1; });

const sum = (k: keyof Payroll) => filtered.value.reduce((s, r) => s + (Number(r[k]) || 0), 0);
const fmt = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('en-US'));

function downloadCsv() {
  const headers = ['성명', 'NIK', '레벨', '직급', '기본급', '직책수당', '고정수당', '변동수당', 'Gross', '기간'];
  const clean = (s: string) => (s === '—' ? '' : s);
  const rows = filtered.value.map(r => [
    clean(nameOf(r.nik)), r.nik, clean(gradeOf(r.nik)), clean(posOf(r.nik)),
    r.gaji_pokok ?? '', r.tunj_jabatan ?? '', r.total_tunj_tetap ?? '', r.total_tunj_tidak_tetap ?? '',
    r.total_gaji_gross ?? '', r.periode,
  ]);
  exportCsv(`직원_급여_${new Date().toISOString().slice(0, 10)}`, headers, rows);
}
</script>

<template>
  <div class="space-y-3">
    <div v-if="missing" class="rounded-xl border border-dashed border-amber-300 bg-amber-50/50 p-6 text-center text-sm text-amber-800">
      <code>staff_payroll</code> 테이블이 아직 없습니다. <code>supabase/migrations/add_staff_payroll.sql</code> 을 대시보드 SQL Editor에서 실행하면 표시됩니다.
    </div>

    <DataState v-else-if="loadError" :error="loadError" @retry="load" />

    <template v-else>
      <div class="flex items-center justify-between gap-2 flex-wrap">
        <p class="text-[11px] text-muted-foreground">
          인원 {{ filtered.length }}명 · 총 Gross {{ fmt(sum('total_gaji_gross')) }} (IDR)
        </p>
        <div class="flex items-center gap-2">
          <div class="inline-flex items-center gap-1.5 bg-card rounded-lg border border-border pl-3 pr-1 focus-within:ring-1 focus-within:ring-teal-400">
            <span class="text-[11px] font-semibold text-muted-foreground shrink-0">기간</span>
            <select v-model="periode" class="text-xs font-semibold bg-transparent text-foreground py-2 pr-6 focus:outline-none cursor-pointer">
              <option v-for="p in periods" :key="p" :value="p">{{ p }}</option>
            </select>
          </div>
          <div class="relative">
            <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input v-model="query" type="text" placeholder="성명·NIK·직급 검색…"
              class="w-48 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-teal-400" />
          </div>
          <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadCsv">
            <Download :size="14" /> 엑셀
          </button>
        </div>
      </div>

      <div class="rounded-xl border border-border bg-card overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full text-sm whitespace-nowrap">
            <caption class="sr-only">직원별 급여 상세</caption>
            <thead>
              <tr class="border-b border-border bg-muted/20 text-xs text-muted-foreground">
                <th scope="col" v-for="col in STAFF_COLS" :key="col.key" class="font-semibold px-3 py-2.5 cursor-pointer select-none hover:text-foreground" :class="col.right ? 'text-right' : col.center ? 'text-center' : 'text-left'" @click="sortBy(col.key)">
                  <span class="inline-flex items-center gap-1" :class="[col.right && 'flex-row-reverse', col.center && 'justify-center']">
                    {{ col.label }}
                    <span class="text-[9px] w-2" :class="sort.key === col.key ? 'text-primary' : 'text-muted-foreground/30'">{{ sort.key === col.key ? (sort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              <TableState
                v-if="loading || !paged.length"
                :colspan="10" :loading="loading" :skeleton-rows="6"
                empty-text="검색 결과가 없습니다."
              />
              <tr
                v-for="r in paged" v-else :key="r.nik + r.periode"
                class="border-b border-border/50 last:border-b-0 hover:bg-accent/40 transition-colors"
              >
                <td class="px-3 py-2.5 font-medium text-foreground">{{ nameOf(r.nik) }}</td>
                <td class="px-3 py-2.5 text-muted-foreground tabular-nums">{{ r.nik }}</td>
                <td class="px-3 py-2.5 text-muted-foreground tabular-nums">{{ gradeOf(r.nik) }}</td>
                <td class="px-3 py-2.5 text-muted-foreground">{{ posOf(r.nik) }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums">{{ fmt(r.gaji_pokok) }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ fmt(r.tunj_jabatan) }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ fmt(r.total_tunj_tetap) }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ fmt(r.total_tunj_tidak_tetap) }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums font-semibold text-teal-700">{{ fmt(r.total_gaji_gross) }}</td>
                <td class="px-3 py-2.5 text-center text-muted-foreground tabular-nums">{{ r.periode }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="!loading && totalPages > 1" class="flex items-center justify-center gap-1 py-3 border-t border-border">
          <button :disabled="page <= 1" class="inline-flex items-center justify-center h-8 w-8 rounded-md border border-border text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page--">‹</button>
          <button v-for="n in totalPages" :key="n"
            :class="['h-8 min-w-8 px-2 rounded-md text-sm border transition-colors', n === page ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
            @click="page = n">{{ n }}</button>
          <button :disabled="page >= totalPages" class="inline-flex items-center justify-center h-8 w-8 rounded-md border border-border text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page++">›</button>
        </div>
      </div>
    </template>
  </div>
</template>
