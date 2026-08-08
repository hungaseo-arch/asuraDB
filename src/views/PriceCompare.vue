<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Plus, Printer, Save, FolderOpen, X, FileText, Trash2 } from 'lucide-vue-next';
import { toast } from 'vue-sonner';
import { sbGet, sbPost, sbPatch, sbDelete, sbRpc } from '@/lib/supabase';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/ui/DataState.vue';
import { errMsg } from '@/lib/utils';

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
interface Product { id: string; item: string | null; brand: string | null; description: string; sku: string | null; wh_price_pcs: number; wh_price_set: number; dist_price_pcs: number | null; unit: string }
const products = ref<Product[]>([]);

// ── 자동 판매가 기준 (2026-08-04: 대리점가(pcs) 기준으로 전환) ────────────────
// 자동 판매가는 DB 대리점가(dist_price_pcs, VAT 포함 저장 → 세전 환산)에서 기준 마진을 역산해 쓴다.
// 아래 카테고리 마진율표(마진율표 2026-07-09)는 **대리점가가 없는 제품의 대체값**으로만 쓰인다.
// 카테고리 = products.item (타이어) · TUBE/FLAP(+description 키워드로 STD/HD·STD/MP 판별).
const TIRE_CATS = new Set(['LTR', 'TBR', 'LTB', 'TBB', 'OTR', 'AGR', 'PNEU', 'SOLID']);
const MARGIN_BASE: Record<string, number> = {
  LTR: 0.20, TBR: 0.25, LTB: 0.20, TBB: 0.25, OTR: 0.30, AGR: 0.30, PNEU: 0.25, SOLID: 0.25,
  TUBE_STD: 0.20, TUBE_HD: 0.30,
  FLAP_STD: 0.35, FLAP_MP: 0.40,
};
// products.item 표기 → 마진표 카테고리. DB 는 'PNEUMATIC', 마진표·화면은 'PNEU' 로 같은 항목이다.
const ITEM_ALIAS: Record<string, string> = { PNEUMATIC: 'PNEU' };
function catOf(item: string | null, desc: string): string | null {
  const raw = (item ?? '').toUpperCase();
  const it = ITEM_ALIAS[raw] ?? raw;
  const d  = desc.toUpperCase();
  if (it === 'TUBE') return /HEAVY DUTY|\bHD\b/.test(d) ? 'TUBE_HD' : 'TUBE_STD';
  if (it === 'FLAP') return /METAL PLATE|\bMP\b/.test(d) ? 'FLAP_MP' : 'FLAP_STD';
  return TIRE_CATS.has(it) ? it : null;
}
const DIST_IDX = 1;   // 대리점 = GRADES[1] (기준 등급)
const gradeIdx = computed(() => { const i = GRADES.indexOf(form.value.grade); return i < 0 ? DIST_IDX : i; });
// 기준 마진(대리점 등급) — 제품에 대리점가(pcs)가 있으면 실제 값(1 − 원가 ÷ 대리점가 세전)으로 역산해 쓰고,
// 없는 제품만 카테고리 마진표(MARGIN_BASE)로 대체한다. (2026-08-04: 마진표 일괄 30~45% → 대리점가 기준 전환)
function baseMargin(it: Item): number | null {
  if (it.wh && it.dist && it.dist > it.wh) return 1 - it.wh / it.dist;
  const base = it.cat ? MARGIN_BASE[it.cat] : undefined;
  return base ?? null;
}
// 등급 마진율 = 기준 마진 + 5%p × (등급 스텝). 0~0.95 로 클램프.
const gradeMargin = (base: number, gi: number) => Math.min(0.95, Math.max(0, base + 0.05 * (gi - DIST_IDX)));
// 자동 판매가 = 원가 ÷ (1−등급 마진). 대리점 등급이면 DB 대리점가(pcs) 그대로가 된다.
// 표기 기준이 'VAT 포함'이면 PPN 11% 를 가산해 반올림.
function priceOf(it: Item, gi: number): number {
  const b = baseMargin(it);
  const net = it.wh ? (b != null ? it.wh / (1 - gradeMargin(b, gi)) : it.wh) : 0;
  return Math.round(form.value.basis === 'incl' ? net * (1 + PPN_RATE) : net);
}
// 마진 배지(%): 현재 입력된 판매가 기준 실제 마진 = (판매가 세전 − 원가) ÷ 판매가 세전.
// 자동 계산가면 등급 마진과 같고, 단가를 손으로 고치면 그 값의 실제 마진(음수 = 원가 이하)이 나온다.
function marginPct(it: Item): number | null {
  if (!it.wh || !it.price) return null;
  const net = form.value.basis === 'incl' ? it.price / (1 + PPN_RATE) : it.price;
  return net > 0 ? ((net - it.wh) / net) * 100 : null;
}

