<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';
import { Search, Package, Users, Contact, Building2, Wrench, Download } from 'lucide-vue-next';
import TubeSpecTable from '@/components/TubeSpecTable.vue';
import StaffPayrollTable from '@/components/StaffPayrollTable.vue';
import { sbGetAll } from '@/lib/supabase';
import { exportCsv } from '@/lib/csv';

// ── 1차 카테고리 ──────────────────────────────────────────────────────────────
type Section = 'product' | 'staff' | 'customer' | 'vendor';
const SECTIONS: { key: Section; label: string; icon: typeof Package }[] = [
  { key: 'product',  label: '제품', icon: Package },
  { key: 'staff',    label: '직원', icon: Users },
  { key: 'customer', label: '고객', icon: Contact },
  { key: 'vendor',   label: '벤더', icon: Building2 },
];
const section = ref<Section>('product');

// 제품 하위 탭
type ProductTab = 'price' | 'spec' | 'shipping';
const PRODUCT_TABS: { key: ProductTab; label: string }[] = [
  { key: 'price',    label: '가격' },
  { key: 'spec',     label: '스펙' },
  { key: 'shipping', label: '운송' },
];
const productTab = ref<ProductTab>('price');

// ── 제품 카탈로그(가격): products 테이블 ──────────────────────────────────────
interface ProductRow {
  id: string;
  item: string | null; brand: string | null; description: string | null; sku: string | null; unit: string | null;
  wh_price: number | null; wh_price_set: number | null;
  category?: string | null; spec?: string | null; weight_kg?: number | null;
  fob?: number | null; cif?: number | null; landed_cost?: number | null; selling_price?: number | null;
}
const rows = ref<ProductRow[]>([]);
const loading = ref(true);
const loadError = ref(false);

async function load() {
  loading.value = true; loadError.value = false;
  try {
    rows.value = await sbGetAll<ProductRow>('products?select=*&is_active=eq.true&order=item.asc,brand.asc,description.asc');
  } catch {
    loadError.value = true; rows.value = [];
  }
  loading.value = false;
}
onMounted(load);

const catOf = (p: ProductRow) => (p.category && p.category.trim()) || p.item || '기타';
const sellingOf = (p: ProductRow) =>
  p.selling_price != null ? p.selling_price : (p.wh_price ? Math.round(p.wh_price / 0.8) : null);
const fmt = (n: number | null | undefined) => (n == null || n === 0 ? '—' : n.toLocaleString('en-US'));
const txt = (s: string | null | undefined) => (s && s.trim() ? s : '—');

const query = ref('');
const category = ref('전체');
const categories = computed(() => ['전체', ...Array.from(new Set(rows.value.map(catOf))).sort()]);
const filtered = computed(() => {
  const q = query.value.trim().toLowerCase();
  return rows.value.filter(r => {
    if (category.value !== '전체' && catOf(r) !== category.value) return false;
    if (!q) return true;
    return [r.item, r.brand, r.description, r.sku].some(v => (v ?? '').toLowerCase().includes(q));
  });
});

// 가격 정렬 (헤더 클릭 토글) — No. 열 제외
const PRICE_COLS: { key: string; label: string; right?: boolean }[] = [
  { key: 'category', label: '분류' },
  { key: 'description', label: '제품' },
  { key: 'fob', label: 'FOB', right: true },
  { key: 'cif', label: 'CIF', right: true },
  { key: 'landed_cost', label: 'Landed', right: true },
  { key: 'wh_price', label: '입고가', right: true },
  { key: 'wh_price_set', label: '입고가(set)', right: true },
  { key: 'selling', label: '판매가', right: true },
];
function priceVal(p: ProductRow, key: string): string | number {
  if (key === 'category') return catOf(p);
  if (key === 'selling') return sellingOf(p) ?? -1;
  const v = p[key as keyof ProductRow];
  return typeof v === 'number' ? v : String(v ?? '');
}
const priceSort = ref<{ key: string; dir: 1 | -1 }>({ key: 'category', dir: 1 });
function priceSortBy(key: string) {
  if (priceSort.value.key === key) priceSort.value.dir = priceSort.value.dir === 1 ? -1 : 1;
  else priceSort.value = { key, dir: 1 };
  page.value = 1;
}
const sortedProducts = computed(() => {
  const { key, dir } = priceSort.value;
  return [...filtered.value].sort((a, b) => {
    const av = priceVal(a, key), bv = priceVal(b, key);
    if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
    return String(av).localeCompare(String(bv), 'ko', { numeric: true }) * dir;
  });
});

