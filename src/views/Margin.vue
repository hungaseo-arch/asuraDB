<script setup lang="ts">
import { ref, computed, watch, onMounted, shallowRef } from 'vue';
import { ChevronLeft, ChevronRight, Printer, Download, TrendingUp, TrendingDown, ChevronUp, ChevronDown, ChevronsUpDown, Loader2, AlertCircle, RotateCw, Database } from 'lucide-vue-next';
import { sbGetAll } from '@/lib/supabase';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/ui/DataState.vue';
import { errMsg } from '@/lib/utils';
import { exportXlsx, exportXlsxSheets } from '@/lib/xlsx';
import { chartSeriesPalette, cssVar } from '@/components/charts/chartSetup';

// ── Types ───────────────────────────────────────────────────────────────────

interface MarginMonthRow {
  year_month:   string;
  total_sales:  number;
  total_margin: number;
}

interface MarginRecordRow {
  year_month:  string;
  axis:        'brand' | 'product' | 'customer' | 'item';
  primary_key: string;
  secondary:   string | null;
  qty:         number | null;
  sales_idr:   number;
  margin_idr:  number;
}

interface BrandRow    { brand: string;  sales: number; margin: number }
interface ProductRow  { product: string; type: string; qty: number; sales: number; margin: number }
interface CustomerRow { buyer: string;  sales: number; margin: number }
interface ItemRow     { description: string; qty: number; sales: number; margin: number }

interface MonthDetail {
  totalSales: number;
  totalMargin: number;
  brands:    BrandRow[];
  products:  ProductRow[];
  customers: CustomerRow[];
  items:     ItemRow[];
}

// 브랜드 6종 색 — chart-1~5 를 명도 3단계로 늘린 팔레트에서 순서대로 배정
// (기본 5색을 넘는 카테고리 수라 §8.2와 동일한 방식으로 확장).
const BRAND_ORDER = ['ASCENDO', 'TECHKING', 'DIAMOND', 'TIRON', 'STARKUS', 'GIS'];
const BRAND_COLOR: Record<string, string> = Object.fromEntries(
  BRAND_ORDER.map((b, i) => [b, chartSeriesPalette(6)[i]]),
);

// ── Supabase state ──────────────────────────────────────────────────────────

const loadingMonths  = ref(true);
const loadingDetail  = ref(false);
const loadError      = ref<string | null>(null);

const monthsList     = shallowRef<MarginMonthRow[]>([]);
const detailCache    = shallowRef<Record<string, MonthDetail>>({});

const MONTH_KEYS     = computed(() => monthsList.value.map(m => m.year_month));

const selectedMonth  = ref<string>('');
type Tab = 'brand' | 'product' | 'customer' | 'item';
const activeTab = ref<Tab>('brand');

// 빈 디테일 — 데이터 로드 전 placeholder
const EMPTY_DETAIL: MonthDetail = {
  totalSales: 0, totalMargin: 0, brands: [], products: [], customers: [], items: [],
};

function buildDetail(month: MarginMonthRow, records: MarginRecordRow[]): MonthDetail {
  const brands:    BrandRow[]    = [];
  const products:  ProductRow[]  = [];
  const customers: CustomerRow[] = [];
  const items:     ItemRow[]     = [];
  for (const r of records) {
    const sales  = Number(r.sales_idr);
    const margin = Number(r.margin_idr);
    const qty    = r.qty == null ? 0 : Number(r.qty);
    switch (r.axis) {
      case 'brand':
        brands.push({ brand: r.primary_key, sales, margin });
        break;
      case 'product':
        products.push({ product: r.primary_key, type: r.secondary ?? '', qty, sales, margin });
        break;
      case 'customer':
        customers.push({ buyer: r.primary_key, sales, margin });
        break;
      case 'item':
        items.push({ description: r.primary_key, qty, sales, margin });
        break;
    }
  }
  return {
    totalSales:  Number(month.total_sales),
    totalMargin: Number(month.total_margin),
    brands, products, customers, items,
  };
}

async function loadDetailForMonth(ym: string): Promise<void> {
  if (detailCache.value[ym]) return;
  const month = monthsList.value.find(m => m.year_month === ym);
  if (!month) return;
  loadingDetail.value = true;
  try {
    const path = `margin_records?select=year_month,axis,primary_key,secondary,qty,sales_idr,margin_idr&year_month=eq.${encodeURIComponent(ym)}`;
    const records = await sbGetAll<MarginRecordRow>(path);
    detailCache.value = { ...detailCache.value, [ym]: buildDetail(month, records) };
  } catch (e) {
    loadError.value = errMsg(e);
  } finally {
    loadingDetail.value = false;
  }
}

// 연간 합계 — 해당 연도의 모든 레코드를 axis + primary_key + secondary 기준 집계
async function loadYearSumDetail(sumKey: string): Promise<void> {
  if (detailCache.value[sumKey]) return;
  const year   = sumKey.slice(0, 4);
  const months = monthsList.value.filter(m => m.year_month.startsWith(year));
  if (!months.length) return;
  loadingDetail.value = true;
  try {
    const path = `margin_records?select=axis,primary_key,secondary,qty,sales_idr,margin_idr&year_month=like.${year}-*`;
    const records = await sbGetAll<MarginRecordRow>(path);

    interface AggBucket { axis: MarginRecordRow['axis']; primary_key: string; secondary: string | null; qty: number; sales: number; margin: number }
    const agg = new Map<string, AggBucket>();
    for (const r of records) {
      const key = `${r.axis}|${r.primary_key}|${r.secondary ?? ''}`;
      const ex  = agg.get(key);
      const s   = Number(r.sales_idr);
      const m   = Number(r.margin_idr);
      const q   = r.qty == null ? 0 : Number(r.qty);
      if (ex) {
        ex.sales += s; ex.margin += m; ex.qty += q;
      } else {
        agg.set(key, { axis: r.axis, primary_key: r.primary_key, secondary: r.secondary, qty: q, sales: s, margin: m });
      }
    }

    const brands:    BrandRow[]    = [];
    const products:  ProductRow[]  = [];
    const customers: CustomerRow[] = [];
    const items:     ItemRow[]     = [];
    for (const v of agg.values()) {
      switch (v.axis) {
        case 'brand':    brands.push({ brand: v.primary_key, sales: v.sales, margin: v.margin }); break;
        case 'product':  products.push({ product: v.primary_key, type: v.secondary ?? '', qty: v.qty, sales: v.sales, margin: v.margin }); break;
        case 'customer': customers.push({ buyer: v.primary_key, sales: v.sales, margin: v.margin }); break;
        case 'item':     items.push({ description: v.primary_key, qty: v.qty, sales: v.sales, margin: v.margin }); break;
      }
    }

    const totalSales  = months.reduce((s, m) => s + Number(m.total_sales),  0);
    const totalMargin = months.reduce((s, m) => s + Number(m.total_margin), 0);

    detailCache.value = {
      ...detailCache.value,
      [sumKey]: { totalSales, totalMargin, brands, products, customers, items },
    };
  } catch (e) {
    loadError.value = errMsg(e);
  } finally {
    loadingDetail.value = false;
  }
}

function loadForKey(key: string): Promise<void> {
  return key.endsWith('-sum') ? loadYearSumDetail(key) : loadDetailForMonth(key);
}

// ── SAP 대사 ──────────────────────────────────────────────────────────────────
// 마진 월 요약(margin_months.total_sales)과 SAP 판매이력(A/R, 할인 후 금액) 월합계를 대조한다.
// 두 소스가 같은 거래를 다른 경로로 집계하므로 일치율이 100% 근처면 정상.
interface SapCheckRow { year_month: string; margin_total_sales: number | string; sap_sales: number | string }
const sapCheck = ref<SapCheckRow[]>([]);
const sapMatch = computed<number | null>(() => {
  const key = selectedMonth.value;
  if (!key || !sapCheck.value.length) return null;
  // 연 합계(YYYY-sum) 선택 시에는 해당 연도 전체를 합산해 일치율을 낸다.
  const year = key.endsWith('-sum') ? key.slice(0, 4) : null;
  const rows = year ? sapCheck.value.filter(r => r.year_month.startsWith(year)) : sapCheck.value.filter(r => r.year_month === key);
  if (!rows.length) return null;
  const base = rows.reduce((a, r) => a + Number(r.margin_total_sales ?? 0), 0);
  const sap = rows.reduce((a, r) => a + Number(r.sap_sales ?? 0), 0);
  if (!base || !sap) return null;
  return (sap / base) * 100;
});
const sapMatchOk = computed(() => sapMatch.value != null && Math.abs(sapMatch.value - 100) <= 1);

// ── 교차 조회 (고객사 × SKU) ──────────────────────────────────────────────────
// margin_records 는 4개 축을 각각 따로 집계한 요약이라 축을 교차할 수 없다.
// margin_lines(월간 리포트 엑셀의 1.Row_Data 시트, 라인 단위)를 써서 두 조건을 동시에 건다.
interface CrossLine {
  year_month: string; doc_no: number | string; status: string; delivery_date: string | null;
  buyer: string; sku: string; description: string; brand: string | null;
  type1: string | null; type2: string | null; type3: string | null;
  qty: number | string; unit_price_idr: number | string;
  sales_idr: number | string; cost_idr: number | string; margin_idr: number | string;
}
interface CrossAgg { buyer: string; description: string; sku: string; qty: number; sales: number; cost: number; margin: number }
const crossOpen    = ref(false);
const crossBuyer   = ref('');
const crossSku     = ref('');
const crossLines   = ref<CrossLine[]>([]);
const crossLoading = ref(false);
const crossError   = ref<string | null>(null);
const crossLoadedKey = ref('');

// 월별 명세 보유/정합 상태 — 엑셀이 없는 달(none)·구버전인 달(mismatch)을 화면에 알린다.
const linesCheck = ref<Record<string, 'ok' | 'mismatch' | 'none'>>({});
const crossState = computed<'ok' | 'mismatch' | 'none' | ''>(() => {
  const key = selectedMonth.value;
  if (!key) return '';
  if (!key.endsWith('-sum')) return linesCheck.value[key] ?? '';
  // 연 합계는 해당 연도에서 가장 나쁜 상태를 대표값으로 쓴다.
  const year = key.slice(0, 4);
  const st = Object.entries(linesCheck.value).filter(([k]) => k.startsWith(year)).map(([, v]) => v);
  if (!st.length) return '';
  return st.includes('none') ? 'none' : st.includes('mismatch') ? 'mismatch' : 'ok';
});