// ── 부가세 표기 기준 토글 (시트 전체) ────────────────────────────────────────
// 'excl' = 품목 단가·세트 소계가 VAT 별도(PPN 행에서 11% 가산) / 'incl' = VAT 포함(PPN 행은 포함분 분리 표시).
// 전환 시 입력돼 있던 단가를 환산해 두 기준의 최종 판매가가 같도록 유지한다.
// 자사 제품 연결 행은 원가(wh)에서 재계산(반올림 누적 방지), 경쟁사 수동 단가는 ×/÷1.11 환산,
// PPN 미적용(c.ppn=false) 경쟁사 열은 부가세와 무관하므로 환산하지 않는다.
const VAT_MODES = [
  { key: 'excl', label: 'VAT 별도' },
  { key: 'incl', label: 'VAT 포함' },
] as const;
const basisLabel = computed(() => (form.value.basis === 'incl' ? 'VAT 포함' : 'VAT 별도'));
function setBasis(mode: 'excl' | 'incl') {
  if (form.value.basis === mode) return;
  form.value.basis = mode;
  for (const c of companies.value) {
    for (const r of ROWS.value) {
      const it = c[r.key];
      if (c.self && it.wh && baseMargin(it) != null) { it.price = priceOf(it, gradeIdx.value); continue; }
      if (!it.price || !c.ppn) continue;
      it.price = Math.round(mode === 'incl' ? it.price * (1 + PPN_RATE) : it.price / (1 + PPN_RATE));
    }
  }
}

