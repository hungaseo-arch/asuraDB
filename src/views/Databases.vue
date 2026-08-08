<script setup lang="ts">
import { ref, computed, watch, onMounted, nextTick, type Ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Search, Package, Users, Contact, Building2, Wrench, Download, ShoppingCart, TrendingUp, X } from 'lucide-vue-next';
import StaffPayrollTable from '@/components/StaffPayrollTable.vue';
import DataState from '@/components/ui/DataState.vue';
import TableState from '@/components/ui/TableState.vue';
import { sbGetAll } from '@/lib/supabase';
import { exportCsv } from '@/lib/csv';
import { errMsg } from '@/lib/utils';
import { exportXlsxSheets, type Cell, type SheetSpec } from '@/lib/xlsx';
import { fmtInt, fmtFob, fmtWeight } from '@/lib/format';

// ── 1차 카테고리 ──────────────────────────────────────────────────────────────
type Section = 'product' | 'staff' | 'customer' | 'vendor' | 'purchase' | 'sales';
// 인사·급여(직원 탭)는 실명·NIK·기본급·Gross 를 담아 super_admin 전용으로 둔다.
// ※ 화면 숨김은 표시 제어일 뿐이며, 실제 차단은 staff_payroll·staff 의 RLS 가 담당한다
//   (supabase/migrations/restrict_staff_payroll_to_admin.sql).
const isSuperAdmin = sessionStorage.getItem('asura_auth') === 'super_admin';
const ALL_SECTIONS: { key: Section; label: string; icon: typeof Package; adminOnly?: boolean }[] = [
  { key: 'product',  label: '제품', icon: Package },
  { key: 'staff',    label: '직원', icon: Users, adminOnly: true },
  { key: 'customer', label: '고객', icon: Contact },
  { key: 'vendor',   label: '벤더', icon: Building2 },
  { key: 'purchase', label: '구매 현황', icon: ShoppingCart },
  { key: 'sales',    label: '판매 현황', icon: TrendingUp },
];
const SECTIONS = ALL_SECTIONS.filter(s => !s.adminOnly || isSuperAdmin);
// 하위 탭은 URL 쿼리(?tab=제품섹션&sub=하위탭)에 동기화한다 —
// 새로고침·뒤로가기에서 보던 탭이 유지되고, 특정 탭 링크를 공유·북마크할 수 있다.
const route = useRoute();
const router = useRouter();
const SECTION_KEYS = SECTIONS.map(s => s.key);
const qs = (v: unknown) => (typeof v === 'string' ? v : undefined);
const section = ref<Section>(
  (SECTION_KEYS as string[]).includes(qs(route.query.tab) ?? '') ? (route.query.tab as Section) : 'product',
);

// 제품 하위 탭
type ProductTab = 'price' | 'spec' | 'shipping';
const PRODUCT_TABS: { key: ProductTab; label: string }[] = [
  { key: 'price',    label: '가격' },
  { key: 'spec',     label: '스펙' },
  { key: 'shipping', label: '운송' },
];
const PRODUCT_TAB_KEYS = PRODUCT_TABS.map(t => t.key);
const productTab = ref<ProductTab>(
  (PRODUCT_TAB_KEYS as string[]).includes(qs(route.query.sub) ?? '') ? (route.query.sub as ProductTab) : 'price',
);

// ※ 탭(tab·sub)뿐 아니라 검색어·필터·정렬·페이지까지 함께 싣는다 —
//   상태 ref 들이 파일 아래쪽에 흩어져 있어 동기화 로직은 이 <script> 맨 끝에 모아 뒀다.

// ── 제품 카탈로그(가격): products 테이블 ──────────────────────────────────────
interface ProductRow {
  id: string;
  item: string | null; brand: string | null; description: string | null; sku: string | null; unit: string | null;
  wh_price_pcs: number | null; wh_price_set: number | null;
  dist_price_pcs?: number | null; dist_price_set?: number | null;
  category?: string | null; spec?: string | null; weight_kg?: number | null;
  fob?: number | null; qty_40ft?: number | null; selling_price?: number | null;
  /** 입고가 산정기준 — 'API-P'(기본) / 'API-U'(대체, 뱃지 표기) / null(원본에 API 구분 없음) */
  wh_price_basis?: string | null;
  /** 확인 필요 — review_field 셀에 「확인」 뱃지, 사유(review_note)는 tooltip */
  review_field?: string | null;
  review_note?: string | null;
  /** SAP 거래이력(A/R) 누적 판매량 — 취소·크레딧메모 반영한 순수량. v_db_products 에서 sku 매칭 */
  sap_sold_qty?: number | null;
  sap_last_sold?: string | null;
}
const rows = ref<ProductRow[]>([]);
const loading = ref(true);
const loadError = ref<string | null>(null);

async function load() {
  loading.value = true; loadError.value = null;
  try {
    // 가격/스펙은 products_price 로 분리됨 → 평면 뷰 products_priced 에서 조회
    rows.value = await sbGetAll<ProductRow>('products_priced?select=*&is_active=eq.true&order=item.asc,brand.asc,description.asc');
    // SAP 판매 롤업은 별도 뷰(v_db_products)에서 받아 sku 로 병합.
    // (가격 원가는 RLS 로 보호되는 products_price 소관이라 브리지 뷰에 없다 → 두 소스를 합친다)
    try {
      const sap = await sbGetAll<{ sku: string | null; sap_sold_qty: number | null; sap_last_sold: string | null }>(
        'v_db_products?select=sku,sap_sold_qty,sap_last_sold',
      );
      const bySku = new Map(sap.filter(s => s.sku).map(s => [s.sku as string, s]));
      rows.value = rows.value.map(p => {
        const s = p.sku ? bySku.get(p.sku) : undefined;
        return s ? { ...p, sap_sold_qty: Number(s.sap_sold_qty ?? 0), sap_last_sold: s.sap_last_sold } : p;
      });
    } catch { /* SAP 이력은 부가 정보 — 실패해도 가격표는 그대로 보여준다 */ }
  } catch (e) {
    loadError.value = errMsg(e); rows.value = [];
  }
  loading.value = false;
}
onMounted(load);

// 아이템 표시용 축약(데이터·매칭은 원본 유지, 화면 라벨만 치환).
// Jadi·Jasa(브랜드 GIS)=VUL → VUL, LTR → TBR 일원화(스펙 탭 TBR 그룹과 동일)
const CAT_LABELS: Record<string, string> = { PNEUMATIC: 'PNEU', JADI: 'VUL', JASA: 'VUL', LTR: 'TBR' };
const catOf = (p: ProductRow) => {
  const c = (p.category && p.category.trim()) || p.item || '기타';
  return CAT_LABELS[c.toUpperCase()] ?? c;
};
// 앱 표준 숫자 표기(한국표기법): 기본=정수 콤마, FOB=소수2, 중량=소수1 → @/lib/format
const fmt = fmtInt;
const txt = (s: string | null | undefined) => (s && s.trim() ? s : '—');
// 스펙 셀 표기 — 중량은 앱 표준(소수1), dp 지정 컬럼은 자릿수 고정, 그 외 정수.
// PostgREST 는 numeric 을 문자열로 돌려주므로 Number() 로 강제 변환한 뒤 포맷한다.
function fmtSpec(c: SpecCol, v: unknown): string {
  if (!c.num) return txt(v as string | null);
  const fixed = c.dp != null || c.maxDp != null;
  if (!fixed && c.key === 'weight_kg') return fmtWeight(v == null ? null : Number(v));
  if (!fixed) return fmt(v == null ? null : Number(v));
  const n = Number(v);
  if (v == null || Number.isNaN(n) || n === 0) return '—';
  return c.dp != null
    ? n.toLocaleString('ko-KR', { minimumFractionDigits: c.dp, maximumFractionDigits: c.dp })
    : n.toLocaleString('ko-KR', { maximumFractionDigits: c.maxDp });
}

// 확인 필요 표기 — review_field 가 가리키는 셀에만 「확인」 뱃지를 띄운다(사유는 title tooltip).
const needsReview = (r: { review_field?: string | null; review_note?: string | null }, key: string) =>
  !!r.review_note && r.review_field === key;
const reviewCount = computed(() => filtered.value.reduce((n, r) => n + (r.review_note ? 1 : 0), 0));

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

// ── 부가세(PPN) 표기 기준 ─────────────────────────────────────────────────────
// DB 저장 기준(CLAUDE.md 「가격 부가세(PPN) 기준」)은 입고가 = VAT 별도, 대리점가 = VAT 포함으로 고정.
// 화면·CSV 는 아래 토글로 두 기준을 오가며 보여준다(저장값은 바꾸지 않는다). 인니 PPN 11%.
const PPN = 0.11;
const VAT_MODES = [
  { key: 'excl', label: 'VAT 별도' },
  { key: 'incl', label: 'VAT 포함' },
] as const;
type VatMode = (typeof VAT_MODES)[number]['key'];
const vatMode = ref<VatMode>('excl');
const vatLabel = computed(() => (vatMode.value === 'incl' ? 'VAT 포함' : 'VAT 별도'));
/** 저장 기준(stored)의 값을 현재 표기 기준(vatMode)으로 환산. 기준이 같으면 원본 그대로. */
function vat(v: number | null | undefined, stored: VatMode): number | null {
  if (v == null || !Number.isFinite(Number(v))) return null;
  if (stored === vatMode.value) return Number(v);
  return Math.round(stored === 'incl' ? Number(v) / (1 + PPN) : Number(v) * (1 + PPN));
}

