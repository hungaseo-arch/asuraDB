<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Plus, Printer, Save, FolderOpen, X, FileText, Trash2 } from 'lucide-vue-next';
import { toast } from 'vue-sonner';
import { sbGet, sbPost, sbPatch, sbDelete, sbRpc } from '@/lib/supabase';
import PageHeader from '@/components/PageHeader.vue';

// ── 권한 ────────────────────────────────────────────────────────────────────
const _auth = sessionStorage.getItem('asura_auth');
const isPrivileged   = _auth === 'super_admin' || _auth === 'staff';   // 내부용 열람 가능
const canSaveImport  = _auth === 'super_admin';                        // 저장/불러오기는 관리자만

// ── 상수 ────────────────────────────────────────────────────────────────────
const PPN_RATE = 0.11;   // 부가세 11% (Quote.vue 와 동일)

const GRADES = [
  '수입상',
  '대리점',
  '서브딜러',
  '타이어판매점',
  '최종소비자',
];
// 구버전 저장값('서브딜러 · Sub-Distributor' 등 3중 표기) → 한국어 단독 표기 정규화
function normGrade(g: string | null): string {
  if (!g) return GRADES[2];
  const k = g.split('·')[0].trim();
  return GRADES.includes(k) ? k : GRADES[2];
}

// ── 제품 마스터 (Supabase products) ─────────────────────────────────────────
interface Product { id: string; item: string | null; brand: string | null; description: string; sku: string | null; wh_price: number; wh_price_set: number; unit: string }
const products = ref<Product[]>([]);

// ── 등급별 마진율 (대리점 기준 · 한 단계당 +5%p, 엔드유저 방향) ──────────────
// 판매가 = wh_price ÷ (1 − 마진율). 대리점(GRADES[1])이 기준값. (마진율표 2026-07-09)
// 카테고리 = products.item (타이어) · TUBE/FLAP(+description 키워드로 STD/HD·STD/MP 판별).
//   타이어: LT Radial(LTR)20·LT Bias(LTB)20 / TB Radial(TBR)25·TB Bias(TBB)25 / OTR30·AGR30 / IND PENU25·SOLID25
//   튜브: STD20·HD30 / 플랩: STD35·MP40
const TIRE_CATS = new Set(['LTR', 'TBR', 'LTB', 'TBB', 'OTR', 'AGR', 'PNEUMATIC', 'SOLID']);
const MARGIN_BASE: Record<string, number> = {
  LTR: 0.20, TBR: 0.25, LTB: 0.20, TBB: 0.25, OTR: 0.30, AGR: 0.30, PNEUMATIC: 0.25, SOLID: 0.25,
  TUBE_STD: 0.20, TUBE_HD: 0.30,
  FLAP_STD: 0.35, FLAP_MP: 0.40,
};
function catOf(item: string | null, desc: string): string | null {
  const it = (item ?? '').toUpperCase();
  const d  = desc.toUpperCase();
  if (it === 'TUBE') return /HEAVY DUTY|\bHD\b/.test(d) ? 'TUBE_HD' : 'TUBE_STD';
  if (it === 'FLAP') return /METAL PLATE|\bMP\b/.test(d) ? 'FLAP_MP' : 'FLAP_STD';
  return TIRE_CATS.has(it) ? it : null;
}
const DIST_IDX = 1;   // 대리점 = GRADES[1] (기준 등급)
const gradeIdx = computed(() => { const i = GRADES.indexOf(form.value.grade); return i < 0 ? DIST_IDX : i; });
// 등급 마진율 = 대리점 기준 + 5%p × (등급 스텝). 0~0.95 로 클램프.
function marginFor(cat: string, gi: number): number {
  const base = MARGIN_BASE[cat];
  if (base == null) return 0;
  return Math.min(0.95, Math.max(0, base + 0.05 * (gi - DIST_IDX)));
}
function sellFrom(wh: number, cat: string, gi: number): number {
  const m = marginFor(cat, gi);
  return Math.round(m > 0 ? wh / (1 - m) : wh);
}

// ── 타입 ────────────────────────────────────────────────────────────────────
interface Item { price: number; code: string; brand: string; wh?: number; cat?: string | null }
interface Promo { desc: string; rate: number; max?: number }   // max = 최대 할인율(%) 상한

// 자사 기본 프로모션 프리셋 (기본값 = 최대치)
const SELF_PROMOS: Promo[] = [
  { desc: '수량 할인', rate: 10, max: 10 },
  { desc: '현금 할인', rate: 5,  max: 5 },
  { desc: '배송 할인', rate: 3,  max: 3 },
];
const selfPromoMax = (desc: string) => SELF_PROMOS.find(s => s.desc === desc.trim())?.max;
interface Company {
  name: string; self: boolean;
  tire: Item; tube: Item; flap: Item;
  landed: number; promos: Promo[];
  ppn: boolean;   // PPN 적용 여부 (자사=항상 true, 경쟁사=토글)
}

const ALL_ROWS = [
  { key: 'tire' as const, label: '타이어' },
  { key: 'tube' as const, label: '튜브' },
  { key: 'flap' as const, label: '플랩' },
];
// 표시 중인 품목 행 (삭제/복원 가능)
const ROWS = ref<typeof ALL_ROWS[number][]>([...ALL_ROWS]);
const removedRows = computed(() => ALL_ROWS.filter(a => !ROWS.value.some(r => r.key === a.key)));

