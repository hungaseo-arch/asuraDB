<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';
import { ClipboardList, Trash2, Printer, Loader2, Save, FolderOpen, FilePlus, Copy, X, ChevronDown } from 'lucide-vue-next';
import Button from '@/components/ui/Button.vue';
import PageHeader from '@/components/PageHeader.vue';
import { sbGet, sbPost, sbPatch, sbDelete, sbRpc } from '@/lib/supabase';


const WAREHOUSES       = ['WH-Karawang', 'WH-Semarang', 'WH-Surabaya'];
const DELIVERY_METHODS = ['Self-Pickup', 'Delivery'];
const PAYMENT_TERMS    = ['CBD', 'Net 15', 'Net 30', 'Net 60'];
const PPN_RATE         = 0.11;

interface Product {
  id:           string;
  item:         string;
  brand:        string;
  description:  string;
  sku:          string;
  wh_price_pcs:   number;   // 입고가(원가) 단품 — 권한 없는 역할에선 0
  wh_price_set:   number;   // 입고가(원가) set — 권한 없는 역할에선 0
  dist_price_pcs: number | null;  // 대리점가(pcs 기준) — 없으면 원가 기준 추천가로 대체
  unit:         'pcs' | 'set';
}

const products        = ref<Product[]>([]);
const productsLoading = ref(false);

// products 와 products_sell 응답을 동일 Product 형태로 정규화.
// (products_sell 은 unit_price/unit_price_set 만 제공 — 원가 컬럼 없음)
interface ProductsSellRow {
  id: string; item: string; brand: string; description: string; sku: string;
  unit_price: number; unit_price_set: number | null;
  unit: 'pcs' | 'set';
}

async function loadProducts() {
  productsLoading.value = true;
  try {
    if (canViewCost) {
      // super_admin / staff — 원가 포함 조회
      products.value = await sbGet<Product[]>(
        'products_priced?select=id,item,brand,description,sku,wh_price_pcs,wh_price_set,dist_price_pcs,unit&is_active=eq.true&order=brand.asc,description.asc',
      ) ?? [];
    } else {
      // distributor / end_user — products RLS 로 차단됨 → products_sell 뷰 사용
      // 서버에서 wh_price_pcs/0.8 로 계산된 판매가만 노출, 원가 컬럼은 응답에 없음.
      // UI 호환을 위해 unit_price → whPrice 슬롯에 그대로 담아 unit_price 계산에 재사용.
      const rows = await sbGet<ProductsSellRow[]>(
        'products_sell?select=id,item,brand,description,sku,unit_price,unit_price_set,unit&order=brand.asc,description.asc',
      ) ?? [];
      products.value = rows.map((r) => ({
        id: r.id, item: r.item, brand: r.brand, description: r.description, sku: r.sku, unit: r.unit,
        // products_sell 은 이미 판매가만 가짐 → '원가' 슬롯에 채워두고 applyProductPricing 이 그대로 사용하게 함
        wh_price_pcs:   r.unit_price,
        wh_price_set:   r.unit_price_set ?? 0,
        // 대리점가는 원가 기반 값이라 이 뷰에 없음 → 기존 판매가 규칙을 그대로 따른다
        dist_price_pcs: null,
      }));
    }
  } catch {
    products.value = [];
  }
  productsLoading.value = false;
}

// ── 고객 ─────────────────────────────────────────────────────────────────────
interface Customer {
  id:             string;
  customer_code:  string;
  customer_name:  string;
  main_pic_name:  string | null;
  acquirer_name:  string | null;
}

const customers = ref<Customer[]>([]);

async function loadCustomers() {
  // customers RLS 는 super_admin/staff 만 select 허용 → 그 외 역할은 조회 자체를 건너뛴다.
  // (Order Information 블록도 isQuoteOnly 에서 숨겨지므로 이 자동완성이 필요 없다)
  if (!canViewCost) return;
  try {
    customers.value = await sbGet<Customer[]>(
      'customers?select=id,customer_code,customer_name,main_pic_name,acquirer_name&is_active=eq.true&order=customer_name.asc',
    ) ?? [];
  } catch {
    customers.value = [];
  }
}

onMounted(() => { void loadProducts(); void loadCustomers(); });

// 4역할 모델 (가이드: app_metadata.role)
//   super_admin / staff : 원가 포함 조회, 마진 표시
//   distributor          : products_sell 만, 마진 숨김, 마크업 없음
//   end_user             : products_sell 만, 마진 숨김, 15% 마크업
const _auth = sessionStorage.getItem('asura_auth');
const canViewCost   = _auth === 'super_admin' || _auth === 'staff';   // 원가/마진 조회 + products 직접 사용
const canSaveImport = _auth === 'super_admin';                          // 저장/불러오기는 관리자만
const isQuoteOnly   = !canViewCost;                                     // UI: 마진 열 숨김 + 인쇄 처리

const today = () => new Date().toISOString().slice(0, 10);

const emptyForm = () => ({
  customerName: '', quoteNumber: '', contactPerson: '',
  deliveryDate: today(), originWH: 'WH-Karawang',
  deliveryMethod: 'Self-Pickup', paymentTerms: 'CBD', remarks: '',
});

const form = ref(emptyForm());

const additionalDiscount = ref(0);

// Order Information 아코디언 펼침 상태 (기본 펼침). 인쇄 시엔 CSS 로 강제 표시.
const showOrderInfo = ref(false);

interface LineItem {
  id:           number;
  type:         string;
  brand:        string;
  description:  string;
  qty:          number;
  unit:         'pcs' | 'set';
  unitPrice:    number;
  whPrice:      number;
  discount:     number;
  productSku:   string;
  productId:    string;
  guestMargin:  number;
}

let _id = 1;
function newLine(): LineItem {
  return { id: _id++, type: '', brand: '', description: '', qty: 0, unit: 'pcs', unitPrice: 0, whPrice: 0, discount: 0, productSku: '', productId: '', guestMargin: 15 };
}

const lines = ref<LineItem[]>([newLine()]);

function addLine()              { lines.value.push(newLine()); }
function removeLine(id: number) { if (lines.value.length > 1) lines.value = lines.value.filter(l => l.id !== id); }

// ── 자동완성 ─────────────────────────────────────────────────────────────────
interface AcRect { bottom: number; left: number; width: number }
const acState = ref<{ lineId: number | null; rect: AcRect | null }>({ lineId: null, rect: null });
const acIdx   = ref(-1);

const acLine = computed(() => lines.value.find(l => l.id === acState.value.lineId) ?? null);

const acSuggestions = computed<Product[]>(() => {
  const line = acLine.value;
  if (!line) return [];
  const q = line.description.trim().toLowerCase();
  if (!q) return [];
  return products.value
    .filter(p =>
      (p.description ?? '').toLowerCase().includes(q) ||
      (p.brand       ?? '').toLowerCase().includes(q) ||
      (p.sku         ?? '').toLowerCase().includes(q) ||
      (p.item        ?? '').toLowerCase().includes(q)
    )
    .slice(0, 8);
});