// 가격 정렬 (헤더 클릭 토글) — No. 열 제외
const PRICE_COLS = computed<{ key: string; label: string; right?: boolean; sub?: string }[]>(() => [
  { key: 'category', label: '아이템' },
  { key: 'description', label: '제품' },
  { key: 'fob', label: 'FOB', right: true },
  { key: 'weight_kg', label: '중량(kg)', right: true },
  { key: 'qty_40ft', label: '40ft(Qty)', right: true },
  { key: 'wh_price_pcs', label: '입고가(pcs)', right: true, sub: vatLabel.value },
  { key: 'wh_price_set', label: '입고가(set)', right: true, sub: vatLabel.value },
  { key: 'dist_price_pcs', label: '대리점가(pcs)', right: true, sub: vatLabel.value },
  { key: 'dist_price_set', label: '대리점가(set)', right: true, sub: vatLabel.value },
  { key: 'sap_sold_qty', label: '판매량(SAP)', right: true, sub: '누적 pcs' },
]);
function priceVal(p: ProductRow, key: string): string | number {
  if (key === 'category') return catOf(p);
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
// dp    = 소수 자릿수 고정(미지정 시 정수). 예) 두께 1.40mm
// maxDp = 최대 소수 자릿수(뒤 0 생략). 예) 트레드 깊이 21 / 16.5
// sub   = 라벨 아래 작은 글씨(단위 등)
interface SpecCol { key: string; label: string; num?: boolean; dp?: number; maxDp?: number; sub?: string }
type SpecTableKey = 'tbr' | 'tbb' | 'otr' | 'agr' | 'tube' | 'solid' | 'pneu' | 'flap' | 'gis';
// full=true 면 specCols 를 전체 컬럼으로 그대로 사용(BASE/WEIGHT 래핑 생략)
interface CatDef { key: string; label: string; items: string[]; specTable: SpecTableKey | null; specCols: SpecCol[]; full?: boolean }
// 제원 용어 규칙(CLAUDE.md 컨벤션) — ① 영문 통일 ② 같은 항목은 같은 용어 ③ 약어 사용
// PAT·Size·PR·LI·SS·RIM·OD·SW·TD·Single·Dual·Pres·WT ④ 단위는 반드시 표기((mm)/(kg)/(psi)/(EA)…).
// 헤더는 1행만 쓴다(2단 그룹 헤더 폐지, 2026-08-04) — 묶음은 라벨 접두사로 표현한다
// (Max Load Single → 'Load Single', Factory Catalog Width → 'Fac. Width'). 단위는 sub 로 붙인다.
// 용어 구분 — Type=제품·트레드 유형 / Grade=등급·사양코드(SHD·LM) / Const.=구조(Radial·Bias).
// 제품 셀(No./아이템/제품) 다음에 오는 공통 컬럼 — 패턴·규격 (SKU·브랜드는 제품 셀 서브라인으로 이동)
const BASE_COLS: SpecCol[] = [
  { key: 'pattern', label: 'PAT' }, { key: 'size', label: 'Size' },
];
const WEIGHT_COL: SpecCol = { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true };
// 카테고리별 제원 컬럼(sku 매칭되는 스펙 테이블 행에서 채움)
// TBR: 카탈로그 제원표 규격(2026-08-03) — Size·PR·Load/Speed·Rim·OD·SW·TD·Load Capacity(Single/Dual)·Pressure
// (full 컬럼셋. 최대하중은 Load Single·Load Dual. Rim 은 '7.50' 표기 유지를 위해 텍스트)
const TBR_SPEC: SpecCol[] = [
  { key: 'size', label: 'Size' },
  { key: 'ply_rating', label: 'PR', num: true },
  { key: 'load_index', label: 'LI / SS' },
  { key: 'rim_width', label: 'RIM', sub: '(inch)' },
  { key: 'overall_diameter_mm', label: 'OD', sub: '(mm)', num: true },
  { key: 'section_width_mm', label: 'SW', sub: '(mm)', num: true },
  { key: 'tread_depth_mm', label: 'TD', sub: '(mm)', num: true, maxDp: 1 },
  { key: 'single_load_kg', label: 'Load Single', sub: '(kg)', num: true },
  { key: 'dual_load_kg', label: 'Load Dual', sub: '(kg)', num: true },
  { key: 'max_pressure_psi', label: 'Pres', sub: '(psi)', num: true },
];
// TBB: 3개 브랜드(JK Tyre·TIRON·Ascendo) 통합 카탈로그 제원표 규격(2026-08-03).
// 최대하중·공기압은 Load Single/Dual · Pres Single/Dual 로 나눈다. RIM 은 '6.00G'·'8.50/1.8' 표기가 있어 텍스트.
const TBB_SPEC: SpecCol[] = [
  { key: 'pattern', label: 'PAT' },
  { key: 'size', label: 'Size' },
  { key: 'ply_rating', label: 'PR', num: true },
  { key: 'tire_type', label: 'Type' },
  { key: 'construction', label: 'Grade' },   // SHD·LM·PRIME 등 등급·사양 코드(구조 아님)
  { key: 'rim_size', label: 'RIM', sub: '(inch)' },
  { key: 'overall_diameter_mm', label: 'OD', sub: '(mm)', num: true },
  { key: 'section_width_mm', label: 'SW', sub: '(mm)', num: true },
  { key: 'tread_depth_mm', label: 'TD', sub: '(mm)', num: true, maxDp: 1 },
  { key: 'load_index', label: 'LI' },
  { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true, maxDp: 1 },
  { key: 'single_load_kg', label: 'Load Single', sub: '(kg)', num: true },
  { key: 'dual_load_kg', label: 'Load Dual', sub: '(kg)', num: true },
  { key: 'single_pressure_psi', label: 'Pres Single', sub: '(psi)', num: true },
  { key: 'dual_pressure_psi', label: 'Pres Dual', sub: '(psi)', num: true },
  { key: 'application', label: 'Application' },
  { key: 'remarks', label: 'Remarks' },
];
// OTR: OTR 통합 카탈로그(2026-08-04, Ascendo·Techking) 제원표 규격 — 구분·★하중등급·TRA·TD·TT/TL·림·SW·OD,
// 하중/공기압은 10·50 km/h 로 분리. 라디얼은 PR 대신 ★(star_rating)으로 하중등급을 표기한다.
// TKPH 는 마스터 174행 전부 값이 없어 뺐고, LI&SS·컴파운드는 값 있는 카탈로그 행(TECHKING 5행)이
// 취급 제품과 패턴이 달라 전부 공란이라 컬럼만 두고 헤더에서는 제외. 중량은 products_priced.weight_kg.
const OTR_SPEC: SpecCol[] = [
  { key: 'construction', label: 'Const.' },   // Radial / Bias
  { key: 'pattern', label: 'PAT' },
  { key: 'size', label: 'Size' },
  { key: 'ply_rating', label: 'PR', num: true },
  { key: 'star_rating', label: 'SR', sub: '(★)' },
  { key: 'tra_code', label: 'TRA' },
  { key: 'tread_depth_mm', label: 'TD', sub: '(mm)', num: true, maxDp: 1 },
  { key: 'tube_type', label: 'TT/TL' },
  { key: 'rim_size', label: 'RIM', sub: '(inch)' },
  { key: 'section_width_mm', label: 'SW', sub: '(mm)', num: true },
  { key: 'overall_diameter_mm', label: 'OD', sub: '(mm)', num: true },
  { key: 'load_10kmh', label: 'Load 10 km/h', sub: '(kg)', num: true },
  { key: 'load_50kmh', label: 'Load 50 km/h', sub: '(kg)', num: true },
  { key: 'pressure_10kmh_psi', label: 'Pres 10 km/h', sub: '(psi)', num: true },
  { key: 'pressure_50kmh_psi', label: 'Pres 50 km/h', sub: '(psi)', num: true },
  { key: 'application', label: 'Application' },
  { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true, maxDp: 1 },
  { key: 'features', label: 'Features' },
];
// AGR: Ascendo AGR-BIAS 카탈로그 제원표 규격(2026-07) — TD·OD·SW·림·TT/TL 추가.
// 속도는 신규 카탈로그에 없는 항목으로 기존 specs_agr 승계분에만 값이 있다. 중량은 products_priced 값.
const AGR_SPEC: SpecCol[] = [
  { key: 'pattern', label: 'PAT' },
  { key: 'size', label: 'Size' },
  { key: 'ply_rating', label: 'PR', num: true },
  { key: 'tread_depth_mm', label: 'TD', sub: '(mm)', num: true, maxDp: 1 },
  { key: 'overall_diameter_mm', label: 'OD', sub: '(mm)', num: true },
  { key: 'section_width_mm', label: 'SW', sub: '(mm)', num: true },
  { key: 'rim_size', label: 'RIM', sub: '(inch)' },
  { key: 'max_load_kg', label: 'Max Load', sub: '(kg)', num: true },
  { key: 'max_pressure_psi', label: 'Pres', sub: '(psi)', num: true },
  { key: 'tube_type', label: 'TT/TL' },
  { key: 'rated_speed_kmh', label: 'Speed', sub: '(km/h)', num: true },
  { key: 'application', label: 'Application' },
  { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true, maxDp: 1 },
];
// TUBE: Ascendo Tube Catalog(2026-07-24) 규격 반영 — 구분·비고 추가, 포장은 Sack/Box 로 분리.
// (full 컬럼셋, Pattern/Size 미표시) 중량은 products_priced.weight_kg, 나머지는 specs_tube 행에서 채움
// (폭=lebar·두께=tebal). Type 은 카탈로그 구분(category_label)이며 내부 생산분류 category(Type 1~4)와 별개.
const TUBE_SPEC: SpecCol[] = [
  { key: 'category_label', label: 'Type' },
  { key: 'size_label', label: 'Size' },
  { key: 'valve', label: 'Valve' },
  { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true, dp: 2 },   // 튜브 제원표 기준 소수 2자리(앱 표준 소수1은 0.45→0.5 로 뭉개짐)
  { key: 'lebar', label: 'Width', sub: '(mm)', num: true },
  { key: 'tebal', label: 'Thick', sub: '(mm)', num: true, dp: 2 },
  { key: 'sack_qty', label: 'Sack', sub: '(EA)', num: true },
  { key: 'box_qty', label: 'Box', sub: '(EA)', num: true },
  { key: 'mold_qty', label: 'Mold', sub: '(set)', num: true },
  { key: 'capa_month', label: 'Output', sub: '(pcs/mo)', num: true },
  { key: 'remarks', label: 'Remarks' },
];
// SOLID: IND 카탈로그 제원표 규격(2026-08-04 갱신) — ASCENDO/DIAMOND 두 표를 하나로 합침.
// 하중은 지게차 구동축(Load Drive)·조향축(Load Steer)과 속도구간별로 나누며, ASCENDO 행은 Load Drive 만 채워짐(나머지 —).
// tire_type 은 전 행 'Solid' 단일값이라 헤더에서 제외(컬럼은 DB 에 보존).
const SOLID_SPEC: SpecCol[] = [
  { key: 'series', label: 'Series' },
  { key: 'pattern', label: 'PAT' },
  { key: 'size', label: 'Size' },
  { key: 'rim_size', label: 'RIM', sub: '(inch)' },
  { key: 'overall_diameter_mm', label: 'OD', sub: '(mm)', num: true },
  { key: 'section_width_mm', label: 'SW', sub: '(mm)', num: true },
  { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true, maxDp: 2 },
  { key: 'load_kg', label: 'Load Drive', sub: '(kg)', num: true },
  { key: 'steer_load_kg', label: 'Load Steer', sub: '(kg)', num: true },
  { key: 'load_6kmh_kg', label: 'Load ≤6 km/h', sub: '(kg)', num: true },
  { key: 'load_10kmh_kg', label: 'Load ≤10 km/h', sub: '(kg)', num: true },
  { key: 'load_25kmh_kg', label: 'Load ≤25 km/h', sub: '(kg)', num: true },
  { key: 'remarks', label: 'Remarks' },
];
// PNEU: IND 카탈로그 공기압 제원표 규격(2026-08-03). RIM 은 '4.33R' 등 문자 표기라 텍스트.
const PNEU_SPEC: SpecCol[] = [
  { key: 'size', label: 'Size' },
  { key: 'ply_rating', label: 'PR', num: true },
  { key: 'tube_type', label: 'TT/TL' },
  { key: 'rim_size', label: 'RIM', sub: '(inch)' },
  { key: 'overall_diameter_mm', label: 'OD', sub: '(mm)', num: true },
  { key: 'section_width_mm', label: 'SW', sub: '(mm)', num: true },
  { key: 'tread_depth_mm', label: 'TD', sub: '(mm)', num: true, maxDp: 1 },
  { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true, maxDp: 2 },
  { key: 'max_load_kg', label: 'Max Load', sub: '(kg)', num: true },
  { key: 'max_pressure_psi', label: 'Pres', sub: '(psi)', num: true },
];
// FLAP: 자사 카탈로그(Flap Ascendo) + 공장 카탈로그(Shanxi Huajun, JUL 2026) 대조표 규격(2026-08-04).
// 자사 값(Type·Class·Sack)과 공장 기준값은 'Fac.' 접두사로 구분한다.
// WT (kg) 는 자사 제품 실중량(products_priced), Fac. WT (kg) 는 공장 카탈로그 기준값.
const FLAP_SPEC: SpecCol[] = [
  { key: 'size', label: 'Size' },
  { key: 'flap_type', label: 'Type' },        // Standard / Metal Plate
  { key: 'tyre_class', label: 'Class' },      // TBR / OTR
  { key: 'qty_sack', label: 'Sack', sub: '(EA)', num: true },
  { key: 'weight_kg', label: 'WT', sub: '(kg)', num: true, maxDp: 2 },
  { key: 'factory_size', label: 'Fac. Size' },
  { key: 'width_mm', label: 'Fac. Width', sub: '(mm)', num: true },
  { key: 'ref_weight_kg', label: 'Fac. WT', sub: '(kg)', num: true, maxDp: 1 },
  { key: 'match_status', label: 'Fac. Match' },
  { key: 'remarks', label: 'Remarks' },
];
// VUL(재생): GIS ECO RETREAD 리플릿 프리큐어 트레드 사양표(2026-08-04).
// BW=Base Width(트레드 바닥 폭), SD=Skid Depth(홈 깊이). 중량은 롤 단위·m 단위 두 컬럼.
const GIS_SPEC: SpecCol[] = [
  { key: 'pattern', label: 'PAT' },
  { key: 'size', label: 'Size' },
  { key: 'construction', label: 'Const.' },   // Bias / Radial
  { key: 'tread_shape', label: 'Tread' },
  { key: 'base_width_mm', label: 'BW', sub: '(mm)', num: true },
  { key: 'skid_depth_mm', label: 'SD', sub: '(mm)', num: true, maxDp: 1 },
  { key: 'roll_length_mm', label: 'Roll', sub: '(mm)', num: true },
  { key: 'weight_kg_roll', label: 'WT', sub: '(kg/roll)', num: true, maxDp: 2 },
  { key: 'weight_kg_m', label: 'WT', sub: '(kg/m)', num: true, maxDp: 2 },
  { key: 'position', label: 'Position' },
  { key: 'application', label: 'Application' },
];
// 스펙 탭 = 제품(products) 기준 조회. products.item 으로 그룹화하여 전 제품이 조회됨.
// 제원은 sku로 매칭되는 specs_<tbr|otr|agr> 행에서 채워 표시(없으면 —).
const SPEC_DEFS: CatDef[] = [
  { key: 'tbr', label: 'TBR', items: ['TBR', 'LTR'], specTable: 'tbr', specCols: TBR_SPEC, full: true },
  { key: 'tbb', label: 'TBB', items: ['TBB'], specTable: 'tbb', specCols: TBB_SPEC, full: true },
  { key: 'otr', label: 'OTR', items: ['OTR'], specTable: 'otr', specCols: OTR_SPEC, full: true },
  { key: 'agr', label: 'AGR', items: ['AGR'], specTable: 'agr', specCols: AGR_SPEC, full: true },
  { key: 'pneu', label: 'PNEU', items: ['PNEUMATIC'], specTable: 'pneu', specCols: PNEU_SPEC, full: true },
  { key: 'solid', label: 'SOLID', items: ['SOLID'], specTable: 'solid', specCols: SOLID_SPEC, full: true },
  { key: 'flap', label: 'FLAP', items: ['FLAP'], specTable: 'flap', specCols: FLAP_SPEC, full: true },
  { key: 'tube', label: 'TUBE', items: ['TUBE'], specTable: 'tube', specCols: TUBE_SPEC, full: true },
  { key: 'gis', label: 'VUL', items: ['JADI', 'JASA'], specTable: 'gis', specCols: GIS_SPEC, full: true },
];
const specTab = ref('tbr');
const specDef = computed(() => SPEC_DEFS.find(d => d.key === specTab.value)!);
// 카테고리 정의 → 화면에 쓸 제원 컬럼(스펙 탭·스펙 모달 공용)
const colsOf = (d: CatDef): SpecCol[] => (d.full ? d.specCols : [...BASE_COLS, ...d.specCols, WEIGHT_COL]);
const specCols = computed<SpecCol[]>(() => colsOf(specDef.value));
/** 제품 아이템(products.item) → 소속 스펙 카테고리 정의 */
const specDefOfItem = (item: string | null | undefined): CatDef | null => {
  const key = String(item ?? '').toUpperCase();
  return SPEC_DEFS.find(d => d.items.some(i => i.toUpperCase() === key)) ?? null;
};
// CSV 헤더용 — 화면의 라벨+단위를 한 칸으로 합친다
const colHead = (c: SpecCol) => (c.sub ? `${c.label} ${c.sub}` : c.label);
type SpecRow = Record<string, string | number | null>;
const specTableData = ref<Record<string, SpecRow[]>>({});   // 제원 원천, key=spec 테이블(tbr/otr/agr)
const specLoading = ref(false);
const specError = ref<string | null>(null);
const specQuery = ref('');
// 실제 테이블명 매핑 — TUBE 를 뺀 전 카테고리가 products_spec_*(sku 1행 기준), TUBE 만 specs_tube
// (specs_agr·specs_otr 은 제품에 연결되지 않은 마스터 행이 남아 있어 테이블 자체는 보존)
const SPEC_TABLE_NAME: Record<string, string> = {
  tbr: 'products_spec_tbr', tbb: 'products_spec_tbb', agr: 'products_spec_agr',
  solid: 'products_spec_solid', pneu: 'products_spec_pneu', flap: 'products_spec_flap',
  gis: 'products_spec_gis', otr: 'products_spec_otr', tube: 'specs_tube',
};
async function loadSpecTable(table: string | null) {
  if (!table || specTableData.value[table]) return;
  specLoading.value = true; specError.value = null;
  try { specTableData.value[table] = await sbGetAll<SpecRow>(`${SPEC_TABLE_NAME[table] ?? `specs_${table}`}?select=*`); }
  catch (e) { specTableData.value[table] = []; specError.value = errMsg(e); }
  specLoading.value = false;
}
// 실패한 카테고리는 빈 배열이 캐시돼 있으므로, 재시도 시 캐시를 지우고 다시 받는다
function retrySpecTable() {
  const table = specDef.value.specTable;
  if (!table) return;
  delete specTableData.value[table];
  specError.value = null;
  void loadSpecTable(table);
}
watch([specTab, productTab], () => { if (productTab.value === 'spec') void loadSpecTable(specDef.value.specTable); }, { immediate: true });

// 제원 매칭용 정규화 — 규격(공백·말단 TL/TT/LT 제거) / 패턴(영숫자+'+'만, 대문자)
const normSize = (v: unknown): string => String(v ?? '').toUpperCase().replace(/\s/g, '').replace(/(TL|TT|LT)$/, '');
const normPat = (v: unknown): string => String(v ?? '').toUpperCase().replace(/[^A-Z0-9+]/g, '');
// 제품 description → 표시용 (size·pattern·ply) 파싱. 예) "ASC 11.00R20 AR313 16" → 11.00R20 · AR313 · 16
const SPEC_MODS = new Set(['TL', 'TT', 'TTF', 'TTC', 'TF', 'TTT', 'SET', 'R']);
function parseDesc(desc: string | null): { size: string; pattern: string; ply: number | null } {
  if (!desc) return { size: '', pattern: '', ply: null };
  const d = desc.replace(/\(R\)\s*$/i, '').trim();
  const toks = d.split(/\s+/);
  const size = toks[1] ?? '';                       // toks[0]=브랜드 약칭, toks[1]=규격
  let ply: number | null = null;
  const m = d.match(/(\d{1,3})\s*PR\b/i);
  if (m) ply = +m[1];
  else { const last = toks[toks.length - 1] ?? ''; if (/^\d{1,2}$/.test(last)) ply = +last; }
  const patToks = toks.slice(2).filter(t => {
    if (/^\d{1,3}PR$/i.test(t)) return false;
    if (/^\d{1,2}$/.test(t)) return false;
    return !SPEC_MODS.has(t.toUpperCase());
  });
  return { size, pattern: patToks.join(' '), ply };
}

// 제원 매칭 인덱스 — sku(정밀) + 속성키 (brand·pattern·size·ply). 카탈로그 제원 행은 sku가 없어 속성키로 매칭.
type SpecIdx = { bySku: Map<string, SpecRow>; byAttr: Map<string, SpecRow>; byAttrNoPly: Map<string, SpecRow> };
function buildSpecIndex(t: string | null): SpecIdx {
  const bySku = new Map<string, SpecRow>();
  const byAttr = new Map<string, SpecRow>();      // ply 포함 키
  const byAttrNoPly = new Map<string, SpecRow>();  // spec.ply=null 인 행만(폴백)
  if (t) for (const r of specTableData.value[t] ?? []) {
    if (r.sku) bySku.set(String(r.sku), r);
    const base = [r.brand, normPat(r.pattern), normSize(r.size)].join('|');
    const ply = r.ply_rating == null ? '' : String(r.ply_rating);
    if (!byAttr.has(base + '|' + ply)) byAttr.set(base + '|' + ply, r);
    if (r.ply_rating == null && !byAttrNoPly.has(base)) byAttrNoPly.set(base, r);
  }
  return { bySku, byAttr, byAttrNoPly };
}
const specIndex = computed(() => buildSpecIndex(specDef.value.specTable));
/** 제품 1건 → 제원 행. sku(정밀) → 속성키(브랜드·패턴·규격·PR) 순으로 카탈로그 제원을 매칭해 채운다. */
function buildSpecRow(p: ProductRow, def: CatDef, idx: SpecIdx): SpecRow {
  const cols = def.specCols;
  const hasPly = cols.some(c => c.key === 'ply_rating');
  const parsed = parseDesc(p.description);
  let spec = p.sku ? idx.bySku.get(String(p.sku)) : undefined;
  if (!spec) {                                   // sku 미매칭 → 속성키로 카탈로그 제원 매칭
    const base = [p.brand, normPat(parsed.pattern), normSize(parsed.size)].join('|');
    const plyKey = parsed.ply == null ? '' : String(parsed.ply);
    spec = idx.byAttr.get(base + '|' + plyKey) ?? idx.byAttrNoPly.get(base);
  }
  const row: SpecRow = {
    id: p.id, sku: p.sku ?? null, brand: p.brand ?? null,
    _title: p.description ?? null, _unit: p.unit ?? null, _cat: catOf(p),
    pattern: parsed.pattern || null, size: parsed.size || null,
    weight_kg: p.weight_kg ?? (spec?.weight_kg as number | null) ?? null,
    _matched: spec ? 1 : 0, _source: spec ? (spec.source_catalog ?? null) : null,
    // 확인 필요 표시는 가격 탭과 동일한 값(products_priced)을 그대로 이어받는다
    _reviewField: p.review_field ?? null, _reviewNote: p.review_note ?? null,
  };
  // 제원 값으로 채우되, 스펙 테이블에 없는 컬럼(예: TUBE 의 weight_kg)은 위에서 넣은 값을 유지
  for (const c of cols) {
    const v = spec ? (spec[c.key] ?? null) : null;
    if (v == null && row[c.key] != null) continue;
    row[c.key] = v;
  }
  if (hasPly && row.ply_rating == null) row.ply_rating = parsed.ply;   // 제원 없으면 파싱 PR 폴백
  return row;
}
// 제품(products) 기준 조회 — 스펙 탭 행 = 가격 탭 제품(가격.sku = 스펙.sku, 행 수 동일).
const specRows = computed<SpecRow[]>(() => {
  const items = new Set(specDef.value.items.map(s => s.toUpperCase()));
  const idx = specIndex.value;
  return rows.value
    .filter(p => items.has(String(p.item ?? '').toUpperCase()))
    .map(p => buildSpecRow(p, specDef.value, idx));
});
const specFiltered = computed(() => {
  const q = specQuery.value.trim().toLowerCase();
  if (!q) return specRows.value;
  return specRows.value.filter(r => Object.values(r).some(v => String(v ?? '').toLowerCase().includes(q)));
});
const specMatched = computed(() => specFiltered.value.reduce((n, r) => n + (r._matched ? 1 : 0), 0));
// 스펙 정렬 (헤더 클릭 토글). 숫자 컬럼(num)은 수치, 나머지는 문자.
const specSort = ref<{ key: string; dir: 1 | -1 }>({ key: '_title', dir: 1 });
watch(specTab, () => { specSort.value = { key: '_title', dir: 1 }; });
function specSortBy(key: string) {
  if (specSort.value.key === key) specSort.value.dir = specSort.value.dir === 1 ? -1 : 1;
  else specSort.value = { key, dir: 1 };
}
const specNumKeys = computed(() => new Set(specCols.value.filter(c => c.num).map(c => c.key)));
const specSorted = computed(() => {
  const { key, dir } = specSort.value;
  const numeric = specNumKeys.value.has(key);
  return [...specFiltered.value].sort((a, b) => {
    if (numeric) return ((a[key] as number ?? -Infinity) - (b[key] as number ?? -Infinity)) * dir;
    return String(a[key] ?? '').localeCompare(String(b[key] ?? ''), 'ko', { numeric: true }) * dir;
  });
});

// ── 가격 ↔ 스펙 교차 모달 ────────────────────────────────────────────────────
// 가격 탭에서 제품을 클릭하면 그 제품의 제원을, 스펙 탭에서 클릭하면 그 제품의 가격을 모달로 보여준다.
// 두 탭의 행은 같은 제품(products) 1건이라 id 로 서로 오갈 수 있다.
const specModal = ref<ProductRow | null>(null);    // 가격 탭 → 제원 모달
const priceModal = ref<ProductRow | null>(null);   // 스펙 탭 → 가격 모달
const specModalDef = computed(() => (specModal.value ? specDefOfItem(specModal.value.item) : null));
const specModalCols = computed<SpecCol[]>(() => (specModalDef.value ? colsOf(specModalDef.value) : []));
/** 제원 원천이 아직 안 받아졌는지 — 모달에서 '불러오는 중' 표시용 */
const specModalPending = computed(() => {
  const t = specModalDef.value?.specTable;
  return !!t && !specTableData.value[t];
});
const specModalRow = computed<SpecRow | null>(() => {
  const p = specModal.value, def = specModalDef.value;
  if (!p || !def) return null;
  return buildSpecRow(p, def, buildSpecIndex(def.specTable));
});
function openSpecModal(p: ProductRow) {
  specModal.value = p;
  void loadSpecTable(specDefOfItem(p.item)?.specTable ?? null);   // 캐시에 없으면 그때 받아온다
}
function openPriceModal(r: SpecRow) {
  priceModal.value = rows.value.find(p => p.id === r.id) ?? null;
}

// ── 고객: customers 테이블 (Supabase) ────────────────────────────────────────
interface CustomerRow {
  id: string; customer_code: string; customer_name: string;
  acquirer_name: string | null; main_pic_name: string | null;
  assist1_name: string | null; assist2_name: string | null; is_active: boolean;
  /** SAP 거래이력(A/R) 롤업 — 할인 후 매출 IDR(취소·크레딧메모 반영), 청구 건수, 최근 청구일 */
  sap_sales_idr: number; sap_invoice_cnt: number; sap_last_invoice: string | null;
}
const custRows = ref<CustomerRow[]>([]);
const custLoading = ref(false);
const custError = ref<string | null>(null);
const custLoaded = ref(false);
const custQuery = ref('');
async function loadCustomers() {
  if (custLoaded.value) return;
  custLoading.value = true; custError.value = null;
  try {
    // customers + SAP 판매 롤업 브리지 뷰. numeric 은 PostgREST 가 문자열로 주므로 Number() 로 정규화.
    const raw = await sbGetAll<CustomerRow>(
      'v_db_customers?select=id,customer_code,customer_name,acquirer_name,main_pic_name,assist1_name,assist2_name,is_active,sap_sales_idr,sap_invoice_cnt,sap_last_invoice&order=customer_code.asc',
    );
    custRows.value = raw.map(c => ({
      ...c,
      sap_sales_idr: Number(c.sap_sales_idr ?? 0),
      sap_invoice_cnt: Number(c.sap_invoice_cnt ?? 0),
    }));
    custLoaded.value = true;
  } catch (e) { custRows.value = []; custError.value = errMsg(e); }
  custLoading.value = false;
}
watch(section, s => { if (s === 'customer') void loadCustomers(); });
function retryCustomers() { custLoaded.value = false; custError.value = null; void loadCustomers(); }
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
const CUST_COLS: { key: keyof CustomerRow; label: string; center?: boolean; right?: boolean }[] = [
  { key: 'customer_code', label: '코드' },
  { key: 'customer_name', label: '고객명' },
  { key: 'acquirer_name', label: 'Acquirer' },
  { key: 'main_pic_name', label: 'Main PIC' },
  { key: 'assist1_name', label: 'Assist 1' },
  { key: 'assist2_name', label: 'Assist 2' },
  { key: 'is_active', label: '상태', center: true },
  { key: 'sap_sales_idr', label: '판매실적(SAP)', right: true },
];
// IDR 대금액 — 인니 실무 단위(juta 10^6 · miliar 10^9 · triliun 10^12). Margin.vue 와 동일 규칙.
function fmtIdr(v: number | null | undefined): string {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n) || n === 0) return '—';
  const a = Math.abs(n), sign = n < 0 ? '-' : '';
  if (a >= 1_000_000_000_000) return `${sign}${(a / 1_000_000_000_000).toFixed(2)} triliun`;
  if (a >= 1_000_000_000)     return `${sign}${(a / 1_000_000_000).toFixed(2)} miliar`;
  if (a >= 1_000_000)         return `${sign}${(a / 1_000_000).toFixed(2)} juta`;
  return Math.round(n).toLocaleString('en-US');
}
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
    if (typeof av === 'number' || typeof bv === 'number') return (Number(av ?? 0) - Number(bv ?? 0)) * dir;
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