// ── 상태 ────────────────────────────────────────────────────────────────────
function defaultCompanies(): Company[] {
  return [
    {
      name: 'PT ASCENDO', self: true,
      tire: { price: 0, code: '', brand: '' }, tube: { price: 0, code: '', brand: '' }, flap: { price: 0, code: '', brand: '' },
      landed: 0, promos: SELF_PROMOS.map(p => ({ ...p })), ppn: true,
    },
    {
      name: '경쟁사 A', self: false,
      tire: { price: 0, code: '', brand: '' }, tube: { price: 0, code: '', brand: '' }, flap: { price: 0, code: '', brand: '' },
      landed: 0, promos: [{ desc: '', rate: 0 }], ppn: true,
    },
  ];
}

const today = new Date().toISOString().slice(0, 10);
const form = ref({
  createdDate: today,
  customer: '',
  grade: GRADES[2],   // 서브딜러
  basis: 'excl' as 'excl' | 'incl',
});
const companies = ref<Company[]>(defaultCompanies());

const currentId = ref<string | null>(null);
const currentNo = ref<string | null>(null);

// ── 계산 (첨부 HTML §계산 로직 그대로) ───────────────────────────────────────
// 표시: 콤마 천단위 + Rp (예: 'Rp 1,862,445')
const fmt = (n: number) => 'Rp ' + Math.round(isNaN(n) ? 0 : n).toLocaleString('en-US');
// 입력칸용 콤마 천단위(0 → 빈칸=placeholder). setNum: 콤마 제거 후 숫자 반영.
const idFmt = (n: number) => (n ? Math.round(n).toLocaleString('en-US') : '');
function setNum(obj: Record<string, unknown>, key: string, val: string) {
  const d = val.replace(/[^\d]/g, '');
  obj[key] = d ? Number(d) : 0;
}
// 계산 순서: 세트 소계 → 총 할인(순차) → 할인후 합계 → PPN 11% → 최종 판매가
const sub    = (c: Company) => ROWS.value.reduce((a, r) => a + (+c[r.key].price || 0), 0);
// 프로모션 순차(복리) 할인: 각 할인율을 직전 잔액에 차례로 적용 (소계 기준)
const clampR = (r: number) => Math.min(100, Math.max(0, +r || 0));
// 적용 할인율 = 입력값을 항목별 최대치(max)로 제한
const pRate  = (p: Promo) => Math.min(clampR(p.rate), p.max ?? 100);
// 프로모션별 할인금액 배열 (i번째 = 직전 잔액 × 할인율)
function promoAmts(c: Company): number[] {
  let run = sub(c);
  return c.promos.map(p => { const a = run * pRate(p) / 100; run -= a; return a; });
}
const discAmt  = (c: Company) => promoAmts(c).reduce((a, v) => a + v, 0);
// 실효 할인율(순차 적용 합산 결과)
const effRate  = (c: Company) => { const s = sub(c); return s > 0 ? discAmt(c) / s * 100 : 0; };
const hasDisc  = (c: Company) => c.promos.some(p => pRate(p) > 0);
// 입력 시 최대치 초과분 자동 보정
function clampPromo(p: Promo) {
  if (p.max != null && +p.rate > p.max) p.rate = p.max;
  if (+p.rate < 0) p.rate = 0;
}
// 할인후 합계 (부가세 전)
const afterDisc = (c: Company) => sub(c) - discAmt(c);
// basis 'excl'(기본): 할인후 합계에 PPN 가산 / 'incl': 이미 포함된 PPN 분리 표시
// 경쟁사는 열별 PPN 미적용 선택 가능 (c.ppn=false → PPN 0)
const ppnAmt = (c: Company) => !c.ppn ? 0 : form.value.basis === 'excl' ? afterDisc(c) * PPN_RATE : afterDisc(c) - afterDisc(c) / (1 + PPN_RATE);
const finalP = (c: Company) => !c.ppn || form.value.basis !== 'excl' ? afterDisc(c) : afterDisc(c) * (1 + PPN_RATE);
const marginV  = (c: Company) => finalP(c) - (+c.landed || 0);
const marginR  = (c: Company) => { const f = finalP(c); return f > 0 ? marginV(c) / f * 100 : 0; };

const selfCompany = computed(() => companies.value.find(c => c.self) ?? companies.value[0]);
const selfFinal   = computed(() => finalP(selfCompany.value));

// 경쟁사 대비 차액 (자사 기준). d>0 = 경쟁사가 더 비쌈 = 자사 저렴
function diff(c: Company) {
  if (c.self || selfFinal.value <= 0 || sub(c) <= 0) return null;
  const d = finalP(c) - selfFinal.value;
  const pct = d / selfFinal.value * 100;
  return { d, pct, cheaper: d > 0, label: d > 0 ? '자사 저렴' : d < 0 ? '자사 비쌈' : '동일' };
}
function marginClass(m: number) { return m >= 15 ? 'text-emerald-500' : m >= 5 ? 'text-amber-500' : 'text-red-500'; }

