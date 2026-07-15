<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { TrendingUp, TrendingDown, Minus, Plus, X, Pencil } from 'lucide-vue-next';
import { sbGet, sbGetAll, sbPost } from '@/lib/supabase';
import KpiEntryModal from '@/components/KpiEntryModal.vue';
import KpiTrendModal, { type TrendSeries } from '@/components/KpiTrendModal.vue';
import PageHeader from '@/components/PageHeader.vue';

// ── Types ───────────────────────────────────────────────────────────────────

interface Indicator {
  id: string;
  name_ko: string;
  name_en: string;
  category: string;
  alert_level: 'daily' | 'weekly' | 'monthly';
  unit: string | null;
  source: 'yfinance' | 'manual' | 'scraper';
  ticker: string | null;
  sort_order: number;
}

interface HistoryRow {
  indicator_id: string;
  value: number;
  recorded_date: string;
}

interface CardData {
  indicator: Indicator;
  current: number | null;
  prev: number | null;
  changePct: number | null;
  history: { date: string; value: number }[];
}

// 사업 실적 KPI (새 kpi_metrics / kpi_monthly 테이블)
interface KpiMetric {
  id: string;
  grp: 'market' | 'internal';
  product: string | null;
  kind: 'qty' | 'amount' | 'financial';
  name_ko: string;
  name_en: string | null;
  unit: string;
  sort_order: number;
}

interface KpiMonthlyRow {
  metric_id: string;
  year_month: string;
  target: number | null;
  actual: number | null;
}

interface MetricSeries {
  metric: KpiMetric;
  months: string[];          // 전체 기간 'YYYY-MM' (정렬됨, 다년도)
  target: (number | null)[];
  actual: (number | null)[];
}

// 특정 연도 기준 카드 표시용 파생값 (데이터 입력 월 기준 월평균)
interface YearView {
  curActual: number | null;  // 그 해 실적 월평균 (입력된 월 평균)
  curTarget: number | null;  // 그 해 목표 월평균 (실적 입력 월 기준)
  avgMonths: number;         // 평균에 쓰인 월 수
  achv: number | null;       // YTD 실적합 / YTD 목표합 (%)
  sparkVals: number[];       // 그 해 실적 (null 제외)
}

interface ProductCard {
  product: string;
  qty: MetricSeries | null;
  amount: MetricSeries | null;
  qtyView: YearView | null;
  amountView: YearView | null;
}

// ── State ───────────────────────────────────────────────────────────────────

const indicators     = ref<Indicator[]>([]);
const cards          = ref<CardData[]>([]);
const loading        = ref(true);
const activeTab      = ref<'all' | 'daily' | 'weekly' | 'monthly'>('all');
const activeCategory = ref<string>('all');
const loadError      = ref<string | null>(null);

// KPI state
const kpiMetrics  = ref<KpiMetric[]>([]);
const kpiSeries   = ref<Record<string, MetricSeries>>({});
const kpiError    = ref<string | null>(null);
const selectedYear = ref<number>(0);   // 0 = 미설정 (로드 후 최신 연도로)

// KPI 입력창 — 실적 수정은 관리자만 (라우터 게이팅과 별개로 UI 에서도 차단)
const kpiEntryOpen = ref(false);
const canEditKpi = sessionStorage.getItem('asura_auth') === 'super_admin';

const inputModal  = ref(false);
const inputTarget = ref<Indicator | null>(null);
const inputValue  = ref('');
const inputNote   = ref('');
const inputSaving = ref(false);

// Trend modal
const trendOpen     = ref(false);
const trendTitle    = ref('');
const trendSubtitle = ref('');
const trendSeries   = ref<TrendSeries[]>([]);
const trendInfo     = ref('');   // 지표 간략 설명 (모달 표시)
const trendSource   = ref('');   // 지표 데이터 출처 (모달 표시)

// 지표별 데이터 출처 (추이 모달에 표시). '근사'=웹 리서치 근사치.
const INDICATOR_SOURCE: Record<string, string> = {
  usd_idr: 'Yahoo Finance (USDIDR=X)', usd_krw: 'Yahoo Finance (USDKRW=X)',
  usd_cny: 'Yahoo Finance (USDCNY=X)', krw_idr: '파생 (USD/IDR ÷ USD/KRW)',
  brent_crude: 'Yahoo Finance (BZ=F)',
  nr_rubber: 'SICOM TSR20 · 웹 리서치 근사', nickel: 'LME · 웹 리서치 근사',
  coal: 'Newcastle 6000kcal · 웹 리서치 근사', cpo: 'Bursa FCPO · 웹 리서치 근사',
  carbon_black: 'FOB Qingdao · ChemAnalyst/Expert MR (분기)',
  synthetic_rubber: 'CFR SE Asia · Expert MR/IMARC/ChemAnalyst (분기)',
  steel_wire: 'FOB Qingdao · PriceWatch (분기)',
  scfi: 'SSE 상하이해운거래소 (SCFI)',
  bi_rate: 'Bank Indonesia', idn_inflation: 'BPS 인도네시아 통계청', idn_pmi: 'S&P Global',
};

