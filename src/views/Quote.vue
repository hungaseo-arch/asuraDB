<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';
import { ClipboardList, Trash2, Printer, Loader2, Save, FolderOpen, FilePlus, X } from 'lucide-vue-next';
import Button from '@/components/ui/Button.vue';
const SB_URL     = import.meta.env.VITE_SB_URL as string;
const SB_KEY     = import.meta.env.VITE_SB_KEY as string;
const SB_HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` };
const SB_JSON    = { ...SB_HEADERS, 'Content-Type': 'application/json' };

async function sbGet<T>(path: string): Promise<T> {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, { headers: SB_HEADERS });
  return res.json() as Promise<T>;
}
async function sbPost<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method: 'POST',
    headers: { ...SB_JSON, Prefer: 'return=representation' },
    body: JSON.stringify(body),
  });
  return res.json() as Promise<T>;
}
async function sbPatch(path: string, body: unknown): Promise<void> {
  await fetch(`${SB_URL}/rest/v1/${path}`, {
    method: 'PATCH', headers: SB_JSON, body: JSON.stringify(body),
  });
}
async function sbDelete(path: string): Promise<void> {
  await fetch(`${SB_URL}/rest/v1/${path}`, { method: 'DELETE', headers: SB_HEADERS });
}
async function sbRpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: SB_JSON, body: JSON.stringify(args),
  });
  return res.json() as Promise<T>;
}

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
  wh_price:     number;
  wh_price_set: number;
  unit:         'pcs' | 'set';
}

const products        = ref<Product[]>([]);
const productsLoading = ref(false);

async function loadProducts() {
  productsLoading.value = true;
  try {
    const res  = await fetch(
      `${SB_URL}/rest/v1/products?select=id,item,brand,description,sku,wh_price,wh_price_set,unit&is_active=eq.true&order=brand.asc,description.asc`,
      { headers: SB_HEADERS },
    );
    const data = await res.json() as Product[];
    products.value = data ?? [];
  } catch {
    products.value = [];
  }
  productsLoading.value = false;
}

onMounted(() => { void loadProducts(); });

const isQuoteOnly = sessionStorage.getItem('asura_auth') === 'quote';

const today = () => new Date().toISOString().slice(0, 10);

const form = ref({
  customerName: '', quoteNumber: '', contactPerson: '',
  deliveryDate: today(), originWH: 'WH-Karawang',
  deliveryMethod: 'Self-Pickup', paymentTerms: 'CBD', remarks: '',
});

const additionalDiscount = ref(0);

interface LineItem {
  id:          number;
  type:        string;
  brand:       string;
  description: string;
  qty:         number;
  unit:        'pcs' | 'set';
  unitPrice:   number;
  whPrice:     number;
  discount:    number;
  productSku:  string;
  productId:   string;
}

let _id = 1;
function newLine(): LineItem {
  return { id: _id++, type: '', brand: '', description: '', qty: 0, unit: 'pcs', unitPrice: 0, whPrice: 0, discount: 0, productSku: '', productId: '' };
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
      p.description.toLowerCase().includes(q) ||
      (p.brand ?? '').toLowerCase().includes(q) ||
      (p.sku   ?? '').toLowerCase().includes(q) ||
      (p.item  ?? '').toLowerCase().includes(q)
    )
    .slice(0, 8);
});

function openAc(e: Event, line: LineItem) {
  const r = (e.target as HTMLInputElement).getBoundingClientRect();
  acState.value = { lineId: line.id, rect: { bottom: r.bottom, left: r.left, width: r.width } };
  acIdx.value   = -1;
}
function closeAc() { acState.value = { lineId: null, rect: null }; acIdx.value = -1; }

function selectSuggestion(p: Product) {
  const line = acLine.value;
  if (!line) return;
  line.description = p.description;
  line.productSku  = p.sku;
  line.productId   = p.id;
  line.type        = p.item  || line.type;
  line.brand       = p.brand || line.brand;
  line.whPrice     = line.unit === 'set' ? p.wh_price_set : p.wh_price;
  line.unitPrice   = Math.round(line.whPrice / 0.8);
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
  if (p) {
    line.whPrice   = line.unit === 'set' ? p.wh_price_set : p.wh_price;
    line.unitPrice = Math.round(line.whPrice / 0.8);
  }
}

// ── 계산 ─────────────────────────────────────────────────────────────────────
function lineNetPrice(l: LineItem): number { return (l.unitPrice || 0) * (1 - (l.discount || 0) / 100); }

function lineAmount(l: LineItem):   number { return (l.qty || 0) * lineNetPrice(l); }

function lineMargin(l: LineItem): string {
  if (!l.whPrice || !l.unitPrice) return '';
  const m = (lineNetPrice(l) - l.whPrice) / l.whPrice * 100;
  return (m >= 0 ? '+' : '') + m.toFixed(1) + '%';
}
function marginColor(l: LineItem): string {
  if (!l.whPrice || !l.unitPrice) return '';
  const m = (lineNetPrice(l) - l.whPrice) / l.whPrice;
  return m >= 0.05 ? 'text-green-400' : m >= 0 ? 'text-yellow-400' : 'text-destructive';
}

const subTotalQty    = computed(() => lines.value.reduce((s, l) => s + (l.qty || 0), 0));
const subTotalAmount = computed(() => lines.value.reduce((s, l) => s + lineAmount(l), 0));
const discAmount     = computed(() => subTotalAmount.value * (additionalDiscount.value / 100));
const afterDisc      = computed(() => subTotalAmount.value - discAmount.value);
const ppnAmount      = computed(() => afterDisc.value * PPN_RATE);
const totalFinal     = computed(() => Math.floor((afterDisc.value + ppnAmount.value) / 1000) * 1000);
const truncation     = computed(() => totalFinal.value - (afterDisc.value + ppnAmount.value));

// ── 포맷 헬퍼 ─────────────────────────────────────────────────────────────────
function fmt(n: number):      string { return n ? Math.round(Math.abs(n)).toLocaleString('en-US') : '0'; }
function fmtInput(n: number): string { return n ? n.toLocaleString('en-US') : ''; }
function parseNum(s: string): number { return parseInt(s.replace(/,/g, ''), 10) || 0; }

function handlePrint() { window.print(); }

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
const saveSuccess        = ref(false);
const showLoadModal      = ref(false);
const savedQuotes        = ref<QuoteSummary[]>([]);
const modalLoading       = ref(false);
const deletingId         = ref<string | null>(null);

async function saveQuote() {
  isSaving.value    = true;
  saveSuccess.value = false;
  try {
    const quoteData = {
      customer_name:       form.value.customerName   || null,
      quote_no:            form.value.quoteNumber     || null,
      contact_person:      form.value.contactPerson       || null,
      warehouse:           form.value.originWH       || null,
      quote_date:          form.value.deliveryDate || null,
      delivery_method:     form.value.deliveryMethod || null,
      payment_terms:       form.value.paymentTerms   || null,
      notes:               form.value.remarks        || null,
      additional_discount: additionalDiscount.value,
      status:              'draft',
      currency:            'USD',
    };

    let quoteId = currentQuoteId.value;

    if (quoteId) {
      await sbPatch(`quotes?id=eq.${quoteId}`, quoteData);
      await sbDelete(`quote_items?quote_id=eq.${quoteId}`);
    } else {
      const qn  = await sbRpc<string>('next_quote_number');
      const ins = await sbPost<Array<{ id: string; quote_number: string }>>('quotes', { ...quoteData, quote_number: qn });
      quoteId = ins[0].id;
      currentQuoteId.value     = quoteId;
      currentQuoteNumber.value = ins[0].quote_number;
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
  } catch { /**/ }
  isSaving.value = false;
}

async function openLoadModal() {
  showLoadModal.value = true;
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
  form.value = {
    customerName: '', quoteNumber: '', contactPerson: '',
    deliveryDate: today(), originWH: 'WH-Karawang',
    deliveryMethod: 'Self-Pickup', paymentTerms: 'CBD', remarks: '',
  };
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
    class="p-4 md:p-6 max-w-6xl mx-auto space-y-5 pb-10"
  >
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-xl font-bold flex items-center gap-2">
          <ClipboardList :size="20" class="text-primary" />
          Quotation
        </h1>
      </div>
      <div class="flex items-center gap-2">
        <span v-if="productsLoading" class="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Loader2 :size="12" class="animate-spin" />
          Item is loading…
        </span>
        <span v-else-if="products.length" class="text-xs text-muted-foreground/60">
          {{ products.length }}개 제품
        </span>
        <span v-if="currentQuoteNumber" class="text-xs px-2 py-0.5 bg-primary/10 text-primary rounded-full font-mono print:hidden">
          {{ currentQuoteNumber }}
        </span>
        <span v-if="saveSuccess" class="text-xs text-green-400 print:hidden">✓ Saved</span>
        <Button variant="ghost" size="sm" class="gap-1.5 text-xs print:hidden" @click="resetForm">
          <FilePlus :size="13" />New
        </Button>
        <Button v-if="!isQuoteOnly" variant="outline" size="sm" class="gap-1.5 text-xs print:hidden" @click="openLoadModal">
          <FolderOpen :size="13" />Import
        </Button>
        <Button v-if="!isQuoteOnly" size="sm" class="gap-1.5 text-xs print:hidden" :disabled="isSaving" @click="saveQuote">
          <Loader2 v-if="isSaving" :size="13" class="animate-spin" />
          <Save v-else :size="13" />
          {{ isSaving ? 'Saving…' : 'SAVE' }}
        </Button>
        <Button variant="outline" size="sm" class="gap-1.5 text-xs print:hidden" @click="handlePrint">
          <Printer :size="13" />Print / PDF
        </Button>
      </div>
    </div>

    <!-- Order Information -->
    <div v-if="!isQuoteOnly" class="rounded-xl border border-border bg-card overflow-hidden">
      <div class="flex items-center gap-3 px-5 py-3 border-b border-border bg-muted/20">
        <span class="text-sm font-bold text-primary bg-primary/10 px-1.5 py-0.5 rounded">I</span>
        <span class="font-semibold text-sm">Order Information</span>
      </div>
      <div class="p-5 grid grid-cols-3 gap-x-5 gap-y-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">Customer Name <span class="text-destructive">*</span></label>
          <input v-model="form.customerName" type="text" :class="cell + ' h-9 text-sm px-3'" />
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
          <label class="text-xs text-muted-foreground">Delivery Date <span class="text-destructive">*</span></label>
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
          class="flex items-center gap-1.5 text-xs border border-border/60 hover:border-primary/40 hover:text-primary px-3 py-1.5 rounded-md transition-colors"
          @click="addLine"
        >
          + Add Line
        </button>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse">
          <colgroup>
            <col class="w-9" /><col class="w-10" /><col class="w-20" />
            <col /><col class="w-20" /><col class="w-14" />
            <col class="w-25" /><col class="w-21" /><col class="w-25" />
            <col class="w-30" /><col class="w-20" /><col class="w-5" />
          </colgroup>
          <thead>
            <tr class="border-b border-border bg-muted/10">
              <th class="text-left   px-3 py-2.5 text-xs font-semibold text-muted-foreground">No.</th>
              <th class="text-left   px-2 py-2.5 text-xs font-semibold text-muted-foreground">Item</th>
              <th class="text-left   px-2 py-2.5 text-xs font-semibold text-muted-foreground">Brand</th>
              <th class="text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground">Item Description</th>
              <th class="text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground">Qty</th>
              <th class="text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground">Unit</th>
              <th class="text-right  px-2 py-2.5 text-xs font-semibold text-muted-foreground">Unit Price</th>
              <th class="text-center px-2 py-2.5 text-xs font-semibold text-muted-foreground">Discount</th>
              <th class="text-right  px-2 py-2.5 text-xs font-semibold text-muted-foreground">Net Price</th>
              <th class="text-right  px-3 py-2.5 text-xs font-semibold text-muted-foreground">Amount</th>
              <th class="text-right  px-2 py-2.5 text-xs font-semibold text-muted-foreground">Margin</th>
              <th />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(line, idx) in lines"
              :key="line.id"
              class="border-b border-border/40 hover:bg-muted/5 transition-colors group"
            >
              <td class="px-3 py-1.5 text-xs text-muted-foreground">{{ idx + 1 }}</td>
              <td class="px-1 py-1.5">
                <input v-model="line.type" type="text" :class="ghost" placeholder="Type" />
              </td>
              <td class="px-1 py-1.5">
                <input v-model="line.brand" type="text" :class="ghost" placeholder="Brand" />
              </td>
              <td class="px-2 py-1.5">
                <input
                  v-model="line.description"
                  type="text"
                  autocomplete="off"
                  :class="cell"
                  placeholder="Input Keyword, Select Product"
                  @focus="(e) => openAc(e, line)"
                  @input="(e) => openAc(e, line)"
                  @blur="closeAc"
                  @keydown="(e) => onDescriptionKeydown(e, line)"
                />
              </td>
              <td class="px-2 py-1.5">
                <input v-model.number="line.qty" type="number" min="0" :class="cell + ' text-center'" />
              </td>
              <td class="px-1 py-1.5">
                <select
                  v-model="line.unit"
                  :class="ghost + ' appearance-none cursor-pointer text-center'"
                  @change="onUnitChange(line)"
                >
                  <option value="pcs">pcs</option>
                  <option value="set">set</option>
                </select>
              </td>
              <td class="px-2 py-1.5">
                <input
                  type="text"
                  :value="fmtInput(line.unitPrice)"
                  :class="cell + ' text-right font-mono tabular-nums'"
                  placeholder="0"
                  @change="line.unitPrice = parseNum(($event.target as HTMLInputElement).value)"
                />
              </td>
              <td class="px-2 py-1.5">
                <div class="flex items-center gap-1">
                  <input v-model.number="line.discount" type="number" min="0" max="100" :class="cell + ' text-center'" />
                  <span class="text-xs text-muted-foreground shrink-0">%</span>
                </div>
              </td>
              <td class="px-2 py-1.5 text-right text-xs font-mono tabular-nums text-muted-foreground">
                {{ Math.round(lineNetPrice(line)).toLocaleString('en-US') || '0' }}
              </td>
              <td class="px-3 py-1.5 text-right text-xs font-mono tabular-nums font-semibold">
                {{ fmtInput(lineAmount(line)) || '0' }}
              </td>
              <td class="px-3 py-1.5 text-right text-xs font-semibold tabular-nums" :class="marginColor(line)">
                {{ lineMargin(line) }}
              </td>
              <td class="py-1.5 pr-2">
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
            <tr class="border-t-2 border-border bg-muted/5">
              <td colspan="4" class="px-3 py-2.5 text-sm font-bold">Sub-Total</td>
              <td class="py-2.5 text-center text-sm font-bold tabular-nums">{{ subTotalQty }}</td>
              <td /><td /><td /><td />
              <td class="px-3 py-2.5 text-right text-sm font-bold font-mono tabular-nums">{{ fmt(subTotalAmount) }}</td>
              <td /><td />
            </tr>
          </tfoot>
        </table>
      </div>

      <!-- Footer totals — column widths mirror table colgroup right→left: w-5 | w-20 | w-28 | w-28 | w-20 -->
      <div class="border-t border-border/60 divide-y divide-border/30">
        <div class="flex items-center py-2.5 pl-5">
          <span class="flex-1 text-sm text-muted-foreground">Additional Discount</span>
          <div class="w-20 flex items-center justify-center gap-1">
            <input
              v-model.number="additionalDiscount"
              type="number" min="0" max="100"
              class="w-12 h-7 rounded border border-input bg-background px-1 text-xs text-center focus:outline-none focus:ring-1 focus:ring-primary/50"
            />
            <span class="text-xs text-muted-foreground">%</span>
          </div>
          <div class="w-28" />
          <span class="w-28 px-3 text-right text-sm font-mono tabular-nums text-destructive">
            {{ discAmount > 0 ? '-' + fmt(discAmount) : '' }}
          </span>
          <div class="w-20" /><div class="w-5" />
        </div>
        <div class="flex items-center py-2.5 pl-5">
          <span class="flex-1 text-sm text-muted-foreground">PPN (Tax)</span>
          <div class="w-20 flex items-center justify-center">
            <span class="text-xs text-muted-foreground">11%</span>
          </div>
          <div class="w-28" />
          <span class="w-28 px-3 text-right text-sm font-mono tabular-nums">{{ fmt(ppnAmount) }}</span>
          <div class="w-20" /><div class="w-5" />
        </div>
        <div class="flex items-center py-2.5 pl-5">
          <span class="flex-1 text-sm text-muted-foreground">Truncation (1,000↓)</span>
          <div class="w-20" /><div class="w-28" />
          <span class="w-28 px-3 text-right text-sm font-mono tabular-nums text-destructive">
            {{ truncation < 0 ? fmt(truncation) : '' }}
          </span>
          <div class="w-20" /><div class="w-5" />
        </div>
        <div class="flex items-center py-3 pl-5">
          <span class="flex-1 text-sm font-bold">Total (incl. PPN)</span>
          <div class="w-20" /><div class="w-28" />
          <span class="w-28 px-3 text-right text-base font-bold font-mono tabular-nums text-primary">
            {{ fmt(totalFinal) }}
          </span>
          <div class="w-20" /><div class="w-5" />
        </div>
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
        <div class="max-h-112 overflow-y-auto">
          <div v-if="modalLoading" class="flex justify-center py-12">
            <Loader2 :size="20" class="animate-spin text-muted-foreground" />
          </div>
          <div v-else-if="!savedQuotes.length" class="py-12 text-center text-sm text-muted-foreground">
            저장된 견적서가 없습니다.
          </div>
          <div v-else class="divide-y divide-border/40">
            <div
              v-for="q in savedQuotes"
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

  <!-- 자동완성 드롭다운 -->
  <Teleport to="body">
    <div
      v-if="acState.lineId !== null && acSuggestions.length > 0 && acState.rect"
      class="fixed z-9999 rounded-lg border border-border bg-card shadow-xl overflow-hidden"
      :style="{
        top:       `${acState.rect.bottom + 4}px`,
        left:      `${acState.rect.left}px`,
        minWidth:  `${Math.max(acState.rect.width, 400)}px`,
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
        <div class="text-right shrink-0 text-[10px] font-mono">
          <div class="text-foreground">{{ p.wh_price.toLocaleString() }} <span class="text-muted-foreground/50">pcs</span></div>
          <div v-if="p.wh_price_set" class="text-muted-foreground">
            {{ p.wh_price_set.toLocaleString() }} <span class="text-muted-foreground/50">set</span>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
select option { background: var(--background); color: var(--foreground); }
input[type="date"]::-webkit-calendar-picker-indicator { opacity: 0.5; cursor: pointer; }
input[type="number"]::-webkit-inner-spin-button,
input[type="number"]::-webkit-outer-spin-button { opacity: 0.4; }
@media print { .print\:hidden { display: none !important; } }
.ac-item { transition: background 80ms; }
</style>