async function loadCrossLines(): Promise<void> {
  const key = selectedMonth.value;
  if (!key || crossLoadedKey.value === key) return;
  crossLoading.value = true; crossError.value = null;
  try {
    const cols = 'year_month,doc_no,status,delivery_date,buyer,sku,description,brand,type1,type2,type3,'
      + 'qty,unit_price_idr,sales_idr,cost_idr,margin_idr';
    const where = key.endsWith('-sum')
      ? `year_month=like.${key.slice(0, 4)}-*`
      : `year_month=eq.${encodeURIComponent(key)}`;
    crossLines.value = await sbGetAll<CrossLine>(`v_margin_lines?select=${cols}&${where}`);
    crossLoadedKey.value = key;
  } catch (e) {
    crossLines.value = [];
    crossError.value = errMsg(e);   // '명세 없음' 과 구분 — 조회 실패는 재시도할 수 있게 알린다
  }
  crossLoading.value = false;
}
watch([crossOpen, selectedMonth], ([open]) => { if (open) void loadCrossLines(); });
function retryCrossLines() { crossLoadedKey.value = ''; crossError.value = null; void loadCrossLines(); }

// 두 조건은 AND 로 걸린다 — 이것이 요약 축으로는 불가능했던 부분.
const crossRows = computed<CrossAgg[]>(() => {
  const b = crossBuyer.value.trim().toLowerCase();
  const s = crossSku.value.trim().toLowerCase();
  const agg = new Map<string, CrossAgg>();
  for (const l of crossLines.value) {
    if (b && !l.buyer.toLowerCase().includes(b)) continue;
    if (s && !(l.description.toLowerCase().includes(s) || l.sku.toLowerCase().includes(s))) continue;
    const k = `${l.buyer}\u0000${l.description}`;
    const cur = agg.get(k) ?? { buyer: l.buyer, description: l.description, sku: l.sku, qty: 0, sales: 0, cost: 0, margin: 0 };
    cur.qty    += Number(l.qty);
    cur.sales  += Number(l.sales_idr);
    cur.cost   += Number(l.cost_idr);
    cur.margin += Number(l.margin_idr);
    agg.set(k, cur);
  }
  return [...agg.values()].sort((x, y) => y.margin - x.margin);
});
const crossTotal = computed(() => crossRows.value.reduce(
  (a, r) => ({ qty: a.qty + r.qty, sales: a.sales + r.sales, margin: a.margin + r.margin }),
  { qty: 0, sales: 0, margin: 0 },
));
const crossAnyFilter = computed(() => !!crossBuyer.value.trim() || !!crossSku.value.trim());

// 엑셀용 원본 명세 — 화면 표는 (고객사 × 품명) 집계지만, 내려받기는 라인 그대로 준다.
// 정렬은 월 → 주문번호(SAP Doc. No.) 순.
const crossRawRows = computed<CrossLine[]>(() => {
  const b = crossBuyer.value.trim().toLowerCase();
  const s = crossSku.value.trim().toLowerCase();
  return crossLines.value
    .filter(l => (!b || l.buyer.toLowerCase().includes(b))
      && (!s || l.description.toLowerCase().includes(s) || l.sku.toLowerCase().includes(s)))
    .sort((x, y) => x.year_month.localeCompare(y.year_month) || Number(x.doc_no) - Number(y.doc_no));
});
// 자동완성 — 현재 기간 명세에 실제로 있는 값만 제안한다.
const crossBuyerOptions = computed(() => [...new Set(crossLines.value.map(l => l.buyer))].sort());
const crossSkuOptions = computed(() => [...new Set(crossLines.value.map(l => l.description))].sort());
function crossClear() { crossBuyer.value = ''; crossSku.value = ''; }

async function initLoad(): Promise<void> {
  loadError.value = null;
  loadingMonths.value = true;
  try {
    const rows = await sbGetAll<MarginMonthRow>('margin_months?select=year_month,total_sales,total_margin&order=year_month.asc');
    monthsList.value = rows;
    // 대사 배지는 부가 정보 — 실패해도 마진 화면은 그대로 동작한다.
    sbGetAll<SapCheckRow>('v_margin_sap_check?select=year_month,margin_total_sales,sap_sales')
      .then(r => { sapCheck.value = r; })
      .catch(() => { sapCheck.value = []; });
    // 명세(margin_lines) 보유·정합 상태 — 교차 조회 배지용
    sbGetAll<{ year_month: string; state: 'ok' | 'mismatch' | 'none' }>('v_margin_lines_check?select=year_month,state')
      .then(r => { linesCheck.value = Object.fromEntries(r.map(x => [x.year_month, x.state])); })
      .catch(() => { linesCheck.value = {}; });
    if (rows.length > 0) {
      selectedMonth.value = rows[rows.length - 1].year_month;
      await loadForKey(selectedMonth.value);
      if (rows.length > 1) void loadDetailForMonth(rows[rows.length - 2].year_month);
    }
  } catch (e) {
    loadError.value = errMsg(e);
  } finally {
    loadingMonths.value = false;
  }
}
onMounted(initLoad);

watch(selectedMonth, async (key) => {
  if (!key) return;
  await loadForKey(key);
  // 비교 대상도 미리 fetch
  if (key.endsWith('-sum')) {
    const prevYr = String(Number(key.slice(0, 4)) - 1);
    if (monthsList.value.some(m => m.year_month.startsWith(prevYr))) {
      void loadForKey(`${prevYr}-sum`);
    }
  } else {
    const idx = MONTH_KEYS.value.indexOf(key);
    if (idx > 0) void loadDetailForMonth(MONTH_KEYS.value[idx - 1]);
  }
});

// ── Computed ────────────────────────────────────────────────────────────────

const detail = computed<MonthDetail>(() => detailCache.value[selectedMonth.value] ?? EMPTY_DETAIL);

const isSumKey = computed(() => selectedMonth.value.endsWith('-sum'));

const compareLabel = computed(() => (isSumKey.value ? 'YoY' : 'MoM'));

// 네비게이션 순서: 각 연도의 월들 + 그 연도의 '합계' (12월 뒤)
const navKeys = computed<string[]>(() => {
  const out: string[] = [];
  const groups = new Map<string, string[]>();
  for (const ym of MONTH_KEYS.value) {
    const y = ym.slice(0, 4);
    if (!groups.has(y)) groups.set(y, []);
    groups.get(y)!.push(ym);
  }
  for (const [y, list] of groups) {
    out.push(...list);
    out.push(`${y}-sum`);
  }
  return out;
});

// ── 연월 콤보박스 (검색 가능한 단일 드롭다운) ───────────────────────────────
interface PeriodOption { key: string; label: string; isSum: boolean }

// 드롭다운 표시는 최근 날짜부터 (prev/next 버튼은 navKeys 원본 순서 유지)
const allPeriodOptions = computed<PeriodOption[]>(() =>
  [...navKeys.value].reverse().map(k => {
    if (k.endsWith('-sum')) {
      return { key: k, label: `${k.slice(0, 4)}년 합계`, isSum: true };
    }
    return { key: k, label: `${k.slice(0, 4)}년 ${Number(k.slice(5))}월`, isSum: false };
  }),
);

const currentPeriodLabel = computed(() =>
  allPeriodOptions.value.find(o => o.key === selectedMonth.value)?.label ?? '',
);

const periodQuery = ref('');
const periodOpen  = ref(false);

const periodDisplay = computed<string>({
  get: () => (periodOpen.value ? periodQuery.value : currentPeriodLabel.value),
  set: (v) => { periodQuery.value = v; periodOpen.value = true; },
});

const filteredPeriods = computed<PeriodOption[]>(() => {
  const q = periodQuery.value.trim().toLowerCase();
  if (!q) return allPeriodOptions.value;
  return allPeriodOptions.value.filter(o => o.label.toLowerCase().includes(q));
});

function openPeriod()  { periodOpen.value = true;  periodQuery.value = ''; }
function closePeriod() { setTimeout(() => { periodOpen.value = false; periodQuery.value = ''; }, 150); }
function selectPeriod(opt: PeriodOption) {
  selectedMonth.value = opt.key;
  periodOpen.value = false;
  periodQuery.value = '';
}

// ── 키워드 검색 (고객사 / SKU) ──────────────────────────────────────────────
type FilterMode = 'customer' | 'item';
const filterMode  = ref<FilterMode>('customer');
const filterQuery = ref('');
const filterOpen  = ref(false);

// 단일 필터(상호배타): 고객사/SKU 키워드를 쓰면 제품/유형 그룹 해제
watch(filterQuery, (q) => {
  if (q.trim()) {
    activeTab.value = filterMode.value;
    productFilter.value = '';
    typeFilter.value = '';
    brandFilter.value = '';
  }
});
watch(filterMode,  (m) => { if (filterQuery.value.trim()) activeTab.value = m; });

// 자동완성 소스 — 현재 기간의 고객사명 / SKU 설명
const filterSource = computed<string[]>(() =>
  filterMode.value === 'customer'
    ? detail.value.customers.map(c => c.buyer)
    : detail.value.items.map(i => i.description),
);

const FILTER_SUGGEST_LIMIT = 50;
const filterSuggestions = computed<string[]>(() => {
  const q = filterQuery.value.trim().toLowerCase();
  const src = filterSource.value;
  if (!q) return src.slice(0, FILTER_SUGGEST_LIMIT);
  return src.filter(s => s.toLowerCase().includes(q)).slice(0, FILTER_SUGGEST_LIMIT);
});

function openFilter()  { filterOpen.value = true; }
function closeFilter() { setTimeout(() => { filterOpen.value = false; }, 150); }
function pickFilter(v: string) {
  filterQuery.value = v;
  filterOpen.value = false;
}

