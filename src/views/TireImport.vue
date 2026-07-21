<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { Printer, X, Upload, Info, Download, CloudDownload } from 'lucide-vue-next';
import { toast } from 'vue-sonner';
import { sbGetAll, sbPost } from '@/lib/supabase';
import { API_BASE, IS_HOST, ensureApiRunning } from '@/lib/api';
import PageHeader from '@/components/PageHeader.vue';
import { exportCsv } from '@/lib/csv';
import { niceCeil, deltaClass, deltaText } from '@/lib/format';
import hsMasterJson from '@/data/hsMaster.json';

// ── Types ───────────────────────────────────────────────────────────────────

interface ImportRow {
  id: string;
  year: number;
  month: number;
  hs_code: string;
  category: string;
  country: string;
  value_usd: number;
}

// ── HS Code 마스터 ──────────────────────────────────────────────────────────

// HS 코드 마스터 v3 (32종·16 category) — AHTN 2022(=BTKI 2022), SNI Wajib Ban 기준.
// HS 코드 숫자 오름차순 정렬 유지 (안내표 No 순번 기준).
// ※ 40118040 은 40118021/29 대체 예정 구코드지만 실데이터 존재로 유지.
// uraian: BTKI/INSW 기준 인니어 품목기술 · lartas: 수입규제 상태(아래 LARTAS_META)
//   'sni'  = SNI Wajib 강제인증 대상(INSW 적색 Lartas). 근거: Permenperin 11/M-IND/PER/1/2012(6종 SNI Wajib Ban)
//            - 외피(ban luar): PC/LT/TB/MC (SNI 0098/0099/0100/0101)
//            - 이너튜브(ban dalam): 40131011(PC·LT)·40131021(TB)·40139020(MC) 만 규정 명시 → sni.
//              나머지 튜브(OTR·광산·자전거·40131029 잔여)는 비명시 → na.
//   'ban'  = Barang dilarang impor(수입금지) — 중고타이어
//   'na'   = SNI Wajib 비대상 (PI/LS 등 기타 Lartas 여부는 INSW에서 개별 확인)
// 단일 소스: src/data/hsMaster.json (collectors/*.py·scripts/bps-parser.mjs 와 공유).
interface HsRow { hs: string; category: string; label: string; label_en: string; uraian: string; lartas: string; }
const HS_MASTER = hsMasterJson as HsRow[];

// Lartas(수입규제) 상태 메타. 근거: SNI Wajib Ban(Permenperin) + Permendag 8/2024(PI/LS) + 중고 수입금지.
const LARTAS_META: Record<string, { label: string; color: string; desc: string }> = {
  sni: { label: 'SNI Wajib',  color: '#ff9900', desc: 'SNI 강제인증 대상 · 수입 시 SPPT-SNI + Pertek + PI 필요 (INSW 적색 Lartas)' },
  ban: { label: '수입금지',    color: '#b91c1c', desc: 'Barang dilarang impor — 수입 금지 품목 (중고 타이어)' },
  na:  { label: 'SNI 비대상',  color: '#64748b', desc: 'SNI Wajib Ban 비해당. PI/LS 등 기타 Lartas 여부는 INSW(insw.go.id)에서 개별 확인' },
};

const CATEGORY_COLOR: Record<string, string> = {
  pc:           '#ec407a',
  lt:           '#42a5f5',
  tb:           '#1e88e5',
  mc:           '#26c6da',
  bc:           '#66bb6a',
  agr:          '#9ccc65',
  ind:          '#ffa726',
  mining_truck: '#ef5350',
  otr:          '#ab47bc',
  aircraft:     '#78909c',
  other:        '#78909c',
  retread:      '#8d6e63',
  used:         '#a1887f',
  solid:        '#26a69a',
  tube:         '#90a4ae',
  flap:         '#607d8b',
};

const CATEGORY_LABEL: Record<string, string> = {
  pc:           'Passenger Car',
  lt:           'Light Truck',
  tb:           'Truck & Bus',
  mc:           'Motorcycle',
  bc:           'Bicycle',
  agr:          'Agricultural',
  ind:          'Industrial/Pneumatic',
  mining_truck: 'Mining Truck',
  otr:          'OTR',
  aircraft:     'Aircraft',
  other:        'Other New',
  retread:      'Retreaded',
  used:         'Used',
  solid:        'Solid',
  tube:         'Inner Tube',
  flap:         'Flap',
};

// KPI·차트·표 집계 대상 (신품 타이어 본계열). aircraft·retread·used 는 참고용,
// tube·flap 은 부자재라 기존과 동일하게 집계 제외.
const TIRE_CATEGORIES = ['pc', 'lt', 'tb', 'mc', 'bc', 'agr', 'ind', 'mining_truck', 'otr', 'other', 'solid'];

// ── State ───────────────────────────────────────────────────────────────────

const today            = new Date();
const selectedYear     = ref(today.getFullYear()); // 메인 뷰 선택 연도
const selectedCategory = ref<string>('');           // '' = 전체

const allRows     = ref<ImportRow[]>([]);
const loading     = ref(true);
const loadError   = ref<string | null>(null);
const showHsRef   = ref(false);

// csv paste modal (entry년월 공용 — DB row가 연/월 키)
const entryYear  = ref(today.getFullYear());
const entryMonth = ref(today.getMonth() + 1);

// csv paste modal
const csvModal = ref(false);
const csvText  = ref('');
const csvError = ref('');
const csvSaving = ref(false);

// ── Computed ─────────────────────────────────────────────────────────────────

// 선택 연도 라벨 ("2024년" / "2026년 Q1")
const yearLabel = computed(() => {
  const y = yearlyTrend.value.find(yt => yt.year === selectedYear.value);
  return y?.periodLabel ? `${selectedYear.value}년 ${y.periodLabel}` : `${selectedYear.value}년`;
});