const PAGE_SIZE = 20;
const page = ref(1);
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / PAGE_SIZE)));
const paged = computed(() => sortedProducts.value.slice((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE));
watch([query, category], () => { page.value = 1; });
const pageWindow = computed(() => {
  const t = totalPages.value;
  const from = Math.max(1, Math.min(page.value - 3, t - 6));
  const to = Math.min(t, from + 6);
  const out: number[] = [];
  for (let i = from; i <= to; i++) out.push(i);
  return out;
});

// ── 스펙: 카테고리별 spec 테이블 (Supabase) ──────────────────────────────────
interface SpecCol { key: string; label: string; num?: boolean }
interface SpecDef { key: string; label: string; table: string | null; cols: SpecCol[] }
const TBR_COLS: SpecCol[] = [
  { key: 'sku', label: 'SKU' }, { key: 'brand', label: '브랜드' }, { key: 'pattern', label: '패턴' }, { key: 'size', label: '규격' },
  { key: 'ply_rating', label: 'PR', num: true }, { key: 'load_index', label: 'LI' },
  { key: 'single_load_kg', label: '단륜(kg)', num: true }, { key: 'dual_load_kg', label: '복륜(kg)', num: true }, { key: 'max_pressure_psi', label: '공기압(psi)', num: true },
];
// 테이블명 규칙: specs_<품목> (2026-07-14 <품목>_specs 에서 리네임됨)
const SPEC_DEFS: SpecDef[] = [
  { key: 'tbr', label: 'TBR', table: 'specs_tbr', cols: TBR_COLS },
  { key: 'tbb', label: 'TBB', table: null, cols: TBR_COLS },       // specs_tbb 미존재 (구 tbb_specs 소실)
  { key: 'otr', label: 'OTR', table: 'specs_otr', cols: [
    { key: 'sku', label: 'SKU' }, { key: 'brand', label: '브랜드' }, { key: 'pattern', label: '패턴' }, { key: 'application', label: '용도' }, { key: 'size', label: '규격' },
    { key: 'ply_rating', label: 'PR', num: true },
    { key: 'load_10kmh', label: '@10km/h', num: true }, { key: 'load_30kmh', label: '@30km/h', num: true }, { key: 'load_40kmh', label: '@40km/h', num: true }, { key: 'load_50kmh', label: '@50km/h', num: true },
    { key: 'tkph_rating', label: '정격 TKPH', num: true },
  ] },
  { key: 'agr', label: 'AGR', table: 'specs_agr', cols: [
    { key: 'sku', label: 'SKU' }, { key: 'brand', label: '브랜드' }, { key: 'pattern', label: '패턴' }, { key: 'application', label: '용도' }, { key: 'size', label: '규격' },
    { key: 'ply_rating', label: 'PR', num: true }, { key: 'max_load_kg', label: '최대하중(kg)', num: true }, { key: 'max_pressure_psi', label: '공기압(psi)', num: true }, { key: 'rated_speed_kmh', label: '속도(km/h)', num: true },
  ] },
  { key: 'tube', label: '튜브', table: 'specs_tube', cols: [] },   // 기존 TubeSpecTable 재사용
  // specs_flap·specs_pneu 는 id/created_at 뿐인 빈 스캐폴드 → 스펙 컬럼 생기면 연결
  { key: 'flap', label: '플랩', table: null, cols: [] },
  { key: 'solid', label: '솔리드', table: null, cols: [] },
  { key: 'pneu', label: '뉴매틱', table: null, cols: [] },
];
const specTab = ref('tbr');
const specDef = computed(() => SPEC_DEFS.find(d => d.key === specTab.value)!);
type SpecRow = Record<string, string | number | null>;
const specData = ref<Record<string, SpecRow[]>>({});
const specLoading = ref(false);
const specQuery = ref('');
async function loadSpec(key: string) {
  const def = SPEC_DEFS.find(d => d.key === key);
  if (!def?.table || def.key === 'tube' || specData.value[key]) return;
  specLoading.value = true;
  try { specData.value[key] = await sbGetAll<SpecRow>(`${def.table}?select=*&order=id.asc`); }
  catch { specData.value[key] = []; }
  specLoading.value = false;
}
watch([specTab, productTab], () => { if (productTab.value === 'spec') void loadSpec(specTab.value); });
const specFiltered = computed(() => {
  const rows0 = specData.value[specTab.value] ?? [];
  const q = specQuery.value.trim().toLowerCase();
  if (!q) return rows0;
  return rows0.filter(r => Object.values(r).some(v => String(v ?? '').toLowerCase().includes(q)));
});
// 스펙 정렬 (헤더 클릭 토글). 숫자 컬럼(num)+weight_kg 는 수치, 나머지는 문자.
const specSort = ref<{ key: string; dir: 1 | -1 }>({ key: 'id', dir: 1 });
watch(specTab, () => { specSort.value = { key: 'id', dir: 1 }; });   // 탭 전환 시 기본 정렬
function specSortBy(key: string) {
  if (specSort.value.key === key) specSort.value.dir = specSort.value.dir === 1 ? -1 : 1;
  else specSort.value = { key, dir: 1 };
}
const specNumKeys = computed(() => new Set([...specDef.value.cols.filter(c => c.num).map(c => c.key), 'weight_kg']));
const specSorted = computed(() => {
  const { key, dir } = specSort.value;
  const numeric = specNumKeys.value.has(key) || key === 'id';
  return [...specFiltered.value].sort((a, b) => {
    if (numeric) return ((a[key] as number ?? -Infinity) - (b[key] as number ?? -Infinity)) * dir;
    return String(a[key] ?? '').localeCompare(String(b[key] ?? ''), 'ko', { numeric: true }) * dir;
  });
});

// ── 고객: customers 테이블 (Supabase) ────────────────────────────────────────
interface CustomerRow {
  id: string; customer_code: string; customer_name: string;
  acquirer_name: string | null; main_pic_name: string | null;
  assist1_name: string | null; assist2_name: string | null; is_active: boolean;
}
const custRows = ref<CustomerRow[]>([]);
const custLoading = ref(false);
const custLoaded = ref(false);
const custQuery = ref('');
async function loadCustomers() {
  if (custLoaded.value) return;
  custLoading.value = true;
  try {
    custRows.value = await sbGetAll<CustomerRow>(
      'customers?select=id,customer_code,customer_name,acquirer_name,main_pic_name,assist1_name,assist2_name,is_active&order=customer_code.asc',
    );
    custLoaded.value = true;
  } catch { custRows.value = []; }
  custLoading.value = false;
}
watch(section, s => { if (s === 'customer') void loadCustomers(); });
const custFiltered = computed(() => {
  const q = custQuery.value.trim().toLowerCase();
  if (!q) return custRows.value;
  return custRows.value.filter(c =>
    [c.customer_code, c.customer_name, c.acquirer_name, c.main_pic_name, c.assist1_name, c.assist2_name]
      .some(v => (v ?? '').toLowerCase().includes(q)));
});
const custPage = ref(1);
const CUST_PAGE = 20;
const custTotalPages = computed(() => Math.max(1, Math.ceil(custFiltered.value.length / CUST_PAGE)));
// 정렬 (헤더 클릭 토글)
const CUST_COLS: { key: keyof CustomerRow; label: string; center?: boolean }[] = [
  { key: 'customer_code', label: '코드' },
  { key: 'customer_name', label: '고객명' },
  { key: 'acquirer_name', label: 'Acquirer' },
  { key: 'main_pic_name', label: 'Main PIC' },
  { key: 'assist1_name', label: 'Assist 1' },
  { key: 'assist2_name', label: 'Assist 2' },
  { key: 'is_active', label: '상태', center: true },
];
const custSort = ref<{ key: keyof CustomerRow; dir: 1 | -1 }>({ key: 'customer_code', dir: 1 });
function custSortBy(key: keyof CustomerRow) {
  if (custSort.value.key === key) custSort.value.dir = custSort.value.dir === 1 ? -1 : 1;
  else custSort.value = { key, dir: 1 };
  custPage.value = 1;
}
const custSorted = computed(() => {
  const { key, dir } = custSort.value;
  return [...custFiltered.value].sort((a, b) => {
    const av = a[key], bv = b[key];
    if (typeof av === 'boolean' || typeof bv === 'boolean') return (Number(av) - Number(bv)) * dir;
    return String(av ?? '').localeCompare(String(bv ?? ''), 'ko', { numeric: true }) * dir;
  });
});
const custPaged = computed(() => custSorted.value.slice((custPage.value - 1) * CUST_PAGE, custPage.value * CUST_PAGE));
watch(custQuery, () => { custPage.value = 1; });
const custPageWindow = computed(() => {
  const t = custTotalPages.value;
  const from = Math.max(1, Math.min(custPage.value - 3, t - 6));
  const to = Math.min(t, from + 6);
  const out: number[] = [];
  for (let i = from; i <= to; i++) out.push(i);
  return out;
});

// ── 엑셀(CSV) 다운로드 ────────────────────────────────────────────────────────
const today = () => new Date().toISOString().slice(0, 10);
function downloadPrice() {
  const headers = ['분류', '제품', '브랜드', 'SKU', '단위', 'FOB', 'CIF', 'Landed', '입고가', '입고가(set)', '판매가'];
  const rows = filtered.value.map(p => [
    catOf(p), p.description ?? '', p.brand ?? '', p.sku ?? '', p.unit ?? '',
    p.fob ?? '', p.cif ?? '', p.landed_cost ?? '', p.wh_price ?? '', p.wh_price_set ?? '', sellingOf(p) ?? '',
  ]);
  exportCsv(`제품_가격_${today()}`, headers, rows);
}
function downloadSpec() {
  const def = specDef.value;
  if (!def.table || def.key === 'tube') return;
  const headers = [...def.cols.map(c => c.label), '중량(kg)'];
  const rows = specFiltered.value.map(r => [
    ...def.cols.map(c => r[c.key] ?? ''),
    (r.weight_kg as number | null) ?? '',
  ]);
  exportCsv(`스펙_${def.label}_${today()}`, headers, rows);
}
function downloadCustomers() {
  const headers = ['코드', '고객명', 'Acquirer', 'Main PIC', 'Assist1', 'Assist2', '상태'];
  const rows = custFiltered.value.map(c => [
    c.customer_code, c.customer_name, c.acquirer_name ?? '', c.main_pic_name ?? '',
    c.assist1_name ?? '', c.assist2_name ?? '', c.is_active ? '활성' : '비활성',
  ]);
  exportCsv(`고객_${today()}`, headers, rows);
}
</script>

<template>
  <div class="p-6 space-y-4 max-w-300 mx-auto">
    <!-- 1차 카테고리 탭 + 설명 (1행) -->
    <div class="flex items-center gap-2 border-b border-border">
      <button
        v-for="s in SECTIONS" :key="s.key"
        :class="['inline-flex items-center gap-1.5 px-4 py-2 text-sm font-semibold border-b-2 -mb-px transition-colors',
          section === s.key ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground']"
        @click="section = s.key"
      >
        <component :is="s.icon" :size="15" /> {{ s.label }}
      </button>
      <span class="ml-auto pb-1 text-xs text-muted-foreground hidden sm:block">제품 / 직원 / 고객 / 벤더 데이터베이스를 한곳에서 관리</span>
    </div>

    <!-- ═══ 제품 ═══ -->
    <template v-if="section === 'product'">
      <!-- 하위 탭 + 툴바 (1행) -->
      <div class="flex items-center gap-2 flex-wrap">
        <div class="flex items-center gap-1">
          <button
            v-for="t in PRODUCT_TABS" :key="t.key"
            :class="['px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors',
              productTab === t.key ? 'bg-primary/15 text-primary' : 'bg-card border border-border text-muted-foreground hover:bg-accent']"
            @click="productTab = t.key"
          >{{ t.label }}</button>
        </div>
        <template v-if="productTab === 'price'">
          <p class="text-[11px] text-muted-foreground ml-2">
            총 {{ filtered.length.toLocaleString() }}개<span v-if="query || category !== '전체'"> / 전체 {{ rows.length.toLocaleString() }}개</span>
            · FOB/CIF/Landed는 확장 컬럼(미입력 시 —)
          </p>
          <div class="flex items-center gap-2 ml-auto">
            <div class="inline-flex items-center gap-1.5 bg-card rounded-lg border border-border pl-3 pr-1 focus-within:ring-1 focus-within:ring-teal-400">
              <span class="text-[11px] font-semibold text-muted-foreground shrink-0">분류</span>
              <select v-model="category" class="text-xs font-semibold bg-transparent text-foreground py-2 pr-6 focus:outline-none cursor-pointer">
                <option v-for="c in categories" :key="c" :value="c">{{ c }}</option>
              </select>
            </div>
            <div class="relative">
              <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input v-model="query" type="text" placeholder="제품·브랜드·SKU 검색…"
                class="w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-teal-400" />
            </div>
            <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadPrice">
              <Download :size="14" /> 엑셀
            </button>
          </div>
        </template>
        <!-- 스펙: 카테고리 칩 + 검색 (같은 행) -->
        <template v-else-if="productTab === 'spec'">
          <div class="flex items-center gap-1 flex-wrap ml-2">
            <button
              v-for="d in SPEC_DEFS" :key="d.key"
              :class="['px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors',
                specTab === d.key ? 'bg-primary/15 text-primary' : 'bg-card border border-border text-muted-foreground hover:bg-accent']"
              @click="specTab = d.key"
            >{{ d.label }}</button>
          </div>
          <div v-if="specDef.table && specDef.key !== 'tube'" class="flex items-center gap-2 ml-auto">
            <div class="relative">
              <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input v-model="specQuery" type="text" placeholder="패턴·규격·SKU 검색…"
                class="w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-teal-400" />
            </div>
            <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadSpec">
              <Download :size="14" /> 엑셀
            </button>
          </div>
        </template>
      </div>

      <!-- 가격: 제품 카탈로그 -->
      <template v-if="productTab === 'price'">

        <div class="rounded-xl border border-border bg-card overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm whitespace-nowrap">
              <thead>
                <tr class="border-b border-border bg-muted/20 text-xs text-muted-foreground">
                  <th class="w-12 text-center font-semibold px-3 py-2.5">No.</th>
                  <th v-for="col in PRICE_COLS" :key="col.key" class="font-semibold px-3 py-2.5 cursor-pointer select-none hover:text-foreground" :class="col.right ? 'text-right' : 'text-left'" @click="priceSortBy(col.key)">
                    <span class="inline-flex items-center gap-1" :class="col.right && 'flex-row-reverse'">
                      {{ col.label }}
                      <span class="text-[9px] w-2" :class="priceSort.key === col.key ? 'text-primary' : 'text-muted-foreground/30'">{{ priceSort.key === col.key ? (priceSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-if="loading"><td colspan="9" class="text-center text-muted-foreground py-10">불러오는 중…</td></tr>
                <tr v-else-if="loadError"><td colspan="9" class="text-center text-red-600 py-10">제품을 불러오지 못했습니다.</td></tr>
                <tr
                  v-for="(p, i) in paged" v-else :key="p.id"
                  class="border-b border-border/50 last:border-b-0 hover:bg-accent/40 transition-colors"
                >
                  <td class="text-center text-muted-foreground tabular-nums px-3 py-2.5">{{ (page - 1) * PAGE_SIZE + i + 1 }}</td>
                  <td class="px-3 py-2.5"><span class="inline-block px-1.5 py-0.5 rounded bg-muted text-[11px] text-foreground/80">{{ catOf(p) }}</span></td>
                  <td class="px-3 py-2.5">
                    <div class="flex items-center gap-2 min-w-0">
                      <Package :size="14" class="text-teal-600 shrink-0" />
                      <div class="min-w-0">
                        <div class="font-medium text-foreground">{{ txt(p.description) }}</div>
                        <div class="text-[11px] text-muted-foreground">{{ txt(p.brand) }}<span v-if="p.sku"> · {{ p.sku }}</span><span v-if="p.unit"> · {{ p.unit }}</span></div>
                      </div>
                    </div>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ fmt(p.fob) }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ fmt(p.cif) }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ fmt(p.landed_cost) }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums font-medium">{{ fmt(p.wh_price) }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ fmt(p.wh_price_set) }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums font-semibold text-teal-700">{{ fmt(sellingOf(p)) }}</td>
                </tr>
                <tr v-if="!loading && !loadError && !paged.length">
                  <td colspan="9" class="text-center text-muted-foreground py-10">{{ query || category !== '전체' ? '검색 결과가 없습니다.' : '제품이 없습니다.' }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div v-if="!loading && !loadError && totalPages > 1" class="flex items-center justify-center gap-1 py-3 border-t border-border">
            <button :disabled="page <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page = 1">«</button>
            <button :disabled="page <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page--">‹</button>
            <button v-for="n in pageWindow" :key="n"
              :class="['h-8 min-w-8 px-2 rounded-md text-sm border transition-colors', n === page ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
              @click="page = n">{{ n }}</button>
            <button :disabled="page >= totalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page++">›</button>
            <button :disabled="page >= totalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="page = totalPages">»</button>
          </div>
        </div>
      </template>

      <!-- 스펙: 카테고리별 규격 (Supabase spec 테이블 · 칩/검색은 상단 탭 행에 통합) -->
      <template v-else-if="productTab === 'spec'">
        <!-- 튜브: 기존 컴포넌트 -->
        <TubeSpecTable v-if="specDef.key === 'tube'" />
        <!-- 미생성 테이블 -->
        <div v-else-if="!specDef.table" class="rounded-xl border border-dashed border-border bg-card p-12 text-center text-sm text-muted-foreground">
          <Wrench :size="24" class="mx-auto mb-3 text-muted-foreground/50" />
          {{ specDef.label }} 스펙 테이블({{ specDef.key }}_specs)은 아직 생성되지 않았습니다. DB 테이블 추가 예정.
        </div>
        <!-- DB 스펙 테이블 -->
        <div v-else class="rounded-xl border border-border bg-card overflow-hidden">
          <div v-if="specLoading" class="p-8 text-center text-sm text-muted-foreground">불러오는 중…</div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-sm whitespace-nowrap">
              <thead>
                <tr class="bg-muted text-muted-foreground text-xs">
                  <th v-for="c in [...specDef.cols, { key: 'weight_kg', label: '중량(kg)', num: true }]" :key="c.key" class="font-semibold px-3 py-2.5 cursor-pointer select-none hover:text-foreground" :class="c.num ? 'text-right' : 'text-left'" @click="specSortBy(c.key)">
                    <span class="inline-flex items-center gap-1" :class="c.num && 'flex-row-reverse'">
                      {{ c.label }}
                      <span class="text-[9px] w-2" :class="specSort.key === c.key ? 'text-primary' : 'text-muted-foreground/30'">{{ specSort.key === c.key ? (specSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="r in specSorted" :key="String(r.id)" class="border-t border-border/50 hover:bg-accent/40">
                  <td v-for="c in specDef.cols" :key="c.key" class="px-3 py-2" :class="c.num ? 'text-right tabular-nums' : 'text-left'">
                    {{ c.num ? fmt(r[c.key] as number | null) : txt(r[c.key] as string | null) }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums">{{ fmt(r.weight_kg as number | null) }}</td>
                </tr>
                <tr v-if="!specSorted.length"><td :colspan="specDef.cols.length + 1" class="px-3 py-8 text-center text-muted-foreground text-sm">데이터가 없습니다.</td></tr>
              </tbody>
            </table>
          </div>
          <div class="px-3 py-2 border-t border-border text-[11px] text-muted-foreground">총 {{ specFiltered.length.toLocaleString() }}건 · 출처: {{ specDef.table }} · 중량은 {{ specDef.table }}.weight_kg (미입력 시 —)</div>
        </div>
      </template>

      <!-- 운송 -->
      <div v-else class="rounded-xl border border-dashed border-border bg-card p-12 text-center text-sm text-muted-foreground">
        <Wrench :size="24" class="mx-auto mb-3 text-muted-foreground/50" />
        운송 정보(제품별 운임·물류 조건)는 준비 중입니다. DB 테이블 연동 예정.
      </div>
    </template>

    <!-- ═══ 직원 (급여) ═══ -->
    <StaffPayrollTable v-else-if="section === 'staff'" />

    <!-- ═══ 고객 (customers) ═══ -->
    <template v-else-if="section === 'customer'">
      <div class="flex items-center gap-2 flex-wrap">
        <p class="text-[11px] text-muted-foreground">
          총 {{ custFiltered.length.toLocaleString() }}개<span v-if="custQuery"> / 전체 {{ custRows.length.toLocaleString() }}개</span> · 출처: customers
        </p>
        <div class="flex items-center gap-2 ml-auto">
          <div class="relative">
            <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input v-model="custQuery" type="text" placeholder="코드·고객명·담당자 검색…"
              class="w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-teal-400" />
          </div>
          <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadCustomers">
            <Download :size="14" /> 엑셀
          </button>
        </div>
      </div>
      <div class="rounded-xl border border-border bg-card overflow-hidden">
        <div v-if="custLoading" class="p-8 text-center text-sm text-muted-foreground">불러오는 중…</div>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm whitespace-nowrap">
            <thead>
              <tr class="bg-muted text-muted-foreground text-xs">
                <th v-for="col in CUST_COLS" :key="col.key" class="font-semibold px-3 py-2.5 cursor-pointer select-none hover:text-foreground" :class="col.center ? 'text-center' : 'text-left'" @click="custSortBy(col.key)">
                  <span class="inline-flex items-center gap-1" :class="col.center && 'justify-center'">
                    {{ col.label }}
                    <span class="text-[9px] w-2" :class="custSort.key === col.key ? 'text-primary' : 'text-muted-foreground/30'">{{ custSort.key === col.key ? (custSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="c in custPaged" :key="c.id" class="border-t border-border/50 hover:bg-accent/40">
                <td class="px-3 py-2 font-mono text-xs">{{ c.customer_code }}</td>
                <td class="px-3 py-2 font-medium">{{ c.customer_name }}</td>
                <td class="px-3 py-2">{{ txt(c.acquirer_name) }}</td>
                <td class="px-3 py-2">{{ txt(c.main_pic_name) }}</td>
                <td class="px-3 py-2">{{ txt(c.assist1_name) }}</td>
                <td class="px-3 py-2">{{ txt(c.assist2_name) }}</td>
                <td class="px-3 py-2 text-center">
                  <span class="text-[10px] font-bold px-2 py-0.5 rounded-full" :class="c.is_active ? 'bg-emerald-500/10 text-emerald-500' : 'bg-muted text-muted-foreground'">{{ c.is_active ? '활성' : '비활성' }}</span>
                </td>
              </tr>
              <tr v-if="!custPaged.length"><td colspan="7" class="px-3 py-8 text-center text-muted-foreground text-sm">데이터가 없습니다.</td></tr>
            </tbody>
          </table>
        </div>
        <div v-if="!custLoading && custTotalPages > 1" class="flex items-center justify-center gap-1 py-3 border-t border-border">
          <button :disabled="custPage <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="custPage = 1">«</button>
          <button :disabled="custPage <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="custPage--">‹</button>
          <button v-for="n in custPageWindow" :key="n"
            :class="['h-8 min-w-8 px-2 rounded-md text-sm border transition-colors', n === custPage ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
            @click="custPage = n">{{ n }}</button>
          <button :disabled="custPage >= custTotalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="custPage++">›</button>
          <button :disabled="custPage >= custTotalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="custPage = custTotalPages">»</button>
        </div>
      </div>
    </template>

    <!-- ═══ 벤더 (준비 중) ═══ -->
    <div v-else class="rounded-xl border border-dashed border-border bg-card p-12 text-center text-sm text-muted-foreground">
      <component :is="SECTIONS.find(s => s.key === section)?.icon" :size="24" class="mx-auto mb-3 text-muted-foreground/50" />
      {{ SECTIONS.find(s => s.key === section)?.label }} 데이터베이스는 준비 중입니다. DB 테이블 연동 예정.
    </div>
  </div>
</template>