// ── 제품 / 유형 / 브랜드 필터 ─────────────────────────────────────────────────
const productFilter = ref<string>('');   // 제품별 (product 축 primary_key)
const typeFilter    = ref<string>('');   // 유형별 (product 축 secondary: TBR/LTR/TBB 등)
const brandFilter   = ref<string>('');   // 브랜드별 (brand 축 primary_key)

const productOptions = computed<string[]>(() => {
  const set = new Set<string>();
  for (const p of detail.value.products) {
    if (p.product) set.add(p.product);
  }
  return [...set].sort();
});

const brandOptions = computed<string[]>(() => {
  const set = new Set<string>();
  for (const b of detail.value.brands) {
    if (b.brand) set.add(b.brand);
  }
  return [...set].sort();
});

const typeOptions = computed<string[]>(() => {
  const set = new Set<string>();
  for (const p of detail.value.products) {
    if (p.type) set.add(p.type);
  }
  return [...set].sort();
});

// 단일 필터(상호배타): 한 그룹을 켜면 나머지 그룹 해제
// 그룹 = ① 브랜드  ② 제품+유형(product 축)  ③ 고객사/SKU 키워드
watch(productFilter, (v) => { if (v) { activeTab.value = 'product'; brandFilter.value = ''; filterQuery.value = ''; } });
watch(typeFilter,    (v) => { if (v) { activeTab.value = 'product'; brandFilter.value = ''; filterQuery.value = ''; } });
watch(brandFilter,   (v) => { if (v) { activeTab.value = 'brand'; productFilter.value = ''; typeFilter.value = ''; filterQuery.value = ''; } });

// 현재 활성 필터 (표·그래프를 구동) — 상호배타이므로 한 번에 하나의 그룹
const anyFilter = computed(() =>
  !!brandFilter.value || !!productFilter.value || !!typeFilter.value || !!filterQuery.value.trim(),
);

const activeFilterLabel = computed(() => {
  const q = filterQuery.value.trim();
  if (q) return `${filterMode.value === 'customer' ? '고객사' : 'SKU'} · ${q}`;
  if (brandFilter.value) return `브랜드 ${brandFilter.value}`;
  const parts: string[] = [];
  if (productFilter.value) parts.push(`제품 ${productFilter.value}`);
  if (typeFilter.value)    parts.push(`유형 ${typeFilter.value}`);
  return parts.join(' · ');
});

function clearAllFilters() {
  productFilter.value = '';
  typeFilter.value = '';
  brandFilter.value = '';
  filterQuery.value = '';
}

// 필터 적용 시 해당 축의 부분합 (필터 없으면 전체 합계) — KPI 카드·표 합계·행 비중의 기준
function filteredTotalsOf(d: MonthDetail): { sales: number; margin: number } {
  const q = filterQuery.value.trim().toLowerCase();
  if (q) {
    const src = filterMode.value === 'customer'
      ? d.customers.map(c => ({ name: c.buyer, sales: c.sales, margin: c.margin }))
      : d.items.map(i => ({ name: i.description, sales: i.sales, margin: i.margin }));
    return src.reduce(
      (a, r) => (r.name.toLowerCase().includes(q) ? { sales: a.sales + r.sales, margin: a.margin + r.margin } : a),
      { sales: 0, margin: 0 },
    );
  }
  if (brandFilter.value) {
    return d.brands.reduce(
      (a, b) => (b.brand === brandFilter.value ? { sales: a.sales + b.sales, margin: a.margin + b.margin } : a),
      { sales: 0, margin: 0 },
    );
  }
  if (productFilter.value || typeFilter.value) {
    return d.products.reduce((a, p) => {
      if (productFilter.value && p.product !== productFilter.value) return a;
      if (typeFilter.value    && p.type    !== typeFilter.value)    return a;
      return { sales: a.sales + p.sales, margin: a.margin + p.margin };
    }, { sales: 0, margin: 0 });
  }
  return { sales: d.totalSales, margin: d.totalMargin };
}

const viewTotals      = computed(() => filteredTotalsOf(detail.value));
const viewMarginShare = computed(() => (detail.value.totalMargin > 0 ? (viewTotals.value.margin / detail.value.totalMargin) * 100 : 0));
const viewSalesShare  = computed(() => (detail.value.totalSales  > 0 ? (viewTotals.value.sales  / detail.value.totalSales)  * 100 : 0));

// 필터 활성 시 표 탭은 필터 축에만 고정 (다른 축 탭은 비활성) — 교차 집계 불가
const lockedTab = computed<Tab | null>(() => {
  if (!anyFilter.value) return null;
  if (filterQuery.value.trim()) return filterMode.value;
  if (brandFilter.value) return 'brand';
  if (productFilter.value || typeFilter.value) return 'product';
  return null;
});

const marginPct = computed(() =>
  viewTotals.value.sales > 0
    ? (viewTotals.value.margin / viewTotals.value.sales) * 100
    : 0,
);

// 비교 기준: 일반 월 → 전월(MoM), 합계 → 전년 합계(YoY)
const prevDetail = computed<MonthDetail | null>(() => {
  const cur = selectedMonth.value;
  if (cur.endsWith('-sum')) {
    const prevYr = String(Number(cur.slice(0, 4)) - 1);
    return detailCache.value[`${prevYr}-sum`] ?? null;
  }
  const idx = MONTH_KEYS.value.indexOf(cur);
  if (idx <= 0) return null;
  return detailCache.value[MONTH_KEYS.value[idx - 1]] ?? null;
});

// 비교 기간도 동일 필터 적용한 부분합으로
const prevViewTotals = computed(() => (prevDetail.value ? filteredTotalsOf(prevDetail.value) : null));

const salesMoM = computed(() => {
  if (!prevViewTotals.value || !prevViewTotals.value.sales) return null;
  return ((viewTotals.value.sales - prevViewTotals.value.sales) / prevViewTotals.value.sales) * 100;
});

const marginMoM = computed(() => {
  if (!prevViewTotals.value || !prevViewTotals.value.margin) return null;
  return ((viewTotals.value.margin - prevViewTotals.value.margin) / prevViewTotals.value.margin) * 100;
});

const topBrand = computed(() =>
  detail.value.brands.length
    ? [...detail.value.brands].sort((a, b) => b.margin - a.margin)[0]
    : null,
);

// 표 행 (정렬 + 비율 계산)
interface DisplayRow {
  key:         string;
  primary:     string;
  secondary?:  string;
  qty?:        number;
  sales:       number;
  margin:      number;
  marginPct:   number;
  salesRatio:  number;
  marginRatio: number;
  color?:      string;
}

const brandRows = computed<DisplayRow[]>(() =>
  [...detail.value.brands]
    .sort((a, b) => b.margin - a.margin)
    .map(b => ({
      key:         b.brand,
      primary:     b.brand,
      sales:       b.sales,
      margin:      b.margin,
      marginPct:   b.sales > 0 ? (b.margin / b.sales) * 100 : 0,
      salesRatio:  viewTotals.value.sales  > 0 ? (b.sales  / viewTotals.value.sales)  * 100 : 0,
      marginRatio: viewTotals.value.margin > 0 ? (b.margin / viewTotals.value.margin) * 100 : 0,
      color:       BRAND_COLOR[b.brand] ?? cssVar('--muted-foreground'),
    })),
);

const productRows = computed<DisplayRow[]>(() =>
  [...detail.value.products]
    .sort((a, b) => b.margin - a.margin)
    .map(p => ({
      key:         `${p.product}-${p.type}`,
      primary:     p.product,
      secondary:   p.type,
      qty:         p.qty,
      sales:       p.sales,
      margin:      p.margin,
      marginPct:   p.sales > 0 ? (p.margin / p.sales) * 100 : 0,
      salesRatio:  viewTotals.value.sales  > 0 ? (p.sales  / viewTotals.value.sales)  * 100 : 0,
      marginRatio: viewTotals.value.margin > 0 ? (p.margin / viewTotals.value.margin) * 100 : 0,
    })),
);

const customerRows = computed<DisplayRow[]>(() =>
  [...detail.value.customers]
    .sort((a, b) => b.margin - a.margin)
    .map(c => ({
      key:         c.buyer,
      primary:     c.buyer,
      sales:       c.sales,
      margin:      c.margin,
      marginPct:   c.sales > 0 ? (c.margin / c.sales) * 100 : 0,
      salesRatio:  viewTotals.value.sales  > 0 ? (c.sales  / viewTotals.value.sales)  * 100 : 0,
      marginRatio: viewTotals.value.margin > 0 ? (c.margin / viewTotals.value.margin) * 100 : 0,
    })),
);

const itemRows = computed<DisplayRow[]>(() =>
  [...detail.value.items]
    .sort((a, b) => b.margin - a.margin)
    .map(i => ({
      key:         i.description,
      primary:     i.description,
      qty:         i.qty,
      sales:       i.sales,
      margin:      i.margin,
      marginPct:   i.sales > 0 ? (i.margin / i.sales) * 100 : 0,
      salesRatio:  viewTotals.value.sales  > 0 ? (i.sales  / viewTotals.value.sales)  * 100 : 0,
      marginRatio: viewTotals.value.margin > 0 ? (i.margin / viewTotals.value.margin) * 100 : 0,
    })),
);

const baseRows = computed<DisplayRow[]>(() => {
  switch (activeTab.value) {
    case 'product':  return productRows.value;
    case 'customer': return customerRows.value;
    case 'item':     return itemRows.value;
    default:         return brandRows.value;
  }
});

// ── Sorting ─────────────────────────────────────────────────────────────────

type SortKey = 'primary' | 'qty' | 'sales' | 'margin' | 'marginPct' | 'salesRatio' | 'marginRatio';
type SortDir = 'asc' | 'desc';

const sortKey = ref<SortKey>('marginRatio');
const sortDir = ref<SortDir>('desc');

// 탭 전환 시 기본 정렬(마진 기여도 내림차순)로 리셋
watch(activeTab, () => {
  sortKey.value = 'marginRatio';
  sortDir.value = 'desc';
});

function toggleSort(key: SortKey) {
  if (sortKey.value === key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortKey.value = key;
    // 텍스트 컬럼은 asc 기본, 숫자 컬럼은 desc 기본
    sortDir.value = key === 'primary' ? 'asc' : 'desc';
  }
}