function openAc(e: Event, line: LineItem) {
  const r = (e.target as HTMLInputElement).getBoundingClientRect();
  acState.value = { lineId: line.id, rect: { bottom: r.bottom, left: r.left, width: r.width } };
  acIdx.value   = -1;
}
function closeAc() { acState.value = { lineId: null, rect: null }; acIdx.value = -1; }

// ── 고객명 자동완성 ───────────────────────────────────────────────────────────
const custAc    = ref<{ open: boolean; rect: AcRect | null }>({ open: false, rect: null });
const custAcIdx = ref(-1);

const custSuggestions = computed<Customer[]>(() => {
  if (!custAc.value.open) return [];
  const q = form.value.customerName.trim().toLowerCase();
  if (!q) return [];
  return customers.value
    .filter(c =>
      (c.customer_name ?? '').toLowerCase().includes(q) ||
      (c.customer_code ?? '').toLowerCase().includes(q) ||
      (c.main_pic_name ?? '').toLowerCase().includes(q)
    )
    .slice(0, 8);
});

function openCustAc(e: Event) {
  const r = (e.target as HTMLInputElement).getBoundingClientRect();
  custAc.value    = { open: true, rect: { bottom: r.bottom, left: r.left, width: r.width } };
  custAcIdx.value = -1;
}
function closeCustAc() { custAc.value = { open: false, rect: null }; custAcIdx.value = -1; }

function selectCustomer(c: Customer) {
  form.value.customerName = c.customer_name;
  // 담당자(quotes.sales_rep)는 비어 있을 때만 채운다 — 사용자가 적어둔 값을 덮지 않기 위함
  if (!form.value.contactPerson && c.main_pic_name) form.value.contactPerson = c.main_pic_name;
  closeCustAc();
}

function onCustomerKeydown(e: KeyboardEvent) {
  if (!custSuggestions.value.length) return;
  if      (e.key === 'ArrowDown')                     { e.preventDefault(); custAcIdx.value = Math.min(custAcIdx.value + 1, custSuggestions.value.length - 1); }
  else if (e.key === 'ArrowUp')                       { e.preventDefault(); custAcIdx.value = Math.max(custAcIdx.value - 1, -1); }
  else if (e.key === 'Enter' && custAcIdx.value >= 0) { e.preventDefault(); selectCustomer(custSuggestions.value[custAcIdx.value]); }
  else if (e.key === 'Escape')                          closeCustAc();
}

// 대리점 기본 마진율 — 판매가 = 원가 ÷ (1 − 마진율). 가격비교(PriceCompare)와 동일한 정의.
const DIST_MARGIN = 0.25;
const recommendDist = (cost: number) => (cost > 0 ? Math.round(cost / (1 - DIST_MARGIN)) : 0);

// 라인의 대리점가(Dist Price).
// products.dist_price_pcs 가 있으면 그 값, 없으면 원가 기준 25% 마진 추천가.
// dist_price_pcs 는 pcs 단가이므로 set 라인에는 쓰지 않고 원가(set) 기준 추천가를 쓴다.
function distPriceFor(p: Product | undefined, unit: 'pcs' | 'set', cost: number): number {
  const dp = unit === 'pcs' ? Number(p?.dist_price_pcs) || 0 : 0;
  return dp || recommendDist(cost);
}

// 표시용 — 저장된 견적을 불러온 경우에도 sku 로 제품을 되찾아 대리점가를 산출한다.
function distPriceOf(l: LineItem): number {
  if (!canViewCost) return l.unitPrice;   // 원가를 못 보는 역할 — products_sell 판매가 그대로
  return distPriceFor(products.value.find(pr => pr.sku === l.productSku), l.unit, l.whPrice);
}

// 제품 가격을 라인에 적용 (대리점가를 기본 단가로 설정)
function applyProductPricing(line: LineItem, p: Product) {
  const raw = line.unit === 'set' ? p.wh_price_set : p.wh_price_pcs;
  line.whPrice = Number(raw) || 0;
  // products_sell 은 원가가 아닌 판매가를 whPrice 슬롯에 담고 있어 기존 규칙(÷0.8)을 유지한다.
  line.unitPrice = canViewCost
    ? distPriceFor(p, line.unit, line.whPrice)
    : Math.round(line.whPrice / 0.8);
}

function selectSuggestion(p: Product) {
  const line = acLine.value;
  if (!line) return;
  line.description = p.description;
  line.productSku  = p.sku;
  line.productId   = p.id;
  line.type        = p.item  || line.type;
  line.brand       = p.brand || line.brand;
  applyProductPricing(line, p);
  closeAc();
}

function onDescriptionKeydown(e: KeyboardEvent, line: LineItem) {
  if (acState.value.lineId !== line.id || !acSuggestions.value.length) return;
  if      (e.key === 'ArrowDown')                    { e.preventDefault(); acIdx.value = Math.min(acIdx.value + 1, acSuggestions.value.length - 1); }
  else if (e.key === 'ArrowUp')                      { e.preventDefault(); acIdx.value = Math.max(acIdx.value - 1, -1); }
  else if (e.key === 'Enter' && acIdx.value >= 0)    { e.preventDefault(); selectSuggestion(acSuggestions.value[acIdx.value]); }
  else if (e.key === 'Escape')                         closeAc();
}

function onUnitChange(line: LineItem) {
  if (!line.productSku) return;
  const p = products.value.find(pr => pr.sku === line.productSku);
  if (p) applyProductPricing(line, p);
}

// Qty 입력 → 콤마 제거 후 정수 저장. blur(change) 시 fmtInput 으로 재포맷되어 콤마 표시.
function onQtyChange(line: LineItem, val: string) {
  line.qty = parseNum(val);
}

// ── 계산 ─────────────────────────────────────────────────────────────────────
// netPrice 역산용 할인 보정 계수 (할인 100% 회피)
function inverseDiscount(l: LineItem): number {
  const d = (l.discount || 0) / 100;
  return d < 1 ? 1 - d : 1;
}

function rawMargin(l: LineItem): number {
  return (lineNetPrice(l) - l.whPrice) / l.whPrice;
}

function lineNetPrice(l: LineItem): number { return (l.unitPrice || 0) * (1 - (l.discount || 0) / 100); }

function lineAmount(l: LineItem):   number { return (l.qty || 0) * lineNetPrice(l); }

function lineMarginNum(l: LineItem): string {
  if (!l.unitPrice) return '';
  if (!l.whPrice) return isQuoteOnly ? l.guestMargin.toFixed(1) : '';
  return (rawMargin(l) * 100).toFixed(1);
}
function marginColor(l: LineItem): string {
  if (!l.whPrice || !l.unitPrice) return '';
  const m = rawMargin(l);
  return m >= 0.05 ? 'text-success' : m >= 0 ? 'text-warning' : 'text-destructive';
}
function onMarginChange(line: LineItem, val: string) {
  const m = parseFloat(val);
  if (isNaN(m)) return;
  if (isQuoteOnly) line.guestMargin = m;
  if (!line.whPrice) return;
  line.unitPrice = Math.round(line.whPrice * (1 + m / 100) / inverseDiscount(line));
}