// ── 편집 액션 ────────────────────────────────────────────────────────────────
function addCompetitor() {
  const n = companies.value.filter(c => !c.self).length;
  const L = String.fromCharCode(65 + n);
  companies.value.push({
    name: `경쟁사 ${L}`, self: false,
    tire: { price: 0, code: '', brand: '' }, tube: { price: 0, code: '', brand: '' }, flap: { price: 0, code: '', brand: '' },
    landed: 0, promos: [{ desc: '', rate: 0 }], ppn: true,
  });
}
function delCompany(i: number) { companies.value.splice(i, 1); }
// 품목 행 삭제/복원 (타이어·튜브·플랩). 삭제 시 값 초기화 → 소계·원가에서 제외.
function delRow(key: 'tire' | 'tube' | 'flap') {
  ROWS.value = ROWS.value.filter(r => r.key !== key);
  for (const c of companies.value) c[key] = { price: 0, code: '', brand: '' };
  recomputeSelf();
}
function addRow(key: 'tire' | 'tube' | 'flap') {
  // 원래 순서(타이어→튜브→플랩) 유지하며 복원
  ROWS.value = ALL_ROWS.filter(a => a.key === key || ROWS.value.some(r => r.key === a.key));
}
function addPromo(i: number) { companies.value[i].promos.push({ desc: '', rate: 0 }); }
function delPromo(i: number, pi: number) { companies.value[i].promos.splice(pi, 1); }
// ── 제품 검색·연결 (자사 3개 행) ─────────────────────────────────────────────
// 드롭다운은 바깥 클릭 시에만 닫힘(blur 타이밍 이슈 회피) — 콤보박스에 data-pick 표시.
const openKey = ref<string | null>(null);
function onPickOutside(e: MouseEvent) {
  if (openKey.value && !(e.target as HTMLElement).closest?.('[data-pick]')) openKey.value = null;
}
function rowItems(key: 'tire' | 'tube' | 'flap', it: string): boolean {
  const u = it.toUpperCase();
  return key === 'tire' ? TIRE_CATS.has(u) : key === 'tube' ? u === 'TUBE' : u === 'FLAP';
}
// 구분자(./-/공백/* 등) 무시 정규화 — 'ASC 10.00-20TR78' ↔ '10.00R20', '1000 20 tr78' 등 표기 차이 흡수
const normTok = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');
function suggestions(key: 'tire' | 'tube' | 'flap', query: string): Product[] {
  const toks = (query ?? '').trim().toLowerCase().split(/\s+/).filter(Boolean);
  return products.value
    .filter(p => rowItems(key, p.item ?? ''))
    .filter(p => {
      const hay  = (p.description + ' ' + (p.sku ?? '')).toLowerCase();
      const nhay = normTok(hay);
      return toks.every(t => hay.includes(t) || (normTok(t) && nhay.includes(normTok(t))));
    })
    .slice(0, 12);
}
function setLanded(c: Company) {
  const s = ROWS.value.reduce((a, r) => a + (c[r.key].wh || 0), 0);
  if (s) c.landed = s;   // 자사 원가(set) = 3개 품목 wh 합
}
// 세트 소계 마진율 = (소계 − 원가 wh 합) ÷ 소계 (자사 · 제품 선택된 경우만)
function setMarginR(c: Company): number | null {
  const s = sub(c);
  const w = ROWS.value.reduce((a, r) => a + (c[r.key].wh || 0), 0);
  return s > 0 && w > 0 ? (s - w) / s * 100 : null;
}
function choose(c: Company, key: 'tire' | 'tube' | 'flap', p: Product) {
  const wh  = p.wh_price || p.wh_price_set || 0;
  const cat = catOf(p.item, p.description);
  const it  = c[key];
  it.code = p.description; it.brand = p.brand ?? ''; it.wh = wh; it.cat = cat;
  it.price = (wh && cat) ? sellFrom(wh, cat, gradeIdx.value) : Math.round(wh);
  setLanded(c);
  openKey.value = null;
}
// 고객등급 변경 → 자사 판매가·원가 재계산 (product 로 채운 행만)
function recomputeSelf() {
  for (const c of companies.value) {
    if (!c.self) continue;
    for (const r of ROWS.value) { const it = c[r.key]; if (it.wh && it.cat) it.price = sellFrom(it.wh, it.cat, gradeIdx.value); }
    setLanded(c);
  }
}
async function loadProducts() {
  if (!isPrivileged) return;   // 원가(wh_price) 조회는 super_admin/staff 만 (products RLS)
  try {
    products.value = await sbGet<Product[]>(
      'products?select=id,item,brand,description,sku,wh_price,wh_price_set,unit&is_active=eq.true&order=item.asc,description.asc',
    );
  } catch { products.value = []; }
}

function resetNew() {
  form.value = { createdDate: today, customer: '', grade: GRADES[2], basis: 'excl' };
  companies.value = defaultCompanies();
  ROWS.value = [...ALL_ROWS];
  currentId.value = null; currentNo.value = null;
}

// ── 저장 / 불러오기 (Quote 패턴) ─────────────────────────────────────────────
const isSaving = ref(false);
const showLoad = ref(false);
const loadList = ref<Array<{ id: string; compare_no: string | null; customer_name: string | null; created_date: string; updated_at: string }>>([]);
const loadSearch = ref('');
const modalLoading = ref(false);