function sortIcon(key: SortKey) {
  if (sortKey.value !== key) return ChevronsUpDown;
  return sortDir.value === 'asc' ? ChevronUp : ChevronDown;
}

const activeRows = computed<DisplayRow[]>(() => {
  let rows = [...baseRows.value];
  const q = filterQuery.value.trim().toLowerCase();
  if (q && activeTab.value === filterMode.value) {
    rows = rows.filter(r =>
      r.primary.toLowerCase().includes(q) ||
      (r.secondary?.toLowerCase().includes(q) ?? false),
    );
  }
  if (activeTab.value === 'product') {
    if (productFilter.value) rows = rows.filter(r => r.primary   === productFilter.value);
    if (typeFilter.value)    rows = rows.filter(r => r.secondary === typeFilter.value);
  }
  if (activeTab.value === 'brand' && brandFilter.value) {
    rows = rows.filter(r => r.primary === brandFilter.value);
  }
  const k = sortKey.value;
  const mult = sortDir.value === 'asc' ? 1 : -1;
  rows.sort((a, b) => {
    if (k === 'primary') {
      return a.primary.localeCompare(b.primary, 'ko') * mult;
    }
    const av = (a[k] ?? 0) as number;
    const bv = (b[k] ?? 0) as number;
    return (av - bv) * mult;
  });
  return rows;
});

// ── Pagination (customer / item 탭만 적용) ───────────────────────────────────

const PAGE_SIZE = 10;
const currentPage = ref(1);

const needsPagination = computed(() => activeTab.value === 'customer' || activeTab.value === 'item');

const totalPages = computed(() =>
  needsPagination.value
    ? Math.max(1, Math.ceil(activeRows.value.length / PAGE_SIZE))
    : 1,
);

const pagedRows = computed<DisplayRow[]>(() => {
  if (!needsPagination.value) return activeRows.value;
  const start = (currentPage.value - 1) * PAGE_SIZE;
  return activeRows.value.slice(start, start + PAGE_SIZE);
});

const rowIndexOffset = computed(() =>
  needsPagination.value ? (currentPage.value - 1) * PAGE_SIZE : 0,
);

// ── 엑셀(.xlsx) 내보내기 (현재 축·기간의 전체 행) ───────────────────────────
function downloadMarginXlsx() {
  const tab = activeTab.value;
  const withQty = tab === 'product' || tab === 'item';
  const headers = ['구분', '세부', ...(withQty ? ['수량'] : []), '매출(IDR)', '마진(IDR)', '마진율(%)', '매출비중(%)', '마진비중(%)'];
  const rows = activeRows.value.map(r => [
    r.primary, r.secondary ?? '',
    ...(withQty ? [r.qty ?? 0] : []),
    r.sales, r.margin,
    Number((r.marginPct ?? 0).toFixed(1)),
    Number((r.salesRatio ?? 0).toFixed(1)),
    Number((r.marginRatio ?? 0).toFixed(1)),
  ]);
  const tabKo = tab === 'brand' ? '브랜드' : tab === 'product' ? '제품' : tab === 'customer' ? '고객사' : 'SKU';
  exportXlsx(`마진_${tabKo}_${selectedMonth.value}`, headers, rows, `마진_${tabKo}`);
}

// 교차 조회 내보내기 — ①원본 명세(월·주문번호별 라인) ②화면과 같은 집계, 2개 시트.
function downloadCrossXlsx() {
  const n = (v: number | string) => Number(v) || 0;
  const raw = {
    name: '명세(raw)',
    headers: ['월', '주문번호', '구분', '배송일', '고객사', 'SKU', '품명', '브랜드',
      'Type1', 'Type2', 'Type3', '수량', '단가(IDR)', '매출(IDR)', '원가(IDR)', '마진(IDR)', '마진율(%)'],
    rows: crossRawRows.value.map(l => {
      const sales = n(l.sales_idr), margin = n(l.margin_idr);
      return [
        l.year_month, n(l.doc_no), l.status === 'DLV_CXL' ? '취소' : '배송', l.delivery_date ?? '',
        l.buyer, l.sku, l.description, l.brand ?? '', l.type1 ?? '', l.type2 ?? '', l.type3 ?? '',
        n(l.qty), Math.round(n(l.unit_price_idr)), Math.round(sales), Math.round(n(l.cost_idr)), Math.round(margin),
        Number((sales ? (margin / sales) * 100 : 0).toFixed(1)),
      ];
    }),
  };
  const agg = {
    name: '집계(고객사×SKU)',
    headers: ['고객사', 'SKU', '품명', '수량', '매출(IDR)', '원가(IDR)', '마진(IDR)', '마진율(%)'],
    rows: crossRows.value.map(r => [
      r.buyer, r.sku, r.description, r.qty, Math.round(r.sales), Math.round(r.cost), Math.round(r.margin),
      Number((r.sales ? (r.margin / r.sales) * 100 : 0).toFixed(1)),
    ]),
  };
  exportXlsxSheets(`마진_교차_${selectedMonth.value}`, [raw, agg]);
}

const pageRangeLabel = computed(() => {
  if (!needsPagination.value) return '';
  const total = activeRows.value.length;
  if (total === 0) return '0 / 0';
  const start = (currentPage.value - 1) * PAGE_SIZE + 1;
  const end   = Math.min(start + PAGE_SIZE - 1, total);
  return `${start}–${end} / ${total}`;
});

const pageNumbers = computed<(number | '…')[]>(() => {
  const total = totalPages.value;
  const cur   = currentPage.value;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const pages: (number | '…')[] = [1];
  if (cur > 3) pages.push('…');
  for (let p = Math.max(2, cur - 1); p <= Math.min(total - 1, cur + 1); p++) pages.push(p);
  if (cur < total - 2) pages.push('…');
  pages.push(total);
  return pages;
});

function goToPage(p: number) {
  currentPage.value = Math.max(1, Math.min(totalPages.value, p));
}

// 탭/정렬/월 변경 시 1페이지로 리셋
watch([activeTab, sortKey, sortDir, selectedMonth], () => {
  currentPage.value = 1;
});

// 월별 추이 차트 (전년 평균, 당년 평균 + 당년 월별)
interface TrendPoint {
  key:       string;
  label:     string;
  sales:     number;
  margin:    number;
  marginPct: number;
  isAverage?: boolean;
}

// 필터 적용을 위한 연도별 raw records 캐시
const yearRecordsCache = shallowRef<Record<string, MarginRecordRow[]>>({});

async function loadYearRecords(year: string): Promise<void> {
  if (yearRecordsCache.value[year]) return;
  loadingDetail.value = true;
  try {
    const path = `margin_records?select=year_month,axis,primary_key,secondary,qty,sales_idr,margin_idr&year_month=like.${year}-*`;
    const records = await sbGetAll<MarginRecordRow>(path);
    yearRecordsCache.value = { ...yearRecordsCache.value, [year]: records };
  } catch (e) {
    loadError.value = errMsg(e);
  } finally {
    loadingDetail.value = false;
  }
}

// 필터에 매칭되는 records만 추리기 — 우선순위는 filteredTotalsOf(KPI 카드) 와 동일하게
// keyword > brand > product/type 를 유지해야 카드 합계와 그래프가 어긋나지 않는다.
function filterRecordsForChart(records: MarginRecordRow[]): MarginRecordRow[] {
  const q = filterQuery.value.trim().toLowerCase();
  if (q) {
    const axis = filterMode.value;
    return records.filter(r => r.axis === axis && r.primary_key.toLowerCase().includes(q));
  }
  if (brandFilter.value) {
    return records.filter(r => r.axis === 'brand' && r.primary_key === brandFilter.value);
  }
  if (productFilter.value || typeFilter.value) {
    return records.filter(r => {
      if (r.axis !== 'product') return false;
      if (productFilter.value && r.primary_key !== productFilter.value) return false;
      if (typeFilter.value    && r.secondary  !== typeFilter.value)    return false;
      return true;
    });
  }
  return records;
}

// 필터가 켜지거나 연도가 바뀌면 raw records 로드
watch([anyFilter, selectedMonth], () => {
  if (!anyFilter.value || !selectedMonth.value) return;
  const yr = selectedMonth.value.slice(0, 4);
  void loadYearRecords(yr);
  void loadYearRecords(String(Number(yr) - 1));
}, { immediate: true });

function yearAvg(year: string): { sales: number; margin: number } | null {
  // 필터 모드: 캐시된 records에서 집계
  if (anyFilter.value) {
    const recs = yearRecordsCache.value[year];
    if (!recs) return null;
    const filt = filterRecordsForChart(recs);
    const byMonth = new Set<string>();
    let sales = 0, margin = 0;
    for (const r of filt) {
      byMonth.add(r.year_month);
      sales  += Number(r.sales_idr);
      margin += Number(r.margin_idr);
    }
    const count = byMonth.size || 0;
    if (count === 0) return null;
    return { sales: sales / count, margin: margin / count };
  }
  // 비필터 모드: monthsList 총계 사용
  const rows = monthsList.value.filter(m => m.year_month.startsWith(year));
  if (!rows.length) return null;
  const sum = rows.reduce(
    (acc, r) => {
      acc.sales  += Number(r.total_sales);
      acc.margin += Number(r.total_margin);
      return acc;
    },
    { sales: 0, margin: 0 },
  );
  return { sales: sum.sales / rows.length, margin: sum.margin / rows.length };
}

// 필터 모드 — 월별 sales/margin 맵
function monthAggFiltered(year: string): Map<string, { sales: number; margin: number }> {
  const out = new Map<string, { sales: number; margin: number }>();
  const recs = yearRecordsCache.value[year];
  if (!recs) return out;
  for (const r of filterRecordsForChart(recs)) {
    const ex = out.get(r.year_month);
    const s = Number(r.sales_idr);
    const m = Number(r.margin_idr);
    if (ex) { ex.sales += s; ex.margin += m; }
    else out.set(r.year_month, { sales: s, margin: m });
  }
  return out;
}