// markup: end_user 만 추가 15% (최종 고객용). distributor 는 products_sell 가격 그대로(1.0).
const markup = _auth === 'end_user' ? 1.15 : 1;

// Unit Price 직접 입력 → unitPrice 역산 (netPrice = unitPrice × (1 - 할인))
function onNetPriceChange(line: LineItem, val: string) {
  line.unitPrice = Math.round(parseNum(val) / markup / inverseDiscount(line));
}

const subTotalQty    = computed(() => lines.value.reduce((s, l) => s + (l.qty || 0), 0));
const subTotalAmount = computed(() => lines.value.reduce((s, l) => s + lineAmount(l), 0));
const discAmount     = computed(() => subTotalAmount.value * (additionalDiscount.value / 100));
const afterDisc      = computed(() => subTotalAmount.value - discAmount.value);
// 표시용 (guest: ×1.15, full: ×1)
const mSubTotal   = computed(() => subTotalAmount.value * markup);
const mDiscAmount = computed(() => discAmount.value * markup);
const mAfterDisc  = computed(() => afterDisc.value * markup);
const mPPN        = computed(() => mAfterDisc.value * PPN_RATE);
const mTotal      = computed(() => Math.floor((mAfterDisc.value + mPPN.value) / 1000) * 1000);
const mTruncation = computed(() => mTotal.value - (mAfterDisc.value + mPPN.value));

// ── 포맷 헬퍼 ─────────────────────────────────────────────────────────────────
function fmt(n: number):      string { return n ? Math.round(Math.abs(n)).toLocaleString('en-US') : '0'; }
function fmtInput(n: number): string { return n ? n.toLocaleString('en-US') : ''; }
function parseNum(s: string): number { return parseInt(s.replace(/,/g, ''), 10) || 0; }

function handlePrint() {
  const d = new Date();
  const dd   = String(d.getDate()).padStart(2, '0');
  const mm   = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  const abbr = form.value.customerName
    .trim()
    .split(/\s+/)
    .map(w => w[0]?.toUpperCase() ?? '')
    .join('')
    .slice(0, 3);
  const prev = document.title;
  document.title = abbr ? `Qt-${abbr}-${dd}${mm}${yyyy}` : `Qt-${dd}${mm}${yyyy}`;
  window.print();
  document.title = prev;
}

// ── Quotation No. 자동 생성 ───────────────────────────────────────────────────
const poAutoGenerated = ref('');

function generateQuotationNo(): string {
  const date    = form.value.deliveryDate || new Date().toISOString().slice(0, 10);
  const dateStr = date.replace(/-/g, '');
  const initials = form.value.customerName
    .trim()
    .split(/\s+/)
    .map(w => w[0]?.toUpperCase() ?? '')
    .join('')
    .slice(0, 4);
  return initials ? `QT-${dateStr}-${initials}` : `QT-${dateStr}`;
}

watch(
  [() => form.value.customerName, () => form.value.deliveryDate],
  () => {
    if (form.value.quoteNumber === '' || form.value.quoteNumber === poAutoGenerated.value) {
      const next = generateQuotationNo();
      form.value.quoteNumber = next;
      poAutoGenerated.value  = next;
    }
  },
);

// ── 견적서 저장/불러오기 ─────────────────────────────────────────────────────
interface QuoteSummary {
  id:            string;
  quote_number:  string;
  quote_date:    string;
  customer_name: string | null;
  status:        string;
  created_at:    string;
  updated_at:    string;
}

const currentQuoteId     = ref<string | null>(null);
const currentQuoteNumber = ref<string | null>(null);
const isSaving           = ref(false);
const savingMode         = ref<'update' | 'new' | null>(null);   // 어느 저장 버튼이 도는 중인지
const saveSuccess        = ref(false);
const saveError          = ref<string | null>(null);
const showLoadModal      = ref(false);
const savedQuotes        = ref<QuoteSummary[]>([]);
const modalLoading       = ref(false);
const deletingId         = ref<string | null>(null);
const quoteSearch        = ref('');

// 업체명/견적번호로 견적 이력 검색
const filteredQuotes = computed(() => {
  const q = quoteSearch.value.trim().toLowerCase();
  if (!q) return savedQuotes.value;
  return savedQuotes.value.filter(it =>
    (it.customer_name ?? '').toLowerCase().includes(q) ||
    (it.quote_number  ?? '').toLowerCase().includes(q),
  );
});

// asNew=true → 불러온 견적을 덮어쓰지 않고 새 번호를 받아 별도 견적으로 저장
async function saveQuote(asNew = false) {
  savingMode.value  = asNew ? 'new' : 'update';
  isSaving.value    = true;
  saveSuccess.value = false;
  saveError.value   = null;
  try {
    const quoteData = {
      customer_name:       form.value.customerName   || null,
      sales_rep:           form.value.contactPerson  || null,
      warehouse:           form.value.originWH        || null,
      delivery_date:       form.value.deliveryDate    || null,
      delivery_method:     form.value.deliveryMethod  || null,
      payment_terms:       form.value.paymentTerms    || null,
      notes:               form.value.remarks         || null,
      additional_discount: additionalDiscount.value,
      status:              'draft',
      currency:            'USD',
    };

    // asNew 면 기존 id 를 무시하고 insert 경로로 보내 원본을 그대로 남긴다
    let quoteId = asNew ? null : currentQuoteId.value;

    if (quoteId) {
      await sbPatch(`quotes?id=eq.${quoteId}`, quoteData);
      await sbDelete(`quote_items?quote_id=eq.${quoteId}`);
    } else {
      const qn  = await sbRpc<string>('next_quote_number');
      const ins = await sbPost<Array<{ id: string; quote_number: string }>>('quotes', { ...quoteData, quote_number: qn });
      quoteId = ins[0].id;
      currentQuoteId.value     = quoteId;
      currentQuoteNumber.value = ins[0].quote_number;
      // 실제 발번된 번호를 입력칸에도 반영. 새로 저장 시 이전 견적 번호가 남아 있으면
      // 화면과 저장된 레코드가 어긋나 보인다 (불러오기 시 이 칸은 DB 번호로 채워짐).
      form.value.quoteNumber = ins[0].quote_number;
    }

    if (lines.value.length) {
      await sbPost('quote_items', lines.value.map((l, idx) => ({
        quote_id:    quoteId,
        line_no:     idx + 1,
        product_id:  l.productId   || null,
        type:        l.type        || null,
        brand:       l.brand       || null,
        description: l.description || null,
        qty:         l.qty,
        unit:        l.unit,
        wh_price:    l.whPrice,
        unit_price:  l.unitPrice,
        discount:    l.discount,
      })));
    }

    saveSuccess.value = true;
    setTimeout(() => { saveSuccess.value = false; }, 2500);
  } catch (e) {
    saveError.value = e instanceof Error ? e.message : String(e);
  }
  isSaving.value   = false;
  savingMode.value = null;
}