// ── 타입 ────────────────────────────────────────────────────────────────────
// dist = DB 대리점가(pcs)의 세전 환산값(÷1.11) — 자동 판매가의 기준 마진 역산에 사용
interface Item { price: number; code: string; brand: string; wh?: number; dist?: number; cat?: string | null }
// max = 권고 최대 할인율(%) · auto = 목표 최종가 맞추기용 자동 프로모션(할인율 자동 계산)
interface Promo { desc: string; rate: number; max?: number; auto?: boolean }
const AUTO_DESC = '가격 조정 할인';

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
  finalOv: string;   // 경쟁사 최종 판매가 직접입력(콤마 문자열). '' = 자동계산
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
      landed: 0, promos: SELF_PROMOS.map(p => ({ ...p })), ppn: true, finalOv: '',
    },
    {
      name: '', self: false,   // 빈칸 → 추천값(상단 고객명, 없으면 '경쟁사 A') 표시
      tire: { price: 0, code: '', brand: '' }, tube: { price: 0, code: '', brand: '' }, flap: { price: 0, code: '', brand: '' },
      landed: 0, promos: [{ desc: '', rate: 0 }], ppn: true, finalOv: '',
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
// 할인 방식 선택 — 순차(각 할인율을 직전 잔액에 차례로 적용) / 합계(모든 할인율을 소계 기준으로 합산)
const DISC_MODES = [
  { key: 'seq', label: '순차 할인' },
  { key: 'sum', label: '합계 할인' },
] as const;
const discMode = ref<'seq' | 'sum'>('seq');
const clampR = (r: number) => Math.min(100, Math.max(0, +r || 0));
// 적용 할인율 = 입력값(0~100%). max 는 하드 제한이 아닌 권고치이므로 초과분도 그대로 반영.
// 자동 프로모션(목표가 역산)만 음수 허용 = 목표가가 계산가보다 높은 경우의 가격 인상분.
const pRate  = (p: Promo) => p.auto ? Math.min(100, Math.max(-100, +p.rate || 0)) : clampR(p.rate);
// 권고 최대치(max) 초과 여부 → 입력칸 경고 표시용
const pOver  = (p: Promo) => p.max != null && clampR(p.rate) > p.max;
// 프로모션별 할인금액 배열 — 순차: i번째 = 직전 잔액 × 할인율 / 합계: 전부 소계 × 할인율
function promoAmts(c: Company): number[] {
  const s = sub(c);
  if (discMode.value === 'sum') return c.promos.map(p => s * pRate(p) / 100);
  let run = s;
  return c.promos.map(p => { const a = run * pRate(p) / 100; run -= a; return a; });
}
const discAmt  = (c: Company) => promoAmts(c).reduce((a, v) => a + v, 0);
const hasDisc  = (c: Company) => c.promos.some(p => pRate(p) !== 0);
// 입력 완료(blur) 시 0~100% 범위만 보정. 권고치(max) 초과는 경고만 하고 값은 유지.
function clampPromo(p: Promo) {
  const r = +p.rate;
  if (!isFinite(r) || r < 0) p.rate = 0;
  else if (r > 100) p.rate = 100;
}
// 할인후 합계 (부가세 전)
const afterDisc = (c: Company) => sub(c) - discAmt(c);
// basis 'excl'(기본): 할인후 합계에 PPN 가산 / 'incl': 이미 포함된 PPN 분리 표시
// 경쟁사는 열별 PPN 미적용 선택 가능 (c.ppn=false → PPN 0)
const ppnAmt = (c: Company) => !c.ppn ? 0 : form.value.basis === 'excl' ? afterDisc(c) * PPN_RATE : afterDisc(c) - afterDisc(c) / (1 + PPN_RATE);
// 품목단가 → 할인 → PPN 순으로 산출한 최종 판매가(자동계산값)
const calcFinal = (c: Company) => !c.ppn || form.value.basis !== 'excl' ? afterDisc(c) : afterDisc(c) * (1 + PPN_RATE);
// 실효 할인율(순차 적용 합산 결과)
const effRate = (c: Company) => { const s = sub(c); return s > 0 ? discAmt(c) / s * 100 : 0; };
// ── 최종 판매가 직접입력(목표가) ─────────────────────────────────────────────
// 목표 최종가를 입력하면 그 가격에 맞도록 '가격 조정 할인' 프로모션이 자동 추가된다(syncAutoPromo).
// 예외: 품목단가 없이 총액만 받은 경쟁사 열(소계 0)은 할인율로 환산할 기준이 없어 목표가를 최종가로 그대로 사용.
const ovNum  = (c: Company) => { const d = (c.finalOv || '').replace(/[^\d]/g, ''); return d ? Number(d) : 0; };
const hasOv  = (c: Company) => ovNum(c) > 0;
const isLump = (c: Company) => hasOv(c) && sub(c) <= 0;
const finalP = (c: Company) => isLump(c) ? ovNum(c) : calcFinal(c);
// 총액 입력 열의 표시용 역산: 최종가 → 할인후 합계(세전) / PPN 분리
const shownAfterDisc = (c: Company) => !isLump(c) ? afterDisc(c)
  : (c.ppn && form.value.basis === 'excl' ? finalP(c) / (1 + PPN_RATE) : finalP(c));
const shownPpn = (c: Company) => !isLump(c) ? ppnAmt(c)
  : (!c.ppn ? 0 : finalP(c) - finalP(c) / (1 + PPN_RATE));
// 목표가 미달(할인율 0~100% 범위로 맞출 수 없는 경우) → 입력칸 경고 표시용
const ovMiss = (c: Company) => hasOv(c) && !isLump(c) && Math.abs(calcFinal(c) - ovNum(c)) >= 1;
// 목표 최종가에 맞추는 자동 프로모션 동기화.
// 순차 할인이므로 수동 프로모션까지 적용한 잔액(base) 기준 비율로 계산하고, 항상 마지막 순서를 유지한다.
// 목표가 삭제·소계 0 이면 자동 프로모션도 제거. 계산 결과가 같으면 쓰지 않으므로 watch 재진입은 즉시 수렴한다.
function syncAutoPromo(c: Company) {
  const manual = c.promos.filter(p => !p.auto);
  const auto   = c.promos.find(p => p.auto);
  if (!hasOv(c) || sub(c) <= 0) {
    if (auto) c.promos = manual;
    return;
  }
  const s = sub(c);
  // 수동 프로모션 적용 후 잔액 — 순차: 복리 / 합계: 소계 기준 합산
  const base = discMode.value === 'sum'
    ? s - manual.reduce((a, p) => a + s * pRate(p) / 100, 0)
    : manual.reduce((run, p) => run - run * pRate(p) / 100, s);
  // 목표 최종가 → 세전(할인후 합계) 환산: PPN 별도(excl)면 나눠서 제거
  const targetAfter = c.ppn && form.value.basis === 'excl' ? ovNum(c) / (1 + PPN_RATE) : ovNum(c);
  // 자동 할인율의 기준 금액 — 순차: 직전 잔액 / 합계: 소계. 음수 = 목표가가 계산가보다 높음(가격 인상분).
  const denom = discMode.value === 'sum' ? s : base;
  const rate = denom > 0 ? Math.min(100, Math.max(-100, (base - targetAfter) / denom * 100)) : 0;
  if (!auto) c.promos = [...manual, { desc: AUTO_DESC, rate, auto: true }];
  else if (Math.abs(auto.rate - rate) > 1e-9) auto.rate = rate;
}
// 품목단가·프로모션·PPN·목표가 변경 시 자동 프로모션 재계산 (자사 판매가 재계산 후에도 목표가 유지)
watch([companies, () => form.value.basis, discMode], () => { for (const c of companies.value) syncAutoPromo(c); }, { deep: true, flush: 'post' });

const marginV  = (c: Company) => finalP(c) - (+c.landed || 0);
const marginR  = (c: Company) => { const f = finalP(c); return f > 0 ? marginV(c) / f * 100 : 0; };

const selfCompany = computed(() => companies.value.find(c => c.self) ?? companies.value[0]);
const selfFinal   = computed(() => finalP(selfCompany.value));

// 경쟁사 대비 차액 (자사 기준). d>0 = 경쟁사가 더 비쌈 = 자사 저렴
function diff(c: Company) {
  // 최종가가 0인 빈 열은 비교 제외. 총액 직접입력(품목단가 미입력) 열도 비교 대상에 포함.
  if (c.self || selfFinal.value <= 0 || finalP(c) <= 0) return null;
  const d = finalP(c) - selfFinal.value;
  const pct = d / selfFinal.value * 100;
  return { d, pct, cheaper: d > 0, label: d > 0 ? '자사 저렴' : d < 0 ? '자사 비쌈' : '동일' };
}
function marginClass(m: number) { return m >= 15 ? 'text-emerald-500' : m >= 5 ? 'text-amber-500' : 'text-red-500'; }

// ── 열 이름 ─────────────────────────────────────────────────────────────────
// 경쟁사 열 이름은 빈칸 + 추천값(placeholder) 방식. 첫 경쟁사는 상단 고객명을 추천,
// 두 번째 이후는 '경쟁사 B·C…'. 실제 입력값이 있으면 항상 그것이 우선.
const compIdx  = (i: number) => companies.value.slice(0, i).filter(c => !c.self).length;
const nameHint = (c: Company, i: number) => {
  if (c.self) return 'PT ASCENDO';
  const n = compIdx(i);
  return (n === 0 && form.value.customer.trim()) || `경쟁사 ${String.fromCharCode(65 + n)}`;
};
// 저장·인쇄에 쓰이는 확정 열 이름 (입력값 없으면 추천값)
const colName  = (c: Company, i: number) => c.name.trim() || nameHint(c, i);

// ── 편집 액션 ────────────────────────────────────────────────────────────────
function addCompetitor() {
  companies.value.push({
    name: '', self: false,   // 이름은 빈칸 → 헤더에서 추천값(고객명/경쟁사 X) 표시
    tire: { price: 0, code: '', brand: '' }, tube: { price: 0, code: '', brand: '' }, flap: { price: 0, code: '', brand: '' },
    landed: 0, promos: [{ desc: '', rate: 0 }], ppn: true, finalOv: '',
  });
}
function delCompany(i: number) { companies.value.splice(i, 1); }
// 최종 판매가 직접입력: 숫자만 남기고 콤마 서식 유지. 빈칸 → 자동계산 복귀.
function setOv(c: Company, val: string) { const d = val.replace(/[^\d]/g, ''); c.finalOv = d ? Number(d).toLocaleString('en-US') : ''; }
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
// 자동 프로모션(가격 조정 할인)은 순차 할인의 마지막을 유지해야 하므로 그 앞에 삽입
function addPromo(i: number) {
  const arr = companies.value[i].promos;
  const at = arr.findIndex(p => p.auto);
  arr.splice(at < 0 ? arr.length : at, 0, { desc: '', rate: 0 });
}
// 자동 프로모션 삭제 = 목표가 해제 (목표가가 남아 있으면 watch 가 다시 생성)
function delPromo(i: number, pi: number) {
  const c = companies.value[i];
  if (c.promos[pi]?.auto) c.finalOv = '';
  c.promos.splice(pi, 1);
}
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
// 원가(wh)는 항상 VAT 별도이므로 'VAT 포함' 표기 중에는 소계를 세전으로 환산해 비교한다.
function setMarginR(c: Company): number | null {
  const s0 = sub(c);
  const s = form.value.basis === 'incl' ? s0 / (1 + PPN_RATE) : s0;
  const w = ROWS.value.reduce((a, r) => a + (c[r.key].wh || 0), 0);
  return s > 0 && w > 0 ? (s - w) / s * 100 : null;
}
function choose(c: Company, key: 'tire' | 'tube' | 'flap', p: Product) {
  const it  = c[key];
  it.code = p.description; it.brand = p.brand ?? '';
  it.wh   = p.wh_price_pcs || p.wh_price_set || 0;
  it.dist = p.dist_price_pcs ? p.dist_price_pcs / (1 + PPN_RATE) : undefined;   // 대리점가는 VAT 포함 저장 → 세전 환산
  it.cat  = catOf(p.item, p.description);
  it.price = priceOf(it, gradeIdx.value);
  setLanded(c);
  openKey.value = null;
}
// 고객등급 변경 → 자사 판매가·원가 재계산 (product 로 채운 행만)
function recomputeSelf() {
  for (const c of companies.value) {
    if (!c.self) continue;
    for (const r of ROWS.value) { const it = c[r.key]; if (it.wh && baseMargin(it) != null) it.price = priceOf(it, gradeIdx.value); }
    setLanded(c);
  }
}
async function loadProducts() {
  if (!isPrivileged) return;   // 원가(wh_price_pcs) 조회는 super_admin/staff 만 (products RLS)
  try {
    products.value = await sbGet<Product[]>(
      'products_priced?select=id,item,brand,description,sku,wh_price_pcs,wh_price_set,dist_price_pcs,unit&is_active=eq.true&order=item.asc,description.asc',
    );
  } catch (e) {
    products.value = [];
    toast.error(`제품 마스터를 불러오지 못했습니다 — ${errMsg(e)}`);
  }
}

function resetNew() {
  form.value = { createdDate: today, customer: '', grade: GRADES[2], basis: 'excl' };
  discMode.value = 'seq';
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
const modalError = ref<string | null>(null);

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
      disc_mode:      discMode.value,
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
      comparison_id: id, col_no: idx, is_self: c.self, company_name: colName(c, idx),   // 빈칸이면 추천값 확정 저장
      tire_price: c.tire.price, tube_price: c.tube.price, flap_price: c.flap.price,
      tire_code: c.tire.code || null, tube_code: c.tube.code || null, flap_code: c.flap.code || null,
      tire_brand: c.tire.brand || null, tube_brand: c.tube.brand || null, flap_brand: c.flap.brand || null,
      apply_ppn: c.ppn,
      landed_cost: c.landed,
      final_override: hasOv(c) ? ovNum(c) : null,   // 최종 판매가 직접입력 목표가 (null = 자동계산)
    }));
    const cols = await sbPost<Array<{ id: string; col_no: number }>>('price_comparison_columns', colRows);
    const idByNo = new Map(cols.map(c => [c.col_no, c.id]));

    const promoRows = companies.value.flatMap((c, idx) =>
      c.promos.filter(p => (p.desc && p.desc.trim()) || p.rate).map((p, pi) => ({
        column_id: idByNo.get(idx), promo_no: pi,
        description: p.desc?.trim() || (p.auto ? AUTO_DESC : null),
        discount_rate: p.rate || 0,
        is_auto: !!p.auto,   // 불러올 때 목표가 기준 재계산 대상 (중복 생성 방지)
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
  showLoad.value = true; loadSearch.value = ''; modalLoading.value = true; modalError.value = null;
  try {
    loadList.value = await sbGet(
      'price_comparisons?select=id,compare_no,customer_name,created_date,updated_at&order=updated_at.desc',
    );
  } catch (e) { loadList.value = []; modalError.value = errMsg(e); }   // '저장된 항목 없음' 과 구분해 사유·재시도 노출
  modalLoading.value = false;
}

async function loadCompare(id: string) {
  try {
    type Hdr = { id: string; compare_no: string; customer_name: string | null; customer_grade: string | null; ppn_basis: 'excl' | 'incl'; disc_mode: 'seq' | 'sum' | null; created_date: string };
    type Pr  = { promo_no: number; description: string | null; discount_rate: number; is_auto: boolean | null };
    type Col = { id: string; col_no: number; is_self: boolean; company_name: string | null; tire_price: number; tube_price: number; flap_price: number; tire_code: string | null; tube_code: string | null; flap_code: string | null; tire_brand: string | null; tube_brand: string | null; flap_brand: string | null; apply_ppn: boolean | null; landed_cost: number; final_override: number | null; price_comparison_promos: Pr[] };
    // 컬럼 + 임베딩 프로모션을 한 번에 조회 (PostgREST 관계 임베딩)
    const [hArr, colArr] = await Promise.all([
      sbGet<Hdr[]>(`price_comparisons?id=eq.${id}&select=*`),
      sbGet<Col[]>(`price_comparison_columns?comparison_id=eq.${id}&select=*,price_comparison_promos(promo_no,description,discount_rate,is_auto)&order=col_no.asc`),
    ]);
    const h = hArr[0]; if (!h) { toast.error('항목을 찾을 수 없습니다'); return; }
    form.value = {
      createdDate: h.created_date, customer: h.customer_name ?? '',
      grade: normGrade(h.customer_grade), basis: h.ppn_basis ?? 'excl',
    };
    discMode.value = h.disc_mode === 'sum' ? 'sum' : 'seq';
    companies.value = colArr.map(col => {
      const promos: Promo[] = [...(col.price_comparison_promos ?? [])]
        .sort((a, b) => a.promo_no - b.promo_no)
        // 자사 프리셋 프로모션(수량/현금/배송 할인)은 desc 매칭으로 최대치(max) 복원
        // 자동 프로모션(가격 조정 할인)은 auto 플래그 복원 → 목표가 기준으로 재계산(중복 생성 방지)
        .map(p => ({
          desc: p.description ?? '', rate: p.discount_rate,
          max: col.is_self && !p.is_auto ? selfPromoMax(p.description ?? '') : undefined,
          auto: p.is_auto ?? false,
        }));
      return {
        name: col.company_name ?? '', self: col.is_self,
        tire: { price: col.tire_price, code: col.tire_code ?? '', brand: col.tire_brand ?? '' },
        tube: { price: col.tube_price, code: col.tube_code ?? '', brand: col.tube_brand ?? '' },
        flap: { price: col.flap_price, code: col.flap_code ?? '', brand: col.flap_brand ?? '' },
        landed: col.landed_cost, promos: promos.length ? promos : (col.is_self ? SELF_PROMOS.map(p => ({ ...p })) : [{ desc: '', rate: 0 }]),
        ppn: col.is_self ? true : (col.apply_ppn ?? true),
        finalOv: col.final_override ? idFmt(col.final_override) : '',
      };
    });
    // 자사 행: 저장된 code(description)로 제품 매칭 → wh/cat 복원(등급 변경 시 재계산 가능)
    for (const c of companies.value) {
      if (!c.self) continue;
      for (const r of ROWS.value) {
        const p = products.value.find(pr => pr.description === c[r.key].code);
        if (p) {
          c[r.key].wh = p.wh_price_pcs || p.wh_price_set || 0;
          c[r.key].dist = p.dist_price_pcs ? p.dist_price_pcs / (1 + PPN_RATE) : undefined;
          c[r.key].cat = catOf(p.item, p.description);
        }
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
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">
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
      <h2 class="text-lg font-bold">타이어 세트 가격 비교</h2>
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
        <!-- 부가세 표기 기준 토글(우측 끝) — 품목 단가·세트 소계에 일괄 적용, 최종 판매가는 동일 -->
        <div class="inline-flex items-center gap-1 rounded-lg border border-border bg-card p-0.5">
          <button
            v-for="m in VAT_MODES" :key="m.key"
            :class="['px-2.5 py-1.5 rounded-md text-[11px] font-semibold transition-colors whitespace-nowrap',
              form.basis === m.key ? 'bg-primary/15 text-primary' : 'text-muted-foreground hover:bg-accent']"
            :title="`품목 단가·세트 소계를 ${m.label} 기준으로 표기 (PPN 11% · 입력값 자동 환산)`"
            @click="setBasis(m.key)"
          >{{ m.label }}</button>
        </div>
      </div>
    </div>

    <!-- 비교표 -->
    <div class="rounded-xl border border-border bg-card overflow-x-auto">
      <table class="w-full text-sm border-collapse min-w-180">
        <caption class="sr-only">경쟁사 가격 비교 표</caption>
        <thead>
          <tr>
            <th scope="col" class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-left text-xs font-semibold w-52">항목</th>
            <th scope="col"
              v-for="(c, i) in companies" :key="i"
              class="border border-border px-3 py-2 text-center"
              :class="c.self ? 'bg-emerald-500/10' : 'bg-primary/5'"
            >
              <!-- 회사명 + 삭제 1행. 경쟁사는 빈칸이면 추천값(상단 고객명 / 경쟁사 X)을 placeholder로 노출 -->
              <div class="flex items-center justify-center gap-1.5 print:hidden">
                <input
                  v-model="c.name" type="text" :placeholder="nameHint(c, i)"
                  :title="c.self ? undefined : '경쟁사명 직접 입력 · 빈칸이면 추천값 사용'"
                  class="min-w-0 bg-transparent text-center text-sm font-bold focus:outline-none placeholder:font-bold placeholder:text-foreground/70"
                />
                <button v-if="!c.self" class="shrink-0 text-muted-foreground hover:text-red-500" title="열 삭제" @click="delCompany(i)"><X :size="12" /></button>
              </div>
              <div class="hidden print:block text-sm font-bold">{{ colName(c, i) }}</div>
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
                      <div class="text-[10px] text-muted-foreground tabular-nums">원가 {{ fmt(p.wh_price_pcs || p.wh_price_set || 0) }} · {{ p.item }}</div>
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
                <span
                  v-if="c.self && isPrivileged && marginPct(c[r.key]) != null" class="print:hidden text-[10px] whitespace-nowrap"
                  :class="marginPct(c[r.key])! < 0 ? 'text-red-600 font-semibold' : 'text-muted-foreground'"
                >
                  마진 {{ marginPct(c[r.key])!.toFixed(1) }}%
                </span>
              </div>
            </td>
          </tr>

          <!-- 세트 소계 -->
          <tr class="bg-muted/50">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold">
              세트 소계 <span class="font-normal text-[10px] text-muted-foreground">({{ basisLabel }})</span>
            </td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 text-right tabular-nums font-semibold">
              {{ fmt(sub(c)) }}
              <span
                v-if="c.self && isPrivileged && setMarginR(c) != null" class="print:hidden ml-1 text-[10px] font-normal"
                :class="setMarginR(c)! < 0 ? 'text-red-600 font-semibold' : 'text-muted-foreground'"
              >마진 {{ setMarginR(c)!.toFixed(1) }}%</span>
            </td>
          </tr>
          <!-- 프로모션 -->
          <tr>
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold align-top">
              프로모션
              <!-- 할인 방식 선택 — 순차: 직전 잔액에 차례로 / 합계: 모든 %를 소계 기준으로 -->
              <div class="print:hidden mt-1.5 inline-flex flex-col gap-1">
                <button
                  v-for="m in DISC_MODES" :key="m.key"
                  :class="['px-2 py-1 rounded-md border text-[10px] font-semibold text-left transition-colors',
                    discMode === m.key ? 'border-primary/40 bg-primary/10 text-primary' : 'border-border bg-card text-muted-foreground hover:bg-accent']"
                  :title="m.key === 'seq' ? '각 할인율을 직전 잔액에 차례로 적용(복리)' : '모든 할인율을 세트 소계 기준으로 합산 적용'"
                  @click="discMode = m.key"
                >{{ m.label }}</button>
              </div>
              <span class="hidden print:block text-[10px] text-muted-foreground font-normal">{{ discMode === 'seq' ? '순차 할인 적용' : '합계 할인 적용' }}</span>
            </td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 align-top">
              <div class="flex flex-col gap-2 min-w-50">
                <!-- 할인내용 → 할인금액(직전 잔액 기준 순차 계산) → 할인율(%) 1행 -->
                <!-- p.auto = 목표 최종가 맞추기용 자동 프로모션: 할인율은 역산값(읽기 전용), 이름은 수정 가능 -->
                <div
                  v-for="(p, pi) in c.promos" :key="pi"
                  class="flex items-center gap-1.5 rounded-lg border p-1.5"
                  :class="p.auto ? 'border-dashed border-primary/50 bg-primary/5' : 'border-border bg-muted/40'"
                >
                  <input
                    v-model="p.desc" type="text" :placeholder="p.auto ? AUTO_DESC : '예) 현금할인'"
                    class="flex-1 min-w-24 text-xs bg-card border border-border rounded px-1.5 py-1 focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                  <span
                    v-if="p.auto" class="print:hidden text-[10px] font-semibold whitespace-nowrap"
                    :class="pRate(p) < 0 ? 'text-red-600' : 'text-primary'"
                    :title="pRate(p) < 0 ? '목표가가 계산가보다 높아 가격 인상분으로 반영' : '최종 판매가 목표값에 맞춰 자동 계산'"
                  >{{ pRate(p) < 0 ? '자동 · 인상' : '자동' }}</span>
                  <!-- 금액: 할인(−) / 인상(+) 부호 표시 -->
                  <span
                    class="w-24 text-right text-xs tabular-nums shrink-0"
                    :class="pRate(p) < 0 ? 'text-red-600' : 'text-amber-600 dark:text-amber-500'"
                  >{{ pRate(p) === 0 ? '-' : (pRate(p) > 0 ? '- ' : '+ ') + fmt(Math.abs(promoAmts(c)[pi])) }}</span>
                  <!-- 자동 프로모션: 최종 판매가 입력값에서 역산되므로 직접 수정 대신 목표가를 조정 -->
                  <span v-if="p.auto" class="w-14 text-right text-xs tabular-nums px-1.5 py-1 shrink-0 font-semibold" :class="pRate(p) < 0 ? 'text-red-600' : ''">{{ pRate(p).toFixed(1) }}</span>
                  <input
                    v-else
                    v-model.number="p.rate" type="number" min="0" max="100" step="0.5"
                    :title="p.max != null ? `권고 최대 ${p.max}% (초과 입력 가능)` : undefined"
                    class="w-14 text-right text-xs bg-card border rounded px-1.5 py-1 tabular-nums focus:outline-none focus:ring-1"
                    :class="pOver(p) ? 'border-red-500 text-red-600 focus:ring-red-500' : 'border-border focus:ring-primary'"
                    @blur="clampPromo(p)"
                  />
                  <span class="text-[10px] whitespace-nowrap" :class="pOver(p) ? 'text-red-600 font-semibold' : 'text-muted-foreground'">
                    % <template v-if="p.max != null">/ {{ p.max }}</template>
                  </span>
                  <button
                    class="print:hidden text-[10px] text-muted-foreground hover:text-red-500 shrink-0"
                    :title="p.auto ? '삭제 (최종 판매가 목표값 해제)' : '삭제'" @click="delPromo(i, pi)"
                  >✕</button>
                </div>
                <button class="print:hidden text-xs px-2 py-1 rounded border border-border hover:bg-accent transition-colors" @click="addPromo(i)">+ 프로모션 추가</button>
              </div>
            </td>
          </tr>
          <!-- 총 할인 (음수 = 목표가 역산 결과가 가격 인상) -->
          <tr>
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold text-amber-600 dark:text-amber-500">총 할인</td>
            <td
              v-for="(c, i) in companies" :key="i"
              class="border border-border px-3 py-2 text-right tabular-nums font-semibold"
              :class="discAmt(c) < 0 ? 'text-red-600' : 'text-amber-600 dark:text-amber-500'"
            >
              {{ hasDisc(c) ? `${discAmt(c) >= 0 ? '- ' : '+ '}${fmt(Math.abs(discAmt(c)))} (${Math.abs(effRate(c)).toFixed(1)}%)` : '-' }}
            </td>
          </tr>
          <!-- 할인후 합계 -->
          <tr class="bg-muted/50">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs font-semibold">할인후 합계</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 text-right tabular-nums font-semibold">
              {{ fmt(shownAfterDisc(c)) }}
              <span v-if="isLump(c)" class="print:hidden ml-1 text-[10px] font-normal text-muted-foreground">최종가 역산</span>
            </td>
          </tr>
          <!-- PPN (경쟁사는 적용/미적용 선택) -->
          <tr class="text-muted-foreground">
            <td class="sticky left-0 z-10 bg-muted border border-border px-3 py-2 text-xs">
              PPN {{ (PPN_RATE * 100).toFixed(1) }}% <span class="text-[10px]">{{ form.basis === 'incl' ? '(포함분)' : '(가산)' }}</span>
            </td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2">
              <div class="flex items-center justify-end gap-2">
                <div v-if="!c.self" class="print:hidden inline-flex rounded-md border border-border overflow-hidden text-[10px]">
                  <button class="px-2 py-0.5 transition-colors" :class="c.ppn ? 'bg-primary/15 text-primary font-semibold' : 'text-muted-foreground hover:bg-accent'" @click="c.ppn = true">적용</button>
                  <button class="px-2 py-0.5 transition-colors" :class="!c.ppn ? 'bg-primary/15 text-primary font-semibold' : 'text-muted-foreground hover:bg-accent'" @click="c.ppn = false">미적용</button>
                </div>
                <span class="text-right tabular-nums">{{ c.ppn ? fmt(shownPpn(c)) : '미적용' }}</span>
              </div>
            </td>
          </tr>

          <!-- 최종 판매가 + 차액 -->
          <tr class="bg-emerald-500/10">
            <td class="sticky left-0 z-10 bg-primary text-primary-foreground border border-border px-3 py-2 text-xs font-bold">최종 판매가</td>
            <td v-for="(c, i) in companies" :key="i" class="border border-border px-3 py-2 text-right">
              <!-- 목표 최종가 직접입력. 자사=추가 할인 역산으로 가격 맞추기 / 경쟁사=총액 견적. 빈칸 = 자동계산 -->
              <div class="print:hidden flex items-center justify-end gap-1">
                <span class="text-[11px] text-muted-foreground shrink-0">Rp</span>
                <input
                  :value="c.finalOv" @input="setOv(c, ($event.target as HTMLInputElement).value)"
                  type="text" inputmode="numeric" :placeholder="idFmt(calcFinal(c)) || '0'"
                  title="최종 판매가 직접 입력 가능 — 입력하면 「가격 조정 할인」이 자동 추가되어 그 가격에 맞춰짐 · 빈칸 = 자동계산"
                  class="w-32 bg-card text-right text-base font-bold tabular-nums border rounded px-1.5 py-0.5 focus:outline-none focus:ring-1 focus:ring-primary placeholder:font-bold placeholder:text-foreground"
                  :class="ovMiss(c) ? 'border-red-500' : hasOv(c) ? 'border-primary' : 'border-border'"
                />
                <button
                  v-if="hasOv(c)" class="text-[10px] text-muted-foreground hover:text-red-500 shrink-0"
                  title="목표값 해제 (자동계산으로 되돌리기)" @click="c.finalOv = ''"
                >✕</button>
              </div>
              <div class="hidden print:block tabular-nums font-bold text-base">{{ fmt(finalP(c)) }}</div>
              <!-- 할인율 0~100% 로 맞출 수 없는 목표가 → 실제 적용값 안내 -->
              <div v-if="ovMiss(c)" class="print:hidden text-[10px] font-semibold text-red-600 mt-0.5">목표가 도달 불가 · 실제 {{ fmt(calcFinal(c)) }}</div>
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
      <p>· 자사 품목은 <b>제품 검색</b>으로 선택하면 판매가가 자동 입력된다 — <b>DB 대리점가(pcs) 기준</b>, 고객등급 한 단계당 5%p 가감.</p>
      <p>· <b>VAT 별도/포함 토글</b>은 단가의 표기 기준만 바꾼다(자동 환산) — 최종 판매가는 같다.</p>
      <p>· <b>최종 판매가 칸에 목표가를 직접 입력</b>하면 「가격 조정 할인」이 자동으로 그 가격에 맞춰준다. ✕ 로 해제(자동계산 복귀).</p>
      <p>· 경쟁사는 품목단가 없이 <b>최종가만 입력해도</b> 비교된다.</p>
      <p>· 프로모션의 「% / 10」은 <b>권고 최대 할인율</b> — 초과하면 <span class="text-red-600 font-semibold">빨간 표시</span>되지만 입력값대로 계산된다.</p>
      <p v-if="isPrivileged">· 원가·마진 행은 관리자 전용(비권한 사용자 미노출).</p>
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
            <DataState
              v-if="modalLoading || modalError || !filteredLoad.length"
              :loading="modalLoading" :error="modalError" :empty="!filteredLoad.length"
              skeleton-class="h-40 m-4" empty-text="저장된 항목이 없습니다."
              @retry="openLoad"
            />
            <button
              v-for="r in filteredLoad" v-else :key="r.id"
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