const trend = computed<TrendPoint[]>(() => {
  if (!selectedMonth.value || !monthsList.value.length) return [];
  const selYear  = selectedMonth.value.slice(0, 4);
  const prevYear = String(Number(selYear) - 1);
  const points: TrendPoint[] = [];

  const prevAvg = yearAvg(prevYear);
  if (prevAvg) {
    const pct = prevAvg.sales > 0 ? (prevAvg.margin / prevAvg.sales) * 100 : 0;
    points.push({ key: `${prevYear}-avg`, label: `'${prevYear.slice(2)} 평균`, sales: prevAvg.sales, margin: prevAvg.margin, marginPct: pct, isAverage: true });
  }
  const selAvg = yearAvg(selYear);
  if (selAvg) {
    const pct = selAvg.sales > 0 ? (selAvg.margin / selAvg.sales) * 100 : 0;
    points.push({ key: `${selYear}-avg`, label: `'${selYear.slice(2)} 평균`, sales: selAvg.sales, margin: selAvg.margin, marginPct: pct, isAverage: true });
  }
  const filtMap = anyFilter.value ? monthAggFiltered(selYear) : null;
  for (const r of monthsList.value.filter(m => m.year_month.startsWith(selYear))) {
    const sales  = filtMap ? (filtMap.get(r.year_month)?.sales  ?? 0) : Number(r.total_sales);
    const margin = filtMap ? (filtMap.get(r.year_month)?.margin ?? 0) : Number(r.total_margin);
    const [, m]  = r.year_month.split('-');
    points.push({
      key:       r.year_month,
      label:     `${Number(m)}월`,
      sales,
      margin,
      marginPct: sales > 0 ? (margin / sales) * 100 : 0,
    });
  }
  return points;
});

// ── Chart helpers (상단: 매출 선 / 하단: 마진율 막대) ─────────────────────────

const CHART_W        = 560;
const CHART_TOP_H    = 90;   // 상단 — 매출 선그래프 영역
const CHART_MID_GAP  = 24;   // 두 영역 사이 시각적 분리
const CHART_BOTTOM_H = 90;   // 하단 — 마진율 막대 영역
const CHART_H        = CHART_TOP_H + CHART_MID_GAP + CHART_BOTTOM_H;
const CHART_PAD_L    = 50;
const CHART_PAD_R    = 16;
const CHART_PAD_T    = 24;
const BAR_GAP        = 32;

// 영역 기준선
const TOP_BASE    = CHART_PAD_T + CHART_TOP_H;
const BOTTOM_BASE = CHART_PAD_T + CHART_TOP_H + CHART_MID_GAP + CHART_BOTTOM_H;

function niceCeil(v: number): number {
  if (v <= 0) return 1;
  const mag  = Math.pow(10, Math.floor(Math.log10(v)));
  const norm = v / mag;
  const nice = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10;
  return nice * mag;
}

const trendBars = computed(() => {
  const data    = trend.value;
  const maxSale = niceCeil(Math.max(...data.map(t => t.sales), 1));
  const maxPct  = niceCeil(Math.max(...data.map(t => t.marginPct), 1));
  const innerW  = CHART_W - CHART_PAD_L - CHART_PAD_R;
  const slotW   = (innerW - BAR_GAP * (data.length - 1)) / data.length;
  const barW    = Math.max(12, Math.min(40, slotW * 0.55));

  return data.map((t, i) => {
    const xCenter = CHART_PAD_L + i * (slotW + BAR_GAP) + slotW / 2;
    // 상단: 매출 선그래프 (TOP_BASE 기준, 위로 자람)
    const ySales  = TOP_BASE - (t.sales / maxSale) * CHART_TOP_H;
    // 하단: 마진율 막대 (BOTTOM_BASE 기준, 위로 자람)
    const hMargin = (t.marginPct / maxPct) * CHART_BOTTOM_H;
    const yMargin = BOTTOM_BASE - hMargin;
    return {
      t,
      xCenter,
      ySales,
      xMargin: xCenter - barW / 2,
      yMargin,
      hMargin,
      barW,
      isCurrent: t.key === selectedMonth.value,
    };
  });
});

// 매출 선그래프는 월별 데이터만 연결 (평균 항목은 점프 없이 건너뜀)
const salesLinePath = computed(() => {
  const pts = trendBars.value
    .filter(b => !b.t.isAverage)
    .map(b => `${b.xCenter},${b.ySales}`);
  return pts.length ? `M${pts.join('L')}` : '';
});

// 평균/월별 경계 x 좌표 (점선 구분선용)
const dividerX = computed(() => {
  const lastAvg = [...trendBars.value].reverse().find(b => b.t.isAverage);
  const firstMonth = trendBars.value.find(b => !b.t.isAverage);
  if (!lastAvg || !firstMonth) return null;
  return (lastAvg.xCenter + firstMonth.xCenter) / 2;
});

// ── Formatters ────────────────────────────────────────────────────────────────

// IDR 대금액 — 인니 실무 단위(juta 10^6 · miliar 10^9 · triliun 10^12) + 소수 둘째자리.
// 천단위 콤마/소수점 마침표는 영미식 고정(en-US). 사내 보고용이라 단위 표기만 사용.
function fmtIdr(v: number): string {
  if (v >= 1_000_000_000_000) return `${(v / 1_000_000_000_000).toFixed(2)} triliun`;
  if (v >= 1_000_000_000)     return `${(v / 1_000_000_000).toFixed(2)} miliar`;
  if (v >= 1_000_000)         return `${(v / 1_000_000).toFixed(2)} juta`;
  return Math.round(v).toLocaleString('en-US');
}

function fmtPct(v: number, digits = 1): string {
  return `${v.toFixed(digits)}%`;
}

function fmtMoM(v: number | null): string {
  if (v === null) return '—';
  const sign = v > 0 ? '+' : '';
  return `${sign}${v.toFixed(1)}%`;
}

function momClass(v: number | null): string {
  if (v === null) return 'text-muted-foreground';
  return v > 0 ? 'text-success' : v < 0 ? 'text-destructive' : 'text-muted-foreground';
}

// 마진율 색상 — Mar 2026 전체 평균 12.0% 기준
function marginPctClass(v: number): string {
  if (v >= 20) return 'text-success';
  if (v >= 12) return 'text-success';
  if (v >= 8)  return 'text-foreground';
  if (v >= 5)  return 'text-warning';
  return 'text-destructive';
}

// ── Navigation ────────────────────────────────────────────────────────────────

function prevMonth() {
  const keys = navKeys.value;
  const idx  = keys.indexOf(selectedMonth.value);
  if (idx > 0) selectedMonth.value = keys[idx - 1];
}

function nextMonth() {
  const keys = navKeys.value;
  const idx  = keys.indexOf(selectedMonth.value);
  if (idx >= 0 && idx < keys.length - 1) selectedMonth.value = keys[idx + 1];
}

function handlePrint() {
  window.print();
}