// 지표별 간략 설명 (추이 모달 상단에 표시). 없으면 미표시.
const INDICATOR_INFO: Record<string, string> = {
  scfi: 'SCFI(상하이컨테이너운임지수)는 상하이항에서 출발하는 15개 주요 노선의 현물 운임을 종합한 글로벌 해운 시황 지표입니다. 2009년 10월을 기준점(1,000)으로 설정하며, 수출입 기업의 물류 비용 및 글로벌 해운사 실적을 가늠하는 핵심 척도로 활용됩니다.',
  brent_crude: '브렌트유는 글로벌 원유 벤치마크로, 타이어 원재료(카본블랙·합성고무)의 원료비 상승 신호이자 운송비 변동의 선행지표입니다. 현지화 매입 시 CFR 또는 CIF 기준이므로 해운비·보험료·환율과 연동되어 3~4개월 시차로 제품 원가에 반영됩니다. (기준지: 북해 ICE Brent)',
  nr_rubber: '천연고무(NR)는 타이어 컴파운드 배합의 25~35%를 차지하는 핵심 원재료입니다. SICOM 지수(RSS3)는 인도네시아·말레이시아·태국 수출가의 글로벌 벤치마크로, 기후 변동(우기 감산)·파업·인도네시아 수출세 정책에 민감합니다. TBR(트럭타이어)·OTR(광산용) 배합 시 원료비 결정의 핵심 변수입니다.',
  cpo: '팜유(CPO)는 타이어 컴파운드 가황(vulcanization)의 계면활성제·내식성 개선제로 소량(1~2%) 쓰이지만, 글로벌 식품·바이오연료 수요로 가격 변동성이 높습니다. 인도네시아 수출 정책, 팜 플랜테이션 수확 스케줄, 말레이시아·인도네시아 기후가 3~6개월 선행 신호입니다. (Bursa Malaysia FOB, MYR/USD ≈ 4.5~4.8)',
  nickel: '니켈은 타이어 강선(steel cord·bead wire) 도금 및 경도 강화제로 쓰이며, 전 지구적 EV 전환으로 배터리 수요가 급증해 원가 변동성이 큽니다. 인도네시아가 세계 최대 니켈 생산국이라, 현지 수출 정책(원광 수출 금지 완화/강화)이 글로벌 가격을 좌우합니다. (LME 3등급)',
  coal: '석탄(열탄)은 타이어 제조 공정의 열원(가황·건조)이자 발전 연료로, 글로벌 탄소중립 정책에 따라 수요 감소 추세입니다. 인도네시아는 세계 최대 열탄 수출국이나 국내 에너지 보안(DMO 30~40%)·수출세 규제를 실시 중입니다. (Newcastle 5,500kcal↑ 저황탄)',
  carbon_black: '카본블랙은 타이어 트레드의 강화·내마모·착색을 담당하는 핵심 원재료(배합율 20~30%)로, 원유 부산물(석유 코크스·석탄 타르) 가격에 직결됩니다. 중국이 세계 생산의 45~50%를 차지해 중국 환경규제(MEE)·크래커 가동률이 글로벌 가격을 좌우합니다. (FOB 칭다오, 등급 N550/N330/N220)',
  synthetic_rubber: '합성고무 BD(고-시스 폴리부타디엔)는 타이어 트레드·사이드월의 탄성·내마모성을 결정하는 핵심 엘라스토머로 20~40% 배합됩니다. 부타디엔 원료비(원유 나프타 크래킹 부산물)에 직결되어 유가(브렌트)·크래커 가동률(중·한·일)·글로벌 타이어 수요의 3중 영향을 받습니다. (CFR 동남아 기준)',
  steel_wire: '강선(비드와이어)은 타이어 림 착용부를 형성하는 강화 구조재로, 생산 원가의 65~70%가 고탄소 선재(high-carbon rod) 비용입니다. 동도금(구리+아연)은 컴파운드 접착성 강화용입니다. 중국 선재 과잉설비와 글로벌 타이어 수요에 직결되며, 2026년 철광석·유가 상승으로 원가 압력이 가시화 중입니다. (FOB 칭다오, HRC 연동)',
};

// ── Helpers (산업 지표) ─────────────────────────────────────────────────────

// 새 KPI 섹션이 대체하므로 산업 지표 그리드에선 market/internal 제외
const INDUSTRY_CATS = ['commodity', 'fx', 'freight', 'policy'] as const;

// 표시 그룹: 물류(freight)+정책/거시(policy)를 '정책·거시/물류' 한 그룹으로 통합
const GROUP_OF: Record<string, string> = {
  commodity: 'commodity', fx: 'fx', freight: 'macro', policy: 'macro',
};
const GROUPS = ['commodity', 'fx', 'macro'] as const;

const CATEGORY_LABELS: Record<string, string> = {
  all:       '전체',
  commodity: '원자재',
  fx:        '환율',
  macro:     '정책·거시/물류',
};

const CATEGORY_ICONS: Record<string, string> = {
  commodity: '🛢',
  fx:        '💱',
  macro:     '🏛',
};

// 카드 카테고리별 연한 배경/테두리 (light 테마). financial·market=사업 KPI, 나머지=산업지표
const CAT_CARD_BG: Record<string, string> = {
  financial: 'border-blue-200/70 bg-blue-50/40 hover:bg-blue-100/50',
  market:    'border-emerald-200/70 bg-emerald-50/40 hover:bg-emerald-100/50',
  commodity: 'border-amber-200/70 bg-amber-50/40 hover:bg-amber-100/50',
  fx:        'border-violet-200/70 bg-violet-50/40 hover:bg-violet-100/50',
  // 물류+정책을 한 그룹으로 통합 → 동일 배경(rose)
  freight:   'border-rose-200/70 bg-rose-50/40 hover:bg-rose-100/50',
  policy:    'border-rose-200/70 bg-rose-50/40 hover:bg-rose-100/50',
};