async function openLoadModal() {
  showLoadModal.value = true;
  quoteSearch.value   = '';
  modalLoading.value  = true;
  try {
    savedQuotes.value = await sbGet<QuoteSummary[]>(
      'quotes?select=id,quote_number,customer_name,status,created_at,updated_at&order=created_at.desc',
    );
  } catch {
    savedQuotes.value = [];
  }
  modalLoading.value = false;
}

async function loadQuote(id: string) {
  try {
    type QuoteRow = {
      id: string; quote_number: string;
      customer_name: string | null; customer_po: string | null;
      sales_rep: string | null; warehouse: string | null;
      delivery_date: string | null; delivery_method: string | null;
      payment_terms: string | null; notes: string | null;
      additional_discount: number;
    };
    type ItemRow = {
      product_id: string | null; type: string | null; brand: string | null;
      description: string | null; qty: number; unit: string;
      wh_price: number; unit_price: number; discount: number;
    };

    const [quoteArr, itemArr] = await Promise.all([
      sbGet<QuoteRow[]>(`quotes?id=eq.${id}&select=*`),
      sbGet<ItemRow[]>(`quote_items?quote_id=eq.${id}&order=line_no.asc`),
    ]);

    const q = quoteArr[0];
    form.value = {
      customerName:   q.customer_name   ?? '',
      quoteNumber: q.quote_number    ?? '',
      contactPerson:       q.sales_rep       ?? '',
      deliveryDate:   q.delivery_date   ?? '',
      originWH:       q.warehouse       ?? 'WH-Karawang',
      deliveryMethod: q.delivery_method ?? 'Self-Pickup',
      paymentTerms:   q.payment_terms   ?? 'CBD',
      remarks:        q.notes           ?? '',
    };
    additionalDiscount.value = q.additional_discount ?? 0;
    currentQuoteId.value     = q.id;
    currentQuoteNumber.value = q.quote_number;
    lines.value = itemArr.map(item => {
      const prod = item.product_id ? products.value.find(p => p.id === item.product_id) : null;
      return {
        id:          _id++,
        type:        item.type        ?? '',
        brand:       item.brand       ?? '',
        description: item.description ?? '',
        qty:         item.qty,
        unit:        item.unit as 'pcs' | 'set',
        unitPrice:   item.unit_price,
        whPrice:     item.wh_price,
        discount:    item.discount,
        productSku:  prod?.sku       ?? '',
        productId:   item.product_id ?? '',
        guestMargin: 15,
      };
    });
    if (lines.value.length === 0) lines.value = [newLine()];
    showLoadModal.value = false;
  } catch { /**/ }
}

async function deleteQuoteFromModal(id: string) {
  deletingId.value = id;
  try {
    await sbDelete(`quotes?id=eq.${id}`);
    savedQuotes.value = savedQuotes.value.filter(q => q.id !== id);
    if (currentQuoteId.value === id) { currentQuoteId.value = null; currentQuoteNumber.value = null; }
  } catch { /**/ }
  deletingId.value = null;
}

function resetForm() {
  currentQuoteId.value     = null;
  currentQuoteNumber.value = null;
  form.value               = emptyForm();
  additionalDiscount.value = 0;
  poAutoGenerated.value    = '';
  _id = 1;
  lines.value = [newLine()];
}

const cell   = 'w-full h-8 rounded border border-input bg-background px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary/50';
const ghost  = 'w-full h-8 border-0 bg-transparent px-1 text-xs focus:outline-none';
const select = 'w-full h-9 rounded border border-input bg-background px-3 text-sm focus:outline-none focus:ring-1 focus:ring-primary/50 appearance-none cursor-pointer';
</script>