const TAB_LABEL: Record<Tab, string> = {
  brand:    '브랜드별',
  product:  '제품유형별',
  customer: '고객사별',
  item:     'SKU별',
};
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">

    <!-- Header -->
    <PageHeader title="마진 분석">
      <template #subtitle>
        <p class="text-xs text-muted-foreground mt-1 flex items-center flex-wrap gap-2">
          <span
            v-if="loadingMonths || loadingDetail"
            class="inline-flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded-md bg-info-soft text-info border border-info-border"
          >
            <Loader2 :size="10" class="animate-spin" /> 로딩 중
          </span>
          <span
            v-else
            class="inline-flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded-md bg-success-soft text-success border border-success-border"
          >
            <Database :size="10" /> Supabase · {{ MONTH_KEYS.length }}개월
          </span>
          <!-- SAP 대사 — 선택 기간의 마진 매출 대비 SAP 판매이력(A/R) 합계 비율 -->
          <span
            v-if="sapMatch != null"
            :class="['inline-flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded-md border',
              sapMatchOk ? 'bg-success-soft text-success border-success-border'
                         : 'bg-warning-soft text-warning border-warning-border']"
            :title="sapMatchOk ? 'SAP 판매이력과 ±1% 이내 일치' : 'SAP 판매이력과 1% 넘게 차이 — 원본 대조 필요'"
          >SAP 대사 {{ sapMatch.toFixed(1) }}%</span>
        </p>
      </template>
      <template #controls>
        <!-- 필터: 연월 네비 · 브랜드/제품/유형 · 키워드 -->
        <div v-if="MONTH_KEYS.length > 0" class="flex items-center gap-2 flex-wrap">
          <button
            class="p-1.5 rounded-lg border border-border hover:bg-accent transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
            :disabled="navKeys[0] === selectedMonth"
            @click="prevMonth"
          >
            <ChevronLeft :size="14" />
          </button>
          <div class="relative">
            <input
              v-model="periodDisplay"
              type="text"
              placeholder="연월 검색"
              class="text-xs px-2 py-1.5 rounded-md border border-border bg-card hover:bg-accent transition-colors focus:outline-none focus:ring-1 focus:ring-primary tabular-nums w-24"
              :class="isSumKey ? 'text-warning font-semibold' : 'text-foreground'"
              @focus="openPeriod"
              @blur="closePeriod"
            />
            <div
              v-if="periodOpen && filteredPeriods.length"
              class="absolute left-0 mt-1 min-w-full max-h-60 overflow-auto rounded-md border border-border bg-card shadow-lg z-20"
            >
              <button
                v-for="o in filteredPeriods"
                :key="o.key"
                type="button"
                class="block w-full text-left text-xs px-2 py-1.5 hover:bg-accent transition-colors tabular-nums whitespace-nowrap"
                :class="[
                  o.key === selectedMonth ? 'bg-primary/10 text-primary' : '',
                  o.isSum ? 'font-semibold text-warning' : '',
                ]"
                @mousedown.prevent="selectPeriod(o)"
              >
                {{ o.label }}
              </button>
            </div>
          </div>
          <button
            class="p-1.5 rounded-lg border border-border hover:bg-accent transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
            :disabled="navKeys[navKeys.length - 1] === selectedMonth"
            @click="nextMonth"
          >
            <ChevronRight :size="14" />
          </button>
          <!-- 모바일(<sm)에서는 필터 4종이 한 줄씩 쌓여 첫 화면을 다 먹으므로 2열 그리드로 접는다.
               sm 이상은 종전과 동일한 한 줄 flex. -->
          <div class="grid grid-cols-2 gap-2 w-full sm:flex sm:w-auto sm:items-center sm:gap-2">
          <select
            v-model="brandFilter"
            class="w-full sm:w-auto text-xs px-2 py-1.5 rounded-md border border-border bg-card text-foreground hover:bg-accent transition-colors cursor-pointer focus:outline-none focus:ring-1 focus:ring-primary"
            :class="brandFilter ? 'font-semibold' : ''"
          >
            <option value="">브랜드 전체</option>
            <option v-for="b in brandOptions" :key="b" :value="b">{{ b }}</option>
          </select>
          <select
            v-model="productFilter"
            class="w-full sm:w-auto text-xs px-2 py-1.5 rounded-md border border-border bg-card text-foreground hover:bg-accent transition-colors cursor-pointer focus:outline-none focus:ring-1 focus:ring-primary"
            :class="productFilter ? 'font-semibold' : ''"
          >
            <option value="">제품별 전체</option>
            <option v-for="p in productOptions" :key="p" :value="p">{{ p }}</option>
          </select>
          <select
            v-model="typeFilter"
            class="w-full sm:w-auto text-xs px-2 py-1.5 rounded-md border border-border bg-card text-foreground hover:bg-accent transition-colors cursor-pointer focus:outline-none focus:ring-1 focus:ring-primary"
            :class="typeFilter ? 'font-semibold' : ''"
          >
            <option value="">유형별 전체</option>
            <option v-for="t in typeOptions" :key="t" :value="t">{{ t }}</option>
          </select>
          <div class="flex items-center gap-1 min-w-0">
            <select
              v-model="filterMode"
              class="text-xs px-2 py-1.5 rounded-md border border-border bg-card text-foreground hover:bg-accent transition-colors cursor-pointer focus:outline-none focus:ring-1 focus:ring-primary"
            >
              <option value="customer">고객사</option>
              <option value="item">SKU</option>
            </select>
            <div class="relative w-full sm:w-auto">
              <input
                v-model="filterQuery"
                type="text"
                :placeholder="filterMode === 'customer' ? '고객사 키워드' : 'SKU 키워드'"
                class="text-xs px-2 py-1.5 pr-6 rounded-md border border-border bg-card text-foreground focus:outline-none focus:ring-1 focus:ring-primary w-full sm:w-44"
                @focus="openFilter"
                @blur="closeFilter"
              />
              <button
                v-if="filterQuery"
                type="button"
                class="absolute right-1 top-1/2 -translate-y-1/2 w-4 h-4 inline-flex items-center justify-center text-muted-foreground hover:text-foreground text-xs leading-none"
                @click="filterQuery = ''"
              >×</button>
              <div
                v-if="filterOpen && filterSuggestions.length"
                class="absolute right-0 mt-1 w-72 max-h-60 overflow-auto rounded-md border border-border bg-card shadow-lg z-20"
              >
                <button
                  v-for="s in filterSuggestions"
                  :key="s"
                  type="button"
                  class="block w-full text-left text-xs px-2 py-1.5 hover:bg-accent transition-colors truncate"
                  :class="s === filterQuery ? 'bg-primary/10 text-primary' : ''"
                  :title="s"
                  @mousedown.prevent="pickFilter(s)"
                >
                  {{ s }}
                </button>
              </div>
            </div>
          </div>
          </div>
        </div>
      </template>
      <template #actions>
        <button
          class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors"
          @click="downloadMarginXlsx"
        >
          <Download :size="12" />
          엑셀
        </button>
        <button
          class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors"
          @click="handlePrint"
        >
          <Printer :size="12" />
          인쇄
        </button>
      </template>
    </PageHeader>

    <!-- Error state -->
    <div
      v-if="loadError"
      class="rounded-xl border border-destructive-border bg-destructive-soft p-3 flex items-start gap-2 text-sm text-destructive"
    >
      <AlertCircle :size="14" class="mt-0.5 shrink-0" />
      <div class="min-w-0">
        <p class="font-semibold">데이터 로드 실패</p>
        <p class="text-xs mt-0.5 text-destructive/80 break-all">{{ loadError }}</p>
        <button
          type="button"
          class="mt-2 inline-flex items-center gap-1.5 rounded-lg border border-destructive-border bg-card px-3 py-1.5 text-xs font-medium text-foreground hover:bg-accent transition-colors"
          @click="initLoad"
        >
          <RotateCw :size="13" /> 다시 시도
        </button>
      </div>
    </div>


    <!-- 활성 필터 표시 + 해제 (단일 필터: 표·그래프를 구동) -->
    <div v-if="anyFilter" class="flex items-center gap-2 -mt-2 flex-wrap">
      <span class="text-xs text-muted-foreground">적용 필터</span>
      <span class="inline-flex items-center gap-1.5 text-xs px-2 py-1 rounded-md bg-primary/10 text-primary border border-primary/20">
        {{ activeFilterLabel }}
      </span>
      <button
        class="text-xs px-2 py-1 rounded-md border border-border text-muted-foreground hover:bg-accent transition-colors"
        @click="clearAllFilters"
      >
        필터 해제
      </button>
      <span class="text-[11px] text-muted-foreground/70">· 표·그래프가 이 필터 기준으로 표시됩니다</span>
    </div>

    <!-- KPI cards -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <div class="rounded-xl border border-border bg-card p-4 space-y-1 min-w-0">
        <p class="text-[11.5px] text-muted-foreground">총 매출{{ anyFilter ? ' · 필터' : '' }}</p>
        <p class="text-xl sm:text-2xl font-extrabold tabular-nums">{{ fmtIdr(viewTotals.sales) }} <span class="text-xs text-muted-foreground font-normal">IDR</span></p>
        <p class="text-xs flex items-center gap-1" :class="momClass(salesMoM)">
          <component :is="(salesMoM ?? 0) >= 0 ? TrendingUp : TrendingDown" :size="10" />
          {{ compareLabel }} {{ fmtMoM(salesMoM) }}
        </p>
      </div>
      <div class="rounded-xl border border-border bg-card p-4 space-y-1 min-w-0">
        <p class="text-[11.5px] text-muted-foreground">총 마진{{ anyFilter ? ' · 필터' : '' }}</p>
        <p class="text-xl sm:text-2xl font-extrabold tabular-nums">{{ fmtIdr(viewTotals.margin) }} <span class="text-xs text-muted-foreground font-normal">IDR</span></p>
        <p class="text-xs flex items-center gap-1" :class="momClass(marginMoM)">
          <component :is="(marginMoM ?? 0) >= 0 ? TrendingUp : TrendingDown" :size="10" />
          {{ compareLabel }} {{ fmtMoM(marginMoM) }}
        </p>
      </div>
      <div class="rounded-xl border border-border bg-card p-4 space-y-1 min-w-0">
        <p class="text-[11.5px] text-muted-foreground">마진율</p>
        <p class="text-xl sm:text-2xl font-extrabold tabular-nums" :class="marginPctClass(marginPct)">{{ fmtPct(marginPct, 1) }}</p>
        <p class="text-xs text-muted-foreground">매출 대비</p>
      </div>
      <div class="rounded-xl border border-border bg-card p-4 space-y-1 min-w-0">
        <template v-if="anyFilter">
          <p class="text-[11.5px] text-muted-foreground">전체 대비 비중</p>
          <p class="text-xl sm:text-2xl font-extrabold tabular-nums text-primary">{{ fmtPct(viewMarginShare, 1) }}</p>
          <p class="text-xs text-muted-foreground">마진 기준 · 매출 {{ fmtPct(viewSalesShare, 1) }}</p>
        </template>
        <template v-else>
          <p class="text-[11.5px] text-muted-foreground">최대 마진 브랜드</p>
          <p class="text-base font-bold truncate flex items-center gap-1.5">
            <span v-if="topBrand" class="w-2 h-2 rounded-full shrink-0" :style="{ background: BRAND_COLOR[topBrand.brand] }" />
            <span class="truncate">{{ topBrand?.brand ?? '—' }}</span>
          </p>
          <p class="text-xs text-muted-foreground">
            {{ topBrand ? `${fmtIdr(topBrand.margin)}${detail.totalMargin > 0 ? ' · ' + fmtPct((topBrand.margin / detail.totalMargin) * 100, 1) : ''}` : '' }}
          </p>
        </template>
      </div>
    </div>

    <!-- Monthly trend chart -->
    <div class="rounded-xl border border-border bg-card p-5 space-y-3">
      <div class="flex items-baseline justify-between">
        <p class="text-xs font-semibold tracking-[0.2em] uppercase">
          <span class="text-destructive">§ 01</span>
          <span class="text-muted-foreground"> · </span>
          <span>Monthly Trend</span>
          <span v-if="anyFilter" class="text-primary normal-case tracking-normal"> · {{ activeFilterLabel }}</span>
        </p>
        <div class="flex items-center gap-3 text-xs text-muted-foreground flex-wrap">
          <span class="flex items-center gap-1.5">
            <svg width="16" height="6" class="shrink-0">
              <line x1="0" y1="3" x2="16" y2="3" class="stroke-border" stroke-width="1.5" />
              <circle cx="8" cy="3" r="2" class="fill-border" />
            </svg>
            매출
          </span>
          <span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-sm bg-chart-2" />마진</span>
          <span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-sm bg-warning" />평균</span>
        </div>
      </div>

      <div class="overflow-x-auto">
        <svg :viewBox="`0 0 ${CHART_W} ${CHART_H + CHART_PAD_T + 30}`" class="w-4/5 mx-auto" preserveAspectRatio="xMidYMid meet">
          <!-- 상단 영역 baseline (매출 선그래프 바닥) -->
          <line
            :x1="CHART_PAD_L" :x2="CHART_W - CHART_PAD_R"
            :y1="TOP_BASE" :y2="TOP_BASE"
            stroke="currentColor" stroke-opacity="0.12" stroke-width="1" stroke-dasharray="2 3"
          />
          <!-- 하단 영역 baseline (마진율 막대 바닥) -->
          <line
            :x1="CHART_PAD_L" :x2="CHART_W - CHART_PAD_R"
            :y1="BOTTOM_BASE" :y2="BOTTOM_BASE"
            stroke="currentColor" stroke-opacity="0.2" stroke-width="1"
          />
          <!-- 영역 라벨 -->
          <text
            :x="CHART_PAD_L - 6" :y="CHART_PAD_T + 4"
            text-anchor="end"
            class="fill-muted-foreground"
            style="font-size: 8px; font-family: monospace; letter-spacing: 0.08em"
          >매출</text>
          <text
            :x="CHART_PAD_L - 6" :y="CHART_PAD_T + CHART_TOP_H + CHART_MID_GAP + 4"
            text-anchor="end"
            class="fill-muted-foreground"
            style="font-size: 8px; font-family: monospace; letter-spacing: 0.08em"
          >마진율</text>

          <!-- Avg / monthly divider (전체 영역 가로지름) -->
          <line
            v-if="dividerX !== null"
            :x1="dividerX" :x2="dividerX"
            :y1="CHART_PAD_T" :y2="BOTTOM_BASE"
            stroke="currentColor" stroke-opacity="0.25" stroke-width="1" stroke-dasharray="3 4"
          />

          <!-- Margin bars -->
          <template v-for="bar in trendBars" :key="`mb-${bar.t.key}`">
            <rect
              :x="bar.xMargin" :y="bar.yMargin" :width="bar.barW" :height="bar.hMargin"
              :fill="bar.t.isAverage
                ? (bar.isCurrent ? 'var(--warning)' : 'var(--warning)')
                : (bar.isCurrent ? 'var(--chart-2)' : 'var(--chart-2)')"
              :opacity="bar.t.isAverage ? 0.85 : (bar.isCurrent ? 1 : 0.7)"
            />
            <text
              :x="bar.xMargin + bar.barW / 2" :y="bar.yMargin - 4"
              text-anchor="middle"
              :fill="bar.t.isAverage ? 'var(--warning)' : 'var(--chart-2)'"
              style="font-size: 7px; font-weight: 600"
            >
              {{ fmtPct(bar.t.marginPct, 1) }}
            </text>
          </template>

          <!-- Sales line (월별만) + 평균 포인트(별도) + 라벨 -->
          <path
            :d="salesLinePath"
            fill="none"
            class="stroke-border"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <template v-for="bar in trendBars" :key="`sp-${bar.t.key}`">
            <circle
              :cx="bar.xCenter"
              :cy="bar.ySales"
              :r="bar.isCurrent ? 5 : 3.5"
              :fill="bar.t.isAverage ? 'var(--warning)' : (bar.isCurrent ? 'var(--muted)' : 'var(--border)')"
              class="stroke-foreground"
              stroke-width="1.5"
            />
            <text
              :x="bar.xCenter" :y="bar.ySales - 8"
              text-anchor="middle"
              :class="bar.t.isAverage ? 'fill-warning' : 'fill-foreground'"
              :style="bar.isCurrent
                ? 'font-size: 7px; font-weight: 700; letter-spacing: 0.02em'
                : 'font-size: 7px; font-weight: 500; letter-spacing: 0.02em'"
            >
              {{ fmtIdr(bar.t.sales) }}
            </text>
          </template>

          <!-- X-axis labels -->
          <text
            v-for="bar in trendBars" :key="`xl-${bar.t.key}`"
            :x="bar.xCenter" :y="CHART_PAD_T + CHART_H + 14"
            text-anchor="middle"
            :class="bar.t.isAverage ? 'fill-warning' : 'fill-muted-foreground'"
            :style="bar.t.isAverage
              ? 'font-size: 7px; font-family: monospace; font-weight: 600'
              : 'font-size: 7px; font-family: monospace'"
          >
            {{ bar.t.label }}
          </text>
        </svg>
      </div>
    </div>

    <!-- Tabs -->
    <div class="rounded-xl border border-border bg-card overflow-hidden">
      <div class="flex border-b border-border">
        <button
          v-for="tab in (['brand','product','customer','item'] as Tab[])"
          :key="tab"
          :disabled="lockedTab !== null && tab !== lockedTab"
          :title="lockedTab !== null && tab !== lockedTab ? '필터 적용 중 — 「필터 해제」 후 전환 가능' : ''"
          class="flex-1 px-4 py-2.5 text-sm font-medium transition-colors border-b-2"
          :class="activeTab === tab
            ? 'border-primary text-primary bg-primary/5'
            : (lockedTab !== null && tab !== lockedTab)
              ? 'border-transparent text-muted-foreground/30 cursor-not-allowed'
              : 'border-transparent text-muted-foreground hover:bg-accent/40'"
          @click="activeTab = tab"
        >
          {{ TAB_LABEL[tab] }}
        </button>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <caption class="sr-only">마진 분석 집계 표</caption>
          <thead>
            <tr class="text-xs uppercase tracking-wide text-muted-foreground border-b border-border select-none">
              <th scope="col" class="px-4 py-2.5 text-left font-medium w-8">#</th>
              <th scope="col" class="px-4 py-2.5 text-left font-medium">
                <button class="inline-flex items-center gap-1 hover:text-foreground transition-colors" @click="toggleSort('primary')">
                  {{ activeTab === 'brand'    ? '브랜드' :
                     activeTab === 'product'  ? '제품 / 유형' :
                     activeTab === 'customer' ? '고객사' :
                     'SKU' }}
                  <component :is="sortIcon('primary')" :size="11" :class="sortKey === 'primary' ? 'text-primary' : 'opacity-50'" />
                </button>
              </th>
              <th scope="col" v-if="activeTab === 'product' || activeTab === 'item'" class="px-4 py-2.5 text-right font-medium">
                <button class="inline-flex items-center gap-1 hover:text-foreground transition-colors" @click="toggleSort('qty')">
                  수량
                  <component :is="sortIcon('qty')" :size="11" :class="sortKey === 'qty' ? 'text-primary' : 'opacity-50'" />
                </button>
              </th>
              <th scope="col" class="px-4 py-2.5 text-right font-medium">
                <button class="inline-flex items-center gap-1 hover:text-foreground transition-colors" @click="toggleSort('sales')">
                  매출 (IDR)
                  <component :is="sortIcon('sales')" :size="11" :class="sortKey === 'sales' ? 'text-primary' : 'opacity-50'" />
                </button>
              </th>
              <th scope="col" class="px-4 py-2.5 text-right font-medium">
                <button class="inline-flex items-center gap-1 hover:text-foreground transition-colors" @click="toggleSort('margin')">
                  마진 (IDR)
                  <component :is="sortIcon('margin')" :size="11" :class="sortKey === 'margin' ? 'text-primary' : 'opacity-50'" />
                </button>
              </th>
              <th scope="col" class="px-4 py-2.5 text-right font-medium">
                <button class="inline-flex items-center gap-1 hover:text-foreground transition-colors" @click="toggleSort('marginPct')">
                  마진율
                  <component :is="sortIcon('marginPct')" :size="11" :class="sortKey === 'marginPct' ? 'text-primary' : 'opacity-50'" />
                </button>
              </th>
              <th scope="col" class="px-4 py-2.5 text-right font-medium w-32">
                <button class="inline-flex items-center gap-1 hover:text-foreground transition-colors" @click="toggleSort('salesRatio')">
                  매출 비중
                  <component :is="sortIcon('salesRatio')" :size="11" :class="sortKey === 'salesRatio' ? 'text-primary' : 'opacity-50'" />
                </button>
              </th>
              <th scope="col" class="px-4 py-2.5 text-right font-medium w-32">
                <button class="inline-flex items-center gap-1 hover:text-foreground transition-colors" @click="toggleSort('marginRatio')">
                  마진 기여도
                  <component :is="sortIcon('marginRatio')" :size="11" :class="sortKey === 'marginRatio' ? 'text-primary' : 'opacity-50'" />
                </button>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, idx) in pagedRows"
              :key="row.key"
              class="border-b border-border/50 hover:bg-muted/30 transition-colors"
            >
              <td class="px-4 py-2.5 text-xs text-muted-foreground font-mono">{{ rowIndexOffset + idx + 1 }}</td>
              <td class="px-4 py-2.5">
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    v-if="row.color"
                    class="w-2 h-2 rounded-full shrink-0"
                    :style="{ background: row.color }"
                  />
                  <span class="font-medium truncate">{{ row.primary }}</span>
                  <span v-if="row.secondary" class="text-xs text-muted-foreground shrink-0">· {{ row.secondary }}</span>
                </div>
              </td>
              <td v-if="activeTab === 'product' || activeTab === 'item'" class="px-4 py-2.5 text-right tabular-nums text-muted-foreground">
                {{ row.qty?.toLocaleString() }}
              </td>
              <td class="px-4 py-2.5 text-right tabular-nums">{{ row.sales.toLocaleString() }}</td>
              <td class="px-4 py-2.5 text-right tabular-nums font-medium">{{ row.margin.toLocaleString() }}</td>
              <td class="px-4 py-2.5 text-right tabular-nums font-semibold" :class="marginPctClass(row.marginPct)">
                {{ fmtPct(row.marginPct, 1) }}
              </td>
              <td class="px-4 py-2.5">
                <div class="flex items-center gap-2 justify-end">
                  <span class="text-xs text-muted-foreground tabular-nums shrink-0 w-10 text-right">{{ fmtPct(row.salesRatio, 1) }}</span>
                  <div class="h-1.5 w-16 rounded-full bg-muted overflow-hidden shrink-0">
                    <div class="h-full bg-chart-1/70 rounded-full" :style="{ width: `${Math.min(100, row.salesRatio)}%` }" />
                  </div>
                </div>
              </td>
              <td class="px-4 py-2.5">
                <div class="flex items-center gap-2 justify-end">
                  <span class="text-xs text-foreground tabular-nums shrink-0 w-10 text-right font-semibold">{{ fmtPct(row.marginRatio, 1) }}</span>
                  <div class="h-1.5 w-16 rounded-full bg-muted overflow-hidden shrink-0">
                    <div class="h-full bg-chart-2/80 rounded-full" :style="{ width: `${Math.min(100, row.marginRatio)}%` }" />
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="bg-muted/30 text-xs">
              <td colspan="2" class="px-4 py-2.5 font-semibold text-muted-foreground uppercase tracking-wide">TOTAL</td>
              <td v-if="activeTab === 'product' || activeTab === 'item'" class="px-4 py-2.5 text-right tabular-nums text-muted-foreground">
                {{ activeRows.reduce((s, r) => s + (r.qty ?? 0), 0).toLocaleString() }}
              </td>
              <td class="px-4 py-2.5 text-right tabular-nums font-semibold">{{ viewTotals.sales.toLocaleString() }}</td>
              <td class="px-4 py-2.5 text-right tabular-nums font-semibold">{{ viewTotals.margin.toLocaleString() }}</td>
              <td class="px-4 py-2.5 text-right tabular-nums font-semibold" :class="marginPctClass(marginPct)">{{ fmtPct(marginPct, 1) }}</td>
              <td class="px-4 py-2.5 text-right tabular-nums text-muted-foreground">100.0%</td>
              <td class="px-4 py-2.5 text-right tabular-nums text-muted-foreground">100.0%</td>
            </tr>
          </tfoot>
        </table>
      </div>

      <!-- Pagination (고객사 / SKU 탭만) -->
      <div
        v-if="needsPagination && totalPages > 1"
        class="flex items-center justify-between gap-3 px-4 py-3 border-t border-border bg-muted/20 flex-wrap"
      >
        <span class="text-xs text-muted-foreground tabular-nums">{{ pageRangeLabel }}</span>
        <div class="flex items-center gap-1">
          <button
            class="p-1.5 rounded-md border border-border hover:bg-accent transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
            :disabled="currentPage === 1"
            @click="goToPage(currentPage - 1)"
          >
            <ChevronLeft :size="12" />
          </button>
          <template v-for="(p, i) in pageNumbers" :key="`p-${i}`">
            <span v-if="p === '…'" class="px-2 text-xs text-muted-foreground select-none">…</span>
            <button
              v-else
              class="min-w-7 h-7 px-2 text-xs rounded-md border transition-colors tabular-nums"
              :class="p === currentPage
                ? 'border-primary bg-primary/10 text-primary font-semibold'
                : 'border-border text-muted-foreground hover:bg-accent'"
              @click="goToPage(p)"
            >{{ p }}</button>
          </template>
          <button
            class="p-1.5 rounded-md border border-border hover:bg-accent transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
            :disabled="currentPage === totalPages"
            @click="goToPage(currentPage + 1)"
          >
            <ChevronRight :size="12" />
          </button>
        </div>
      </div>
    </div>

    <!-- 교차 조회 (고객사 × SKU) — 요약 축이 아니라 명세(margin_lines) 기반이라 두 조건을 동시에 건다 -->
    <div class="rounded-xl border border-border bg-card overflow-hidden">
      <button
        class="w-full flex items-center gap-2 px-4 py-3 text-left hover:bg-accent/40 transition-colors"
        @click="crossOpen = !crossOpen"
      >
        <span class="text-sm font-semibold">교차 조회 · 고객사 × SKU</span>
        <span class="text-[11px] text-muted-foreground">두 조건 동시 적용 · 원가·마진 포함</span>
        <span
          v-if="crossOpen && crossState === 'mismatch'"
          class="text-[11px] px-1.5 py-0.5 rounded-md border bg-warning-soft text-warning border-warning-border"
          title="이 달의 명세 엑셀이 요약본보다 이전 판이라 합계가 다릅니다"
        >명세 구버전</span>
        <span
          v-else-if="crossOpen && crossState === 'none'"
          class="text-[11px] px-1.5 py-0.5 rounded-md border bg-muted text-muted-foreground border-border"
          title="이 달은 명세 엑셀이 없어 교차 조회를 할 수 없습니다"
        >명세 없음</span>
        <ChevronDown :size="14" class="ml-auto text-muted-foreground transition-transform" :class="crossOpen && 'rotate-180'" />
      </button>

      <div v-if="crossOpen" class="border-t border-border">
        <div class="flex items-end gap-2 flex-wrap px-4 py-3 bg-muted/20">
          <label class="flex flex-col gap-1">
            <span class="text-[11px] font-semibold text-muted-foreground">고객사</span>
            <input v-model="crossBuyer" list="cross-buyers" type="text" placeholder="고객사명"
              class="w-64 bg-card border border-border rounded-lg px-3 py-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" />
            <datalist id="cross-buyers"><option v-for="b in crossBuyerOptions" :key="b" :value="b" /></datalist>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-[11px] font-semibold text-muted-foreground">SKU · 품명</span>
            <input v-model="crossSku" list="cross-skus" type="text" placeholder="품명 또는 품목코드"
              class="w-64 bg-card border border-border rounded-lg px-3 py-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" />
            <datalist id="cross-skus"><option v-for="s in crossSkuOptions" :key="s" :value="s" /></datalist>
          </label>
          <button v-if="crossAnyFilter" class="px-3 py-2 text-xs rounded-lg border border-border hover:bg-accent transition-colors" @click="crossClear">필터 해제</button>
          <div class="ml-auto flex items-center gap-2">
            <span class="text-[11px] text-muted-foreground tabular-nums">
              {{ crossRows.length.toLocaleString() }}개 조합 · 수량 {{ crossTotal.qty.toLocaleString('en-US') }} ·
              매출 {{ fmtIdr(crossTotal.sales) }} · 마진 {{ fmtIdr(crossTotal.margin) }}
              ({{ crossTotal.sales ? fmtPct(crossTotal.margin / crossTotal.sales * 100) : '—' }})
            </span>
            <button class="px-3 py-2 text-xs rounded-lg border border-border hover:bg-accent transition-colors disabled:opacity-40"
              :disabled="!crossRows.length"
              :title="`원본 명세 ${crossRawRows.length.toLocaleString()}건(월·주문번호별) + 집계 ${crossRows.length.toLocaleString()}건`"
              @click="downloadCrossXlsx">엑셀 (명세 {{ crossRawRows.length.toLocaleString() }}건)</button>
          </div>
        </div>

        <DataState
          v-if="crossLoading || crossError || !crossLines.length"
          :loading="crossLoading" :error="crossError" :empty="!crossLines.length"
          loading-text="명세 불러오는 중…" empty-text="이 기간은 명세 데이터가 없습니다."
          skeleton-class="h-40 m-4"
          @retry="retryCrossLines"
        />
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm">
            <caption class="sr-only">거래 명세 상세</caption>
            <thead>
              <tr class="text-xs uppercase tracking-wide text-muted-foreground border-b border-border">
                <th scope="col" class="px-4 py-2.5 text-left font-medium w-8">#</th>
                <th scope="col" class="px-4 py-2.5 text-left font-medium">고객사</th>
                <th scope="col" class="px-4 py-2.5 text-left font-medium">SKU · 품명</th>
                <th scope="col" class="px-4 py-2.5 text-right font-medium">수량</th>
                <th scope="col" class="px-4 py-2.5 text-right font-medium">매출 (IDR)</th>
                <th scope="col" class="px-4 py-2.5 text-right font-medium">원가 (IDR)</th>
                <th scope="col" class="px-4 py-2.5 text-right font-medium">마진 (IDR)</th>
                <th scope="col" class="px-4 py-2.5 text-right font-medium">마진율</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(r, i) in crossRows.slice(0, 200)" :key="`${r.buyer}|${r.description}`"
                  class="border-b border-border/50 last:border-b-0 hover:bg-accent/40 transition-colors">
                <td class="px-4 py-2.5 text-xs text-muted-foreground tabular-nums">{{ i + 1 }}</td>
                <td class="px-4 py-2.5">{{ r.buyer }}</td>
                <td class="px-4 py-2.5">
                  <div>{{ r.description }}</div>
                  <div class="text-[11px] text-muted-foreground font-mono">{{ r.sku }}</div>
                </td>
                <td class="px-4 py-2.5 text-right tabular-nums text-muted-foreground">{{ r.qty.toLocaleString('en-US') }}</td>
                <td class="px-4 py-2.5 text-right tabular-nums">{{ fmtIdr(r.sales) }}</td>
                <td class="px-4 py-2.5 text-right tabular-nums text-muted-foreground">{{ fmtIdr(r.cost) }}</td>
                <td class="px-4 py-2.5 text-right tabular-nums font-medium" :class="r.margin < 0 && 'text-destructive'">{{ fmtIdr(r.margin) }}</td>
                <td class="px-4 py-2.5 text-right tabular-nums">{{ r.sales ? fmtPct(r.margin / r.sales * 100) : '—' }}</td>
              </tr>
              <tr v-if="!crossRows.length">
                <td colspan="8" class="px-4 py-8 text-center text-sm text-muted-foreground">조건에 맞는 거래가 없습니다.</td>
              </tr>
            </tbody>
          </table>
          <p v-if="crossRows.length > 200" class="px-4 py-2 text-[11px] text-muted-foreground border-t border-border">
            상위 200개 조합만 표시합니다 — 전체는 엑셀로 내려받으세요.
          </p>
        </div>
      </div>
    </div>

    <!-- Note -->
    <div class="rounded-xl border border-border bg-muted/20 p-4 space-y-1">
      <p class="text-xs font-semibold text-muted-foreground">데이터 소스</p>
      <p class="text-xs text-muted-foreground">
        Supabase 테이블 <code class="bg-muted px-1 rounded">margin_months</code> ·
        <code class="bg-muted px-1 rounded">margin_records</code> — 월별 <code class="bg-muted px-1 rounded">sales analysis report</code> PDF 추출본 기반.
        「교차 조회」는 같은 리포트 엑셀의 명세 시트를 적재한 <code class="bg-muted px-1 rounded">margin_lines</code>(라인 단위)를 쓰므로
        요약 축으로는 불가능한 <strong>고객사 × SKU 동시 조건</strong>과 원가·마진을 함께 볼 수 있습니다.
        전월 대비(MoM)는 직전 월 데이터와 비교하며, 추이 차트는 선택 월이 속한 연도의 월별 매출/마진과 전년·당년 평균을 함께 표시합니다.
      </p>
    </div>

  </div>
</template>