// 선택 연도 데이터 (전체 row)
const yearRows = computed(() =>
  allRows.value.filter(r => r.year === selectedYear.value)
);

// 타이어 카테고리만 필터링 (KPI/차트/표 모두 공통) + 카테고리 드롭다운 적용
const yearTireRows = computed(() =>
  yearRows.value.filter(r =>
    TIRE_CATEGORIES.includes(r.category) &&
    (!selectedCategory.value || r.category === selectedCategory.value),
  ),
);

const yearTotal = computed(() =>
  yearTireRows.value.reduce((s, r) => s + (r.value_usd ?? 0), 0)
);

// ── CSV 내보내기 (선택 연도·분류의 원시 행) ──────────────────────────────────
function downloadImportCsv() {
  const headers = ['연도', '월', 'HS코드', '분류', '국가', '금액(USD)'];
  const rows = [...yearTireRows.value]
    .sort((a, b) => a.month - b.month || a.hs_code.localeCompare(b.hs_code))
    .map(r => [r.year, r.month, r.hs_code, r.category, r.country, r.value_usd]);
  exportCsv(`타이어수입_${selectedYear.value}`, headers, rows);
}

// KPI 카드 YoY = 연간 추이(yearlyTrend)가 이미 계산한 선택연도 전년 대비 증감률을 재사용.
// (partial 연도의 동기간 비교 로직도 yearlyTrend 안에 있어 별도 재계산 불필요 → 값 불일치 방지)
const yoyPct = computed(() =>
  yearlyTrend.value.find(y => y.year === selectedYear.value)?.yoy ?? null,
);

// 가장 최신 데이터 연월 (max year → max month)
const latestPeriod = computed((): { year: number; month: number } | null => {
  if (!allRows.value.length) return null;
  let maxY = -Infinity, maxM = -Infinity;
  for (const r of allRows.value) {
    if (r.year > maxY || (r.year === maxY && r.month > maxM)) {
      maxY = r.year;
      maxM = r.month;
    }
  }
  return { year: maxY, month: maxM };
});

// 카테고리별 집계 (선택 연도)
const catBreakdown = computed(() => {
  const map: Record<string, number> = {};
  for (const r of yearTireRows.value) {
    map[r.category] = (map[r.category] ?? 0) + r.value_usd;
  }
  return TIRE_CATEGORIES
    .map(cat => ({ cat, usd: map[cat] ?? 0 }))
    .sort((a, b) => b.usd - a.usd);
});

// 국가별 집계 (선택 연도, country != 'ALL') · pct = 국가별 총합 대비 비율
const countryBreakdown = computed(() => {
  const map: Record<string, number> = {};
  for (const r of yearRows.value.filter(r =>
    r.country !== 'ALL' &&
    TIRE_CATEGORIES.includes(r.category) &&
    (!selectedCategory.value || r.category === selectedCategory.value),
  )) {
    map[r.country] = (map[r.country] ?? 0) + r.value_usd;
  }
  const entries = Object.entries(map)
    .map(([country, usd]) => ({ country, usd }))
    .sort((a, b) => b.usd - a.usd);
  const totalUsd = entries.reduce((s, e) => s + e.usd, 0);
  return entries.slice(0, 7).map(item => ({
    ...item,
    pct: totalUsd > 0 ? (item.usd / totalUsd) * 100 : 0,
  }));
});

// 상단 필터(타이어 카테고리 + 선택 카테고리) 적용 스코프 — KPI·차트·표 공통
function inScope(r: ImportRow): boolean {
  return TIRE_CATEGORIES.includes(r.category) && (!selectedCategory.value || r.category === selectedCategory.value);
}

// ── Annual trajectory ────────────────────────────────────────────────────────

// 기본 분석 윈도우 (5년 고정). 데이터 유무와 무관하게 항상 이 5개 연도를 표시.
const TRAJECTORY_START_YEAR = 2022;
const TRAJECTORY_END_YEAR   = 2026;
const TRAJECTORY_YEARS: number[] = Array.from(
  { length: TRAJECTORY_END_YEAR - TRAJECTORY_START_YEAR + 1 },
  (_, i) => TRAJECTORY_START_YEAR + i,
);

interface YearlyTotal {
  year: number;
  total_usd: number;
  months: number[];    // 보유한 월 (1-12)
  isPartial: boolean;  // 12개월 미만 = 진행 중인 연도 (데이터 없으면 true)
  periodLabel: string; // 'Q1' / 'H1' / '9M' / '' (full year)
  yoy: number | null;
}

function periodSuffix(monthsArr: number[]): string {
  if (!monthsArr.length || monthsArr.length === 12) return '';
  const sorted = [...monthsArr].sort((a, b) => a - b);
  const max    = sorted[sorted.length - 1];
  const continuous = sorted.length === max && sorted.every((m, i) => m === i + 1);
  if (continuous) {
    if (max === 3) return 'Q1';
    if (max === 6) return 'H1';
    if (max === 9) return '9M';
  }
  return `${sorted.length}M`;
}