<template>
  <div
    v-motion
    :initial="{ opacity: 0, y: 16 }"
    :enter="{ opacity: 1, y: 0, transition: { duration: 320 } }"
    class="quote-doc p-4 md:p-6 max-w-300 mx-auto space-y-5 pb-10"
  >
    <!-- 인쇄 문서 제목 (화면엔 아래 PageHeader에, 인쇄엔 이 제목만 표시) -->
    <h2 class="hidden print:block text-center text-2xl font-bold tracking-wide text-foreground">QUOTATION</h2>

    <!-- Header -->
    <PageHeader class="print:hidden">
      <!-- Quote는 문서형이라 제목을 화면 헤더에도 표시 -->
      <template #subtitle>
        <h2 class="text-lg font-bold tracking-tight text-foreground flex items-center gap-2">
          <ClipboardList :size="20" class="text-primary" /> QUOTATION
        </h2>
      </template>
      <template #actions>
        <!-- 모바일(390px)에서 SAVE·Print 가 화면 밖으로 밀려 아예 누를 수 없었다 → 줄바꿈 허용 -->
        <div class="flex flex-wrap items-center justify-end gap-2 max-w-full">
        <span v-if="productsLoading" class="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Loader2 :size="12" class="animate-spin" />
          Item is loading…
        </span>
        <span v-else-if="products.length" class="text-xs text-muted-foreground/60">
          {{ products.length }}개 제품
        </span>
        <span v-if="currentQuoteNumber" class="text-xs px-2 py-0.5 bg-warning-soft text-warning rounded-full font-mono print:hidden">
          수정 중 · {{ currentQuoteNumber }}
        </span>
        <span v-if="saveSuccess" class="text-xs text-success print:hidden">✓ Saved</span>
        <span v-if="saveError" class="text-xs text-destructive print:hidden max-w-xs truncate" :title="saveError">저장 실패: {{ saveError }}</span>
        <Button variant="ghost" size="sm" class="gap-1.5 text-xs print:hidden" @click="resetForm">
          <FilePlus :size="13" />New
        </Button>
        <Button v-if="canSaveImport" variant="outline" size="sm" class="gap-1.5 text-xs print:hidden" @click="openLoadModal">
          <FolderOpen :size="13" />Import
        </Button>
        <!-- 이 화면의 주요 CTA — solid 는 화면당 1개(가이드 2항) -->
        <Button v-if="canSaveImport" variant="solid" size="sm" class="gap-1.5 text-xs print:hidden" :disabled="isSaving" @click="saveQuote()">
          <Loader2 v-if="savingMode === 'update'" :size="13" class="animate-spin" />
          <Save v-else :size="13" />
          {{ savingMode === 'update' ? 'Saving…' : (currentQuoteId ? '수정 저장' : 'SAVE') }}
        </Button>
        <!-- 불러온 견적을 원본 유지한 채 새 번호로 복제 저장 -->
        <Button
          v-if="canSaveImport && currentQuoteId"
          variant="outline"
          size="sm"
          class="gap-1.5 text-xs print:hidden"
          :disabled="isSaving"
          @click="saveQuote(true)"
        >
          <Loader2 v-if="savingMode === 'new'" :size="13" class="animate-spin" />
          <Copy v-else :size="13" />
          {{ savingMode === 'new' ? 'Saving…' : '새로 저장' }}
        </Button>
        <Button variant="outline" size="sm" class="gap-1.5 text-xs print:hidden" @click="handlePrint">
          <Printer :size="13" />Print / PDF
        </Button>
        </div>
      </template>
    </PageHeader>

    <!-- Order Information (아코디언) -->
    <div v-if="!isQuoteOnly" class="rounded-xl border border-border bg-card overflow-hidden order-info">
      <button
        type="button"
        class="w-full flex items-center gap-3 px-5 py-3 bg-muted/20 hover:bg-muted/30 transition-colors text-left print:cursor-default"
        :class="showOrderInfo ? 'border-b border-border' : 'print:border-b print:border-border'"
        :aria-expanded="showOrderInfo"
        @click="showOrderInfo = !showOrderInfo"
      >
        <span class="text-sm font-bold text-primary bg-primary/10 px-1.5 py-0.5 rounded">I</span>
        <span class="font-semibold text-sm flex-1">Order Information</span>
        <ChevronDown
          :size="16"
          class="text-muted-foreground transition-transform duration-200 shrink-0 print:hidden"
          :class="!showOrderInfo && '-rotate-90'"
        />
      </button>
      <div v-show="showOrderInfo" class="order-info-body px-4 sm:px-10 py-5 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 print:grid-cols-3 gap-x-5 gap-y-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Customer Name <span class="text-destructive">*</span></label>
          <input
            v-model="form.customerName"
            type="text"
            autocomplete="off"
            :class="cell + ' h-9 text-sm px-3'"
            placeholder="고객명 입력 · 기존 고객 검색"
            @focus="openCustAc"
            @input="openCustAc"
            @blur="closeCustAc"
            @keydown="onCustomerKeydown"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Quotation No.</label>
          <input v-model="form.quoteNumber" type="text" :class="cell + ' h-9 text-sm px-3'" />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Contact Person</label>
          <input v-model="form.contactPerson" type="text" :class="cell + ' h-9 text-sm px-3'" placeholder="Name of PIC" />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Quotation Date <span class="text-destructive">*</span></label>
          <input v-model="form.deliveryDate" type="date" :class="cell + ' h-9 text-sm px-3'" />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Origin WH</label>
          <div class="relative">
            <select v-model="form.originWH" :class="select + ' pr-8'">
              <option v-for="w in WAREHOUSES" :key="w">{{ w }}</option>
            </select>
            <span class="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground text-xs">▾</span>
          </div>
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Delivery Method</label>
          <div class="relative">
            <select v-model="form.deliveryMethod" :class="select + ' pr-8'">
              <option v-for="m in DELIVERY_METHODS" :key="m">{{ m }}</option>
            </select>
            <span class="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground text-xs">▾</span>
          </div>
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Payment Terms</label>
          <div class="relative">
            <select v-model="form.paymentTerms" :class="select + ' pr-8'">
              <option v-for="t in PAYMENT_TERMS" :key="t">{{ t }}</option>
            </select>
            <span class="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground text-xs">▾</span>
          </div>
        </div>
        <div class="col-span-2 flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Remarks</label>
          <input v-model="form.remarks" type="text" :class="cell + ' h-9 text-sm px-3'" />
        </div>
      </div>
    </div>

    <!-- Item Detail -->
    <div class="rounded-xl border border-border bg-card overflow-hidden">
      <div class="flex items-center justify-between px-5 py-3 border-b border-border bg-muted/20">
        <div class="flex items-center gap-3">
          <span class="text-sm font-bold text-primary bg-primary/10 px-1.5 py-0.5 rounded">II</span>
          <span class="font-semibold text-sm">Item Detail</span>
        </div>
        <button
          class="flex items-center gap-1.5 text-xs border border-border/60 hover:border-primary/40 hover:text-primary px-3 py-1.5 rounded-md transition-colors print:hidden"
          @click="addLine"
        >
          + Add Line
        </button>
      </div>

      <div class="overflow-x-auto px-10">
        <table class="w-full text-sm border-collapse">
          <caption class="sr-only">견적 품목 명세</caption>
          <colgroup>
            <col :style="{ width: '2%' }" />
            <col :style="{ width: '8%' }" />
            <col :style="{ width: '10%' }" />
            <col />
            <col :style="{ width: '8%' }" />
            <col :style="{ width: '2%' }" />
            <col class="print:hidden" :style="{ width: '10%' }" /> <!-- Dist Price -->
            <col class="print:hidden" :style="{ width: '5%' }" />  <!-- Discount -->
            <col :style="{ width: '10%' }" />
            <col class="print:hidden" :style="{ width: '3%' }" />  <!-- Margin -->
            <col :style="{ width: '10%' }" />
            <col :style="{ width: '2%' }" />
          </colgroup>
          <thead>
            <tr class="border-b border-border bg-muted/10">
              <th scope="col" class="hidden md:table-cell text-left   px-3 py-2.5 text-xs font-semibold text-muted-foreground">No.</th>
              <th scope="col" class="hidden md:table-cell text-left   px-2 py-2.5 text-xs font-semibold text-muted-foreground">Item</th>
              <th scope="col" class="hidden md:table-cell text-left   px-2 py-2.5 text-xs font-semibold text-muted-foreground">Brand</th>
              <th scope="col" class="w-full md:w-auto text-left px-2 py-2.5 text-xs font-semibold text-muted-foreground">Item Description</th>
              <th scope="col" class="hidden md:table-cell text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground">Qty</th>
              <th scope="col" class="hidden md:table-cell text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground">Unit</th>
              <th scope="col" class="hidden md:table-cell text-right  px-2 py-2.5 text-xs font-semibold text-muted-foreground print:hidden">Dist Price</th>
              <th scope="col" class="hidden md:table-cell text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground print:hidden">Discount</th>
              <th scope="col" class="text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground">Unit Price</th>
              <th scope="col" class="text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground print:hidden">Margin</th>
              <th scope="col" class="hidden md:table-cell text-right  px-3 py-2.5 text-xs font-semibold text-muted-foreground">Amount</th>
              <th scope="col" class="hidden md:table-cell" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(line, idx) in lines"
              :key="line.id"
              class="border-b border-border/40 hover:bg-muted/5 transition-colors group"
            >
              <td class="hidden md:table-cell px-3 py-1.5 text-xs text-muted-foreground">{{ idx + 1 }}</td>
              <td class="hidden md:table-cell px-1 py-1.5">
                <input v-model="line.type" type="text" :class="ghost" placeholder="Type" />
              </td>
              <td class="hidden md:table-cell px-1 py-1.5">
                <input v-model="line.brand" type="text" :class="ghost" placeholder="Brand" />
              </td>
              <td class="w-full md:w-auto px-2 py-1.5">
                <input
                  v-model="line.description"
                  type="text"
                  autocomplete="off"
                  :class="cell + ' print:border-transparent print:bg-transparent'"
                  placeholder="Input Keyword, Select Product"
                  @focus="(e) => openAc(e, line)"
                  @input="(e) => openAc(e, line)"
                  @blur="closeAc"
                  @keydown="(e) => onDescriptionKeydown(e, line)"
                />
              </td>
              <td class="hidden md:table-cell px-2 py-1.5">
                <input
                  type="text"
                  inputmode="numeric"
                  :value="fmtInput(line.qty)"
                  :class="cell + ' text-center tabular-nums print:border-transparent print:bg-transparent'"
                  placeholder="0"
                  @change="onQtyChange(line, ($event.target as HTMLInputElement).value)"
                />
              </td>
              <td class="hidden md:table-cell px-1 py-1.5">
                <select
                  v-model="line.unit"
                  :class="ghost + ' appearance-none cursor-pointer text-center'"
                  @change="onUnitChange(line)"
                >
                  <option value="pcs">pcs</option>
                  <option value="set">set</option>
                </select>
              </td>
              <td class="hidden md:table-cell px-2 py-1.5 text-right text-xs font-mono tabular-nums text-muted-foreground print:hidden">
                {{ Math.round(distPriceOf(line) * markup).toLocaleString('en-US') || '0' }}
              </td>
              <td class="hidden md:table-cell px-2 py-1.5 print:hidden">
                <div class="flex items-center gap-1">
                  <input v-model.number="line.discount" type="number" min="0" max="100" :class="cell + ' text-center'" />
                  <span class="text-xs text-muted-foreground shrink-0">%</span>
                </div>
              </td>
              <td class="px-2 py-1.5">
                <input
                  type="text"
                  :value="fmtInput(Math.round(lineNetPrice(line) * markup))"
                  :class="cell + ' text-right font-mono tabular-nums print:border-transparent print:bg-transparent'"
                  placeholder="0"
                  @change="onNetPriceChange(line, ($event.target as HTMLInputElement).value)"
                />
              </td>
              <td class="px-2 py-1.5 print:hidden">
                <div class="flex items-center justify-end gap-0.5">
                  <input
                    type="number"
                    step="0.1"
                    :value="lineMarginNum(line)"
                    :class="['w-16 h-8 rounded border border-input bg-background px-2 text-xs text-center font-semibold tabular-nums focus:outline-none focus:ring-1 focus:ring-primary/50', marginColor(line)]"
                    :disabled="!line.whPrice"
                    @change="onMarginChange(line, ($event.target as HTMLInputElement).value)"
                  />
                  <span class="text-xs text-muted-foreground shrink-0">%</span>
                </div>
              </td>
              <td class="hidden md:table-cell px-2 py-1.5 text-right text-xs font-mono tabular-nums font-semibold">
                {{ fmtInput(lineAmount(line) * markup) || '0' }}
              </td>
              <td class="hidden md:table-cell py-1.5 pr-2">
                <button
                  class="opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground/40 hover:text-destructive"
                  @click="removeLine(line.id)"
                >
                  <Trash2 :size="12" />
                </button>
              </td>
            </tr>
          </tbody>
          <tfoot>
            <!-- ── 모바일(sm): 3컬럼 합계 (Item Description · Unit Price · Margin 만 표시) ── -->
            <tr class="md:hidden border-t-2 border-border bg-muted/5">
              <td colspan="2" class="px-3 py-2.5 text-sm font-bold">Sub-Total</td>
              <td class="px-2 py-2.5 text-right text-sm font-bold font-mono tabular-nums">{{ fmt(mSubTotal) }}</td>
            </tr>
            <tr class="md:hidden border-t border-border/40">
              <td class="pl-3 py-2.5 text-xs text-muted-foreground">Add. Disc</td>
              <td class="py-2.5">
                <div class="flex items-center justify-center gap-1">
                  <input
                    v-model.number="additionalDiscount"
                    type="number" min="0" max="100"
                    class="w-12 h-7 rounded border border-input bg-background px-1 text-xs text-center focus:outline-none focus:ring-1 focus:ring-primary/50 print:border-transparent print:bg-transparent"
                  />
                  <span class="text-xs text-muted-foreground">%</span>
                </div>
              </td>
              <td class="px-2 py-2.5 text-right text-sm font-mono tabular-nums text-destructive">
                {{ mDiscAmount > 0 ? '-' + fmt(mDiscAmount) : '0' }}
              </td>
            </tr>
            <tr class="md:hidden border-t border-border/40">
              <td colspan="2" class="pl-3 py-2.5 text-sm text-muted-foreground">PPN (11%)</td>
              <td class="px-2 py-2.5 text-right text-sm font-mono tabular-nums">{{ fmt(mPPN) }}</td>
            </tr>
            <tr v-if="mTruncation < 0" class="md:hidden border-t border-border/40">
              <td colspan="2" class="pl-3 py-2.5 text-sm text-muted-foreground">Truncation</td>
              <td class="px-2 py-2.5 text-right text-sm font-mono tabular-nums text-destructive">{{ fmt(mTruncation) }}</td>
            </tr>
            <tr class="md:hidden border-t border-border/40">
              <td colspan="2" class="pl-3 py-3 text-sm font-bold">Total (incl. PPN)</td>
              <td class="px-2 py-3 text-right text-base font-bold font-mono tabular-nums text-primary">{{ fmt(mTotal) }}</td>
            </tr>
            <tr class="md:hidden">
              <td colspan="3" class="total-rule h-1.5 bg-foreground p-0" />
            </tr>

            <!-- ── 데스크탑(md+): 전체 12컬럼 합계 ── -->
            <tr class="hidden md:table-row border-t-2 border-border bg-muted/5">
              <td colspan="4" class="px-3 py-2.5 text-sm font-bold">Sub-Total</td>
              <td class="py-2.5 text-center text-sm font-bold tabular-nums">{{ fmt(subTotalQty) }}</td>
              <td colspan="5" />
              <td class="px-3 py-2.5 text-right text-sm font-bold font-mono tabular-nums">{{ fmt(mSubTotal) }}</td>
              <td />
            </tr>
            <!-- Additional Discount / PPN / Truncation / Total — share same colgroup as line items for alignment -->
            <tr class="hidden md:table-row border-t border-border/40">
              <td colspan="8" class="pl-5 py-2.5 text-sm text-muted-foreground">Additional Discount</td>
              <td class="px-2 py-2.5">
                <div class="flex items-center justify-end gap-0.5">
                  <input
                    v-model.number="additionalDiscount"
                    type="number" min="0" max="100"
                    class="w-10 h-7 rounded border border-input bg-background px-1 text-xs text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-primary/50 print:border-transparent print:bg-transparent"
                  />
                  <span class="text-xs text-muted-foreground">%</span>
                </div>
              </td>
              <td />
              <td class="px-3 py-2.5 text-right text-sm font-mono tabular-nums text-destructive">
                {{ mDiscAmount > 0 ? '-' + fmt(mDiscAmount) : '0' }}
              </td>
              <td />
            </tr>
            <tr class="hidden md:table-row border-t border-border/40">
              <td colspan="6" class="pl-5 py-2.5 text-sm text-muted-foreground">PPN (11%)</td>
              <td /><td />
              <td /><td />
              <td class="px-3 py-2.5 text-right text-sm font-mono tabular-nums">{{ fmt(mPPN) }}</td>
              <td />
            </tr>
            <tr class="hidden md:table-row border-t border-border/40">
              <td colspan="6" class="pl-5 py-2.5 text-sm text-muted-foreground">Truncation (1,000↓)</td>
              <td /><td /><td /><td />
              <td class="px-3 py-2.5 text-right text-sm font-mono tabular-nums text-destructive">
                {{ mTruncation < 0 ? fmt(mTruncation) : '' }}
              </td>
              <td />
            </tr>
            <tr class="hidden md:table-row border-t border-border/40">
              <td colspan="6" class="pl-5 py-3 text-sm font-bold">Total (incl. PPN)</td>
              <td /><td /><td /><td />
              <td class="px-3 py-3 text-right text-base font-bold font-mono tabular-nums text-primary">
                {{ fmt(mTotal) }}
              </td>
              <td />
            </tr>
            <!-- Total 하단 강조선 -->
            <tr class="hidden md:table-row">
              <td colspan="12" class="total-rule h-0.5 bg-primary p-0" />
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  </div>

  <!-- 견적서 불러오기 모달 -->
  <Teleport to="body">
    <div
      v-if="showLoadModal"
      class="fixed inset-0 z-9998 flex items-center justify-center bg-black/60"
      @click.self="showLoadModal = false"
    >
      <div class="bg-card border border-border rounded-xl w-full max-w-2xl mx-4 shadow-2xl overflow-hidden">
        <div class="flex items-center justify-between px-5 py-4 border-b border-border">
          <h2 class="text-sm font-bold flex items-center gap-2">
            <FolderOpen :size="16" class="text-primary" />
            저장된 견적서
          </h2>
          <button class="p-1 rounded hover:bg-accent transition-colors" @click="showLoadModal = false">
            <X :size="16" />
          </button>
        </div>
        <div class="px-5 py-3 border-b border-border">
          <input
            v-model="quoteSearch"
            type="text"
            placeholder="업체명 또는 견적번호 검색"
            class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>
        <div class="max-h-112 overflow-y-auto">
          <div v-if="modalLoading" class="flex justify-center py-12">
            <Loader2 :size="20" class="animate-spin text-muted-foreground" />
          </div>
          <div v-else-if="!savedQuotes.length" class="py-12 text-center text-sm text-muted-foreground">
            저장된 견적서가 없습니다.
          </div>
          <div v-else-if="!filteredQuotes.length" class="py-12 text-center text-sm text-muted-foreground">
            "{{ quoteSearch }}" 검색 결과가 없습니다.
          </div>
          <div v-else class="divide-y divide-border/40">
            <div
              v-for="q in filteredQuotes"
              :key="q.id"
              class="flex items-center gap-3 px-5 py-3 hover:bg-muted/10 transition-colors"
            >
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-xs font-mono text-primary">{{ q.quote_number }}</span>
                  <span class="text-[10px] px-1.5 py-0.5 rounded-full bg-muted/50 text-muted-foreground capitalize">
                    {{ q.status }}
                  </span>
                </div>
                <div class="text-sm font-medium mt-0.5 truncate">{{ q.customer_name || '(고객명 없음)' }}</div>
                <div class="text-[10px] text-muted-foreground mt-0.5">
                  {{ q.updated_at.slice(0, 16).replace('T', ' ') }}
                </div>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <button
                  class="text-xs px-3 py-1.5 rounded-md border border-border hover:border-primary/40 hover:text-primary transition-colors"
                  @click="loadQuote(q.id)"
                >
                  불러오기
                </button>
                <button
                  class="p-1.5 rounded-md text-muted-foreground/50 hover:text-destructive transition-colors disabled:opacity-40"
                  :disabled="deletingId === q.id"
                  @click="deleteQuoteFromModal(q.id)"
                >
                  <Loader2 v-if="deletingId === q.id" :size="13" class="animate-spin" />
                  <Trash2 v-else :size="13" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>

  <!-- 고객명 자동완성 드롭다운 -->
  <Teleport to="body">
    <div
      v-if="custAc.open && custSuggestions.length > 0 && custAc.rect"
      class="fixed z-9999 rounded-lg border border-border bg-card shadow-xl overflow-hidden print:hidden"
      :style="{
        top:       `${custAc.rect.bottom + 4}px`,
        left:      `${custAc.rect.left}px`,
        minWidth:  `${Math.max(custAc.rect.width, 280)}px`,
        maxHeight: '280px',
        overflowY: 'auto',
      }"
      @mousedown.prevent
    >
      <div
        v-for="(c, i) in custSuggestions"
        :key="c.id"
        class="ac-item flex items-center gap-3 px-3 py-2.5 cursor-pointer border-b border-border/30 last:border-0"
        :class="i === custAcIdx ? 'bg-primary/10' : 'hover:bg-accent'"
        @click="selectCustomer(c)"
      >
        <div class="flex-1 min-w-0">
          <div class="text-xs font-medium text-foreground truncate">{{ c.customer_name }}</div>
          <div class="flex items-center gap-1.5 mt-0.5 text-[10px] text-muted-foreground">
            <span class="font-mono">{{ c.customer_code }}</span>
            <template v-if="c.main_pic_name">
              <span class="text-muted-foreground/40">·</span>
              <span>PIC {{ c.main_pic_name }}</span>
            </template>
          </div>
        </div>
      </div>
    </div>
  </Teleport>

  <!-- 자동완성 드롭다운 -->
  <Teleport to="body">
    <div
      v-if="acState.lineId !== null && acSuggestions.length > 0 && acState.rect"
      class="fixed z-9999 rounded-lg border border-border bg-card shadow-xl overflow-hidden"
      :style="{
        top:       `${acState.rect.bottom + 4}px`,
        left:      `${acState.rect.left}px`,
        minWidth:  `${Math.max(acState.rect.width, isQuoteOnly ? 260 : 400)}px`,
        maxHeight: '280px',
        overflowY: 'auto',
      }"
      @mousedown.prevent
    >
      <div
        v-for="(p, i) in acSuggestions"
        :key="p.sku"
        class="ac-item flex items-center gap-3 px-3 py-2.5 cursor-pointer border-b border-border/30 last:border-0"
        :class="i === acIdx ? 'bg-primary/10' : 'hover:bg-accent'"
        @click="selectSuggestion(p)"
      >
        <div class="flex-1 min-w-0">
          <div class="text-xs font-medium text-foreground truncate">{{ p.description }}</div>
          <div class="flex items-center gap-1.5 mt-0.5 text-[10px] text-muted-foreground">
            <span>{{ p.brand }}</span>
            <span class="text-muted-foreground/40">·</span>
            <span class="font-mono">{{ p.sku }}</span>
            <template v-if="p.item">
              <span class="text-muted-foreground/40">·</span>
              <span>{{ p.item }}</span>
            </template>
          </div>
        </div>
        <div v-if="!isQuoteOnly" class="text-right shrink-0 text-[10px] font-mono">
          <div class="text-foreground">{{ (p.wh_price_pcs ?? 0).toLocaleString() }} <span class="text-muted-foreground/50">pcs</span></div>
          <div v-if="p.wh_price_set" class="text-muted-foreground">
            {{ (p.wh_price_set ?? 0).toLocaleString() }} <span class="text-muted-foreground/50">set</span>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