// 스파크라인 색 (누적 달성률 100% 이상=파랑, 미만=주황)
function sparkStroke(achv: number | null | undefined): string {
  return (achv ?? 0) >= 100 ? '#3b82f6' : '#f59e0b';
}

const ALERT_LABELS: Record<string, string> = {
  all:     '전체',
  daily:   '🔴 일일',
  weekly:  '🟡 주간',
  monthly: '🟢 월간',
};

const categories = computed(() => ['all', ...GROUPS]);

const filteredCards = computed(() =>
  cards.value.filter(c => {
    if (!INDUSTRY_CATS.includes(c.indicator.category as typeof INDUSTRY_CATS[number])) return false;
    const tabOk = activeTab.value === 'all' || c.indicator.alert_level === activeTab.value;
    const catOk = activeCategory.value === 'all' || GROUP_OF[c.indicator.category] === activeCategory.value;
    return tabOk && catOk;
  })
);

const groupedCards = computed(() => {
  const groups = activeCategory.value !== 'all' ? [activeCategory.value] : [...GROUPS];
  return groups
    .map(cat => ({ cat, items: filteredCards.value.filter(c => GROUP_OF[c.indicator.category] === cat) }))
    .filter(g => g.items.length > 0);
});

function formatValue(val: number | null, unit: string | null, id?: string): string {
  if (val === null) return '—';
  const n = Number(val);
  switch (id) {
    case 'usd_idr': return n.toLocaleString('ko-KR', { maximumFractionDigits: 0 });
    case 'usd_krw': return n.toLocaleString('en-US', { maximumFractionDigits: 0 });
    case 'krw_idr': return n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    case 'scfi':    return n.toLocaleString('en-US', { maximumFractionDigits: 0 });  // 컨테이너 운임: 정수
    case 'bi_rate':
    case 'idn_inflation':
    case 'idn_pmi':  return n.toFixed(1);  // 소수점 한자리
  }
  if (unit === 'IDR' || unit === 'IDR M') return n.toLocaleString('id-ID', { maximumFractionDigits: 0 });
  if (unit === '%' || unit === 'Index') return n.toFixed(2);
  return n.toLocaleString('en-US', { maximumFractionDigits: 2 });
}

function alertDot(level: string): string {
  return level === 'daily' ? 'bg-red-500' : level === 'weekly' ? 'bg-yellow-400' : 'bg-green-400';
}

function latestDate(history: { date: string; value: number }[]): string {
  if (!history.length) return '';
  return history.reduce((max, h) => (h.date > max ? h.date : max), history[0].date);
}

function formatRecordedDate(card: CardData): string {
  const d = latestDate(card.history);
  if (!d) return '';
  return card.indicator.alert_level === 'monthly' ? d.slice(0, 7) : d.slice(5);
}

function changeBadgeClass(pct: number | null): string {
  if (pct === null) return 'text-muted-foreground';
  if (pct > 0) return 'text-red-600';
  if (pct < 0) return 'text-green-400';
  return 'text-muted-foreground';
}

function trendIcon(pct: number | null) {
  if (pct === null || pct === 0) return Minus;
  return pct > 0 ? TrendingUp : TrendingDown;
}

// ── KPI helpers ───────────────────────────────────────────────────────────────

// 카드용 컴팩트 포맷 ('761K' / '2.39M' / '4,046')
function fmtCompact(v: number | null, unit: string): string {
  if (v === null || v === undefined || Number.isNaN(v)) return '—';
  if (unit === 'pcs') return Math.round(v).toLocaleString('en-US');
  const abs = Math.abs(v);
  const sign = v < 0 ? '-' : '';
  if (abs >= 1_000_000) return `${sign}$${(abs / 1_000_000).toFixed(2)}M`;
  if (abs >= 1_000)     return `${sign}$${(abs / 1_000).toFixed(0)}K`;
  return `${sign}$${Math.round(abs).toLocaleString('en-US')}`;
}

function achvClass(achv: number | null): string {
  if (achv === null) return 'bg-muted text-muted-foreground';
  return achv >= 100 ? 'bg-blue-500/15 text-blue-400' : 'bg-amber-500/15 text-amber-600';
}

// 데이터가 존재하는 연도 목록 (오름차순)
const availableYears = computed<number[]>(() => {
  const ys = new Set<number>();
  for (const s of Object.values(kpiSeries.value)) {
    for (const m of s.months) ys.add(Number(m.slice(0, 4)));
  }
  return [...ys].sort((a, b) => a - b);
});

// 특정 연도 기준 파생값 — 실적이 입력된 월의 '월평균' (2025=12개월, 2026=Jan~Apr 등)
function buildYearView(s: MetricSeries | null, year: number): YearView | null {
  if (!s || !year) return null;
  const idx: number[] = [];
  s.months.forEach((m, i) => { if (m.slice(0, 4) === String(year)) idx.push(i); });

  let n = 0, actualSum = 0, targetSum = 0;
  const sparkVals: number[] = [];
  for (const i of idx) {
    const a = s.actual[i];
    if (a !== null && a !== undefined) {
      n++;
      actualSum += a;
      sparkVals.push(a);
      if (s.target[i] !== null && s.target[i] !== undefined) targetSum += s.target[i]!;
    }
  }
  return {
    curActual: n > 0 ? actualSum / n : null,   // 월평균 실적
    curTarget: n > 0 ? targetSum / n : null,   // 월평균 목표 (실적 입력 월 기준)
    avgMonths: n,
    achv:      targetSum > 0 ? (actualSum / targetSum) * 100 : null,
    sparkVals,
  };
}