// ── 벤더: v_db_vendors (vendors 마스터 + SAP 구매이력(A/P) 롤업) ─────────────
// 수기 관리 항목(연락처·결제조건·NPWP·은행)은 vendors 테이블, 실적은 SAP 롤업.
// 금액 기준은 할인 반영액(disc_amount_idr), USD 는 IDR ÷ 문서환율 — 뷰에서 계산된 값을 그대로 쓴다.
interface VendorRow {
  id: string; vendor_code: string; vendor_name: string;
  sourcing: 'LOCAL' | 'IMPORT' | 'UNKNOWN'; country: string | null;
  vendor_type: string | null; payment_term: string | null; incoterms: string | null;
  settle_currency: string | null;
  contact_person: string | null; contact_phone: string | null; contact_email: string | null;
  npwp: string | null; pic_name: string | null; is_active: boolean;
  sap_partner_id: number | null;
  ap_invoice_cnt: number; ap_line_cnt: number; qty_total: number;
  purchase_idr: number; purchase_usd: number; share_pct: number;
  first_inv_date: string | null; last_inv_date: string | null; months_since_last: number | null;
  cxl_line_cnt: number; cxl_usd: number;
  top_brand: string | null; top_category: string | null;
}
const venRows = ref<VendorRow[]>([]);
const venLoading = ref(false);
const venError = ref<string | null>(null);
const venLoaded = ref(false);
const venQuery = ref('');
const venDetail = ref<VendorRow | null>(null);

async function loadVendors() {
  if (venLoaded.value) return;
  venLoading.value = true; venError.value = null;
  try {
    const raw = await sbGetAll<VendorRow>('v_db_vendors?select=*&order=vendor_code.asc');
    // PostgREST 는 numeric 을 문자열로 돌려주므로 숫자 열을 정규화한다.
    venRows.value = raw.map(v => ({
      ...v,
      ap_invoice_cnt: Number(v.ap_invoice_cnt ?? 0), ap_line_cnt: Number(v.ap_line_cnt ?? 0),
      qty_total: Number(v.qty_total ?? 0), purchase_idr: Number(v.purchase_idr ?? 0),
      purchase_usd: Number(v.purchase_usd ?? 0), share_pct: Number(v.share_pct ?? 0),
      cxl_line_cnt: Number(v.cxl_line_cnt ?? 0), cxl_usd: Number(v.cxl_usd ?? 0),
      months_since_last: v.months_since_last == null ? null : Number(v.months_since_last),
    }));
    venLoaded.value = true;
  } catch (e) { venRows.value = []; venError.value = errMsg(e); }
  venLoading.value = false;
}
watch(section, s => { if (s === 'vendor') void loadVendors(); });
function retryVendors() { venLoaded.value = false; venError.value = null; void loadVendors(); }

// 거래 상태 — 최종 거래일로부터 경과 개월. 파생 라벨이라 DB 에 저장하지 않는다.
type VenStatus = '활성' | '관찰' | '휴면' | '거래중단' | '거래없음';
function venStatusOf(v: VendorRow): VenStatus {
  const m = v.months_since_last;
  if (m == null) return '거래없음';
  return m <= 6 ? '활성' : m <= 12 ? '관찰' : m <= 24 ? '휴면' : '거래중단';
}
const VEN_STATUS_CLASS: Record<VenStatus, string> = {
  활성: 'bg-emerald-500/10 text-emerald-600 border-emerald-500/20',
  관찰: 'bg-muted text-foreground/70 border-border',
  휴면: 'bg-muted text-muted-foreground border-border',
  거래중단: 'bg-muted text-muted-foreground/70 border-border',
  거래없음: 'bg-muted text-muted-foreground/70 border-border',
};
// ABC 등급 — 구성비 내림차순 누적. 누적(직전까지) 80% 미만 A · 95% 미만 B · 그 외 C.
// 임계를 넘기는 벤더까지 상위 등급에 포함하는 파레토 관례를 따른다(상위 4개사 = A, 누적 93.2%).
const venGrades = computed(() => {
  const m = new Map<string, 'A' | 'B' | 'C'>();
  let cum = 0;
  for (const v of [...venRows.value].sort((a, b) => b.share_pct - a.share_pct)) {
    m.set(v.id, cum < 80 ? 'A' : cum < 95 ? 'B' : 'C');
    cum += v.share_pct;
  }
  return m;
});
const venGradeOf = (v: VendorRow) => venGrades.value.get(v.id) ?? 'C';