select option { background: var(--background); color: var(--foreground); }
input[type="date"]::-webkit-calendar-picker-indicator { opacity: 0.5; cursor: pointer; }
/* 숫자 입력칸 ▴▾ 스피너 완전 숨김 (화면·인쇄 공통) */
input[type="number"]::-webkit-inner-spin-button,
input[type="number"]::-webkit-outer-spin-button {
  -webkit-appearance: none;
  appearance: none;
  margin: 0;
}
input[type="number"] {
  -moz-appearance: textfield;
  appearance: textfield;
}
@page { size: A4 portrait; margin: 20mm; }
@media print {
  /* 인쇄도 화면(데스크탑)과 동일한 전체 컬럼 레이아웃 유지 */
  .quote-doc .md\:table-cell { display: table-cell !important; }
  .quote-doc .md\:table-row  { display: table-row !important; }
  .quote-doc .md\:hidden     { display: none !important; }
  .quote-doc .md\:w-auto     { width: auto !important; }

  /* 조작용 UI(버튼 등 print:hidden)만 출력에서 제외 */
  .quote-doc .print\:hidden { display: none !important; }
  /* 인쇄 숨김 열(Dist Price·Discount·Margin)은 display:none 하지 않고 폭 0 + 내용 클리핑으로 처리.
     (열/셀을 display:none 하면 컬럼 모델이 붕괴 → thead·tbody(개별셀) vs tfoot(colspan) 정렬 어긋남.
      12열 구조를 그대로 유지해야 세 영역의 Amount 열이 같은 위치에 정렬됨) */
  .quote-doc col.print\:hidden { display: table-column !important; width: 0 !important; }
  .quote-doc table th.print\:hidden,
  .quote-doc table td.print\:hidden {
    display: table-cell !important;
    width: 0 !important;
    max-width: 0 !important;
    padding: 0 !important;
    overflow: hidden !important;
    white-space: nowrap !important;
  }
  /* 인쇄는 colgroup 폭 고정(table-fixed) + 각 열 폭 명시(합계 100%, 숨김열=0)
     → 남는 폭을 Description 이 흡수하고 Amount 가 우측 가장자리에 정렬됨(좌우 배분) */
  .quote-doc table { table-layout: fixed !important; width: 100% !important; }
  .quote-doc table > colgroup > col:nth-child(1)  { width: 4%  !important; } /* No */
  .quote-doc table > colgroup > col:nth-child(2)  { width: 8%  !important; } /* Item */
  .quote-doc table > colgroup > col:nth-child(3)  { width: 10% !important; } /* Brand */
  .quote-doc table > colgroup > col:nth-child(4)  { width: 34% !important; } /* Description */
  .quote-doc table > colgroup > col:nth-child(5)  { width: 8%  !important; } /* Qty */
  .quote-doc table > colgroup > col:nth-child(6)  { width: 5%  !important; } /* Unit */
  .quote-doc table > colgroup > col:nth-child(7)  { width: 0   !important; } /* Dist Price(숨김) */
  .quote-doc table > colgroup > col:nth-child(8)  { width: 0   !important; } /* Discount(숨김) */
  .quote-doc table > colgroup > col:nth-child(9)  { width: 15% !important; } /* Unit Price */
  .quote-doc table > colgroup > col:nth-child(10) { width: 0   !important; } /* Margin(숨김) */
  .quote-doc table > colgroup > col:nth-child(11) { width: 16% !important; } /* Amount (기존 12% + 여백 4% 흡수) */
  .quote-doc table > colgroup > col:nth-child(12) { width: 0   !important; } /* delete(숨김) — 여백 열 제거, px-10 거터로 통일 */
  /* Amount 열(11번째) 숫자 우측 끝을 가이드선 안쪽으로 살짝 들여 정렬.
     헤더·본문(nth-child 11)·합계(tfoot, colspan이라 nth-child 안 걸림) 모두 같은 여백 → 함께 이동해 정렬 유지 */
  .quote-doc table th:nth-child(11),
  .quote-doc table td:nth-child(11),
  .quote-doc table tfoot td { padding-right: 0.5rem !important; }

  /* Order Information 입력/셀렉트/날짜 박스 테두리·배경 인쇄 시 숨김(값만 텍스트로) */
  .quote-doc .order-info-body input,
  .quote-doc .order-info-body select {
    border-color: transparent !important;
    background-color: transparent !important;
    box-shadow: none !important;
  }

  /* 인쇄는 배경 그래픽 없이 출력 — 음영·색 채움을 모두 없애고 선(border)·글자색만 남긴다 */
  .quote-doc,
  .quote-doc * {
    background-color: transparent !important;
    background-image: none !important;
    box-shadow: none !important;
  }
  /* 배경으로 그리던 구분선(Sub-Total 위 굵은 선 · Total 아래 파란 선)은 border 로 대체 */
  .quote-doc .total-rule {
    height: 0 !important;
    border-top-style: solid !important;
  }
  .quote-doc .total-rule.bg-foreground { border-top-width: 2px !important; border-top-color: var(--foreground) !important; }
  .quote-doc .total-rule.bg-primary    { border-top-width: 2px !important; border-top-color: var(--primary) !important; }

  /* 한 페이지에 맞도록 압축 */
  .quote-doc {
    max-width: none !important;
    padding: 0 !important;
    margin: 0 !important;
    zoom: 0.8;
  }
  .quote-doc > * + * { margin-top: 0.5rem !important; }
  .quote-doc tr { break-inside: avoid; }

  /* Order Information 접힘 강제 표시 */
  .quote-doc .order-info .order-info-body { display: grid !important; }
}
.ac-item { transition: background 80ms; }
</style>