// 그 해 실적 sparkline
function sparkFromVals(vals: number[]): string {
  if (vals.length < 2) return '';
  const min = Math.min(...vals), max = Math.max(...vals);
  const range = max - min || 1;
  const W = 80, H = 24;
  return 'M' + vals.map((v, i) => {
    const x = (i / (vals.length - 1)) * W;
    const y = H - ((v - min) / range) * H;
    return `${x},${y}`;
  }).join('L');
}

const productCards = computed<ProductCard[]>(() => {
  const order: string[] = [];
  for (const m of kpiMetrics.value) {
    if (m.grp === 'market' && m.product && !order.includes(m.product)) order.push(m.product);
  }
  const y = selectedYear.value;
  return order.map(product => {
    const qtyMetric = kpiMetrics.value.find(m => m.product === product && m.kind === 'qty');
    const amtMetric = kpiMetrics.value.find(m => m.product === product && m.kind === 'amount');
    const qty    = qtyMetric ? kpiSeries.value[qtyMetric.id] ?? null : null;
    const amount = amtMetric ? kpiSeries.value[amtMetric.id] ?? null : null;
    return { product, qty, amount, qtyView: buildYearView(qty, y), amountView: buildYearView(amount, y) };
  });
});

// 매출(fin_sales) 당해연도 view — 재무지표 매출 대비 비율 계산용
const salesView = computed(() => {
  const sales = kpiSeries.value['fin_sales'];
  return sales ? buildYearView(sales, selectedYear.value) : null;
});

const financialCards = computed(() =>
  kpiMetrics.value
    .filter(m => m.grp === 'internal')
    .map(m => kpiSeries.value[m.id])
    .filter((s): s is MetricSeries => !!s)
    .map(s => {
      const view = buildYearView(s, selectedYear.value);
      const salesCur = salesView.value?.curActual ?? null;
      const ratio = (s.metric.id !== 'fin_sales' && view?.curActual != null && salesCur)
        ? (view.curActual / salesCur) * 100
        : null;
      return { series: s, view, ratio };
    })
);

const hasKpi = computed(() => productCards.value.length > 0 || financialCards.value.length > 0);

// 선택 연도에서 실적이 입력된 '마지막 월' 라벨 (예: 2026년 5월까지 → "26년 5월까지")
const latestActualLabel = computed<string>(() => {
  const y = selectedYear.value;
  let maxMonth = 0;
  for (const s of Object.values(kpiSeries.value)) {
    s.months.forEach((m, i) => {
      const a = s.actual[i];
      if (m.slice(0, 4) === String(y) && a !== null && a !== undefined) {
        const mo = Number(m.slice(5, 7));
        if (mo > maxMonth) maxMonth = mo;
      }
    });
  }
  return maxMonth ? `${String(y).slice(2)}년 ${maxMonth}월까지 월평균` : '월평균';
});

// ── Trend modal openers ─────────────────────────────────────────────────────

function toTrendSeries(s: MetricSeries, label: string): TrendSeries {
  return { label, unit: s.metric.unit, months: s.months, target: s.target, actual: s.actual };
}

function openProductTrend(pc: ProductCard) {
  const series: TrendSeries[] = [];
  if (pc.amount) series.push(toTrendSeries(pc.amount, '판매금액'));
  if (pc.qty)    series.push(toTrendSeries(pc.qty, '판매량'));
  if (!series.length) return;
  trendTitle.value    = `${pc.product} — 판매 추이`;
  trendSubtitle.value = '목표 vs 실적 · 월간/연간';
  trendInfo.value     = '';
  trendSource.value   = '';
  trendSeries.value   = series;
  trendOpen.value     = true;
}

// fin_sales(매출) 시계열을 s.months 에 정렬해 분모로 반환 (비율 모드용)
function salesDenomFor(s: MetricSeries): { denomTarget: (number | null)[]; denomActual: (number | null)[] } | null {
  const sales = kpiSeries.value['fin_sales'];
  if (!sales) return null;
  const map: Record<string, { t: number | null; a: number | null }> = {};
  sales.months.forEach((m, i) => { map[m] = { t: sales.target[i], a: sales.actual[i] }; });
  return {
    denomTarget: s.months.map(m => map[m]?.t ?? null),
    denomActual: s.months.map(m => map[m]?.a ?? null),
  };
}

function openFinancialTrend(s: MetricSeries) {
  const base = toTrendSeries(s, s.metric.name_ko);
  // 재무매출 외 재무지표는 '매출 대비 비율' 모드 지원
  if (s.metric.id !== 'fin_sales') {
    const d = salesDenomFor(s);
    if (d) {
      base.denomTarget = d.denomTarget;
      base.denomActual = d.denomActual;
      base.ratioLabel  = '매출 대비';
    }
  }
  trendTitle.value    = `${s.metric.name_ko} — 추이`;
  trendSubtitle.value = '목표 vs 실적 · 금액/비율 · 월간/연간';
  trendInfo.value     = '';
  trendSource.value   = '';
  trendSeries.value   = [base];
  trendOpen.value     = true;
}