const venSourcing = ref<'전체' | 'LOCAL' | 'IMPORT'>('전체');
const venFiltered = computed(() => {
  const q = venQuery.value.trim().toLowerCase();
  return venRows.value.filter(v => {
    if (venSourcing.value !== '전체' && v.sourcing !== venSourcing.value) return false;
    if (!q) return true;
    return [v.vendor_code, v.vendor_name, v.country, v.top_brand].some(x => (x ?? '').toLowerCase().includes(q));
  });
});
// 정렬 — 파생 열(상태·ABC)은 각각 경과개월·구성비로 정렬한다.
type VenSortKey = keyof VendorRow | '_status' | '_grade';
const VEN_COLS: { key: VenSortKey; label: string; center?: boolean; right?: boolean }[] = [
  { key: 'vendor_code', label: '코드' },
  { key: 'vendor_name', label: '벤더명' },
  { key: 'sourcing', label: '소싱', center: true },
  { key: 'country', label: '국가' },
  { key: '_status', label: '상태', center: true },
  { key: '_grade', label: 'ABC', center: true },
  { key: 'top_brand', label: '주요 브랜드' },
  { key: 'top_category', label: '주요 품목' },
  { key: 'ap_invoice_cnt', label: '인보이스', right: true },
  { key: 'qty_total', label: '수량 (EA)', right: true },
  { key: 'purchase_usd', label: '매입액 (USD)', right: true },
  { key: 'share_pct', label: '구성비 (%)', right: true },
  { key: 'last_inv_date', label: '최종 거래일', center: true },
  { key: 'payment_term', label: '결제조건' },
];
const venSort = ref<{ key: VenSortKey; dir: 1 | -1 }>({ key: 'purchase_usd', dir: -1 });
function venSortBy(key: VenSortKey) {
  if (venSort.value.key === key) venSort.value.dir = venSort.value.dir === 1 ? -1 : 1;
  else venSort.value = { key, dir: key === 'vendor_code' || key === 'vendor_name' ? 1 : -1 };
  venPage.value = 1;
}
function venSortVal(v: VendorRow, key: VenSortKey): string | number {
  if (key === '_status') return v.months_since_last ?? 9999;   // 거래없음은 맨 뒤
  if (key === '_grade') return v.share_pct;
  const raw = v[key as keyof VendorRow];
  return typeof raw === 'number' ? raw : String(raw ?? '');
}
const venSorted = computed(() => {
  const { key, dir } = venSort.value;
  return [...venFiltered.value].sort((a, b) => {
    const av = venSortVal(a, key), bv = venSortVal(b, key);
    if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
    return String(av).localeCompare(String(bv), 'ko', { numeric: true }) * dir;
  });
});
const VEN_PAGE = 20;
const venPage = ref(1);
const venTotalPages = computed(() => Math.max(1, Math.ceil(venFiltered.value.length / VEN_PAGE)));
const venPaged = computed(() => venSorted.value.slice((venPage.value - 1) * VEN_PAGE, venPage.value * VEN_PAGE));
watch([venQuery, venSourcing], () => { venPage.value = 1; });
const venPageWindow = computed(() => {
  const t = venTotalPages.value;
  const from = Math.max(1, Math.min(venPage.value - 3, t - 6));
  const to = Math.min(t, from + 6);
  const out: number[] = [];
  for (let i = from; i <= to; i++) out.push(i);
  return out;
});
// 취소율 — 취소액 ÷ 매입액. 파생값이라 화면에서만 계산한다.
const venCxlPct = (v: VendorRow) => (v.purchase_usd ? (v.cxl_usd / v.purchase_usd) * 100 : null);
const venSourcingLabel = (s: VendorRow['sourcing']) =>
  s === 'LOCAL' ? '로컬 (Lokal)' : s === 'IMPORT' ? '해외 (Impor)' : '미확인';

// ── 거래 현황(구매/판매) — SAP 거래이력 집계 뷰 ───────────────────────────────
// 구매·판매가 구조가 같아 한 벌로 처리한다. 거래처 축만 벤더/고객으로 갈린다.
// 금액은 할인 후 기준이며, 취소·크레딧메모가 음수로 반영된 순(net) 값이다.
type TradeSide = 'purchase' | 'sales';
type TradeDim = 'period' | 'partner' | 'item' | 'sku';
const TRADE_DIMS: { key: TradeDim; label: (s: TradeSide) => string }[] = [
  { key: 'period',  label: () => '기간별' },
  { key: 'partner', label: s => (s === 'sales' ? '고객별' : '벤더별') },
  { key: 'item',    label: () => '아이템별' },
  { key: 'sku',     label: () => 'SKU별' },
];
interface TradeMonthRow { year_month: string; doc_cnt: number; partner_cnt: number; qty: number; amount_idr: number; amount_usd: number | null }
interface TradePartnerRow { year_month: string; partner_id: number; partner_name: string; customer_code?: string | null; vendor_code?: string | null; doc_cnt: number; qty: number; amount_idr: number; amount_usd: number | null }
interface TradeSkuRow { year_month: string; sku: string; description: string; brand: string | null; item: string; doc_cnt: number; qty: number; amount_idr: number; amount_usd: number | null }

const tradeDim = ref<TradeDim>('period');
const tradeQuery = ref('');
const tradeMonths = ref<TradeMonthRow[]>([]);
const tradePartners = ref<TradePartnerRow[]>([]);
const tradeSkus = ref<TradeSkuRow[]>([]);
/** 상세 모달은 구매·판매 양쪽 SKU 뷰를 함께 쓰므로 side 별로 캐시해 둔다. */
const skuCache = ref<Partial<Record<TradeSide, TradeSkuRow[]>>>({});
const tradeLoading = ref(false);
const tradeError = ref<string | null>(null);
const tradeLoadedSide = ref<TradeSide | ''>('');

// 기간 — 뷰가 월 단위라 시작/종료 월로 자른다. 기본은 최근 12개월.
const tradeFrom = ref('');
const tradeTo = ref('');
const tradeMonthOptions = computed(() => [...new Set(tradeMonths.value.map(m => m.year_month))].sort());
const TRADE_PRESETS = [
  { key: '12', label: '최근 12개월' },
  { key: '24', label: '최근 24개월' },
  { key: 'ytd', label: '올해' },
  { key: 'all', label: '전체' },
] as const;
function applyTradePreset(key: (typeof TRADE_PRESETS)[number]['key']) {
  const all = tradeMonthOptions.value;
  if (!all.length) return;
  const last = all[all.length - 1];
  if (key === 'all') { tradeFrom.value = all[0]; tradeTo.value = last; return; }
  if (key === 'ytd') { tradeFrom.value = `${last.slice(0, 4)}-01`; tradeTo.value = last; return; }
  const n = Number(key);
  tradeFrom.value = all[Math.max(0, all.length - n)];
  tradeTo.value = last;
}

const tradeSide = computed<TradeSide>(() => (section.value === 'sales' ? 'sales' : 'purchase'));
function retryTrade() { tradeLoadedSide.value = ''; tradeError.value = null; void loadTrade(); }
async function loadTrade() {
  const side = tradeSide.value;
  if (tradeLoadedSide.value === side) return;
  tradeLoading.value = true; tradeError.value = null;
  const base = side === 'sales' ? 'v_db_sales' : 'v_db_purchases';
  const partnerView = side === 'sales' ? 'v_db_sales_by_customer' : 'v_db_purchases_by_vendor';
  const codeCol = side === 'sales' ? 'customer_code' : 'vendor_code';
  try {
    const [m, p, s] = await Promise.all([
      sbGetAll<TradeMonthRow>(`${base}_monthly?select=*&order=year_month.asc`),
      sbGetAll<TradePartnerRow>(`${partnerView}?select=year_month,partner_id,partner_name,${codeCol},doc_cnt,qty,amount_idr,amount_usd`),
      sbGetAll<TradeSkuRow>(`${base}_by_sku?select=year_month,sku,description,brand,item,doc_cnt,qty,amount_idr,amount_usd`),
    ]);
    const n = (v: unknown) => Number(v ?? 0);
    tradeMonths.value = m.map(r => ({ ...r, doc_cnt: n(r.doc_cnt), partner_cnt: n(r.partner_cnt), qty: n(r.qty), amount_idr: n(r.amount_idr), amount_usd: r.amount_usd == null ? null : n(r.amount_usd) }));
    tradePartners.value = p.map(r => ({ ...r, doc_cnt: n(r.doc_cnt), qty: n(r.qty), amount_idr: n(r.amount_idr), amount_usd: r.amount_usd == null ? null : n(r.amount_usd) }));
    tradeSkus.value = s.map(r => ({ ...r, doc_cnt: n(r.doc_cnt), qty: n(r.qty), amount_idr: n(r.amount_idr), amount_usd: r.amount_usd == null ? null : n(r.amount_usd) }));
    skuCache.value = { ...skuCache.value, [side]: tradeSkus.value };  // 상세 모달이 양쪽 축을 함께 쓴다
    tradeLoadedSide.value = side;
    applyTradePreset('12');
  } catch (e) {
    tradeMonths.value = []; tradePartners.value = []; tradeSkus.value = [];
    tradeError.value = errMsg(e);
  }
  tradeLoading.value = false;
}
watch(section, s => {
  if (s === 'purchase' || s === 'sales') {
    if (tradeLoadedSide.value && tradeLoadedSide.value !== (s === 'sales' ? 'sales' : 'purchase')) tradeLoadedSide.value = '';
    tradeDim.value = 'period'; tradeQuery.value = ''; tradeDetail.value = null;
    void loadTrade();
  }
});

const inTradeRange = (ym: string) =>
  (!tradeFrom.value || ym >= tradeFrom.value) && (!tradeTo.value || ym <= tradeTo.value);

/** 화면 표 공통 행 — 축에 따라 라벨/보조라벨만 달라진다. */
interface TradeRow { key: string; label: string; sub: string; docCnt: number; qty: number; idr: number; usd: number | null }
const tradeRows = computed<TradeRow[]>(() => {
  const q = tradeQuery.value.trim().toLowerCase();
  const agg = new Map<string, TradeRow>();
  const add = (key: string, label: string, sub: string, r: { doc_cnt: number; qty: number; amount_idr: number; amount_usd: number | null }) => {
    const cur = agg.get(key) ?? { key, label, sub, docCnt: 0, qty: 0, idr: 0, usd: 0 };
    cur.docCnt += r.doc_cnt; cur.qty += r.qty; cur.idr += r.amount_idr;
    cur.usd = (cur.usd ?? 0) + (r.amount_usd ?? 0);
    agg.set(key, cur);
  };
  if (tradeDim.value === 'period') {
    for (const m of tradeMonths.value) {
      if (!inTradeRange(m.year_month)) continue;
      add(m.year_month, m.year_month, `거래처 ${m.partner_cnt.toLocaleString()}곳`, m);
    }
    return [...agg.values()].sort((a, b) => b.key.localeCompare(a.key));
  }
  if (tradeDim.value === 'partner') {
    for (const p of tradePartners.value) {
      if (!inTradeRange(p.year_month)) continue;
      const code = p.customer_code ?? p.vendor_code ?? '';
      if (q && !`${p.partner_name} ${code}`.toLowerCase().includes(q)) continue;
      add(String(p.partner_id), p.partner_name, code, p);
    }
  } else if (tradeDim.value === 'item') {
    for (const s of tradeSkus.value) {
      if (!inTradeRange(s.year_month)) continue;
      if (q && !s.item.toLowerCase().includes(q)) continue;
      add(s.item, s.item, '', s);
    }
  } else {
    for (const s of tradeSkus.value) {
      if (!inTradeRange(s.year_month)) continue;
      if (q && !`${s.sku} ${s.description} ${s.brand ?? ''}`.toLowerCase().includes(q)) continue;
      add(s.sku, s.description, `${s.sku}${s.brand ? ` · ${s.brand}` : ''}`, s);
    }
  }
  return [...agg.values()].sort((a, b) => b.idr - a.idr);
});
const tradeTotal = computed(() => tradeRows.value.reduce(
  (a, r) => ({ docCnt: a.docCnt + r.docCnt, qty: a.qty + r.qty, idr: a.idr + r.idr, usd: a.usd + (r.usd ?? 0) }),
  { docCnt: 0, qty: 0, idr: 0, usd: 0 },
));
const tradeUnitLabel = computed(() => (tradeSide.value === 'sales' ? '매출' : '매입'));
// 기간별 축은 문서 건수 합이 의미 있지만, 다른 축은 같은 문서가 여러 행에 걸쳐 중복 집계된다.
const tradeDocCntMeaningful = computed(() => tradeDim.value === 'period');

const TRADE_PAGE = 20;
const tradePage = ref(1);
const tradeTotalPages = computed(() => Math.max(1, Math.ceil(tradeRows.value.length / TRADE_PAGE)));
const tradePaged = computed(() => tradeRows.value.slice((tradePage.value - 1) * TRADE_PAGE, tradePage.value * TRADE_PAGE));
watch([tradeDim, tradeQuery, tradeFrom, tradeTo], () => { tradePage.value = 1; });
const tradePageWindow = computed(() => {
  const t = tradeTotalPages.value;
  const from = Math.max(1, Math.min(tradePage.value - 3, t - 6));
  const to = Math.min(t, from + 6);
  const out: number[] = [];
  for (let i = from; i <= to; i++) out.push(i);
  return out;
});

// ── 아이템·SKU 상세 모달 — 한 품목의 구매(A/P)·판매(A/R) 월별 내역 ───────────
// 표에서 아이템/SKU 행을 클릭하면 연다. 화면 표는 현재 탭 한쪽만 쓰지만, 모달은 반대편
// SKU 뷰까지 받아 캐시해 구매·판매를 나란히 보여준다. 기간 필터와 무관하게 전체 이력.
interface TradeDetailTarget { dim: 'item' | 'sku'; key: string; title: string; sub: string }
const tradeDetail = ref<TradeDetailTarget | null>(null);
const tradeDetailLoading = ref(false);
const tradeDetailError = ref(false);
/** 아이템/SKU 축에서만 상세가 의미 있다(기간·거래처 축은 품목 이력이 아니다). */
const tradeRowClickable = computed(() => tradeDim.value === 'item' || tradeDim.value === 'sku');

async function openTradeDetail(r: TradeRow) {
  if (!tradeRowClickable.value) return;
  tradeDetail.value = { dim: tradeDim.value as 'item' | 'sku', key: r.key, title: r.label, sub: r.sub };
  const other: TradeSide = tradeSide.value === 'sales' ? 'purchase' : 'sales';
  if (skuCache.value[other]) return;
  tradeDetailLoading.value = true; tradeDetailError.value = false;
  try {
    const base = other === 'sales' ? 'v_db_sales' : 'v_db_purchases';
    const rows = await sbGetAll<TradeSkuRow>(`${base}_by_sku?select=year_month,sku,description,brand,item,doc_cnt,qty,amount_idr,amount_usd`);
    const n = (v: unknown) => Number(v ?? 0);
    skuCache.value = {
      ...skuCache.value,
      [other]: rows.map(x => ({ ...x, doc_cnt: n(x.doc_cnt), qty: n(x.qty), amount_idr: n(x.amount_idr), amount_usd: x.amount_usd == null ? null : n(x.amount_usd) })),
    };
  } catch {
    tradeDetailError.value = true;  // 캐시에 넣지 않는다 → 다음에 열 때 재시도
  }
  tradeDetailLoading.value = false;
}

interface TradeDetailMonth { ym: string; buyQty: number; buyIdr: number; sellQty: number; sellIdr: number }
const tradeDetailRows = computed<TradeDetailMonth[]>(() => {
  const t = tradeDetail.value;
  if (!t) return [];
  const agg = new Map<string, TradeDetailMonth>();
  const collect = (rows: TradeSkuRow[] | undefined, side: TradeSide) => {
    for (const s of rows ?? []) {
      if ((t.dim === 'sku' ? s.sku : s.item) !== t.key) continue;
      const cur = agg.get(s.year_month) ?? { ym: s.year_month, buyQty: 0, buyIdr: 0, sellQty: 0, sellIdr: 0 };
      if (side === 'purchase') { cur.buyQty += s.qty; cur.buyIdr += s.amount_idr; }
      else { cur.sellQty += s.qty; cur.sellIdr += s.amount_idr; }
      agg.set(s.year_month, cur);
    }
  };
  collect(skuCache.value.purchase, 'purchase');
  collect(skuCache.value.sales, 'sales');
  return [...agg.values()].sort((a, b) => b.ym.localeCompare(a.ym));
});
const tradeDetailTotal = computed(() => tradeDetailRows.value.reduce(
  (a, r) => ({ buyQty: a.buyQty + r.buyQty, buyIdr: a.buyIdr + r.buyIdr, sellQty: a.sellQty + r.sellQty, sellIdr: a.sellIdr + r.sellIdr }),
  { buyQty: 0, buyIdr: 0, sellQty: 0, sellIdr: 0 },
));
/** 최근 거래월 — 수량·금액이 0 인 달은 실적으로 보지 않는다. */
const tradeDetailLast = (side: 'buy' | 'sell') =>
  tradeDetailRows.value.find(r => (side === 'buy' ? r.buyQty || r.buyIdr : r.sellQty || r.sellIdr))?.ym ?? '—';