const filteredLoad = computed(() => {
  const q = loadSearch.value.trim().toLowerCase();
  if (!q) return loadList.value;
  return loadList.value.filter(r =>
    (r.customer_name ?? '').toLowerCase().includes(q) || (r.compare_no ?? '').toLowerCase().includes(q));
});

async function save() {
  if (!canSaveImport) return;
  isSaving.value = true;
  try {
    const header = {
      customer_name:  form.value.customer || null,
      customer_grade: form.value.grade,
      ppn_rate:       PPN_RATE,
      ppn_basis:      form.value.basis,
      created_date:   form.value.createdDate,
      status:         'draft',
    };
    let id = currentId.value;
    if (id) {
      await sbPatch(`price_comparisons?id=eq.${id}`, header);
      await sbDelete(`price_comparison_columns?comparison_id=eq.${id}`); // cascade → promos
    } else {
      const no  = await sbRpc<string>('next_compare_number');
      const ins = await sbPost<Array<{ id: string; compare_no: string }>>('price_comparisons', { ...header, compare_no: no });
      id = ins[0].id; currentId.value = id; currentNo.value = ins[0].compare_no;
    }

    const colRows = companies.value.map((c, idx) => ({
      comparison_id: id, col_no: idx, is_self: c.self, company_name: c.name,
      tire_price: c.tire.price, tube_price: c.tube.price, flap_price: c.flap.price,
      tire_code: c.tire.code || null, tube_code: c.tube.code || null, flap_code: c.flap.code || null,
      tire_brand: c.tire.brand || null, tube_brand: c.tube.brand || null, flap_brand: c.flap.brand || null,
      apply_ppn: c.ppn,
      landed_cost: c.landed,
    }));
    const cols = await sbPost<Array<{ id: string; col_no: number }>>('price_comparison_columns', colRows);
    const idByNo = new Map(cols.map(c => [c.col_no, c.id]));

    const promoRows = companies.value.flatMap((c, idx) =>
      c.promos.filter(p => (p.desc && p.desc.trim()) || p.rate).map((p, pi) => ({
        column_id: idByNo.get(idx), promo_no: pi, description: p.desc || null, discount_rate: p.rate || 0,
      })));
    if (promoRows.length) await sbPost('price_comparison_promos', promoRows);

    if (currentId.value) router.replace(`/price-compare/${currentId.value}`);
    toast.success(`저장 완료 · ${currentNo.value ?? ''}`);
  } catch (e) {
    toast.error(e instanceof Error ? e.message : String(e));
  } finally {
    isSaving.value = false;
  }
}

async function openLoad() {
  if (!canSaveImport) return;
  showLoad.value = true; loadSearch.value = ''; modalLoading.value = true;
  try {
    loadList.value = await sbGet(
      'price_comparisons?select=id,compare_no,customer_name,created_date,updated_at&order=updated_at.desc',
    );
  } catch { loadList.value = []; }
  modalLoading.value = false;
}

async function loadCompare(id: string) {
  try {
    type Hdr = { id: string; compare_no: string; customer_name: string | null; customer_grade: string | null; ppn_basis: 'excl' | 'incl'; created_date: string };
    type Pr  = { promo_no: number; description: string | null; discount_rate: number };
    type Col = { id: string; col_no: number; is_self: boolean; company_name: string | null; tire_price: number; tube_price: number; flap_price: number; tire_code: string | null; tube_code: string | null; flap_code: string | null; tire_brand: string | null; tube_brand: string | null; flap_brand: string | null; apply_ppn: boolean | null; landed_cost: number; price_comparison_promos: Pr[] };
    // 컬럼 + 임베딩 프로모션을 한 번에 조회 (PostgREST 관계 임베딩)
    const [hArr, colArr] = await Promise.all([
      sbGet<Hdr[]>(`price_comparisons?id=eq.${id}&select=*`),
      sbGet<Col[]>(`price_comparison_columns?comparison_id=eq.${id}&select=*,price_comparison_promos(promo_no,description,discount_rate)&order=col_no.asc`),
    ]);
    const h = hArr[0]; if (!h) { toast.error('항목을 찾을 수 없습니다'); return; }
    form.value = {
      createdDate: h.created_date, customer: h.customer_name ?? '',
      grade: normGrade(h.customer_grade), basis: h.ppn_basis ?? 'excl',
    };
    companies.value = colArr.map(col => {
      const promos: Promo[] = [...(col.price_comparison_promos ?? [])]
        .sort((a, b) => a.promo_no - b.promo_no)
        // 자사 프리셋 프로모션(수량/현금/배송 할인)은 desc 매칭으로 최대치(max) 복원
        .map(p => ({ desc: p.description ?? '', rate: p.discount_rate, max: col.is_self ? selfPromoMax(p.description ?? '') : undefined }));
      return {
        name: col.company_name ?? '', self: col.is_self,
        tire: { price: col.tire_price, code: col.tire_code ?? '', brand: col.tire_brand ?? '' },
        tube: { price: col.tube_price, code: col.tube_code ?? '', brand: col.tube_brand ?? '' },
        flap: { price: col.flap_price, code: col.flap_code ?? '', brand: col.flap_brand ?? '' },
        landed: col.landed_cost, promos: promos.length ? promos : (col.is_self ? SELF_PROMOS.map(p => ({ ...p })) : [{ desc: '', rate: 0 }]),
        ppn: col.is_self ? true : (col.apply_ppn ?? true),
      };
    });
    // 자사 행: 저장된 code(description)로 제품 매칭 → wh/cat 복원(등급 변경 시 재계산 가능)
    for (const c of companies.value) {
      if (!c.self) continue;
      for (const r of ROWS.value) {
        const p = products.value.find(pr => pr.description === c[r.key].code);
        if (p) { c[r.key].wh = p.wh_price || p.wh_price_set || 0; c[r.key].cat = catOf(p.item, p.description); }
      }
    }
    ROWS.value = [...ALL_ROWS];   // 불러오기 시 품목 행 전체 복원
    currentId.value = h.id; currentNo.value = h.compare_no;
    showLoad.value = false;
  } catch (e) {
    toast.error(e instanceof Error ? e.message : String(e));
  }
}