const yearlyTrend = computed((): YearlyTotal[] => {
  // 1) 데이터를 연도별로 집계
  const map: Record<number, { year: number; total_usd: number; months: Set<number> }> = {};
  for (const r of allRows.value.filter(inScope)) {
    if (!map[r.year]) map[r.year] = { year: r.year, total_usd: 0, months: new Set() };
    map[r.year].total_usd += r.value_usd ?? 0;
    map[r.year].months.add(r.month);
  }
  // 2) 분석 윈도우(2022-2026) 모든 연도를 강제로 포함 — 데이터 없으면 0/빈 months
  const arr = TRAJECTORY_YEARS.map(y => {
    const m = map[y];
    return {
      year:      y,
      total_usd: m?.total_usd ?? 0,
      months:    m ? [...m.months].sort((a, b) => a - b) : [],
    };
  });

  return arr.map((y, i) => {
    const hasData     = y.months.length > 0;
    const isPartial   = hasData && y.months.length < 12;
    const periodLabel = periodSuffix(y.months);

    let yoy: number | null = null;

    if (hasData && i > 0) {
      const prev = arr[i - 1];
      if (isPartial) {
        // 진행 중인 연도: 작년 같은 기간(월 집합)과 비교
        const monthSet = new Set(y.months);
        const prevPartial = allRows.value
          .filter(r => r.year === prev.year && monthSet.has(r.month) && inScope(r))
          .reduce((acc, r) => acc + (r.value_usd ?? 0), 0);
        if (prevPartial > 0) {
          yoy = ((y.total_usd - prevPartial) / prevPartial) * 100;
        }
      } else if (prev.total_usd > 0) {
        yoy = ((y.total_usd - prev.total_usd) / prev.total_usd) * 100;
      }
    }

    return {
      year: y.year,
      total_usd: y.total_usd,
      months:    y.months,
      isPartial,
      periodLabel,
      yoy,
    };
  });
});

const peakYearValue = computed(() => {
  const full = yearlyTrend.value.filter(y => !y.isPartial);
  if (!full.length) return null;
  return full.reduce((m, y) => (y.total_usd > m.total_usd ? y : m), full[0]);
});

const yearRangeLabel = computed(() => {
  const arr = yearlyTrend.value;
  if (!arr.length) return '';
  return `${arr[0].year}—${arr[arr.length - 1].year}`;
});

// ── Bar chart SVG helpers ─────────────────────────────────────────────────────

const CHART_W      = 700;
const CHART_H      = 280;
const CHART_PAD_L  = 56;   // y-axis 라벨 공간
const CHART_PAD_R  = 16;
const CHART_PAD_T  = 40;   // 막대 위 YoY/PEAK 라벨 공간
const BAR_GAP      = 40;

const yearBars = computed(() => {
  const data = yearlyTrend.value;
  if (!data.length) return [];
  const maxVal = niceCeil(Math.max(...data.map(d => d.total_usd), 1));
  const innerW = CHART_W - CHART_PAD_L - CHART_PAD_R;
  const barW   = Math.max(8, (innerW - BAR_GAP * (data.length - 1)) / data.length);
  const peakYr = peakYearValue.value?.year ?? null;

  return data.map((d, i) => {
    const hasData = d.total_usd > 0;
    const h = hasData ? Math.max(2, (d.total_usd / maxVal) * CHART_H) : 0;
    const x = CHART_PAD_L + i * (barW + BAR_GAP);
    const y = CHART_PAD_T + (CHART_H - h);
    const isPeak     = peakYr === d.year;
    const isNegYoy   = d.yoy !== null && d.yoy < 0 && !d.isPartial;
    let fill = '#1a1a1a';                              // 기본 검정
    if (d.isPartial)        fill = '#e89c8a';          // 진행 중 = 연한 코랄
    else if (isPeak)        fill = '#c9a049';          // 피크 = 금색
    else if (isNegYoy)      fill = '#d44a2a';          // YoY 음수 = 빨강
    const isSelected = d.year === selectedYear.value;
    return { x, y, w: barW, h, d, hasData, isPeak, isNegYoy, fill, isSelected };
  });
});

const yAxisTicks = computed(() => {
  const data = yearlyTrend.value;
  if (!data.length) return [];
  const maxVal = niceCeil(Math.max(...data.map(d => d.total_usd), 1));
  // 0, 1/3, 2/3, max 4개 눈금
  return [0, 1, 2, 3].map(i => {
    const v = (maxVal * i) / 3;
    const y = CHART_PAD_T + CHART_H - (v / maxVal) * CHART_H;
    return { value: v, y, label: fmtAxis(v) };
  });
});

function fmtAxis(v: number): string {
  if (v === 0) return '0';
  if (v >= 1_000_000_000) return `${(v / 1_000_000_000).toFixed(1).replace(/\.0$/, '')}B`;
  if (v >= 1_000_000)     return `${Math.round(v / 1_000_000)}M`;
  if (v >= 1_000)         return `${Math.round(v / 1_000)}K`;
  return String(Math.round(v));
}

function fmtUsdCompact(v: number): string {
  if (v >= 1_000_000_000) return `${(v / 1_000_000_000).toFixed(2)}B`;
  if (v >= 1_000_000)     return `${Math.round(v / 1_000_000)}M`;
  if (v >= 1_000)         return `${Math.round(v / 1_000)}K`;
  return String(Math.round(v));
}

function yearAxisLabel(y: YearlyTotal): string {
  return y.periodLabel ? `${y.year} ${y.periodLabel}` : String(y.year);
}

function fmtUsd(v: number): string {
  if (v >= 1_000_000) return `$${(v / 1_000_000).toFixed(1)}M`;
  if (v >= 1_000)     return `$${(v / 1_000).toFixed(0)}K`;
  return `$${v.toFixed(0)}`;
}

// ── Navigation ────────────────────────────────────────────────────────────────

const availableYears = computed(() =>
  [...new Set(allRows.value.map(r => r.year))].sort((a, b) => a - b)
);

// 카테고리 드롭다운: 실제 데이터가 있는 카테고리만 (예: 'Other New' 데이터 없으면 제외).
// HS 코드 안내 모달(HS_MASTER)에는 전체 유지.
const dropdownCategories = computed(() => {
  const present = new Set(allRows.value.map(r => r.category));
  return TIRE_CATEGORIES.filter(c => present.has(c));
});

// ── Data loading ─────────────────────────────────────────────────────────────