// 산업 지표(원자재/환율/물류/정책) 추이 모달 — 목표 없이 실적(수집값) 시계열만 표시
function openIndicatorTrend(card: CardData) {
  const hist = [...card.history].reverse();  // 최신순 → 시간순
  if (!hist.length) return;
  trendTitle.value    = `${card.indicator.name_ko} — 추이`;
  trendSubtitle.value = '수집값 추이 · 월간/연간';
  trendInfo.value     = INDICATOR_INFO[card.indicator.id] ?? '';
  trendSource.value   = INDICATOR_SOURCE[card.indicator.id] ?? '';
  trendSeries.value   = [{
    label:  card.indicator.name_ko,
    unit:   card.indicator.unit ?? '',
    months: hist.map(h => h.date),        // 'YYYY-MM(-DD)'
    target: hist.map(() => null),          // 목표 없음
    actual: hist.map(h => h.value),
  }];
  trendOpen.value = true;
}

// 카드 클릭: 데이터 있으면 추이 모달, 값 없는 수동 카드는 입력 모달
function onIndicatorClick(card: CardData) {
  if (card.history.length) openIndicatorTrend(card);
  else if (card.indicator.source === 'manual') openInput(card);
}

// ── Data loading ─────────────────────────────────────────────────────────────

function buildKpiSeries(metrics: KpiMetric[], rows: KpiMonthlyRow[]): Record<string, MetricSeries> {
  const byMetric: Record<string, KpiMonthlyRow[]> = {};
  for (const r of rows) {
    (byMetric[r.metric_id] ??= []).push(r);
  }
  const out: Record<string, MetricSeries> = {};
  for (const metric of metrics) {
    const rs = (byMetric[metric.id] ?? []).slice().sort((a, b) => a.year_month.localeCompare(b.year_month));
    const months = rs.map(r => r.year_month);
    const target = rs.map(r => (r.target === null || r.target === undefined ? null : Number(r.target)));
    const actual = rs.map(r => (r.actual === null || r.actual === undefined ? null : Number(r.actual)));
    out[metric.id] = { metric, months, target, actual };
  }
  return out;
}

async function loadKpi() {
  kpiError.value = null;
  try {
    // kpi_monthly 는 다년도 누적 → 기본 1000행 cap 회피 위해 sbGetAll 사용
    const [metrics, monthly] = await Promise.all([
      sbGet<KpiMetric[]>('kpi_metrics?select=*&order=sort_order'),
      sbGetAll<KpiMonthlyRow>('kpi_monthly?select=metric_id,year_month,target,actual&order=year_month'),
    ]);
    kpiMetrics.value = metrics;
    kpiSeries.value  = buildKpiSeries(metrics, monthly);
    if (!selectedYear.value && availableYears.value.length) {
      selectedYear.value = availableYears.value[availableYears.value.length - 1];
    }
  } catch (e) {
    console.error('[Monitor] loadKpi error', e);
    kpiError.value = e instanceof Error ? e.message : String(e);
  }
}

async function loadData() {
  loading.value   = true;
  loadError.value = null;
  try {
    const [inds, histories] = await Promise.all([
      sbGet<Indicator[]>('market_indicators?select=*&order=sort_order'),
      sbGet<HistoryRow[]>(
        'indicator_history?select=indicator_id,value,recorded_date&order=recorded_date.desc&limit=500',
      ),
    ]);

    indicators.value = inds;

    const byId: Record<string, HistoryRow[]> = {};
    for (const h of histories) {
      if (!byId[h.indicator_id]) byId[h.indicator_id] = [];
      byId[h.indicator_id].push(h);
    }

    cards.value = inds.map(ind => {
      const rows      = byId[ind.id] ?? [];
      const current   = rows[0]?.value ?? null;
      const prev      = rows[1]?.value ?? null;
      const changePct =
        current !== null && prev !== null && prev !== 0
          ? Math.round(((current - prev) / prev) * 10000) / 100
          : null;
      return {
        indicator: ind,
        current,
        prev,
        changePct,
        history: rows.slice(0, 7).map(r => ({ date: r.recorded_date, value: r.value })),
      };
    });
  } catch (e) {
    console.error('[Monitor] loadData error', e);
    loadError.value = e instanceof Error ? e.message : String(e);
  } finally {
    loading.value = false;
  }
}

// ── Manual input (산업 지표 수동값) ────────────────────────────────────────────

function openInput(card: CardData) {
  if (card.indicator.source !== 'manual') return;
  inputTarget.value = card.indicator;
  inputValue.value  = card.current !== null ? String(card.current) : '';
  inputNote.value   = '';
  inputModal.value  = true;
}

async function saveInput() {
  if (!inputTarget.value || inputValue.value === '') return;
  inputSaving.value = true;
  try {
    const today = new Date().toISOString().split('T')[0];
    await sbPost('indicator_history', {
      indicator_id:  inputTarget.value.id,
      value:         Number(inputValue.value),
      recorded_date: today,
      note:          inputNote.value || null,
    });
    inputModal.value = false;
    await loadData();
  } catch (e) {
    console.error('[Monitor] saveInput error', e);
  } finally {
    inputSaving.value = false;
  }
}

// ── Mini sparkline (산업 지표) ──────────────────────────────────────────────────

function sparkPath(history: { date: string; value: number }[]): string {
  if (history.length < 2) return '';
  const vals  = [...history].reverse().map(h => h.value);
  const min   = Math.min(...vals);
  const max   = Math.max(...vals);
  const range = max - min || 1;
  const W = 80, H = 28;
  const points = vals.map((v, i) => {
    const x = (i / (vals.length - 1)) * W;
    const y = H - ((v - min) / range) * H;
    return `${x},${y}`;
  });
  return `M${points.join('L')}`;
}