async function removeCompare(id: string) {
  try {
    await sbDelete(`price_comparisons?id=eq.${id}`);  // cascade columns/promos
    loadList.value = loadList.value.filter(r => r.id !== id);
    if (currentId.value === id) resetNew();
  } catch (e) { toast.error(e instanceof Error ? e.message : String(e)); }
}

// ── 인쇄 (Quote 패턴: 문서 제목 규칙) ────────────────────────────────────────
function handlePrint() {
  const d = new Date(form.value.createdDate + 'T00:00:00');
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  const abbr = form.value.customer.trim().split(/\s+/).map(w => w[0]?.toUpperCase() ?? '').join('').slice(0, 3);
  const prev = document.title;
  document.title = abbr ? `PC-${abbr}-${dd}${mm}${yyyy}` : `PC-${dd}${mm}${yyyy}`;
  window.print();
  document.title = prev;
}

// ── 라우트 :id 로드 ──────────────────────────────────────────────────────────
const route = useRoute();
const router = useRouter();
onMounted(async () => { window.addEventListener('click', onPickOutside); await loadProducts(); if (route.params.id) void loadCompare(String(route.params.id)); });
onUnmounted(() => window.removeEventListener('click', onPickOutside));
watch(() => route.params.id, (id) => { if (!id) resetNew(); else void loadCompare(String(id)); });
watch(() => form.value.grade, recomputeSelf);   // 고객등급 변경 → 자사 판매가 재계산
</script>