const unitIdr = (idr: number, qty: number) => (qty > 0 ? idr / qty : null);

// ── 엑셀(CSV) 다운로드 ────────────────────────────────────────────────────────
const today = () => new Date().toISOString().slice(0, 10);
function downloadPrice() {
  // 헤더 2개 국어: 1행 영문 · 2행 한글. 가격 4열은 화면과 같은 부가세 기준(vatMode)으로 내보낸다.
  const vEn = vatMode.value === 'incl' ? 'incl. VAT' : 'excl. VAT';
  const vKo = vatLabel.value;
  const headEn = ['Item', 'Product', 'Brand', 'SKU', 'Unit', 'FOB', 'Weight(kg)', '40ft(Qty)', `Purchase Price(pcs, ${vEn})`, 'Basis', `Purchase Price(set, ${vEn})`, `Dealer Price(pcs, ${vEn})`, `Dealer Price(set, ${vEn})`, 'Review'];
  const headKo = ['아이템', '제품', '브랜드', 'SKU', '단위', 'FOB', '중량(kg)', '40ft(Qty)', `입고가(pcs, ${vKo})`, '입고가 기준', `입고가(set, ${vKo})`, `대리점가(pcs, ${vKo})`, `대리점가(set, ${vKo})`, '확인 필요'];
  const rows = filtered.value.map(p => [
    catOf(p), p.description ?? '', p.brand ?? '', p.sku ?? '', p.unit ?? '',
    p.fob ?? '', p.weight_kg ?? '', p.qty_40ft ?? '',
    vat(p.wh_price_pcs, 'excl') ?? '', p.wh_price_basis ?? '', vat(p.wh_price_set, 'excl') ?? '',
    vat(p.dist_price_pcs, 'incl') ?? '', vat(p.dist_price_set, 'incl') ?? '',
    p.review_note ?? '',
  ]);
  exportCsv(`제품_가격_${vatMode.value === 'incl' ? 'VAT포함' : 'VAT별도'}_${today()}`, headEn, [headKo, ...rows]);
}
function downloadSpec() {
  const cols = specCols.value;
  const headers = ['아이템', '제품', 'Brand', 'SKU', ...cols.map(colHead)];
  const rows = specFiltered.value.map(r => [
    r._cat ?? '', r._title ?? '', r.brand ?? '', r.sku ?? '',
    ...cols.map(c => r[c.key] ?? ''),
  ]);
  exportCsv(`스펙_${specDef.value.label}_${today()}`, headers, rows);
}
function downloadCustomers() {
  // SAP 매출은 화면의 단위 표기(juta 등) 대신 원값(IDR)으로 내보낸다.
  const headers = ['코드', '고객명', 'Acquirer', 'Main PIC', 'Assist1', 'Assist2', '상태', '판매실적(SAP, IDR)', '청구건수(SAP)', '최근청구일(SAP)'];
  const rows = custFiltered.value.map(c => [
    c.customer_code, c.customer_name, c.acquirer_name ?? '', c.main_pic_name ?? '',
    c.assist1_name ?? '', c.assist2_name ?? '', c.is_active ? '활성' : '비활성',
    Math.round(c.sap_sales_idr ?? 0), c.sap_invoice_cnt ?? 0, c.sap_last_invoice ?? '',
  ]);
  exportCsv(`고객_${today()}`, headers, rows);
}
function downloadVendors() {
  // 금액은 표기 단위 없이 원값으로 내보낸다(USD·IDR 각각). 파생 열(상태·ABC·취소율)도 함께.
  const headers = [
    '코드', '벤더명', '소싱', '국가', '상태', 'ABC', '주요브랜드', '주요품목',
    '인보이스', '라인수', '수량(EA)', '매입액(USD)', '매입액(IDR)', '구성비(%)',
    '최초거래일', '최종거래일', '취소라인', '취소액(USD)', '취소율(%)',
    '결제조건', 'Incoterms', '결제통화', '담당자', '연락처', '이메일', 'NPWP', '자사담당', '상태(활성)',
  ];
  const rows = venFiltered.value.map(v => [
    v.vendor_code, v.vendor_name, venSourcingLabel(v.sourcing), v.country ?? '미확인',
    venStatusOf(v), venGradeOf(v), v.top_brand ?? '', v.top_category ?? '',
    v.ap_invoice_cnt, v.ap_line_cnt, v.qty_total,
    v.purchase_usd, Math.round(v.purchase_idr), v.share_pct.toFixed(1),
    v.first_inv_date ?? '', v.last_inv_date ?? '',
    v.cxl_line_cnt, v.cxl_usd, venCxlPct(v)?.toFixed(1) ?? '',
    v.payment_term ?? '', v.incoterms ?? '', v.settle_currency ?? '',
    v.contact_person ?? '', v.contact_phone ?? '', v.contact_email ?? '',
    v.npwp ?? '', v.pic_name ?? '', v.is_active ? '활성' : '비활성',
  ]);
  exportCsv(`벤더_${today()}`, headers, rows);
}
/** 엑셀 2번째 시트 — 요약 행을 연월 단위로 펼친 상세. 필터·검색·정렬 순서는 화면과 같다. */
function tradeMonthlyDetail(): Cell[][] {
  const rank = new Map(tradeRows.value.map((r, i) => [r.key, i]));
  interface D { rank: number; label: string; sub: string; ym: string; qty: number; idr: number; usd: number }
  const agg = new Map<string, D>();
  const add = (key: string, label: string, sub: string, ym: string, r: { qty: number; amount_idr: number; amount_usd: number | null }) => {
    const rk = rank.get(key);
    if (rk === undefined) return;  // 검색어에서 빠진 항목
    const k = `${key}|${ym}`;
    const cur = agg.get(k) ?? { rank: rk, label, sub, ym, qty: 0, idr: 0, usd: 0 };
    cur.qty += r.qty; cur.idr += r.amount_idr; cur.usd += r.amount_usd ?? 0;
    agg.set(k, cur);
  };
  if (tradeDim.value === 'partner') {
    for (const p of tradePartners.value) {
      if (!inTradeRange(p.year_month)) continue;
      add(String(p.partner_id), p.partner_name, p.customer_code ?? p.vendor_code ?? '', p.year_month, p);
    }
  } else if (tradeDim.value === 'item') {
    for (const s of tradeSkus.value) {
      if (!inTradeRange(s.year_month)) continue;
      add(s.item, s.item, '', s.year_month, s);
    }
  } else {
    for (const s of tradeSkus.value) {
      if (!inTradeRange(s.year_month)) continue;
      add(s.sku, s.description, `${s.sku}${s.brand ? ` · ${s.brand}` : ''}`, s.year_month, s);
    }
  }
  return [...agg.values()]
    .sort((a, b) => a.rank - b.rank || a.ym.localeCompare(b.ym))  // 요약 순서 유지 + 각 항목 안에서는 오래된 달부터
    .map(d => [d.label, d.sub, d.ym, d.qty, Math.round(d.idr), d.usd ? Math.round(d.usd) : '']);
}
function downloadTrade() {
  // 시트 2개: ① 요약(화면 표 그대로) ② 연월별 상세. 기간별 축은 요약이 이미 월 단위라 상세 시트가 없다.
  const dimKo = TRADE_DIMS.find(d => d.key === tradeDim.value)!.label(tradeSide.value);
  const sideKo = tradeSide.value === 'sales' ? '판매' : '구매';
  const unit = tradeUnitLabel.value;
  const sheets: SheetSpec[] = [{
    name: `요약_${dimKo}`,
    headers: ['구분', '코드·부가정보', '건수', '수량(EA)', `${unit}(IDR)`, `${unit}(USD)`],
    rows: tradeRows.value.map(r => [
      r.label, r.sub, tradeDocCntMeaningful.value ? r.docCnt : '', r.qty,
      Math.round(r.idr), r.usd == null ? '' : Math.round(r.usd),
    ]),
  }];
  if (tradeDim.value !== 'period') {
    sheets.push({
      name: '상세_연월별',
      headers: ['구분', '코드·부가정보', '연월', '수량(EA)', `${unit}(IDR)`, `${unit}(USD)`],
      rows: tradeMonthlyDetail(),
    });
  }
  exportXlsxSheets(`${sideKo}현황_${dimKo}_${tradeFrom.value}~${tradeTo.value}`, sheets);
}

// ── URL 쿼리 동기화 (탭 · 검색어 · 필터 · 정렬 · 페이지) ──────────────────────
// 지금 보고 있는 화면 상태를 주소에 싣는다(?tab=&sub=&q=&cat=&sort=&dir=&page=).
//   → 새로고침·뒤로가기에서 그대로 복원되고, 필터·정렬이 걸린 화면을 링크로 공유할 수 있다.
// 섹션마다 상태 ref 가 따로 있어 '활성 섹션의 ref' 만 골라 쓰고, 기본값과 같으면 쿼리에서 뺀다.
type SortState = { key: string; dir: 1 | -1 };
interface ViewSync {
  q?: Ref<string>;
  /** 드롭다운 필터 — all 은 '필터 없음' 기본값 */
  cat?: { ref: Ref<string>; all: string; values?: string[] };
  sort?: { ref: Ref<SortState>; keys: string[]; def: SortState };
  page?: Ref<number>;
}
function activeSync(): ViewSync {
  if (section.value === 'product') {
    if (productTab.value === 'price') {
      return {
        q: query, cat: { ref: category, all: '전체' }, page,
        sort: { ref: priceSort, keys: PRICE_COLS.value.map(c => c.key), def: { key: 'category', dir: 1 } },
      };
    }
    if (productTab.value === 'spec') {
      return {
        q: specQuery,
        sort: { ref: specSort, keys: specCols.value.map(c => c.key), def: { key: '_title', dir: 1 } },
      };
    }
    return {};   // 운송 탭은 필터가 없다
  }
  if (section.value === 'customer') {
    return {
      q: custQuery, page: custPage,
      sort: { ref: custSort as unknown as Ref<SortState>, keys: CUST_COLS.map(c => String(c.key)), def: { key: 'customer_code', dir: 1 } },
    };
  }
  if (section.value === 'vendor') {
    return {
      q: venQuery, page: venPage,
      cat: { ref: venSourcing as unknown as Ref<string>, all: '전체', values: ['전체', 'LOCAL', 'IMPORT'] },
      sort: { ref: venSort as unknown as Ref<SortState>, keys: VEN_COLS.map(c => String(c.key)), def: { key: 'purchase_usd', dir: -1 } },
    };
  }
  if (section.value === 'purchase' || section.value === 'sales') {
    return { q: tradeQuery, page: tradePage };
  }
  return {};   // 직원 탭은 별도 컴포넌트가 상태를 갖는다
}

function buildQuery(): Record<string, string> {
  const out: Record<string, string> = { tab: section.value };
  if (section.value === 'product') out.sub = productTab.value;
  const s = activeSync();
  const kw = s.q?.value.trim();
  if (kw) out.q = kw;
  if (s.cat && s.cat.ref.value !== s.cat.all) out.cat = s.cat.ref.value;
  if (s.sort) {
    const cur = s.sort.ref.value;
    if (cur.key !== s.sort.def.key || cur.dir !== s.sort.def.dir) {
      out.sort = cur.key;
      out.dir = cur.dir === 1 ? 'asc' : 'desc';
    }
  }
  if (s.page && s.page.value > 1) out.page = String(s.page.value);
  return out;
}

// 화면 상태 → URL (히스토리를 쌓지 않도록 replace)
watch(buildQuery, next => {
  const cur = route.query;
  const keys = new Set([...Object.keys(next), ...Object.keys(cur)]);
  for (const k of keys) if ((next[k] ?? '') !== (qs(cur[k]) ?? '')) { void router.replace({ query: next }); return; }
});