onMounted(async () => {
  await Promise.all([loadData(), loadKpi()]);
});
</script>

<template>
  <div class="p-6 space-y-6 max-w-300 mx-auto">

    <!-- Header -->
    <PageHeader title="KPI 모니터링" subtitle="사업 실적 · 산업 핵심 지표 대시보드">
      <template #controls>
        <div v-if="hasKpi" class="flex items-center gap-1 flex-wrap">
          <span class="text-xs text-muted-foreground mr-0.5">연도</span>
          <button
            v-for="y in availableYears"
            :key="y"
            :class="[
              'px-3 py-1 rounded-full text-xs font-medium transition-colors tabular-nums',
              selectedYear === y
                ? 'bg-primary text-primary-foreground'
                : 'bg-card border border-border text-muted-foreground hover:bg-accent',
            ]"
            @click="selectedYear = y"
          >
            {{ y }}
          </button>
        </div>
      </template>
      <template #actions>
        <button
          v-if="canEditKpi && hasKpi"
          class="inline-flex items-center gap-1.5 text-xs font-medium text-muted-foreground hover:text-foreground border border-border rounded-lg px-3 py-2 transition-colors"
          title="KPI 월별 목표·실적 직접 입력"
          @click="kpiEntryOpen = true"
        >
          <Pencil :size="14" /> 데이터 입력
        </button>
      </template>
    </PageHeader>

    <KpiEntryModal
      v-if="kpiEntryOpen"
      :metrics="kpiMetrics"
      :year="selectedYear"
      @close="kpiEntryOpen = false"
      @saved="loadKpi"
    />

    <!-- ═══ 시장/경쟁 (제품별 판매) ═══ -->
    <section v-if="hasKpi" class="space-y-4">
      <!-- 재무 (재무지표) -->
      <div v-if="financialCards.length" class="space-y-3">
        <div class="flex items-center gap-2">
          <span class="text-base">📈</span>
          <h2 class="text-sm font-semibold text-foreground">재무</h2>
          <span class="text-xs text-muted-foreground">전체 재무지표 · 값={{ latestActualLabel }} · 배지=누적 목표달성률 · 클릭 시 추이</span>
          <div class="flex-1 border-t border-border/50 ml-1" />
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          <button
            v-for="fc in financialCards"
            :key="fc.series.metric.id"
            :class="['text-left relative rounded-xl border p-3.5 flex flex-col gap-2 transition-all duration-150 cursor-pointer hover:border-primary/40', CAT_CARD_BG.financial]"
            @click="openFinancialTrend(fc.series)"
          >
            <div class="flex items-center justify-between">
              <span class="text-xs font-semibold text-foreground">{{ fc.series.metric.name_ko }}</span>
              <span
                v-if="fc.view?.achv != null"
                :title="`누적 목표달성률 ${fc.view.achv.toFixed(0)}% = ${fc.view.avgMonths}개월(Jan~) 실적합÷목표합 — 5월 단월 아님 · 시트 전년대비 Achiv.(%)와 다른 지표`"
                :class="['text-[10px] font-semibold px-1.5 py-0.5 rounded tabular-nums', achvClass(fc.view.achv)]"
              >{{ fc.view.achv.toFixed(0) }}%</span>
            </div>

            <p class="text-lg font-bold text-foreground tabular-nums leading-tight">
              {{ fmtCompact(fc.view?.curActual ?? null, fc.series.metric.unit) }}
            </p>
            <p class="text-[10px] text-muted-foreground/60 tabular-nums">
              목표 {{ fmtCompact(fc.view?.curTarget ?? null, fc.series.metric.unit) }}
              <span v-if="fc.ratio != null" class="text-primary/80"> · 매출 대비 {{ fc.ratio.toFixed(1) }}%</span>
            </p>

            <svg v-if="fc.view && sparkFromVals(fc.view.sparkVals)" width="80" height="24" class="self-end" style="overflow: visible">
              <path
                :d="sparkFromVals(fc.view.sparkVals)"
                fill="none"
                :stroke="sparkStroke(fc.view.achv)"
                stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"
              />
            </svg>

            <p v-if="fc.view?.avgMonths" class="absolute top-3 right-3 text-[9px] text-muted-foreground/40 tabular-nums">
              {{ fc.view.avgMonths }}개월 평균
            </p>
          </button>
        </div>
      </div>
      
      <!-- 시장/경쟁 -->
      <div class="space-y-3">
        <div class="flex items-center gap-2">
          <span class="text-base">📊</span>
          <h2 class="text-sm font-semibold text-foreground">시장/경쟁</h2>
          <span class="text-xs text-muted-foreground">제품별 판매량·판매금액(USD) · 값={{ latestActualLabel }} · 배지=누적 목표달성률 · 클릭 시 추이</span>
          <div class="flex-1 border-t border-border/50 ml-1" />
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          <button
            v-for="pc in productCards"
            :key="pc.product"
            :class="['text-left relative rounded-xl border p-3.5 flex flex-col gap-2.5 transition-all duration-150 cursor-pointer hover:border-primary/40', CAT_CARD_BG.market]"
            @click="openProductTrend(pc)"
          >
            <div class="flex items-center justify-between">
              <span class="text-sm font-bold text-foreground">{{ pc.product }}</span>
              <span
                v-if="pc.amountView?.achv != null"
                :title="`누적 목표달성률 ${pc.amountView.achv.toFixed(0)}% = ${pc.amountView.avgMonths}개월(Jan~) 실적합÷목표합 — 단월 아님 · 시트 전년대비 Achiv.(%)와 다른 지표`"
                :class="['text-[10px] font-semibold px-1.5 py-0.5 rounded tabular-nums', achvClass(pc.amountView.achv)]"
              >{{ pc.amountView.achv.toFixed(0) }}%</span>
            </div>

            <div>
              <p class="text-[10px] text-muted-foreground/70">판매금액 (USD)</p>
              <p class="text-lg font-bold text-foreground tabular-nums leading-tight">
                {{ fmtCompact(pc.amountView?.curActual ?? null, 'USD') }}
              </p>
              <p class="text-[10px] text-muted-foreground/60 tabular-nums">
                목표 {{ fmtCompact(pc.amountView?.curTarget ?? null, 'USD') }}
              </p>
            </div>

            <div class="flex items-end justify-between gap-1">
              <div>
                <p class="text-[10px] text-muted-foreground/70">판매량 (pcs)</p>
                <p class="text-xs font-semibold text-foreground tabular-nums">
                  {{ fmtCompact(pc.qtyView?.curActual ?? null, 'pcs') }}
                </p>
              </div>
              <svg v-if="pc.amountView && sparkFromVals(pc.amountView.sparkVals)" width="80" height="24" class="self-end" style="overflow: visible">
                <path
                  :d="sparkFromVals(pc.amountView.sparkVals)"
                  fill="none"
                  :stroke="sparkStroke(pc.amountView.achv)"
                  stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"
                />
              </svg>
            </div>

            <p v-if="pc.amountView?.avgMonths" class="absolute top-3 right-3 text-[9px] text-muted-foreground/40 tabular-nums">
              {{ pc.amountView.avgMonths }}개월 평균
            </p>
          </button>
        </div>
      </div>
    </section>

    <!-- KPI 데이터 없음 안내 -->
    <div
      v-else-if="!loading && !hasKpi && kpiError"
      class="rounded-xl border border-yellow-500/20 bg-yellow-500/5 p-4 text-center space-y-1"
    >
      <p class="text-sm font-semibold text-yellow-400">사업 KPI 데이터 없음</p>
      <p class="text-xs text-muted-foreground">
        Supabase에서 <span class="font-mono text-foreground/70">supabase/migrations/add_business_kpi.sql</span> 을 실행하세요.
      </p>
    </div>

    <!-- ═══ 산업 지표 (원자재/환율/물류/정책) ═══ -->
    <div class="flex items-center gap-2 pt-2">
      <h2 class="text-sm font-semibold text-muted-foreground">산업 지표</h2>
      <div class="flex-1 border-t border-border/50" />
    </div>

    <!-- Filters -->
    <div class="flex gap-1.5 flex-wrap">
      <button
        v-for="tab in (['all','daily','weekly','monthly'] as const)"
        :key="tab"
        :class="[
          'px-3 py-1 rounded-full text-xs font-medium transition-colors',
          activeTab === tab
            ? 'bg-primary text-primary-foreground'
            : 'bg-card border border-border text-muted-foreground hover:bg-accent',
        ]"
        @click="activeTab = tab"
      >
        {{ ALERT_LABELS[tab] }}
      </button>

      <div class="ml-auto flex gap-1.5 flex-wrap">
        <button
          v-for="cat in categories"
          :key="cat"
          :class="[
            'px-3 py-1 rounded-full text-xs font-medium transition-colors',
            activeCategory === cat
              ? 'bg-muted text-foreground'
              : 'bg-card border border-border text-muted-foreground hover:bg-accent',
          ]"
          @click="activeCategory = cat"
        >
          {{ CATEGORY_ICONS[cat] ? CATEGORY_ICONS[cat] + ' ' : '' }}{{ CATEGORY_LABELS[cat] }}
        </button>
      </div>
    </div>


    <!-- Loading skeleton -->
    <div v-if="loading" class="space-y-6">
      <div v-for="g in 2" :key="g" class="space-y-3">
        <div class="h-4 w-24 rounded bg-muted animate-pulse" />
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          <div v-for="i in 5" :key="i" class="h-28 rounded-xl bg-muted animate-pulse" />
        </div>
      </div>
    </div>

    <!-- Grouped indicator cards -->
    <div v-else-if="!loadError && filteredCards.length > 0" class="space-y-7">
      <div v-for="group in groupedCards" :key="group.cat" class="space-y-3">
        <div class="flex items-center gap-2">
          <span class="text-base">{{ CATEGORY_ICONS[group.cat] }}</span>
          <h2 class="text-sm font-semibold text-foreground">{{ CATEGORY_LABELS[group.cat] }}</h2>
          <span class="text-xs text-muted-foreground">({{ group.items.length }})</span>
          <div class="flex-1 border-t border-border/50 ml-1" />
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          <div
            v-for="card in group.items"
            :key="card.indicator.id"
            :class="[
              'relative rounded-xl border p-3.5 flex flex-col gap-2 transition-all duration-150',
              CAT_CARD_BG[card.indicator.category] ?? 'border-border bg-card',
              (card.history.length || card.indicator.source === 'manual')
                ? 'cursor-pointer hover:border-primary/40'
                : 'cursor-default',
            ]"
            @click="onIndicatorClick(card)"
          >
            <div class="flex items-center justify-between">
              <span :class="['w-2 h-2 rounded-full shrink-0', alertDot(card.indicator.alert_level)]" />
              <div class="flex items-center gap-1.5">
                <span v-if="formatRecordedDate(card)" class="text-[9px] text-muted-foreground/60 tabular-nums">
                  {{ formatRecordedDate(card) }}
                </span>
                <span class="text-[9px] text-muted-foreground/50 uppercase tracking-wide">
                  {{ card.indicator.source === 'manual' ? '수동' : 'auto' }}
                </span>
                <button
                  v-if="card.indicator.source === 'manual' && card.current !== null"
                  class="p-0.5 rounded text-muted-foreground/60 hover:text-foreground hover:bg-accent transition-colors"
                  title="값 입력/수정"
                  @click.stop="openInput(card)"
                ><Pencil :size="10" /></button>
              </div>
            </div>

            <div>
              <p class="text-xs font-semibold text-foreground leading-tight truncate">
                {{ card.indicator.name_ko }}
              </p>
              <p class="text-[9px] text-muted-foreground/60 truncate">{{ card.indicator.unit ?? '' }}</p>
            </div>

            <div class="flex items-end justify-between gap-1">
              <span class="text-base font-bold text-foreground tabular-nums leading-none">
                {{ formatValue(card.current, card.indicator.unit, card.indicator.id) }}
              </span>
              <div
                v-if="card.changePct !== null"
                :class="['flex items-center gap-0.5 text-[10px] font-medium', changeBadgeClass(card.changePct)]"
              >
                <component :is="trendIcon(card.changePct)" :size="10" />
                {{ Math.abs(card.changePct).toFixed(1) }}%
              </div>
            </div>

            <svg
              v-if="card.history.length >= 2"
              width="80"
              height="28"
              class="self-end"
              style="overflow: visible"
            >
              <path
                :d="sparkPath(card.history)"
                fill="none"
                :stroke="card.changePct !== null && card.changePct < 0 ? '#4ade80' : '#f87171'"
                stroke-width="1.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>

            <div
              v-if="card.indicator.source === 'manual' && card.current === null"
              class="absolute inset-0 flex items-center justify-center rounded-xl bg-muted/60"
            >
              <div class="flex items-center gap-1 text-xs text-muted-foreground">
                <Plus :size="12" />
                값 입력
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Error state -->
    <div
      v-if="!loading && loadError"
      class="rounded-xl border border-red-500/20 bg-red-500/5 p-6 text-center space-y-3"
    >
      <p class="text-sm font-semibold text-red-600">데이터 로드 실패</p>
      <p class="text-xs text-muted-foreground">
        Supabase 마이그레이션이 적용되지 않았거나 테이블 접근 권한이 없습니다.
      </p>
      <code class="block text-[11px] bg-muted rounded-lg px-4 py-2 text-left text-muted-foreground whitespace-pre-wrap break-all">
        {{ loadError }}
      </code>
    </div>

    <!-- Filter empty -->
    <div
      v-else-if="!loading && !loadError && filteredCards.length === 0"
      class="text-center py-10 text-muted-foreground text-sm"
    >
      해당 필터의 산업 지표가 없습니다.
    </div>

    <!-- Trend modal -->
    <KpiTrendModal
      :open="trendOpen"
      :title="trendTitle"
      :subtitle="trendSubtitle"
      :info="trendInfo"
      :source="trendSource"
      :series="trendSeries"
      :year="selectedYear"
      :years="availableYears"
      @close="trendOpen = false"
    />

    <!-- Manual input modal -->
    <transition
      enter-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-150"
      leave-to-class="opacity-0"
    >
      <div
        v-if="inputModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
        @click.self="inputModal = false"
      >
        <div class="bg-card border border-border rounded-2xl p-6 w-full max-w-sm shadow-2xl space-y-4">
          <div class="flex items-start justify-between">
            <div>
              <h3 class="font-semibold text-sm">{{ inputTarget?.name_ko }}</h3>
              <p class="text-xs text-muted-foreground">{{ inputTarget?.unit ?? '' }} · 오늘 기준</p>
            </div>
            <button class="p-1 rounded hover:bg-accent text-muted-foreground" @click="inputModal = false">
              <X :size="14" />
            </button>
          </div>

          <div class="space-y-3">
            <div>
              <label class="text-xs text-muted-foreground mb-1 block">값</label>
              <input
                v-model="inputValue"
                type="number"
                step="any"
                placeholder="숫자 입력"
                class="w-full bg-muted border border-border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
                @keyup.enter="saveInput"
              />
            </div>
            <div>
              <label class="text-xs text-muted-foreground mb-1 block">메모 (선택)</label>
              <input
                v-model="inputNote"
                type="text"
                placeholder="출처 등"
                class="w-full bg-muted border border-border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
              />
            </div>
          </div>

          <div class="flex gap-2 justify-end">
            <button
              class="px-4 py-1.5 text-sm rounded-lg border border-border hover:bg-accent transition-colors"
              @click="inputModal = false"
            >
              취소
            </button>
            <button
              :disabled="inputSaving || !inputValue"
              class="px-4 py-1.5 text-sm rounded-lg bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50 transition-colors"
              @click="saveInput"
            >
              {{ inputSaving ? '저장 중...' : '저장' }}
            </button>
          </div>
        </div>
      </div>
    </transition>

  </div>
</template>