async function loadData() {
  loading.value   = true;
  loadError.value = null;
  try {
    // 필요한 컬럼만 조회 (id/weight_kg/created_at 미사용 — 페이로드 ~40% 절감)
    allRows.value = await sbGetAll<ImportRow>(
      'tire_imports?select=year,month,hs_code,category,country,value_usd&order=year.desc,month.desc'
    );
    // 선택연도에 데이터가 없으면 가장 최신 연도로 자동 이동
    const hasSelected = allRows.value.some(r => r.year === selectedYear.value);
    if (!hasSelected && allRows.value.length > 0) {
      selectedYear.value = allRows.value[0].year; // order=year.desc 정렬 보장
    }
  } catch (e) {
    loadError.value = e instanceof Error ? e.message : String(e);
  } finally {
    loading.value = false;
  }
}

// ── 최신 데이터 가져오기 (로컬 FastAPI → BPS WebAPI dataexim) ─────────────────
// 호스트 PC(localhost)에서만 동작 — service_role 백엔드가 로컬에만 있음.

const collecting = ref(false);

async function fetchLatest() {
  if (collecting.value) return;
  collecting.value = true;
  try {
    // 런처가 유휴 시 API(8000)를 자동 종료하므로, 직접 호출 전 먼저 깨운다.
    // (이 단계 없이 바로 POST 하면 API 가 꺼져 있을 때 fetch 가 throw → '오프라인' 오진)
    if (!await ensureApiRunning()) {
      toast.error('로컬 API(:8000) 오프라인 — 런처(com.asuradb.launcher) 상태를 확인하세요.');
      return;
    }
    // years 미전송 → 서버가 수집 대상 연도를 결정(연초엔 전년도 발표분·소급 수정까지 포함).
    const res = await fetch(`${API_BASE}/collect/tire-imports`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    const json = await res.json();
    if (!res.ok || json.ok === false) {
      toast.error(json.error ?? `수집 실패 (HTTP ${res.status})`);
      return;
    }
    const years: Array<{ year: number; ok: boolean; rows: number; error?: string }> = json.years ?? [];
    const total = years.reduce((s, y) => s + (y.ok ? y.rows : 0), 0);
    const failed = years.filter(y => !y.ok);
    if (total > 0) {
      const span = years.filter(y => y.ok && y.rows > 0).map(y => y.year).join(', ');
      toast.success(`${span}년 총 ${total}행 갱신 완료`);
      await loadData();
    } else if (failed.length) {
      toast.error(`BPS 호출 실패: ${failed[0].error ?? '알 수 없는 오류'}`);
    } else {
      toast.info('BPS에 신규 데이터 없음');
    }
  } catch {
    toast.error('로컬 API(:8000) 오프라인 — 런처(com.asuradb.launcher) 상태를 확인하세요.');
  } finally {
    collecting.value = false;
  }
}

// ── PDF print ─────────────────────────────────────────────────────────────────

function handlePrint() {
  window.print();
}

function openCsv() {
  entryYear.value  = selectedYear.value;
  entryMonth.value = today.getMonth() + 1;
  csvText.value    = '';
  csvError.value   = '';
  csvModal.value   = true;
}

// ── CSV paste ────────────────────────────────────────────────────────────────
// 형식: HS코드 TAB 국가 TAB USD금액
// 예)  40112013	China	12345678

async function saveCsv() {
  csvError.value  = '';
  csvSaving.value = true;
  const lines = csvText.value.trim().split('\n').filter(Boolean);
  const rows: object[] = [];

  for (const line of lines) {
    // 탭 구분 우선(엑셀 복사). 탭이 없으면 콤마 폴백 — 단 앞 2필드(HS·국가)만 분리하고
    // 나머지는 금액으로 합쳐 천단위 콤마(예: 12,345,678)가 쪼개지지 않게 한다.
    let cols = line.split('\t').map(c => c.trim());
    if (cols.length < 3) {
      const parts = line.split(',');
      if (parts.length >= 3) cols = [parts[0].trim(), parts[1].trim(), parts.slice(2).join(',').trim()];
    }
    if (cols.length < 3) { csvError.value = `파싱 실패: "${line}"`; csvSaving.value = false; return; }
    const [hs, country, usdStr] = cols;
    const hsMeta = HS_MASTER.find(h => h.hs === hs);
    if (!hsMeta) { csvError.value = `알 수 없는 HS 코드: ${hs}`; csvSaving.value = false; return; }
    rows.push({
      year:      entryYear.value,
      month:     entryMonth.value,
      hs_code:   hs,
      category:  hsMeta.category,
      country:   country || 'ALL',
      value_usd: Number(usdStr.replace(/,/g, '')) || 0,
    });
  }

  try {
    // upsert in batches of 50 (UNIQUE 재입력 시 409 대신 병합 갱신)
    for (let i = 0; i < rows.length; i += 50) {
      await sbPost('tire_imports', rows.slice(i, i + 50) as any, { onConflict: 'year,month,hs_code,country' });
    }
    csvModal.value = false;
    csvText.value  = '';
    await loadData();
  } catch (e) {
    csvError.value = e instanceof Error ? e.message : String(e);
  } finally {
    csvSaving.value = false;
  }
}

onMounted(loadData);
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">

    <!-- Header -->
    <PageHeader title="인도네시아 타이어 수입량">
      <template #subtitle>
        <p class="text-xs text-muted-foreground mt-1">
          BPS EXIM 연도별 수입 분석
          <span v-if="latestPeriod" class="ml-2 text-xs">
            · {{ latestPeriod.year }}-{{ String(latestPeriod.month).padStart(2, '0') }}
          </span>
        </p>
      </template>
      <template #controls>
        <!-- 필터: 연도 / 카테고리 -->
        <div class="flex items-center gap-2 flex-wrap">
          <select
            v-model="selectedYear"
            class="text-xs px-2 py-1.5 rounded-md border border-border bg-card text-foreground hover:bg-accent transition-colors cursor-pointer focus:outline-none focus:ring-1 focus:ring-primary tabular-nums print-hide"
          >
            <option v-for="y in availableYears" :key="y" :value="y">{{ y }}년</option>
          </select>
          <select
            v-model="selectedCategory"
            class="text-xs px-2 py-1.5 rounded-md border border-border bg-card text-foreground hover:bg-accent transition-colors cursor-pointer focus:outline-none focus:ring-1 focus:ring-primary print-hide"
            :class="selectedCategory ? 'font-semibold' : ''"
          >
            <option value="">카테고리 전체</option>
            <option v-for="cat in dropdownCategories" :key="cat" :value="cat">{{ CATEGORY_LABEL[cat] }}</option>
          </select>
        </div>
      </template>
      <template #actions>
        <div class="flex items-center gap-2 print-hide">
        <button
          class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors"
          @click="showHsRef = !showHsRef"
        >
          <Info :size="12" />
          HS 코드 안내
        </button>
        <button
          v-if="IS_HOST"
          class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-primary/10 text-primary border border-primary/20 hover:bg-primary/20 transition-colors disabled:opacity-50"
          :disabled="collecting"
          @click="fetchLatest"
        >
          <CloudDownload :size="12" :class="collecting && 'animate-pulse'" />
          {{ collecting ? '가져오는 중…' : '최신데이터가져오기' }}
        </button>
        <button
          class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors"
          @click="openCsv"
        >
          <Upload :size="12" />
          CSV 붙여넣기
        </button>
        <button
          class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-border bg-card hover:bg-accent transition-colors"
          @click="downloadImportCsv"
        >
          <Download :size="12" />
          CSV 내보내기
        </button>
        <button
          class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-primary/10 text-primary border border-primary/20 hover:bg-primary/20 transition-colors"
          @click="handlePrint"
        >
          <Printer :size="12" />
          인쇄
        </button>
        </div>
      </template>
    </PageHeader>



    <!-- Loading -->
    <div v-if="loading" class="space-y-4">
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div v-for="i in 3" :key="i" class="h-20 rounded-xl bg-muted animate-pulse" />
      </div>
      <div class="h-48 rounded-xl bg-muted animate-pulse" />
    </div>

    <template v-else-if="!loadError">

      <!-- KPI cards -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div class="rounded-xl border border-border bg-card p-4 space-y-1">
          <p class="text-[11.5px] text-muted-foreground">연간 수입금액</p>
          <p class="text-2xl font-extrabold tabular-nums">{{ fmtUsd(yearTotal) }}</p>
          <p class="text-xs" :class="deltaClass(yoyPct)">YoY {{ deltaText(yoyPct, { arrow: true }) }}</p>
        </div>
        <div class="rounded-xl border border-border bg-card p-4 space-y-1">
          <p class="text-[11.5px] text-muted-foreground">최대 카테고리</p>
          <p class="text-base font-bold truncate">
            {{ catBreakdown[0] ? CATEGORY_LABEL[catBreakdown[0].cat] : '—' }}
          </p>
          <p class="text-xs text-muted-foreground">
            {{ catBreakdown[0] ? fmtUsd(catBreakdown[0].usd) : '' }}
          </p>
        </div>
        <div class="rounded-xl border border-border bg-card p-4 space-y-1">
          <p class="text-[11.5px] text-muted-foreground">최대 원산지</p>
          <p class="text-base font-bold truncate">
            {{ countryBreakdown[0]?.country ?? '—' }}
          </p>
          <p class="text-xs text-muted-foreground">
            {{ countryBreakdown[0] ? fmtUsd(countryBreakdown[0].usd) : '' }}
          </p>
        </div>
      </div>

      <!-- 그래프 1개와 테이블 2개 묶음 : 가로 정렬-->
      <div class="flex flex-col-2 md:flex-row gap-4">
        
        <!-- Annual trajectory bar chart -->
        <div class="w-[50%] rounded-xl border border-border bg-card p-4 space-y-4">
          <div class="flex items-baseline justify-between">
            <p class="text-xs font-semibold tracking-[0.2em] uppercase">
              <span class="text-primary">§ 01</span>
              <span class="text-muted-foreground"> · </span>
              <span>Annual Trajectory</span>
              <span v-if="selectedCategory" class="text-primary normal-case tracking-normal"> · {{ CATEGORY_LABEL[selectedCategory] }}</span>
            </p>
            <p class="text-xs tracking-[0.2em] text-muted-foreground">
              {{ yearRangeLabel }}
            </p>
          </div>

          <div v-if="!yearlyTrend.length" class="h-40 flex items-center justify-center text-sm text-muted-foreground">
            데이터 없음
          </div>

          <div v-else class="overflow-x-auto">
            <svg
              :viewBox="`0 0 ${CHART_W} ${CHART_H + CHART_PAD_T + 30}`"
              class="w-full"
              preserveAspectRatio="xMidYMid meet"
            >
              <!-- Y-axis grid lines + labels -->
              <g>
                <line
                  v-for="t in yAxisTicks"
                  :key="'g-' + t.value"
                  :x1="CHART_PAD_L"
                  :x2="CHART_W - CHART_PAD_R"
                  :y1="t.y"
                  :y2="t.y"
                  stroke="currentColor"
                  stroke-opacity="0.12"
                  stroke-width="1"
                />
                <text
                  v-for="t in yAxisTicks"
                  :key="'yl-' + t.value"
                  :x="CHART_PAD_L - 8"
                  :y="t.y + 3"
                  text-anchor="end"
                  class="fill-muted-foreground"
                  style="font-size: 10px; font-family: monospace"
                >
                  {{ t.label }}
                </text>
              </g>

              <!-- Bars (데이터 없는 연도는 점선으로 자리만 표시) -->
              <template v-for="bar in yearBars" :key="'b-' + bar.d.year">
                <rect
                  v-if="bar.hasData"
                  :x="bar.x"
                  :y="bar.y"
                  :width="bar.w"
                  :height="bar.h"
                  :fill="bar.fill"
                  :stroke="bar.isSelected ? '#e2e8f0' : 'none'"
                  :stroke-width="bar.isSelected ? 2 : 0"
                />
                <!-- 선택 연도 표시 점 (데이터 없는 연도 포함) -->
                <circle
                  v-if="bar.isSelected"
                  :cx="bar.x + bar.w / 2"
                  :cy="CHART_PAD_T + CHART_H + 30"
                  r="2.5"
                  fill="#e2e8f0"
                />
                <line
                  v-else
                  :x1="bar.x"
                  :x2="bar.x + bar.w"
                  :y1="CHART_PAD_T + CHART_H"
                  :y2="CHART_PAD_T + CHART_H"
                  stroke="currentColor"
                  stroke-opacity="0.3"
                  stroke-width="2"
                  stroke-dasharray="3 3"
                />
              </template>

              <!-- Labels above bar: PEAK · 878M or ±YoY% -->
              <template v-for="bar in yearBars" :key="'top-' + bar.d.year">
                <text
                  v-if="bar.isPeak"
                  :x="bar.x + bar.w / 2"
                  :y="bar.y - 10"
                  text-anchor="middle"
                  fill="#c9a049"
                  style="font-size: 11px; font-weight: 600; letter-spacing: 0.1em"
                >
                  PEAK · {{ fmtUsdCompact(bar.d.total_usd) }}
                </text>
                <text
                  v-else-if="bar.d.yoy !== null && !bar.d.isPartial"
                  :x="bar.x + bar.w / 2"
                  :y="bar.y - 10"
                  text-anchor="middle"
                  :fill="bar.d.yoy > 0 ? '#10b981' : '#ef4444'"
                  style="font-size: 11px; font-weight: 600"
                >
                  {{ bar.d.yoy > 0 ? '+' : '' }}{{ bar.d.yoy.toFixed(1) }}%
                </text>
              </template>

              <!-- X-axis (year) labels -->
              <text
                v-for="bar in yearBars"
                :key="'yr-' + bar.d.year"
                :x="bar.x + bar.w / 2"
                :y="CHART_PAD_T + CHART_H + 20"
                text-anchor="middle"
                :class="bar.isSelected ? 'fill-foreground' : 'fill-muted-foreground'"
                :style="`font-size: 11px; font-family: monospace; letter-spacing: 0.05em; font-weight: ${bar.isSelected ? 700 : 400}`"
              >
                {{ yearAxisLabel(bar.d) }}
              </text>
            </svg>
          </div>

          <!-- Yearly totals table -->
          <div v-if="yearlyTrend.length" class="pt-2">
            <div class="grid grid-cols-[1fr_auto_auto] gap-x-6 text-xs uppercase tracking-[0.18em] text-muted-foreground border-b border-border pb-2">
              <span>Year</span>
              <span class="text-right">Total</span>
              <span class="text-right">YoY</span>
            </div>
            <div
              v-for="y in yearlyTrend"
              :key="'row-' + y.year"
              class="grid grid-cols-[1fr_auto_auto] gap-x-6 items-baseline py-3 border-b border-border last:border-b-0"
            >
              <span class="font-serif text-lg" :class="y.total_usd === 0 && 'text-muted-foreground/60'">
                {{ yearAxisLabel(y) }}
              </span>
              <span class="font-mono text-sm text-right tabular-nums" :class="y.total_usd === 0 && 'text-muted-foreground/60'">
                {{ y.total_usd > 0 ? y.total_usd.toLocaleString() : '—' }}
              </span>
              <span class="text-right text-sm" :class="deltaClass(y.yoy)">
                <span class="font-semibold">{{ deltaText(y.yoy) }}</span>
              </span>
            </div>
          </div>
        </div>

        <!-- Category breakdown + Country ranking -->
        <div class="w-[50%] grid grid-row-1 gap-4">

          <!-- Category breakdown -->
          <div class="rounded-xl border border-border bg-card p-4 space-y-3">
            <p class="text-sm font-semibold">{{ yearLabel }} · 카테고리별 수입금액</p>
            <div v-if="!catBreakdown.filter(c => c.usd > 0).length" class="text-sm text-muted-foreground py-4 text-center">
              선택 연도 데이터 없음
            </div>
            <div v-else class="space-y-2.5">
              <div
                v-for="item in catBreakdown"
                :key="item.cat"
                class="space-y-1"
              >
                <div class="flex items-center justify-between text-xs">
                  <div class="flex items-center gap-1.5">
                    <span
                      class="w-2 h-2 rounded-full shrink-0"
                      :style="{ background: CATEGORY_COLOR[item.cat] }"
                    />
                    <span class="font-medium">{{ CATEGORY_LABEL[item.cat] }}</span>
                  </div>
                  <div class="flex items-center gap-2 text-muted-foreground">
                    <span>{{ yearTotal > 0 ? ((item.usd / yearTotal) * 100).toFixed(1) + '%' : '—' }}</span>
                    <span class="font-semibold text-foreground">{{ fmtUsd(item.usd) }}</span>
                  </div>
                </div>
                <div class="h-1.5 rounded-full bg-muted overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all duration-500"
                    :style="{
                      width: yearTotal > 0 ? `${(item.usd / yearTotal) * 100}%` : '0%',
                      background: CATEGORY_COLOR[item.cat],
                    }"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- Country ranking -->
          <div class="rounded-xl border border-border bg-card p-4 space-y-3">
            <p class="text-sm font-semibold">{{ yearLabel }} · 원산지별 수입금액 Top 7</p>
            <div v-if="!countryBreakdown.length" class="text-sm text-muted-foreground py-4 text-center">
              국가별 데이터 없음<br />
              <span class="text-xs">country ≠ 'ALL' 데이터 입력 시 표시됩니다.</span>
            </div>
            <div v-else class="space-y-2">
              <div
                v-for="(item, idx) in countryBreakdown"
                :key="item.country"
                class="flex items-center gap-2 text-xs"
              >
                <span class="w-5 text-right text-muted-foreground font-mono shrink-0">{{ idx + 1 }}</span>
                <div class="flex-1 space-y-1">
                  <div class="flex justify-between">
                    <span class="font-medium">{{ item.country }}</span>
                    <div class="flex items-center gap-2 text-muted-foreground">
                      <span class="tabular-nums">{{ item.pct.toFixed(1) }}%</span>
                      <span class="font-semibold text-foreground">{{ fmtUsd(item.usd) }}</span>
                    </div>
                  </div>
                  <div class="h-1 rounded-full bg-muted overflow-hidden">
                    <div
                      class="h-full rounded-full bg-blue-500/70 transition-all duration-500"
                      :style="{ width: `${item.pct}%` }"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

      </div>

      <!-- BPS 수집 가이드 -->
      <div class="rounded-xl border border-border bg-muted/20 p-4 space-y-2">
        <p class="text-xs font-semibold text-muted-foreground">BPS EXIM 데이터 수집 방법</p>
        <ol class="text-xs text-muted-foreground space-y-1 list-decimal list-inside">
          <li><a href="https://www.bps.go.id/id/exim" class="text-primary hover:underline" target="_blank">bps.go.id/id/exim</a> 접속 → 연도·HS Code·월 선택 → 테이블 생성</li>
          <li>US$ 선택 후 엑셀 다운로드</li>
          <li>엑셀 정리 후 <strong>CSV 붙여넣기</strong> 버튼 사용 (형식: HS코드 TAB 국가 TAB USD)</li>
        </ol>
        <p class="text-[11px] text-muted-foreground/60">
          HS 코드 확인: INSW (insw.go.id) · BTKI (beacukai.go.id/arsip/lan/BTKI-2022.html)
        </p>
        <p class="text-[11px] text-primary pt-1 border-t border-border/50">
          ⚡ 일괄 적재(무키): 포털에서 XLSX 다운로드 후
          <code class="bg-muted px-1 rounded">node scripts/ingest-bps-file.mjs &lt;파일.xlsx&gt; [--dry-run]</code>
          — 32종 HS 월별·국가별로 파싱해 upsert. KG 표는 <code class="bg-muted px-1 rounded">--metric=weight</code>
        </p>
        <p class="text-[11px] text-muted-foreground/60">
          API 자동 적재(BPS_API_KEY 필요 시): <code class="bg-muted px-1 rounded">python collectors/bps_import_collector.py 2025</code>
        </p>
      </div>

    </template>

    <!-- Error state -->
    <div
      v-if="!loading && loadError"
      class="rounded-xl border border-red-500/20 bg-red-500/5 p-6 text-center space-y-3"
    >
      <p class="text-sm font-semibold text-red-600">데이터 로드 실패</p>
      <code class="block text-[11px] bg-muted rounded-lg px-4 py-2 text-left text-muted-foreground break-all">
        {{ loadError }}
      </code>
      <p class="text-xs text-muted-foreground">
        Supabase SQL Editor에서 <code class="bg-muted px-1 rounded">supabase/migrations/add_tire_imports.sql</code> 을 실행하세요.
      </p>
    </div>

    <!-- HS 코드 안내 modal -->
    <transition enter-active-class="transition-opacity duration-150" enter-from-class="opacity-0" leave-active-class="transition-opacity duration-150" leave-to-class="opacity-0">
      <div v-if="showHsRef" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" @click.self="showHsRef = false">
        <div class="bg-card border border-border rounded-2xl w-full max-w-5xl max-h-[85vh] shadow-2xl flex flex-col overflow-hidden">
          <div class="flex items-start justify-between px-5 py-4 border-b border-border">
            <div>
              <h3 class="font-semibold text-sm">HS 코드 마스터 (BPS EXIM 기준)</h3>
              <p class="text-xs text-muted-foreground mt-0.5">인도네시아 타이어 수입 HS 코드 {{ HS_MASTER.length }}종 · 품목기술(Uraian Barang) · Lartas 수입규제 · DB 카테고리</p>
            </div>
            <button class="p-1 rounded hover:bg-accent text-muted-foreground" @click="showHsRef = false"><X :size="16" /></button>
          </div>
          <div class="overflow-auto">
            <table class="w-full text-xs">
              <thead class="sticky top-0 bg-card z-10">
                <tr class="border-b border-border text-muted-foreground">
                  <th class="px-3 py-2 text-right font-medium w-10">No</th>
                  <th class="px-3 py-2 text-left font-medium">HS Code</th>
                  <th class="px-3 py-2 text-left font-medium">분류</th>
                  <th class="px-3 py-2 text-left font-medium">품목기술 (Uraian Barang)</th>
                  <th class="px-3 py-2 text-left font-medium">Lartas</th>
                  <th class="px-3 py-2 text-left font-medium">DB 카테고리</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(h, i) in HS_MASTER"
                  :key="h.hs"
                  class="border-b border-border/50 hover:bg-muted/30"
                >
                  <td class="px-3 py-2 text-right font-mono text-muted-foreground tabular-nums">{{ i + 1 }}</td>
                  <td class="px-3 py-2 font-mono text-foreground/80 whitespace-nowrap">{{ h.hs }}</td>
                  <td class="px-3 py-2 whitespace-nowrap">
                    <span class="inline-flex items-center gap-1">
                      <span
                        class="w-2 h-2 rounded-full shrink-0"
                        :style="{ background: CATEGORY_COLOR[h.category] }"
                      />
                      {{ h.label }}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-muted-foreground" :title="h.label_en">{{ h.uraian }}</td>
                  <td class="px-3 py-2 whitespace-nowrap">
                    <span
                      class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[11px] font-medium"
                      :style="{ background: LARTAS_META[h.lartas].color + '22', color: LARTAS_META[h.lartas].color }"
                      :title="LARTAS_META[h.lartas].desc"
                    >
                      <span v-if="h.lartas !== 'na'">🚩</span>
                      {{ LARTAS_META[h.lartas].label }}
                    </span>
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap">
                    <span
                      class="inline-flex items-center gap-1.5 px-1.5 py-0.5 rounded font-mono text-[11px]"
                      :style="{ background: CATEGORY_COLOR[h.category] + '22', color: CATEGORY_COLOR[h.category] }"
                    >
                      {{ h.category }}
                      <span class="text-muted-foreground">· {{ CATEGORY_LABEL[h.category] }}</span>
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="px-5 py-3 border-t border-border space-y-2">
            <!-- Lartas 범례 -->
            <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5">
              <span class="text-[11px] font-semibold text-muted-foreground">Lartas 범례:</span>
              <span v-for="(m, key) in LARTAS_META" :key="key" class="inline-flex items-center gap-1 text-[11px]" :title="m.desc">
                <span class="inline-flex items-center px-1.5 py-0.5 rounded font-medium" :style="{ background: m.color + '22', color: m.color }">
                  <span v-if="key !== 'na'">🚩</span>{{ m.label }}
                </span>
                <span class="text-muted-foreground">{{ m.desc }}</span>
              </span>
            </div>
            <p class="text-[11px] text-muted-foreground/70">
              ※ Lartas(Larangan/Pembatasan) 상태는 SNI Wajib Ban(SNI 0098/0099/0100/0101 외피 + PC·LT·TB·MC 이너튜브)·중고 수입금지 기준.
              PI/LS 등 개별 규제는
              <a href="https://insw.go.id/intr" target="_blank" class="text-primary hover:underline">INSW INTR</a>
              에서 HS별 적색 깃발로 최종 확인 필요.
            </p>
            <p class="text-[11px] text-yellow-400/90 pt-1 border-t border-yellow-500/20">
              ⚠ OTR 이너튜브: 40139011/19 → 굴삭기·로더 등 건설기계(8429/8430),
              40139031/39 → 광산 덤프트럭·도로차량(Ch.87)
            </p>
          </div>
        </div>
      </div>
    </transition>

    <!-- CSV paste modal -->
    <transition enter-active-class="transition-opacity duration-150" enter-from-class="opacity-0" leave-active-class="transition-opacity duration-150" leave-to-class="opacity-0">
      <div v-if="csvModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" @click.self="csvModal = false">
        <div class="bg-card border border-border rounded-2xl p-6 w-full max-w-lg shadow-2xl space-y-4">
          <div class="flex items-start justify-between">
            <div>
              <h3 class="font-semibold text-sm">CSV 붙여넣기</h3>
              <p class="text-xs text-muted-foreground">{{ entryYear }}년 {{ String(entryMonth).padStart(2, '0') }}월 데이터 일괄 입력</p>
            </div>
            <button class="p-1 rounded hover:bg-accent text-muted-foreground" @click="csvModal = false"><X :size="14" /></button>
          </div>

          <div class="space-y-3">
            <div class="grid grid-cols-2 gap-2">
              <div>
                <label class="text-xs text-muted-foreground mb-1 block">연도</label>
                <input v-model.number="entryYear" type="number" min="2000" max="2099" class="w-full bg-muted border border-border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary" />
              </div>
              <div>
                <label class="text-xs text-muted-foreground mb-1 block">월</label>
                <select v-model.number="entryMonth" class="w-full bg-muted border border-border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary">
                  <option v-for="m in 12" :key="m" :value="m">{{ String(m).padStart(2, '0') }}월</option>
                </select>
              </div>
            </div>
            <p class="text-xs text-muted-foreground">형식: <code class="bg-muted px-1 rounded">HS코드 [탭] 원산지 [탭] USD금액</code></p>
            <p class="text-xs text-muted-foreground">예시: <code class="bg-muted px-1 rounded">40112013	China	12345678</code></p>
            <textarea
              v-model="csvText"
              rows="8"
              placeholder="엑셀에서 복사한 데이터를 여기에 붙여넣으세요..."
              class="w-full bg-muted border border-border rounded-lg px-3 py-2 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-primary resize-none"
            />
            <p v-if="csvError" class="text-xs text-red-600">{{ csvError }}</p>
          </div>

          <div class="flex gap-2 justify-end">
            <button class="px-4 py-1.5 text-sm rounded-lg border border-border hover:bg-accent transition-colors" @click="csvModal = false">취소</button>
            <button :disabled="csvSaving || !csvText.trim()" class="px-4 py-1.5 text-sm rounded-lg bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50 transition-colors" @click="saveCsv">
              {{ csvSaving ? '저장 중…' : '저장' }}
            </button>
          </div>
        </div>
      </div>
    </transition>

  </div>
</template>

<style scoped>
@media print {
  .print-hide { display: none !important; }
  /* 인쇄 시 그림자/배경 단순화 */
  :deep(.shadow-2xl) { box-shadow: none !important; }
  /* 페이지 분할: 카드/표가 잘리지 않도록 */
  :deep(.rounded-xl) { break-inside: avoid; page-break-inside: avoid; }
  :deep(table) { break-inside: auto; }
  :deep(tr)    { break-inside: avoid; page-break-inside: avoid; }
}
@page { margin: 10mm; }
</style>