// URL → 화면 상태 (뒤로가기·공유 링크·새로고침)
function applyQuery(q: typeof route.query) {
  const tab = qs(q.tab);
  if (tab && (SECTION_KEYS as string[]).includes(tab) && tab !== section.value) section.value = tab as Section;
  const sub = qs(q.sub);
  if (sub && (PRODUCT_TAB_KEYS as string[]).includes(sub) && sub !== productTab.value) productTab.value = sub as ProductTab;

  const s = activeSync();   // 위에서 탭을 먼저 맞춘 뒤라야 올바른 섹션의 ref 가 잡힌다
  if (s.q) {
    const v = qs(q.q) ?? '';
    if (v !== s.q.value) s.q.value = v;
  }
  if (s.cat) {
    const v = qs(q.cat) ?? s.cat.all;
    if ((!s.cat.values || s.cat.values.includes(v)) && v !== s.cat.ref.value) s.cat.ref.value = v;
  }
  if (s.sort) {
    const k = qs(q.sort);
    const dir: 1 | -1 = qs(q.dir) === 'desc' ? -1 : 1;
    const next = k && (s.sort.keys.includes(k) || k === s.sort.def.key) ? { key: k, dir } : s.sort.def;
    const cur = s.sort.ref.value;
    if (next.key !== cur.key || next.dir !== cur.dir) s.sort.ref.value = { ...next };
  }
  if (s.page) {
    const n = Math.max(1, Number(qs(q.page) ?? 1) || 1);
    // 검색어·필터 변경 watch 가 page 를 1 로 되돌리므로, 그 뒤(다음 tick)에 페이지를 적용한다
    const pageRef = s.page;
    void nextTick(() => { if (pageRef.value !== n) pageRef.value = n; });
  }
}
watch(() => route.query, q => { if (route.name === 'databases') applyQuery(q); });
applyQuery(route.query);   // 첫 진입 — 주소에 담긴 상태 복원
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">
    <!-- 1차 카테고리 탭 + 설명 (1행)
         모바일에서 라벨이 글자 단위로 세로 줄바꿈("제/품")되던 문제 → 가로 스크롤 + nowrap -->
    <div class="flex items-center gap-2 border-b border-border overflow-x-auto">
      <button
        v-for="s in SECTIONS" :key="s.key"
        :class="['inline-flex shrink-0 whitespace-nowrap items-center gap-1.5 px-4 py-2 text-sm font-semibold border-b-2 -mb-px transition-colors',
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
          <!-- 아이템 드롭다운 좌측 배치(스펙 탭과 동일 위치·스타일) -->
          <div class="inline-flex items-center gap-1.5 bg-card rounded-lg border border-border pl-3 pr-1 ml-2 focus-within:ring-1 focus-within:ring-primary">
            <span class="text-[11px] font-semibold text-muted-foreground shrink-0">아이템</span>
            <select v-model="category" class="text-xs font-semibold bg-transparent text-foreground py-2 pr-6 focus:outline-none cursor-pointer">
              <option v-for="c in categories" :key="c" :value="c">{{ c }}</option>
            </select>
          </div>
          <p class="text-[11px] text-muted-foreground">
            총 {{ filtered.length.toLocaleString() }}개<span v-if="query || category !== '전체'"> / 전체 {{ rows.length.toLocaleString() }}개</span>
            · FOB/중량(kg)는 확장 컬럼(미입력 시 —) · 입고가·대리점가는 <b>{{ vatLabel }}</b> 기준 표기(PPN 11%)
            <span v-if="reviewCount"> · <span class="rounded border border-rose-300 bg-rose-50 px-1 py-px text-[10px] font-medium text-rose-700">확인</span> {{ reviewCount }}건 — 출처 상충·급변 값(뱃지에 마우스를 올리면 사유)</span>
          </p>
          <div class="flex flex-wrap items-center gap-2 w-full sm:w-auto sm:ml-auto">
            <div class="relative flex-1 min-w-40 sm:flex-none">
              <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input v-model="query" type="text" placeholder="제품·브랜드·SKU 검색…"
                class="w-full sm:w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary" />
            </div>
            <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadPrice">
              <Download :size="14" /> 엑셀
            </button>
            <!-- 부가세 표기 기준 토글(우측 끝) — 입고가·대리점가 4개 열에 일괄 적용(저장값은 불변) -->
            <div class="inline-flex items-center gap-1 rounded-lg border border-border bg-card p-0.5">
              <button
                v-for="m in VAT_MODES" :key="m.key"
                :class="['px-2.5 py-1.5 rounded-md text-[11px] font-semibold transition-colors',
                  vatMode === m.key ? 'bg-primary/15 text-primary' : 'text-muted-foreground hover:bg-accent']"
                :title="`입고가·대리점가를 ${m.label} 기준으로 표기 (PPN 11%)`"
                @click="vatMode = m.key"
              >{{ m.label }}</button>
            </div>
          </div>
        </template>
        <!-- 스펙: 카테고리 드롭다운 + 검색 (같은 행) -->
        <template v-else-if="productTab === 'spec'">
          <div class="inline-flex items-center gap-1.5 bg-card rounded-lg border border-border pl-3 pr-1 ml-2 focus-within:ring-1 focus-within:ring-primary">
            <span class="text-[11px] font-semibold text-muted-foreground shrink-0">아이템</span>
            <select v-model="specTab" class="text-xs font-semibold bg-transparent text-foreground py-2 pr-6 focus:outline-none cursor-pointer">
              <option v-for="d in SPEC_DEFS" :key="d.key" :value="d.key">{{ d.label }}</option>
            </select>
          </div>
          <div v-if="productTab === 'spec'" class="flex flex-wrap items-center gap-2 w-full sm:w-auto sm:ml-auto">
            <div class="relative flex-1 min-w-40 sm:flex-none">
              <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input v-model="specQuery" type="text" placeholder="패턴·규격·SKU 검색…"
                class="w-full sm:w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary" />
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
              <caption class="sr-only">제품 가격 목록</caption>
              <thead>
                <tr class="border-b border-border bg-muted/20 text-xs text-muted-foreground">
                  <th scope="col" class="w-12 text-center font-semibold px-3 py-2.5 align-top">No.</th>
                  <th scope="col" v-for="col in PRICE_COLS" :key="col.key" class="font-semibold px-3 py-2.5 align-top cursor-pointer select-none hover:text-foreground" :class="col.right ? 'text-right' : 'text-left'" @click="priceSortBy(col.key)">
                    <span class="inline-flex items-start gap-1" :class="col.right && 'flex-row-reverse'">
                      <span class="inline-flex flex-col leading-tight" :class="col.right ? 'items-end' : 'items-start'">
                        <span>{{ col.label }}</span>
                        <span v-if="col.sub" class="text-[10px] font-normal opacity-70">{{ col.sub }}</span>
                      </span>
                      <span class="text-[9px] w-2" :class="priceSort.key === col.key ? 'text-primary' : 'text-muted-foreground/30'">{{ priceSort.key === col.key ? (priceSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <TableState
                  v-if="loading || loadError || !paged.length"
                  :colspan="11" :loading="loading" :error="loadError" :skeleton-rows="8"
                  :empty-text="query || category !== '전체' ? '검색 결과가 없습니다.' : '제품이 없습니다.'"
                  @retry="load"
                />
                <!-- 행 클릭 → 그 제품의 제원(스펙) 모달 -->
                <tr
                  v-for="(p, i) in paged" v-else :key="p.id"
                  class="border-b border-border/50 last:border-b-0 hover:bg-accent/40 transition-colors cursor-pointer"
                  @click="openSpecModal(p)"
                >
                  <td class="text-center text-muted-foreground tabular-nums px-3 py-2.5">{{ (page - 1) * PAGE_SIZE + i + 1 }}</td>
                  <td class="px-3 py-2.5"><span class="inline-block px-1.5 py-0.5 rounded bg-muted text-[11px] text-foreground/80">{{ catOf(p) }}</span></td>
                  <td class="px-3 py-2.5">
                    <div class="flex items-center gap-2 min-w-0">
                      <Package :size="14" class="text-primary shrink-0" />
                      <div class="min-w-0">
                        <div class="font-medium text-foreground">{{ txt(p.description) }}</div>
                        <div class="text-[11px] text-muted-foreground">{{ txt(p.brand) }}<span v-if="p.sku"> · {{ p.sku }}</span><span v-if="p.unit"> · {{ p.unit }}</span></div>
                      </div>
                    </div>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">
                    <span class="inline-flex items-center justify-end gap-1.5">
                      <span v-if="needsReview(p, 'fob')" :title="p.review_note ?? ''" class="rounded border border-rose-300 bg-rose-50 px-1 py-px text-[10px] font-medium leading-none text-rose-700 cursor-help">확인</span>
                      {{ fmtFob(p.fob) }}
                    </span>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">
                    <span class="inline-flex items-center justify-end gap-1.5">
                      <!-- 출처(제원표/가격표) 값이 상충하는 중량은 「확인」 뱃지로 표기 -->
                      <span v-if="needsReview(p, 'weight_kg')" :title="p.review_note ?? ''" class="rounded border border-rose-300 bg-rose-50 px-1 py-px text-[10px] font-medium leading-none text-rose-700 cursor-help">확인</span>
                      {{ fmtWeight(p.weight_kg) }}
                    </span>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">
                    <span class="inline-flex items-center justify-end gap-1.5">
                      <span v-if="needsReview(p, 'qty_40ft')" :title="p.review_note ?? ''" class="rounded border border-rose-300 bg-rose-50 px-1 py-px text-[10px] font-medium leading-none text-rose-700 cursor-help">확인</span>
                      {{ fmt(p.qty_40ft) }}
                    </span>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">
                    <span class="inline-flex items-center justify-end gap-1.5">
                      <!-- 입고가 기준은 API-P. API-U 로 채운 품목만 뱃지로 구분 표기 -->
                      <span v-if="p.wh_price_basis === 'API-U'"
                            class="rounded border border-amber-300 bg-amber-50 px-1 py-px text-[10px] font-medium leading-none text-amber-700">API-U</span>
                      <span v-if="needsReview(p, 'wh_price_pcs')" :title="p.review_note ?? ''" class="rounded border border-rose-300 bg-rose-50 px-1 py-px text-[10px] font-medium leading-none text-rose-700 cursor-help">확인</span>
                      {{ fmt(vat(p.wh_price_pcs, 'excl')) }}
                    </span>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">
                    <span class="inline-flex items-center justify-end gap-1.5">
                      <span v-if="needsReview(p, 'wh_price_set')" :title="p.review_note ?? ''" class="rounded border border-rose-300 bg-rose-50 px-1 py-px text-[10px] font-medium leading-none text-rose-700 cursor-help">확인</span>
                      {{ fmt(vat(p.wh_price_set, 'excl')) }}
                    </span>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums font-medium">{{ fmt(vat(p.dist_price_pcs, 'incl')) }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{{ fmt(vat(p.dist_price_set, 'incl')) }}</td>
                  <!-- SAP A/R 누적 판매량(취소·반품 반영 순수량). 최근 판매일은 tooltip -->
                  <td class="px-3 py-2.5 text-right tabular-nums" :title="p.sap_last_sold ? `최근 판매 ${p.sap_last_sold}` : ''">
                    <span :class="p.sap_sold_qty ? 'text-foreground' : 'text-muted-foreground'">{{ p.sap_sold_qty ? fmt(p.sap_sold_qty) : '—' }}</span>
                  </td>
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

      <!-- 스펙: 제품(products) 기준 조회 · 제원은 sku 매칭으로 채움 (칩/검색은 상단 탭 행에 통합) -->
      <template v-else-if="productTab === 'spec'">
        <div class="rounded-xl border border-border bg-card overflow-hidden">
          <DataState
          v-if="specLoading || specError"
          :loading="specLoading" :error="specError" skeleton-class="h-64 m-3"
          @retry="retrySpecTable"
        />
          <div v-else class="overflow-x-auto">
            <table class="w-full text-sm whitespace-nowrap">
              <caption class="sr-only">제품 제원(스펙) 목록</caption>
              <thead>
                <!-- 가격 탭과 동일한 헤더(muted). No·아이템·제품 3개 고정 + 이후 제원 컬럼 -->
                <!-- 헤더는 1행 고정(2단 그룹 헤더 폐지) — 묶음은 라벨 접두사, 단위는 sub 로 표기 -->
                <tr class="border-b border-border bg-muted/20 text-xs text-muted-foreground">
                  <th scope="col" class="w-12 text-center font-semibold px-3 py-2.5 align-top">No.</th>
                  <th scope="col" class="font-semibold px-3 py-2.5 text-left align-top cursor-pointer select-none hover:text-foreground" @click="specSortBy('_cat')">
                    <span class="inline-flex items-center gap-1">아이템
                      <span class="text-[9px] w-2" :class="specSort.key === '_cat' ? 'text-primary' : 'text-muted-foreground/30'">{{ specSort.key === '_cat' ? (specSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                    </span>
                  </th>
                  <th scope="col" class="font-semibold px-3 py-2.5 text-left align-top cursor-pointer select-none hover:text-foreground" @click="specSortBy('_title')">
                    <span class="inline-flex items-center gap-1">제품
                      <span class="text-[9px] w-2" :class="specSort.key === '_title' ? 'text-primary' : 'text-muted-foreground/30'">{{ specSort.key === '_title' ? (specSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                    </span>
                  </th>
                  <th scope="col" v-for="c in specCols" :key="c.key" class="font-semibold px-3 py-2.5 align-top cursor-pointer select-none hover:text-foreground"
                      :class="c.num ? 'text-right' : 'text-left'" @click="specSortBy(c.key)">
                    <span class="inline-flex items-start gap-1" :class="c.num && 'flex-row-reverse'">
                      <span class="inline-flex flex-col leading-tight" :class="c.num ? 'items-end' : 'items-start'">
                        <span>{{ c.label }}</span>
                        <span v-if="c.sub" class="text-[10px] font-normal opacity-70">{{ c.sub }}</span>
                      </span>
                      <span class="text-[9px] w-2" :class="specSort.key === c.key ? 'text-primary' : 'text-muted-foreground/30'">{{ specSort.key === c.key ? (specSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <!-- 매칭된 카탈로그 출처는 행 hover 툴팁으로 표시 -->
                <!-- 행 클릭 → 그 제품의 가격 모달 -->
                <tr v-for="(r, i) in specSorted" :key="String(r.id)" class="border-b border-border/50 last:border-b-0 hover:bg-accent/40 transition-colors cursor-pointer"
                    :title="r._source ? `카탈로그 출처: ${r._source}` : ''" @click="openPriceModal(r)">
                  <td class="text-center text-muted-foreground tabular-nums px-3 py-2.5">{{ i + 1 }}</td>
                  <td class="px-3 py-2.5"><span class="inline-block px-1.5 py-0.5 rounded bg-muted text-[11px] text-foreground/80">{{ r._cat }}</span></td>
                  <td class="px-3 py-2.5">
                    <div class="flex items-center gap-2 min-w-0">
                      <Package :size="14" class="text-primary shrink-0" />
                      <div class="min-w-0">
                        <div class="font-medium text-foreground">{{ txt(r._title as string | null) }}</div>
                        <div class="text-[11px] text-muted-foreground">{{ txt(r.brand as string | null) }}<span v-if="r.sku"> · {{ r.sku }}</span><span v-if="r._unit"> · {{ r._unit }}</span></div>
                      </div>
                    </div>
                  </td>
                  <td v-for="c in specCols" :key="c.key" class="px-3 py-2.5" :class="c.num ? 'text-right tabular-nums' : 'text-left'">
                    <span class="inline-flex items-center gap-1.5" :class="c.num && 'justify-end'">
                      <!-- 가격 탭과 동일 기준의 「확인」 뱃지(예: 제원표↔가격표 중량 상충) -->
                      <span v-if="needsReview({ review_field: r._reviewField as string | null, review_note: r._reviewNote as string | null }, c.key)"
                            :title="(r._reviewNote as string | null) ?? ''"
                            class="rounded border border-rose-300 bg-rose-50 px-1 py-px text-[10px] font-medium leading-none text-rose-700 cursor-help">확인</span>
                      {{ fmtSpec(c, r[c.key]) }}
                    </span>
                  </td>
                </tr>
                <tr v-if="!specSorted.length"><td :colspan="specCols.length + 3" class="px-3 py-8 text-center text-muted-foreground text-sm">데이터가 없습니다.</td></tr>
              </tbody>
            </table>
          </div>
          <div class="px-3 py-2 border-t text-[11px] flex items-center gap-2 flex-wrap" :style="{ borderColor: '#ECEFF1', color: '#546E7A' }">
            <!-- SAGE GREEN 강조 뱃지 — 제품 수(가격 탭과 동일) -->
            <span class="inline-flex items-center px-2 py-0.5 rounded font-semibold" :style="{ background: '#E8F5E9', color: '#546E7A' }">
              제품 {{ specFiltered.length.toLocaleString() }}건
            </span>
            <span v-if="specDef.specTable">· 제원 매칭 {{ specMatched.toLocaleString() }}건</span>
            <span v-if="specTab === 'tube'" class="opacity-70">
              · 월생산량 = 일생산량 × 24일 · Box 포장: TB HD · OTR · AGR 튜브 / Sack 포장: TB STD · IND 튜브 · 미입력 —
            </span>
            <span v-else class="opacity-70">· 제원 미매칭 규격·패턴은 제품 설명 파싱 · 미입력 —</span>
          </div>
        </div>
      </template>

      <!-- 운송 -->
      <div v-else class="rounded-xl border border-dashed border-border bg-card p-12 text-center text-sm text-muted-foreground">
        <Wrench :size="24" class="mx-auto mb-3 text-muted-foreground/50" />
        운송 정보(제품별 운임·물류 조건)는 준비 중입니다. DB 테이블 연동 예정.
      </div>

      <!-- 가격 탭에서 제품 클릭 → 제원(스펙) 모달 -->
      <div v-if="specModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" @click.self="specModal = null">
        <div class="bg-card border border-border rounded-2xl shadow-2xl w-full max-w-3xl max-h-[86vh] overflow-y-auto p-5 space-y-3">
          <div class="flex items-start gap-2">
            <Package :size="16" class="text-primary shrink-0 mt-0.5" />
            <div class="min-w-0">
              <div class="font-semibold truncate">{{ txt(specModal.description) }}</div>
              <div class="text-[11px] text-muted-foreground">
                {{ txt(specModal.brand) }}<span v-if="specModal.sku"> · {{ specModal.sku }}</span><span v-if="specModal.unit"> · {{ specModal.unit }}</span>
              </div>
            </div>
            <span class="ml-auto inline-block px-1.5 py-0.5 rounded bg-muted text-[11px] text-foreground/80 shrink-0">{{ catOf(specModal) }}</span>
            <button class="p-1 rounded hover:bg-accent text-muted-foreground shrink-0" @click="specModal = null"><X :size="16" /></button>
          </div>
          <div v-if="!specModalDef" class="border-t border-border pt-3 text-xs text-muted-foreground">
            이 아이템에는 정의된 제원표가 없습니다.
          </div>
          <div v-else-if="specModalPending" class="border-t border-border pt-6 pb-4 text-center text-sm text-muted-foreground">불러오는 중…</div>
          <template v-else-if="specModalRow">
            <div class="border-t border-border pt-3 grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3 text-xs">
              <div v-for="c in specModalCols" :key="c.key">
                <div class="text-muted-foreground mb-0.5">{{ c.label }}<span v-if="c.sub" class="opacity-70"> {{ c.sub }}</span></div>
                <div :class="c.num && 'tabular-nums'">{{ fmtSpec(c, specModalRow[c.key]) }}</div>
              </div>
            </div>
            <p class="text-[11px] text-muted-foreground">
              <span v-if="specModalRow._matched">카탈로그 제원 매칭<span v-if="specModalRow._source"> · 출처 {{ specModalRow._source }}</span></span>
              <span v-else>제원 미매칭 — 규격·패턴은 제품 설명에서 파싱한 값입니다. 미입력은 —.</span>
            </p>
          </template>
        </div>
      </div>

      <!-- 스펙 탭에서 제품 클릭 → 가격 모달 -->
      <div v-if="priceModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" @click.self="priceModal = null">
        <div class="bg-card border border-border rounded-2xl shadow-2xl w-full max-w-2xl max-h-[86vh] overflow-y-auto p-5 space-y-3">
          <div class="flex items-start gap-2">
            <Package :size="16" class="text-primary shrink-0 mt-0.5" />
            <div class="min-w-0">
              <div class="font-semibold truncate">{{ txt(priceModal.description) }}</div>
              <div class="text-[11px] text-muted-foreground">
                {{ txt(priceModal.brand) }}<span v-if="priceModal.sku"> · {{ priceModal.sku }}</span><span v-if="priceModal.unit"> · {{ priceModal.unit }}</span>
              </div>
            </div>
            <span class="ml-auto inline-block px-1.5 py-0.5 rounded bg-muted text-[11px] text-foreground/80 shrink-0">{{ catOf(priceModal) }}</span>
            <button class="p-1 rounded hover:bg-accent text-muted-foreground shrink-0" @click="priceModal = null"><X :size="16" /></button>
          </div>
          <div class="border-t border-border pt-3 grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3 text-xs">
            <div><div class="text-muted-foreground mb-0.5">FOB</div><div class="tabular-nums">{{ fmtFob(priceModal.fob) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">중량 <span class="opacity-70">(kg)</span></div><div class="tabular-nums">{{ fmtWeight(priceModal.weight_kg) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">40ft <span class="opacity-70">(Qty)</span></div><div class="tabular-nums">{{ fmt(priceModal.qty_40ft) }}</div></div>
            <div>
              <div class="text-muted-foreground mb-0.5">판매량 <span class="opacity-70">(SAP 누적 pcs)</span></div>
              <div class="tabular-nums">{{ priceModal.sap_sold_qty ? fmt(priceModal.sap_sold_qty) : '—' }}</div>
            </div>
          </div>
          <!-- 가격은 화면 상단 VAT 토글 기준으로 환산해 보여준다(저장값은 입고가=별도·대리점가=포함) -->
          <div class="border-t border-border pt-3 grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3 text-xs">
            <div>
              <div class="text-muted-foreground mb-0.5">입고가 (pcs) <span class="opacity-70">{{ vatLabel }}</span></div>
              <div class="tabular-nums font-medium">
                {{ fmt(vat(priceModal.wh_price_pcs, 'excl')) }}
                <span v-if="priceModal.wh_price_basis === 'API-U'" class="ml-1 rounded border border-amber-300 bg-amber-50 px-1 py-px text-[10px] font-medium leading-none text-amber-700">API-U</span>
              </div>
            </div>
            <div><div class="text-muted-foreground mb-0.5">입고가 (set) <span class="opacity-70">{{ vatLabel }}</span></div><div class="tabular-nums">{{ fmt(vat(priceModal.wh_price_set, 'excl')) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">대리점가 (pcs) <span class="opacity-70">{{ vatLabel }}</span></div><div class="tabular-nums font-medium">{{ fmt(vat(priceModal.dist_price_pcs, 'incl')) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">대리점가 (set) <span class="opacity-70">{{ vatLabel }}</span></div><div class="tabular-nums">{{ fmt(vat(priceModal.dist_price_set, 'incl')) }}</div></div>
          </div>
          <p class="text-[11px] text-muted-foreground">
            <span v-if="priceModal.review_note" class="text-rose-700">확인 필요 — {{ priceModal.review_note }}</span>
            <span v-else-if="priceModal.sap_last_sold">최근 판매 {{ priceModal.sap_last_sold }}</span>
            <span v-else>가격 단위 IDR · 미입력은 —.</span>
          </p>
        </div>
      </div>
    </template>

    <!-- ═══ 직원 (급여) ═══ -->
    <StaffPayrollTable v-else-if="section === 'staff' && isSuperAdmin" />

    <!-- ═══ 고객 (customers) ═══ -->
    <template v-else-if="section === 'customer'">
      <div class="flex items-center gap-2 flex-wrap">
        <p class="text-[11px] text-muted-foreground">
          총 {{ custFiltered.length.toLocaleString() }}개<span v-if="custQuery"> / 전체 {{ custRows.length.toLocaleString() }}개</span> · 출처: customers + SAP 판매이력(v_db_customers)
        </p>
        <div class="flex flex-wrap items-center gap-2 w-full sm:w-auto sm:ml-auto">
          <div class="relative flex-1 min-w-40 sm:flex-none">
            <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input v-model="custQuery" type="text" placeholder="코드·고객명·담당자 검색…"
              class="w-full sm:w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary" />
          </div>
          <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadCustomers">
            <Download :size="14" /> 엑셀
          </button>
        </div>
      </div>
      <div class="rounded-xl border border-border bg-card overflow-hidden">
        <DataState
          v-if="custLoading || custError"
          :loading="custLoading" :error="custError" skeleton-class="h-64 m-3"
          @retry="retryCustomers"
        />
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm whitespace-nowrap">
            <caption class="sr-only">고객 목록</caption>
            <thead>
              <tr class="bg-muted text-muted-foreground text-xs">
                <th scope="col" v-for="col in CUST_COLS" :key="col.key" class="font-semibold px-3 py-2.5 cursor-pointer select-none hover:text-foreground" :class="col.center ? 'text-center' : col.right ? 'text-right' : 'text-left'" @click="custSortBy(col.key)">
                  <span class="inline-flex items-center gap-1" :class="col.center ? 'justify-center' : col.right ? 'justify-end' : ''">
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
                <!-- SAP A/R 누적 매출(할인 후·취소 반영). 청구 건수와 최근 청구일은 tooltip -->
                <td class="px-3 py-2 text-right tabular-nums"
                    :title="c.sap_invoice_cnt ? `청구 ${c.sap_invoice_cnt.toLocaleString('en-US')}건 · 최근 ${c.sap_last_invoice ?? '—'}` : ''">
                  <span :class="c.sap_sales_idr ? 'text-foreground' : 'text-muted-foreground'">{{ fmtIdr(c.sap_sales_idr) }}</span>
                </td>
              </tr>
              <tr v-if="!custPaged.length"><td colspan="8" class="px-3 py-8 text-center text-muted-foreground text-sm">데이터가 없습니다.</td></tr>
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

    <!-- ═══ 구매 현황 / 판매 현황 (SAP 거래이력 집계) ═══ -->
    <template v-if="section === 'purchase' || section === 'sales'">
      <!-- 축 탭 + 기간 -->
      <div class="flex items-center gap-2 flex-wrap">
        <div class="inline-flex items-center gap-1 rounded-lg border border-border bg-card p-0.5">
          <button
            v-for="d in TRADE_DIMS" :key="d.key"
            :class="['px-3 py-1.5 rounded-md text-xs font-semibold transition-colors',
              tradeDim === d.key ? 'bg-primary/15 text-primary' : 'text-muted-foreground hover:bg-accent']"
            @click="tradeDim = d.key"
          >{{ d.label(tradeSide) }}</button>
        </div>
        <div class="inline-flex items-center gap-1">
          <button
            v-for="p in TRADE_PRESETS" :key="p.key"
            class="px-2 py-1.5 rounded-md border border-border text-[11px] text-muted-foreground hover:bg-accent transition-colors"
            @click="applyTradePreset(p.key)"
          >{{ p.label }}</button>
        </div>
        <div class="inline-flex items-center gap-1 text-xs">
          <select v-model="tradeFrom" class="bg-card border border-border rounded-lg px-2 py-1.5 focus:outline-none focus:ring-1 focus:ring-primary">
            <option v-for="m in tradeMonthOptions" :key="`f-${m}`" :value="m">{{ m }}</option>
          </select>
          <span class="text-muted-foreground">~</span>
          <select v-model="tradeTo" class="bg-card border border-border rounded-lg px-2 py-1.5 focus:outline-none focus:ring-1 focus:ring-primary">
            <option v-for="m in tradeMonthOptions" :key="`t-${m}`" :value="m">{{ m }}</option>
          </select>
        </div>
        <div class="flex flex-wrap items-center gap-2 w-full sm:w-auto sm:ml-auto">
          <div v-if="tradeDim !== 'period'" class="relative flex-1 min-w-40 sm:flex-none">
            <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input v-model="tradeQuery" type="text"
              :placeholder="tradeDim === 'partner' ? (tradeSide === 'sales' ? '고객명·코드 검색…' : '벤더명·코드 검색…') : tradeDim === 'item' ? '아이템 검색…' : 'SKU·품명·브랜드 검색…'"
              class="w-full sm:w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary" />
          </div>
          <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadTrade">
            <Download :size="14" /> 엑셀
          </button>
        </div>
      </div>

      <!-- 요약 -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div class="rounded-xl border border-border bg-card p-4">
          <p class="text-[11px] text-muted-foreground mb-1">{{ tradeUnitLabel }} (IDR)</p>
          <p class="text-xl font-bold tabular-nums">{{ fmtIdr(tradeTotal.idr) }}</p>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <p class="text-[11px] text-muted-foreground mb-1">{{ tradeUnitLabel }} (USD)</p>
          <p class="text-xl font-bold tabular-nums">{{ tradeTotal.usd ? `USD ${fmt(tradeTotal.usd)}` : '—' }}</p>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <p class="text-[11px] text-muted-foreground mb-1">수량 (EA)</p>
          <p class="text-xl font-bold tabular-nums">{{ fmt(tradeTotal.qty) }}</p>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <p class="text-[11px] text-muted-foreground mb-1">{{ TRADE_DIMS.find(d => d.key === tradeDim)?.label(tradeSide) }} 항목</p>
          <p class="text-xl font-bold tabular-nums">{{ tradeRows.length.toLocaleString() }}</p>
        </div>
      </div>

      <p class="text-[11px] text-muted-foreground">
        출처: SAP {{ tradeSide === 'sales' ? '판매(A/R)' : '구매(A/P)' }} 이력 · {{ tradeFrom }} ~ {{ tradeTo }} ·
        금액은 할인 후 · 취소·반품이 음수로 반영된 순액 · VAT 별도<span v-if="tradeRowClickable"> · 행을 클릭하면 구매·판매 월별 내역</span>
      </p>

      <div class="rounded-xl border border-border bg-card overflow-hidden">
        <DataState
          v-if="tradeLoading || tradeError"
          :loading="tradeLoading" :error="tradeError" skeleton-class="h-64 m-3"
          @retry="retryTrade"
        />
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm whitespace-nowrap">
            <caption class="sr-only">거래 집계 표</caption>
            <thead>
              <tr class="bg-muted text-muted-foreground text-xs">
                <th scope="col" class="font-semibold px-3 py-2.5 text-center w-12">No.</th>
                <th scope="col" class="font-semibold px-3 py-2.5 text-left">
                  {{ tradeDim === 'period' ? '연월' : tradeDim === 'partner' ? (tradeSide === 'sales' ? '고객사' : '벤더') : tradeDim === 'item' ? '아이템' : 'SKU · 품명' }}
                </th>
                <th scope="col" v-if="tradeDocCntMeaningful" class="font-semibold px-3 py-2.5 text-right">건수</th>
                <th scope="col" class="font-semibold px-3 py-2.5 text-right">수량 (EA)</th>
                <th scope="col" class="font-semibold px-3 py-2.5 text-right">{{ tradeUnitLabel }} (IDR)</th>
                <th scope="col" class="font-semibold px-3 py-2.5 text-right">{{ tradeUnitLabel }} (USD)</th>
                <th scope="col" class="font-semibold px-3 py-2.5 text-right">비중</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(r, i) in tradePaged" :key="r.key"
                class="border-t border-border/50 hover:bg-accent/40"
                :class="tradeRowClickable && 'cursor-pointer'"
                @click="openTradeDetail(r)">
                <td class="px-3 py-2 text-center text-muted-foreground tabular-nums">{{ (tradePage - 1) * TRADE_PAGE + i + 1 }}</td>
                <td class="px-3 py-2">
                  <div class="font-medium" :class="tradeRowClickable && 'text-primary'">{{ r.label }}</div>
                  <div v-if="r.sub" class="text-[11px] text-muted-foreground font-mono">{{ r.sub }}</div>
                </td>
                <td v-if="tradeDocCntMeaningful" class="px-3 py-2 text-right tabular-nums text-muted-foreground">{{ fmt(r.docCnt) }}</td>
                <td class="px-3 py-2 text-right tabular-nums">{{ fmt(r.qty) }}</td>
                <td class="px-3 py-2 text-right tabular-nums font-medium" :class="r.idr < 0 && 'text-red-600'">{{ fmtIdr(r.idr) }}</td>
                <td class="px-3 py-2 text-right tabular-nums text-muted-foreground">{{ r.usd ? fmt(r.usd) : '—' }}</td>
                <td class="px-3 py-2 text-right tabular-nums text-muted-foreground">
                  {{ tradeTotal.idr ? `${(r.idr / tradeTotal.idr * 100).toFixed(1)}%` : '—' }}
                </td>
              </tr>
              <tr v-if="!tradePaged.length">
                <td :colspan="tradeDocCntMeaningful ? 7 : 6" class="px-3 py-8 text-center text-muted-foreground text-sm">데이터가 없습니다.</td>
              </tr>
            </tbody>
          </table>
        </div>
        <div v-if="!tradeLoading && tradeTotalPages > 1" class="flex items-center justify-center gap-1 py-3 border-t border-border">
          <button :disabled="tradePage <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="tradePage = 1">«</button>
          <button :disabled="tradePage <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="tradePage--">‹</button>
          <button v-for="n in tradePageWindow" :key="n"
            :class="['h-8 min-w-8 px-2 rounded-md text-sm border transition-colors', n === tradePage ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
            @click="tradePage = n">{{ n }}</button>
          <button :disabled="tradePage >= tradeTotalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="tradePage++">›</button>
          <button :disabled="tradePage >= tradeTotalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="tradePage = tradeTotalPages">»</button>
        </div>
      </div>

      <!-- 상세 모달 — 클릭한 아이템/SKU 의 구매·판매 월별 내역(전체 기간) -->
      <div v-if="tradeDetail" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" @click.self="tradeDetail = null">
        <div class="bg-card border border-border rounded-2xl shadow-2xl w-full max-w-4xl max-h-[86vh] flex flex-col">
          <div class="flex items-start gap-3 px-5 py-4 border-b border-border">
            <div class="min-w-0">
              <h3 class="font-semibold text-sm truncate">{{ tradeDetail.title }}</h3>
              <p class="text-[11px] text-muted-foreground font-mono truncate">
                {{ tradeDetail.sub || (tradeDetail.dim === 'item' ? '아이템' : 'SKU') }}
              </p>
            </div>
            <button class="ml-auto p-1 rounded hover:bg-accent text-muted-foreground" @click="tradeDetail = null"><X :size="16" /></button>
          </div>

          <div v-if="tradeDetailLoading" class="p-10 text-center text-sm text-muted-foreground">불러오는 중…</div>
          <template v-else>
            <!-- 요약: 구매 / 판매 각각 수량·금액·평균단가·최근월 -->
            <div class="grid grid-cols-2 gap-3 px-5 py-4">
              <div class="rounded-xl border border-border p-3">
                <p class="text-[11px] font-semibold text-muted-foreground mb-2">구매 (A/P)</p>
                <p class="text-lg font-bold tabular-nums">{{ fmtIdr(tradeDetailTotal.buyIdr) }}</p>
                <p class="text-[11px] text-muted-foreground tabular-nums mt-1">
                  {{ fmt(tradeDetailTotal.buyQty) }} EA · 평균 {{ fmtIdr(unitIdr(tradeDetailTotal.buyIdr, tradeDetailTotal.buyQty)) }}/EA
                </p>
                <p class="text-[11px] text-muted-foreground tabular-nums">최근 {{ tradeDetailLast('buy') }}</p>
              </div>
              <div class="rounded-xl border border-border p-3">
                <p class="text-[11px] font-semibold text-muted-foreground mb-2">판매 (A/R)</p>
                <p class="text-lg font-bold tabular-nums">{{ fmtIdr(tradeDetailTotal.sellIdr) }}</p>
                <p class="text-[11px] text-muted-foreground tabular-nums mt-1">
                  {{ fmt(tradeDetailTotal.sellQty) }} EA · 평균 {{ fmtIdr(unitIdr(tradeDetailTotal.sellIdr, tradeDetailTotal.sellQty)) }}/EA
                </p>
                <p class="text-[11px] text-muted-foreground tabular-nums">최근 {{ tradeDetailLast('sell') }}</p>
              </div>
            </div>

            <div class="flex-1 overflow-auto border-t border-border">
              <table class="w-full text-xs whitespace-nowrap">
                <caption class="sr-only">거래처 월별 구매·판매 상세</caption>
                <thead class="sticky top-0 bg-muted text-muted-foreground">
                  <tr>
                    <th scope="col" rowspan="2" class="font-semibold px-3 py-2 text-left border-r border-border/60">연월</th>
                    <th scope="colgroup" colspan="3" class="font-semibold px-3 py-1.5 text-center border-r border-border/60">구매 (A/P)</th>
                    <th scope="colgroup" colspan="3" class="font-semibold px-3 py-1.5 text-center">판매 (A/R)</th>
                  </tr>
                  <tr>
                    <th scope="col" class="font-medium px-3 py-1.5 text-right">수량 (EA)</th>
                    <th scope="col" class="font-medium px-3 py-1.5 text-right">금액 (IDR)</th>
                    <th scope="col" class="font-medium px-3 py-1.5 text-right border-r border-border/60">단가 (IDR)</th>
                    <th scope="col" class="font-medium px-3 py-1.5 text-right">수량 (EA)</th>
                    <th scope="col" class="font-medium px-3 py-1.5 text-right">금액 (IDR)</th>
                    <th scope="col" class="font-medium px-3 py-1.5 text-right">단가 (IDR)</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="d in tradeDetailRows" :key="d.ym" class="border-t border-border/50 hover:bg-accent/40">
                    <td class="px-3 py-1.5 tabular-nums font-medium border-r border-border/60">{{ d.ym }}</td>
                    <td class="px-3 py-1.5 text-right tabular-nums text-muted-foreground">{{ d.buyQty ? fmt(d.buyQty) : '—' }}</td>
                    <td class="px-3 py-1.5 text-right tabular-nums" :class="d.buyIdr < 0 && 'text-red-600'">{{ fmtIdr(d.buyIdr) }}</td>
                    <td class="px-3 py-1.5 text-right tabular-nums text-muted-foreground border-r border-border/60">{{ fmtIdr(unitIdr(d.buyIdr, d.buyQty)) }}</td>
                    <td class="px-3 py-1.5 text-right tabular-nums text-muted-foreground">{{ d.sellQty ? fmt(d.sellQty) : '—' }}</td>
                    <td class="px-3 py-1.5 text-right tabular-nums" :class="d.sellIdr < 0 && 'text-red-600'">{{ fmtIdr(d.sellIdr) }}</td>
                    <td class="px-3 py-1.5 text-right tabular-nums text-muted-foreground">{{ fmtIdr(unitIdr(d.sellIdr, d.sellQty)) }}</td>
                  </tr>
                  <tr v-if="!tradeDetailRows.length">
                    <td colspan="7" class="px-3 py-8 text-center text-muted-foreground">거래 내역이 없습니다.</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <p class="px-5 py-3 text-[11px] text-muted-foreground border-t border-border">
              전체 기간 · 최근월 순 · 금액은 할인 후 순액(취소·반품 음수 반영) · VAT 별도 · 화면 상단 기간 필터와 무관
              <span v-if="tradeDetailError" class="text-red-600"> · 반대편(구매/판매) 이력을 불러오지 못했습니다</span>
            </p>
          </template>
        </div>
      </div>
    </template>

    <!-- ═══ 벤더 (vendors + SAP 구매이력) ═══ -->
    <template v-else-if="section === 'vendor'">
      <div class="flex items-center gap-2 flex-wrap">
        <p class="text-[11px] text-muted-foreground">
          총 {{ venFiltered.length.toLocaleString() }}개<span v-if="venFiltered.length !== venRows.length"> / 전체 {{ venRows.length.toLocaleString() }}개</span>
          · 출처: vendors + SAP 구매이력(v_db_vendors) · 매입액은 할인 반영 · VAT 별도
        </p>
        <div class="flex flex-wrap items-center gap-2 w-full sm:w-auto sm:ml-auto">
          <div class="relative flex-1 min-w-40 sm:flex-none">
            <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input v-model="venQuery" type="text" placeholder="코드·벤더명·국가·브랜드 검색…"
              class="w-full sm:w-56 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary" />
          </div>
          <button class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors whitespace-nowrap" title="엑셀(CSV) 다운로드" @click="downloadVendors">
            <Download :size="14" /> 엑셀
          </button>
        </div>
      </div>

      <!-- 필터 칩: 소싱 -->
      <div class="flex items-center gap-4 flex-wrap text-[11px]">
        <div class="inline-flex items-center gap-1">
          <span class="font-semibold text-muted-foreground mr-1">소싱</span>
          <button v-for="s in (['전체', 'LOCAL', 'IMPORT'] as const)" :key="s"
            :class="['px-2 py-1 rounded-md border transition-colors',
              venSourcing === s ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
            @click="venSourcing = s">{{ s === '전체' ? '전체' : s === 'LOCAL' ? '로컬' : '해외' }}</button>
        </div>
      </div>

      <div class="rounded-xl border border-border bg-card overflow-hidden">
        <DataState
          v-if="venLoading || venError"
          :loading="venLoading" :error="venError" skeleton-class="h-64 m-3"
          @retry="retryVendors"
        />
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm whitespace-nowrap">
            <caption class="sr-only">벤더 목록</caption>
            <thead>
              <tr class="bg-muted text-muted-foreground text-xs">
                <th scope="col" v-for="col in VEN_COLS" :key="col.key" class="font-semibold px-3 py-2.5 cursor-pointer select-none hover:text-foreground"
                  :class="col.center ? 'text-center' : col.right ? 'text-right' : 'text-left'" @click="venSortBy(col.key)">
                  <span class="inline-flex items-center gap-1" :class="col.center ? 'justify-center' : col.right ? 'justify-end' : ''">
                    {{ col.label }}
                    <span class="text-[9px] w-2" :class="venSort.key === col.key ? 'text-primary' : 'text-muted-foreground/30'">{{ venSort.key === col.key ? (venSort.dir === 1 ? '▲' : '▼') : '▲' }}</span>
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="v in venPaged" :key="v.id"
                class="border-t border-border/50 hover:bg-accent/40 cursor-pointer"
                :class="venDetail?.id === v.id && 'bg-accent/40'"
                @click="venDetail = v">
                <td class="px-3 py-2 font-mono text-xs">{{ v.vendor_code }}</td>
                <td class="px-3 py-2 font-medium">{{ v.vendor_name }}</td>
                <td class="px-3 py-2 text-center">
                  <span class="text-[10px] font-bold px-2 py-0.5 rounded-full border"
                    :class="v.sourcing === 'LOCAL' ? 'bg-emerald-500/10 text-emerald-600 border-emerald-500/20' : 'bg-muted text-foreground/70 border-border'">
                    {{ venSourcingLabel(v.sourcing) }}
                  </span>
                </td>
                <!-- 국가 미확인(NULL)은 추정으로 채우지 않고 뱃지로 드러낸다 -->
                <td class="px-3 py-2">
                  <span v-if="v.country">{{ v.country }}</span>
                  <span v-else class="rounded border border-amber-300 bg-amber-50 px-1 py-px text-[10px] font-medium leading-none text-amber-700">미확인</span>
                </td>
                <td class="px-3 py-2 text-center">
                  <span class="text-[10px] font-bold px-2 py-0.5 rounded-full border" :class="VEN_STATUS_CLASS[venStatusOf(v)]">{{ venStatusOf(v) }}</span>
                </td>
                <td class="px-3 py-2 text-center">
                  <span class="text-[10px] font-bold px-1.5 py-0.5 rounded border"
                    :class="venGradeOf(v) === 'A' ? 'bg-emerald-500/10 text-emerald-600 border-emerald-500/20' : 'bg-muted text-muted-foreground border-border'">{{ venGradeOf(v) }}</span>
                </td>
                <td class="px-3 py-2">{{ txt(v.top_brand) }}</td>
                <td class="px-3 py-2">{{ txt(v.top_category) }}</td>
                <td class="px-3 py-2 text-right tabular-nums">{{ fmt(v.ap_invoice_cnt) }}</td>
                <td class="px-3 py-2 text-right tabular-nums">{{ fmt(v.qty_total) }}</td>
                <td class="px-3 py-2 text-right tabular-nums font-medium">
                  <span v-if="v.purchase_usd">USD {{ fmt(v.purchase_usd) }}</span><span v-else>—</span>
                </td>
                <td class="px-3 py-2 text-right tabular-nums">{{ v.share_pct.toFixed(1) }}%</td>
                <td class="px-3 py-2 text-center tabular-nums text-muted-foreground">{{ v.last_inv_date ?? '—' }}</td>
                <td class="px-3 py-2">{{ txt(v.payment_term) }}</td>
              </tr>
              <tr v-if="!venPaged.length"><td colspan="14" class="px-3 py-8 text-center text-muted-foreground text-sm">데이터가 없습니다.</td></tr>
            </tbody>
          </table>
        </div>
        <div v-if="!venLoading && venTotalPages > 1" class="flex items-center justify-center gap-1 py-3 border-t border-border">
          <button :disabled="venPage <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="venPage = 1">«</button>
          <button :disabled="venPage <= 1" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="venPage--">‹</button>
          <button v-for="n in venPageWindow" :key="n"
            :class="['h-8 min-w-8 px-2 rounded-md text-sm border transition-colors', n === venPage ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
            @click="venPage = n">{{ n }}</button>
          <button :disabled="venPage >= venTotalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="venPage++">›</button>
          <button :disabled="venPage >= venTotalPages" class="h-8 px-2 rounded-md border border-border text-sm text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed" @click="venPage = venTotalPages">»</button>
        </div>
      </div>

      <!-- 상세 모달: 수기 관리 항목(SAP 에 없는 값) + 거래 요약. 미입력은 '—' -->
      <div v-if="venDetail" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" @click.self="venDetail = null">
        <div class="bg-card border border-border rounded-2xl shadow-2xl w-full max-w-3xl max-h-[86vh] overflow-y-auto p-5 space-y-3">
          <div class="flex items-center gap-2">
            <Building2 :size="16" class="text-primary" />
            <span class="font-semibold">{{ venDetail.vendor_name }}</span>
            <span class="font-mono text-xs text-muted-foreground">{{ venDetail.vendor_code }}</span>
            <button class="ml-auto p-1 rounded hover:bg-accent text-muted-foreground" @click="venDetail = null"><X :size="16" /></button>
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3 text-xs">
            <div><div class="text-muted-foreground mb-0.5">담당자</div><div>{{ txt(venDetail.contact_person) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">연락처</div><div>{{ txt(venDetail.contact_phone) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">이메일</div><div>{{ txt(venDetail.contact_email) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">NPWP</div><div>{{ txt(venDetail.npwp) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">결제조건</div><div>{{ txt(venDetail.payment_term) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">Incoterms</div><div>{{ txt(venDetail.incoterms) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">결제통화</div><div>{{ txt(venDetail.settle_currency) }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">자사 담당</div><div>{{ txt(venDetail.pic_name) }}</div></div>
          </div>
          <div class="border-t border-border pt-3 grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3 text-xs">
            <div><div class="text-muted-foreground mb-0.5">거래 기간</div><div class="tabular-nums">{{ venDetail.first_inv_date ?? '—' }} ~ {{ venDetail.last_inv_date ?? '—' }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">매입액 (IDR)</div><div class="tabular-nums">{{ venDetail.purchase_idr ? `IDR ${fmtIdr(venDetail.purchase_idr)}` : '—' }}</div></div>
            <div><div class="text-muted-foreground mb-0.5">라인 수</div><div class="tabular-nums">{{ fmt(venDetail.ap_line_cnt) }}</div></div>
            <div>
              <div class="text-muted-foreground mb-0.5">취소</div>
              <div class="tabular-nums">
                <span v-if="venDetail.cxl_line_cnt">{{ fmt(venDetail.cxl_line_cnt) }}건 · USD {{ fmt(venDetail.cxl_usd) }} ({{ venCxlPct(venDetail)?.toFixed(1) ?? '—' }}%)</span>
                <span v-else>—</span>
              </div>
            </div>
          </div>
          <p class="text-[11px] text-muted-foreground">
            연락처·결제조건·NPWP·은행정보는 SAP 에 없는 수기 관리 항목입니다 — 계약서·ERP 확인 후 입력 예정.
          </p>
        </div>
      </div>
    </template>
  </div>
</template>