<template>
  <div class="p-6 space-y-4 max-w-300 mx-auto">
    <PageHeader title="가격비교" subtitle="타이어 세트(타이어+튜브+플랩) · 동일 고객등급 기준">
      <template #actions>
        <div class="flex items-center gap-2 print:hidden flex-wrap">
          <button class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors" @click="resetNew">
            <FileText :size="12" /> 새로 작성
          </button>
          <button v-if="canSaveImport" class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors" @click="openLoad">
            <FolderOpen :size="12" /> 불러오기
          </button>
          <button v-if="canSaveImport" class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-primary/10 text-primary border border-primary/20 hover:bg-primary/20 transition-colors disabled:opacity-50" :disabled="isSaving" @click="save">
            <Save :size="12" /> {{ isSaving ? '저장 중…' : '저장' }}
          </button>
          <button class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors" @click="handlePrint">
            <Printer :size="12" /> 인쇄
          </button>
        </div>
      </template>
    </PageHeader>

    <!-- 인쇄 전용 제목 -->
    <div class="hidden print:block text-center">
      <h1 class="text-lg font-bold">타이어 세트 가격 비교</h1>
      <p v-if="currentNo" class="text-xs text-muted-foreground">{{ currentNo }}</p>
    </div>

    <!-- 문서 정보 + 컨트롤 (1행 · 문서 정보는 행의 50%) -->
    <div class="flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-4">
      <!-- 라벨을 입력창 내부(왼쪽)에 표시 -->
      <div class="flex items-center gap-3 w-full lg:w-1/2">
        <label class="flex items-center gap-2 h-9 bg-muted border border-border rounded-lg px-2 shrink-0 focus-within:ring-1 focus-within:ring-primary">
          <span class="text-[11px] font-semibold text-muted-foreground whitespace-nowrap">작성일</span>
          <input v-model="form.createdDate" type="date" class="bg-transparent text-xs focus:outline-none" />
        </label>
        <label class="flex items-center gap-2 h-9 bg-muted border border-border rounded-lg px-2 flex-1 min-w-32 focus-within:ring-1 focus-within:ring-primary">
          <span class="text-[11px] font-semibold text-muted-foreground whitespace-nowrap">고객명</span>
          <input v-model="form.customer" type="text" placeholder="PT. ___" class="w-full bg-transparent text-xs focus:outline-none" />
        </label>
        <label class="flex items-center gap-2 h-9 bg-muted border border-border rounded-lg px-2 shrink-0 focus-within:ring-1 focus-within:ring-primary">
          <span class="text-[11px] font-semibold text-muted-foreground whitespace-nowrap">고객등급</span>
          <select v-model="form.grade" class="bg-transparent text-xs focus:outline-none">
            <option v-for="g in GRADES" :key="g" :value="g">{{ g }}</option>
          </select>
        </label>
      </div>
      <div class="flex items-center gap-2 h-9 ml-auto print:hidden">
        <!-- 삭제된 품목 복원 -->
        <button
          v-for="rr in removedRows" :key="rr.key"
          class="inline-flex items-center gap-1 text-xs px-2.5 py-1.5 rounded-lg border border-dashed border-border text-muted-foreground hover:bg-accent transition-colors whitespace-nowrap"
          @click="addRow(rr.key)"
        >
          <Plus :size="12" /> {{ rr.label }}
        </button>
        <button class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-primary/10 text-primary border border-primary/20 hover:bg-primary/20 transition-colors whitespace-nowrap" @click="addCompetitor">
          <Plus :size="12" /> 경쟁사 추가
        </button>
      </div>
    </div>

    <!-- 비교표 -->
    <div class="rounded-xl border border-border bg-card overflow-x-auto">
      <table class="w-full text-sm border-collapse min-w-180">
        <thead>
          <tr>
            <th class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-left text-xs font-semibold w-52">항목</th>
            <th
              v-for="(c, i) in companies" :key="i"
              class="border border-border px-3 py-2 text-center"
              :class="c.self ? 'bg-emerald-500/10' : 'bg-primary/5'"
            >
              <!-- 회사명 + 삭제 1행 -->
              <div class="flex items-center justify-center gap-1.5">
                <input v-model="c.name" class="min-w-0 bg-transparent text-center text-sm font-bold focus:outline-none" />
                <button v-if="!c.self" class="print:hidden shrink-0 text-muted-foreground hover:text-red-500" title="열 삭제" @click="delCompany(i)"><X :size="12" /></button>
              </div>
            </th>
          </tr>
        </thead>
        <tbody>
          <!-- 품목 행 (삭제 가능) -->
          <tr v-for="r in ROWS" :key="r.key">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-left text-xs font-semibold whitespace-nowrap">
              <div class="flex items-center justify-between gap-2">
                <span>{{ r.label }}</span>
                <button class="print:hidden text-muted-foreground hover:text-red-500" title="품목 삭제" @click="delRow(r.key)"><X :size="12" /></button>
              </div>
            </td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2">
              <!-- 한 줄 배치(자사·경쟁사 동일): 브랜드 → 품목/사양 코드 → 가격(Rp) → 마진. 좁으면 자동 줄바꿈 -->
              <div class="flex flex-wrap items-center justify-end gap-x-2 gap-y-1">
                <!-- 브랜드 -->
                <input
                  v-model="c[r.key].brand" type="text" placeholder="브랜드"
                  class="w-24 min-w-20 bg-transparent text-left text-[11px] text-muted-foreground border border-transparent hover:border-border focus:border-primary rounded px-1 py-0.5 focus:outline-none"
                />
                <!-- 품목/사양 코드 : 자사(권한자)=제품 검색(Description) / 그 외=수동 입력 -->
                <div v-if="c.self && isPrivileged" data-pick class="relative flex-1 min-w-36 print:hidden">
                  <input
                    v-model="c[r.key].code" type="text" placeholder="제품 검색"
                    class="w-full bg-transparent text-left text-[11px] border border-transparent hover:border-border focus:border-primary rounded px-1 py-0.5 focus:outline-none"
                    @focus="openKey = i + ':' + r.key" @click.stop
                  />
                  <ul
                    v-if="openKey === i + ':' + r.key && suggestions(r.key, c[r.key].code).length"
                    class="absolute left-0 mt-1 w-64 max-h-56 overflow-auto rounded-lg border border-border bg-card shadow-xl text-left z-30"
                  >
                    <li
                      v-for="p in suggestions(r.key, c[r.key].code)" :key="p.id"
                      class="px-2.5 py-1.5 hover:bg-accent cursor-pointer border-b border-border/40 last:border-0"
                      @mousedown.prevent="choose(c, r.key, p)"
                    >
                      <div class="text-[11px] font-medium truncate">{{ p.description }}</div>
                      <div class="text-[10px] text-muted-foreground tabular-nums">원가 {{ fmt(p.wh_price || p.wh_price_set || 0) }} · {{ p.item }}</div>
                    </li>
                  </ul>
                </div>
                <input
                  v-else
                  v-model="c[r.key].code" type="text" placeholder="품목/사양 코드"
                  class="flex-1 min-w-36 bg-transparent text-left text-[11px] text-muted-foreground border border-transparent hover:border-border focus:border-primary rounded px-1 py-0.5 focus:outline-none"
                />
                <!-- 자사 코드 인쇄용 표시 (검색 input 은 print:hidden) -->
                <span v-if="c.self && isPrivileged" class="hidden print:block flex-1 text-left text-[11px] text-muted-foreground">{{ c[r.key].code }}</span>
                <!-- 가격 (Rp 접두 · 자사=자동계산·수정가능 / 경쟁사=수동) -->
                <div class="flex items-center gap-1 shrink-0">
                  <span class="text-[11px] text-muted-foreground">Rp</span>
                  <input
                    :value="idFmt(c[r.key].price)" @input="setNum(c[r.key], 'price', ($event.target as HTMLInputElement).value)"
                    type="text" inputmode="numeric" placeholder="0"
                    class="w-24 bg-transparent text-right text-sm font-semibold tabular-nums border border-transparent hover:border-border focus:border-primary rounded px-1 py-0.5 focus:outline-none"
                  />
                </div>
                <!-- 자사 마진 배지 (내부용) -->
                <span v-if="c.self && isPrivileged && c[r.key].wh && c[r.key].cat" class="print:hidden text-[10px] text-muted-foreground whitespace-nowrap">
                  마진 {{ (marginFor(c[r.key].cat!, gradeIdx) * 100).toFixed(1) }}%
                </span>
              </div>
            </td>
          </tr>

          <!-- 세트 소계 -->
          <tr class="bg-muted/50">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold">세트 소계</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 text-right tabular-nums font-semibold">
              {{ fmt(sub(c)) }}
              <span v-if="c.self && isPrivileged && setMarginR(c) != null" class="print:hidden ml-1 text-[10px] font-normal text-muted-foreground">마진 {{ setMarginR(c)!.toFixed(1) }}%</span>
            </td>
          </tr>
          <!-- 프로모션 -->
          <tr>
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold align-top">
              프로모션<br /><span class="text-[10px] text-muted-foreground font-normal">순차 할인 적용</span>
            </td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 align-top">
              <div class="flex flex-col gap-2 min-w-50">
                <!-- 할인내용 → 할인금액(직전 잔액 기준 순차 계산) → 할인율(%) 1행 -->
                <div v-for="(p, pi) in c.promos" :key="pi" class="flex items-center gap-1.5 rounded-lg border border-border bg-muted/40 p-1.5">
                  <input v-model="p.desc" type="text" placeholder="예) 현금할인" class="flex-1 min-w-24 text-xs bg-card border border-border rounded px-1.5 py-1 focus:outline-none focus:ring-1 focus:ring-primary" />
                  <span class="w-24 text-right text-xs tabular-nums text-amber-600 dark:text-amber-500 shrink-0">{{ pRate(p) > 0 ? '- ' + fmt(promoAmts(c)[pi]) : '-' }}</span>
                  <input v-model.number="p.rate" type="number" min="0" :max="p.max" :title="p.max != null ? `최대 ${p.max}%` : undefined" class="w-14 text-right text-xs bg-card border border-border rounded px-1.5 py-1 tabular-nums focus:outline-none focus:ring-1 focus:ring-primary" @input="clampPromo(p)" />
                  <span class="text-[10px] text-muted-foreground whitespace-nowrap">% <template v-if="p.max != null">/ {{ p.max }}</template></span>
                  <button v-if="c.promos.length > 1" class="print:hidden text-[10px] text-muted-foreground hover:text-red-500 shrink-0" title="삭제" @click="delPromo(i, pi)">✕</button>
                </div>
                <button class="print:hidden text-xs px-2 py-1 rounded border border-border hover:bg-accent transition-colors" @click="addPromo(i)">+ 프로모션 추가</button>
              </div>
            </td>
          </tr>
          <!-- 총 할인 -->
          <tr class="text-amber-600 dark:text-amber-500">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold">총 할인</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 text-right tabular-nums font-semibold">
              {{ hasDisc(c) ? `- ${fmt(discAmt(c))} (${effRate(c).toFixed(1)}%)` : '-' }}
            </td>
          </tr>
          <!-- 할인후 합계 -->
          <tr class="bg-muted/50">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold">할인후 합계</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 text-right tabular-nums font-semibold">{{ fmt(afterDisc(c)) }}</td>
          </tr>
          <!-- PPN (경쟁사는 적용/미적용 선택) -->
          <tr class="text-muted-foreground">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs">PPN {{ (PPN_RATE * 100).toFixed(1) }}%</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2">
              <div class="flex items-center justify-end gap-2">
                <div v-if="!c.self" class="print:hidden inline-flex rounded-md border border-border overflow-hidden text-[10px]">
                  <button class="px-2 py-0.5 transition-colors" :class="c.ppn ? 'bg-primary/15 text-primary font-semibold' : 'text-muted-foreground hover:bg-accent'" @click="c.ppn = true">적용</button>
                  <button class="px-2 py-0.5 transition-colors" :class="!c.ppn ? 'bg-primary/15 text-primary font-semibold' : 'text-muted-foreground hover:bg-accent'" @click="c.ppn = false">미적용</button>
                </div>
                <span class="text-right tabular-nums">{{ c.ppn ? fmt(ppnAmt(c)) : '미적용' }}</span>
              </div>
            </td>
          </tr>

          <!-- 최종 판매가 + 차액 -->
          <tr class="bg-emerald-500/10">
            <td class="sticky left-0 z-10 bg-primary text-primary-foreground border border-border px-3 py-2 text-xs font-bold">최종 판매가</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 text-right">
              <div class="tabular-nums font-bold text-base">{{ fmt(finalP(c)) }}</div>
              <div v-if="diff(c)" class="text-[11px] font-semibold mt-0.5" :class="diff(c)!.cheaper ? 'text-emerald-500' : 'text-amber-600'">
                {{ diff(c)!.d >= 0 ? '+' : '' }}{{ fmt(Math.abs(diff(c)!.d)).replace('Rp ', diff(c)!.d >= 0 ? 'Rp ' : '-Rp ') }}
                ({{ diff(c)!.d >= 0 ? '+' : '' }}{{ diff(c)!.pct.toFixed(1) }}% · {{ diff(c)!.label }})
              </div>
            </td>
          </tr>

          <!-- 내부 정보(권한자만): 원가(세트) · 마진금액 · 마진율 1행 -->
          <tr v-if="isPrivileged" class="bg-muted/30">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold">원가 · 마진</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2">
              <div class="flex flex-wrap items-center justify-end gap-x-3 gap-y-1 tabular-nums">
                <span class="flex items-center gap-1">
                  <span class="text-[10px] text-muted-foreground">원가</span>
                  <!-- 자사(제품 연결 시): 타이어 + 튜브 + 플랩 = 세트가격 분해 표시 -->
                  <span v-if="c.self && ROWS.some(r => c[r.key].wh)" class="text-[11px] text-muted-foreground tabular-nums whitespace-nowrap">
                    {{ ROWS.map(r => idFmt(c[r.key].wh || 0) || '0').join(' + ') }} =
                  </span>
                  <input :value="idFmt(c.landed)" @input="setNum(c, 'landed', ($event.target as HTMLInputElement).value)" type="text" inputmode="numeric" placeholder="0" class="w-24 bg-transparent text-right text-sm tabular-nums border border-transparent hover:border-border focus:border-primary rounded px-1 py-0.5 focus:outline-none" />
                </span>
                <span class="flex items-center gap-1">
                  <span class="text-[10px] text-muted-foreground">마진</span>
                  <span class="text-sm">{{ c.landed ? fmt(marginV(c)) : '-' }}</span>
                </span>
                <span v-if="c.landed && finalP(c) > 0" class="text-sm font-semibold" :class="marginClass(marginR(c))">{{ marginR(c).toFixed(1) }}%</span>
                <span v-else class="text-sm font-semibold">-</span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- 안내 -->
    <div class="rounded-xl border border-border bg-muted/20 p-4 text-[11px] text-muted-foreground space-y-1.5">
      <div class="flex flex-wrap gap-4">
        <span class="inline-flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-emerald-500/40 border border-emerald-500" /> 자사 (PT ASCENDO)</span>
        <span class="inline-flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-primary/20 border border-primary/40" /> 경쟁사</span>
        <span v-if="isPrivileged" class="inline-flex items-center gap-1.5"><span class="text-emerald-500 font-semibold">초록 차액</span> = 자사가 더 저렴</span>
      </div>
      <p>· 통화 IDR 단일, 부가세 PPN 11%. 최종 가격비교는 <b>동일 고객등급 기준</b>으로 작성(등급별 단가 상이).</p>
      <p>· 자사 3개 품목은 <b>제품 검색</b>으로 선택 → 고객등급 마진을 적용해 <b>판매가 자동 계산</b>(판매가 = 원가 ÷ (1−마진율), 등급 한 단계당 5%p). 프로모션은 다건 추가, <b>순차 할인</b>(직전 잔액에 차례로 적용).</p>
      <p v-if="isPrivileged">· 원가 입력 시 마진금액·마진율과 경쟁사 대비 차액 표시 (권한자 전용 · 비권한 사용자는 미노출).</p>
    </div>

    <!-- 불러오기 모달 -->
    <transition enter-active-class="transition-opacity duration-150" enter-from-class="opacity-0" leave-active-class="transition-opacity duration-150" leave-to-class="opacity-0">
      <div v-if="showLoad" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" @click.self="showLoad = false">
        <div class="bg-card border border-border rounded-2xl w-full max-w-lg max-h-[80vh] shadow-2xl flex flex-col overflow-hidden">
          <div class="flex items-center justify-between px-5 py-4 border-b border-border">
            <h3 class="font-semibold text-sm">저장된 가격비교 불러오기</h3>
            <button class="p-1 rounded hover:bg-accent text-muted-foreground" @click="showLoad = false"><X :size="16" /></button>
          </div>
          <div class="px-5 py-3 border-b border-border">
            <input v-model="loadSearch" type="text" placeholder="고객명 · 번호 검색" class="w-full h-9 bg-muted border border-border rounded-lg px-3 text-sm focus:outline-none focus:ring-1 focus:ring-primary" />
          </div>
          <div class="overflow-auto flex-1">
            <div v-if="modalLoading" class="p-6 text-center text-sm text-muted-foreground">불러오는 중…</div>
            <div v-else-if="!filteredLoad.length" class="p-6 text-center text-sm text-muted-foreground">저장된 항목이 없습니다.</div>
            <button
              v-for="r in filteredLoad" :key="r.id"
              class="w-full text-left px-5 py-3 border-b border-border/50 hover:bg-accent transition-colors flex items-center justify-between gap-3"
              @click="loadCompare(r.id)"
            >
              <div class="min-w-0">
                <p class="text-sm font-medium truncate">{{ r.customer_name || '(고객명 없음)' }}</p>
                <p class="text-xs text-muted-foreground font-mono">{{ r.compare_no }} · {{ r.created_date }}</p>
              </div>
              <span class="p-1.5 rounded hover:bg-red-500/10 text-muted-foreground hover:text-red-500 shrink-0" title="삭제" @click.stop="removeCompare(r.id)"><Trash2 :size="14" /></span>
            </button>
          </div>
        </div>
      </div>
    </transition>

  </div>
</template>

<style scoped>
@media print {
  @page { size: A4 landscape; margin: 12mm; }
  :deep(.rounded-xl) { break-inside: avoid; }
}
</style>
