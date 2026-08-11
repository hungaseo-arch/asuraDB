<!--
  src/views/tools/DotLookup.vue
  DOT 타이어 공장코드 조회 / Pencarian Kode Pabrik Ban DOT

  전제:
    - `@/lib/supabase` 의 supabase 클라이언트 사용.
    - 뷰 v_dot_lookup, v_dot_conflicts, 테이블 dot_plant_codes·dot_inspection_logs 선행 필요.
      (마이그레이션: supabase/migrations/add_dot_plant_codes.sql + seed_dot_plant_codes_vpic.sql)

  관련 문서: 작업지시서 WO-ASURADB-2026-DOT-01
-->

<script setup lang="ts">
import { ref, computed, onMounted, watch } from "vue";
import { Search, Eraser, MapPin, ClipboardCheck } from "lucide-vue-next";
import { supabase } from "@/lib/supabase";
import PageHeader from "@/components/PageHeader.vue";

/* ------------------------------------------------------------------ */
/* 타입                                                                */
/* ------------------------------------------------------------------ */

interface PlantRow {
  dot_code: string;
  code_legacy2: string | null;
  code_current3: string | null;
  plant_name: string;
  city: string | null;
  state: string | null;
  country: string | null;
  status: string | null;
  source: string;
  source_year: number | null;
  updated_at: string | null;
}

const SOURCE_LABEL: Record<string, string> = {
  vpic: "NHTSA vPIC",
  tire_business: "Tire Business",
  casing_jockey: "Casing Jockey",
  dtw: "Discount Tires World",
  tire_safety_group: "Tire Safety Group",
};

/* ------------------------------------------------------------------ */
/* 입력 파싱                                                            */
/* ------------------------------------------------------------------ */

const rawInput = ref("");

/** 사이드월 각인을 정규화한다. "DOT 1MA XY9 2426" → "1MAXY92426" */
const normalized = computed(() =>
  rawInput.value.toUpperCase().replace(/^DOT/, "").replace(/[^A-Z0-9]/g, "")
);

/** 뒤 4자리가 WWYY 형태이면 생산주차 코드로 본다. */
const dateCode = computed(() => {
  const m = /(\d{4})$/.exec(normalized.value);
  if (!m) return "";
  const wk = Number(m[1].slice(0, 2));
  return wk >= 1 && wk <= 53 ? m[1] : "";
});

/** 공장코드 후보. 3자리를 먼저 시도하고 없으면 2자리로 조회한다. */
const codeCandidates = computed(() => {
  const s = normalized.value;
  if (s.length < 2) return [];
  if (s.length === 2) return [s];
  return [s.slice(0, 3), s.slice(0, 2)];
});

/** 사이드월 표시용 구간 분할 */
const segments = computed(() => {
  const s = normalized.value;
  if (!s) return [];
  const plantLen = resolvedCode.value ? resolvedCode.value.length : Math.min(3, s.length);
  const dateLen = dateCode.value ? 4 : 0;
  const midLen = Math.max(0, s.length - plantLen - dateLen);
  return [
    { key: "plant", text: s.slice(0, plantLen), label: "공장 / Pabrik" },
    ...(midLen ? [{ key: "mid", text: s.slice(plantLen, plantLen + midLen), label: "규격·브랜드" }] : []),
    ...(dateLen ? [{ key: "date", text: s.slice(-4), label: "생산주차 / Produksi" }] : []),
  ];
});

/* ------------------------------------------------------------------ */
/* 생산일 계산                                                          */
/* ------------------------------------------------------------------ */

/** WWYY → 해당 주의 월요일. 주차 1은 1월 1일이 속한 주로 근사한다. */
function weekStart(week: number, year: number): Date {
  const jan1 = new Date(Date.UTC(year, 0, 1));
  const offset = (jan1.getUTCDay() + 6) % 7; // 월요일 기준 요일 인덱스
  return new Date(Date.UTC(year, 0, 1 - offset + (week - 1) * 7));
}

const production = computed(() => {
  if (!dateCode.value) return null;
  const week = Number(dateCode.value.slice(0, 2));
  // 4자리 WWYY 형식은 2000년부터 사용된다. 그 이전 생산분은 3자리 코드이므로
  // 여기서는 항상 2000년대로 해석하고, 미래 일자로 계산되면 오독으로 본다.
  const year = 2000 + Number(dateCode.value.slice(2));

  const start = weekStart(week, year);
  const end = new Date(start.getTime() + 6 * 86400000);
  const now = new Date();
  const months =
    (now.getUTCFullYear() - start.getUTCFullYear()) * 12 +
    (now.getUTCMonth() - start.getUTCMonth());

  const fmt = (d: Date) =>
    `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(
      d.getUTCDate()
    ).padStart(2, "0")}`;

  return {
    week,
    year,
    range: `${fmt(start)} ~ ${fmt(end)}`,
    months: Math.max(0, months),
    future: start.getTime() > now.getTime(),
  };
});

/* ------------------------------------------------------------------ */
/* 조회                                                                */
/* ------------------------------------------------------------------ */

const loading = ref(false);
const errorMsg = ref("");
const result = ref<PlantRow | null>(null);
const resolvedCode = ref("");
const allSources = ref<PlantRow[]>([]);
const hasConflict = ref(false);
const suggestions = ref<PlantRow[]>([]);
const searched = ref(false);

async function lookup() {
  errorMsg.value = "";
  result.value = null;
  resolvedCode.value = "";
  allSources.value = [];
  suggestions.value = [];
  hasConflict.value = false;
  searched.value = false;

  const candidates = codeCandidates.value;
  if (!candidates.length) {
    errorMsg.value = "공장코드는 2자리 또는 3자리입니다. 사이드월의 DOT 뒤 문자를 입력하세요.";
    return;
  }

  loading.value = true;
  try {
    for (const code of candidates) {
      const { data, error } = await supabase
        .from("v_dot_lookup")
        .select("*")
        .eq("dot_code", code)
        .maybeSingle();
      if (error) throw error;
      if (data) {
        result.value = data as PlantRow;
        resolvedCode.value = code;
        break;
      }
    }
    searched.value = true;

    if (result.value) {
      await loadDetail(resolvedCode.value);
    } else {
      const { data } = await supabase
        .from("v_dot_lookup")
        .select("*")
        .ilike("dot_code", `${candidates[candidates.length - 1]}%`)
        .limit(10);
      suggestions.value = (data ?? []) as PlantRow[];
    }
  } catch (e: any) {
    errorMsg.value = `조회에 실패했습니다. ${e?.message ?? "네트워크 상태를 확인하세요."}`;
  } finally {
    loading.value = false;
  }
}

/** 소스별 원본 행과 소스 간 불일치 여부를 가져온다. */
async function loadDetail(code: string) {
  const [{ data: rows }, { data: conflict }] = await Promise.all([
    supabase.from("dot_plant_codes").select("*").eq("dot_code", code),
    supabase.from("v_dot_conflicts").select("dot_code").eq("dot_code", code).maybeSingle(),
  ]);
  allSources.value = (rows ?? []) as PlantRow[];
  hasConflict.value = Boolean(conflict);
}

function reset() {
  rawInput.value = "";
  result.value = null;
  suggestions.value = [];
  searched.value = false;
  errorMsg.value = "";
}

function pick(code: string) {
  rawInput.value = code + (dateCode.value || "");
  lookup();
}

/* ------------------------------------------------------------------ */
/* 국가별 목록                                                          */
/* ------------------------------------------------------------------ */

const PRIORITY_COUNTRIES = ["Indonesia", "China", "Thailand", "India", "Vietnam", "Korea, Republic of"];
const country = ref("");
const countryRows = ref<PlantRow[]>([]);
const countryLoading = ref(false);
/** 서버 조회 상한 — 국가 하나에 공장이 이보다 많으면 잘려 나오므로 아래 표에 그 사실을 함께 표기한다. */
const COUNTRY_LIMIT = 300;
const countryTruncated = computed(() => countryRows.value.length >= COUNTRY_LIMIT);

async function browseCountry() {
  if (!country.value) {
    countryRows.value = [];
    return;
  }
  countryLoading.value = true;
  try {
    const { data } = await supabase
      .from("v_dot_lookup")
      .select("*")
      .ilike("country", `%${country.value}%`)
      .order("plant_name")
      .limit(COUNTRY_LIMIT);
    countryRows.value = (data ?? []) as PlantRow[];
  } finally {
    countryLoading.value = false;
  }
}
watch(country, browseCountry);

/** 국가 목록 표시용 — 3자리 현행코드를 대표로 삼아 구코드(2자리) 중복 행을 병합. */
const countryDisplay = computed(() => {
  const map = new Map<string, PlantRow>();
  for (const r of countryRows.value) {
    const key = `${r.code_current3 || r.dot_code}·${r.source}`;
    const isCurrent = !!r.code_current3 && r.dot_code === r.code_current3;
    if (!map.has(key) || isCurrent) map.set(key, r);
  }
  return Array.from(map.values());
});

/** 비고란: 대표(3자리)와 다른 2자리 구코드를 표기, 없으면 대시. */
function legacyNote(r: PlantRow): string {
  const main = r.code_current3 || r.dot_code;
  return r.code_legacy2 && r.code_legacy2 !== main ? r.code_legacy2 : "—";
}

/* ------------------------------------------------------------------ */
/* 검수 기록 (로그인 사용자 전용)                                        */
/* ------------------------------------------------------------------ */

const signedIn = ref(false);
const logOpen = ref(false);
const logSaving = ref(false);
const logSaved = ref(false);
const logForm = ref({ po_no: "", container_no: "", tire_size: "", expected_plant: "", remark: "" });

onMounted(async () => {
  const { data } = await supabase.auth.getUser();
  signedIn.value = Boolean(data?.user);
});

const matched = computed(() => {
  const exp = logForm.value.expected_plant.trim().toLowerCase();
  if (!exp || !result.value) return null;
  return result.value.plant_name.toLowerCase().includes(exp);
});

async function saveLog() {
  if (!result.value) return;
  logSaving.value = true;
  logSaved.value = false;
  try {
    const { data: u } = await supabase.auth.getUser();
    const { error } = await supabase.from("dot_inspection_logs").insert({
      po_no: logForm.value.po_no || null,
      container_no: logForm.value.container_no || null,
      tire_size: logForm.value.tire_size || null,
      dot_code: resolvedCode.value,
      week_year_code: dateCode.value || null,
      expected_plant: logForm.value.expected_plant || null,
      matched: matched.value,
      remark: logForm.value.remark || null,
      created_by: u?.user?.id ?? null,
    });
    if (error) throw error;
    logSaved.value = true;
    logForm.value = { po_no: "", container_no: "", tire_size: "", expected_plant: "", remark: "" };
  } catch (e: any) {
    errorMsg.value = `검수 기록을 저장하지 못했습니다. ${e?.message ?? ""}`;
  } finally {
    logSaving.value = false;
  }
}

/* ------------------------------------------------------------------ */
/* 표시 헬퍼                                                            */
/* ------------------------------------------------------------------ */

const location = computed(() => {
  const r = result.value;
  if (!r) return "";
  return [r.city, r.state, r.country].filter(Boolean).join(", ") || "소재지 미기재";
});

const num = (n: number) => n.toLocaleString("en-US");
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">
    <PageHeader
      title="DOT 공장코드 조회"
      subtitle="Pencarian Kode Pabrik Ban DOT · 사이드월 각인으로 생산공장과 생산시기를 확인합니다."
    />

    <!-- 입력 + 결과 (한 박스, 좌우 50%) -->
    <section class="rounded-xl border border-border bg-card p-4">
      <div class="grid gap-4 lg:grid-cols-2">
      <!-- 왼쪽: 입력 -->
      <div>
      <label class="block text-sm font-semibold mb-1.5" for="dot-input">
        사이드월 각인 / Kode pada dinding ban
      </label>
      <div class="flex flex-wrap gap-2">
        <input
          id="dot-input"
          v-model="rawInput"
          class="flex-1 min-w-55 rounded-lg border border-border bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          type="text"
          autocomplete="off"
          spellcheck="false"
          placeholder="예: 1MA 또는 DOT 1MA XY9 2426"
          @keyup.enter="lookup"
        />
        <button
          class="inline-flex items-center gap-1.5 rounded-lg border border-primary/40 bg-primary/15 px-4 py-2 text-sm font-semibold text-primary transition-colors hover:bg-primary/20 disabled:opacity-50"
          :disabled="loading"
          @click="lookup"
        >
          <Search :size="15" /> {{ loading ? "조회 중" : "조회" }}
        </button>
        <button
          class="inline-flex items-center gap-1.5 rounded-lg border border-border bg-card px-4 py-2 text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground"
          @click="reset"
        >
          <Eraser :size="15" /> 지우기
        </button>
      </div>
      <p class="text-xs text-muted-foreground mt-2">
        전체 각인을 그대로 붙여넣어도 됩니다. 앞 2~3자리를 공장코드로, 뒤 4자리를 생산주차로 읽습니다.
      </p>

      <!-- 사이드월 구간 표시 -->
      <div v-if="segments.length" class="flex flex-wrap items-stretch gap-1.5 mt-3.5 p-3 bg-muted/40 rounded-lg" aria-label="각인 구간 분해">
        <span class="self-center font-mono font-bold tracking-widest text-muted-foreground">DOT</span>
        <span
          v-for="s in segments" :key="s.key"
          class="flex flex-col items-center px-2.5 py-1.5 rounded-md border"
          :class="s.key === 'plant'
            ? 'border-primary/40 bg-primary/10'
            : s.key === 'mid' ? 'border-dashed border-border bg-card opacity-75' : 'border-border bg-card'"
        >
          <span class="font-mono text-lg font-bold tracking-wider text-foreground">{{ s.text }}</span>
          <span class="text-[10px] text-muted-foreground mt-0.5">{{ s.label }}</span>
        </span>
      </div>
      </div>

      <!-- 오른쪽: 결과 / 미등록 / 안내 -->
      <div class="lg:border-l lg:border-border lg:pl-4">
      <p v-if="errorMsg" class="rounded-lg border border-destructive/40 border-l-[3px] border-l-destructive bg-destructive/5 px-3 py-2.5 text-sm text-destructive" role="alert">{{ errorMsg }}</p>

      <!-- 결과 -->
      <div v-if="result">
      <div class="flex flex-wrap items-start justify-between gap-2">
        <div class="flex items-baseline gap-2">
          <span class="font-mono text-xl font-bold tracking-wider">{{ resolvedCode }}</span>
          <span v-if="result.code_legacy2 && result.code_current3" class="text-xs text-muted-foreground">
            {{ result.code_legacy2 }} / {{ result.code_current3 }}
          </span>
        </div>
        <div class="flex flex-wrap gap-1.5">
          <span class="text-[11px] px-2 py-0.5 rounded-full border border-border bg-muted text-muted-foreground">{{ SOURCE_LABEL[result.source] ?? result.source }}</span>
          <span v-if="result.source_year" class="text-[11px] px-2 py-0.5 rounded-full border border-border bg-muted text-muted-foreground">{{ result.source_year }} 기준</span>
          <span v-if="hasConflict" class="text-[11px] px-2 py-0.5 rounded-full border border-warning-border bg-warning-soft font-semibold text-warning">소스 간 상이</span>
        </div>
      </div>

      <h2 class="text-lg font-bold mt-2.5">{{ result.plant_name }}</h2>
      <p class="flex items-center gap-1 text-sm text-muted-foreground mt-0.5">
        <MapPin :size="14" class="shrink-0" /> {{ location }}
      </p>

      <dl class="flex flex-wrap gap-x-8 gap-y-3 mt-3.5">
        <div><dt class="text-[11px] text-muted-foreground mb-0.5">상태 / Status</dt><dd class="text-sm font-semibold">{{ result.status || "미확인" }}</dd></div>
        <div v-if="production">
          <dt class="text-[11px] text-muted-foreground mb-0.5">생산주차 / Produksi</dt>
          <dd class="text-sm font-semibold">{{ production.year }}년 {{ production.week }}주차 <span class="font-normal text-muted-foreground">({{ production.range }})</span></dd>
        </div>
        <div v-if="production">
          <dt class="text-[11px] text-muted-foreground mb-0.5">경과</dt>
          <dd class="text-sm font-semibold tabular-nums">{{ num(production.months) }}개월</dd>
        </div>
      </dl>

      <p v-if="production?.future" class="rounded-lg border border-warning-border border-l-[3px] border-l-warning bg-warning-soft px-3 py-2.5 text-sm text-warning mt-3">
        생산일이 미래로 계산됩니다. 뒤 4자리를 다시 확인하세요. 2000년 이전 생산분은 3자리 날짜코드를 사용합니다.
      </p>

      <!-- 소스 간 상이 시 전체 표시 -->
      <details v-if="hasConflict" class="mt-3.5">
        <summary class="cursor-pointer text-sm font-semibold">소스별 등록 내용 {{ allSources.length }}건 보기</summary>
        <div class="overflow-x-auto mt-2.5">
          <table class="w-full text-xs border-collapse whitespace-nowrap">
            <caption class="sr-only">소스별 DOT 등록 내용</caption>
            <thead>
              <tr class="text-muted-foreground">
                <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">소스</th>
                <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">기준연도</th>
                <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">공장명</th>
                <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">소재지</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(r, i) in allSources" :key="i" class="border-b border-border/50">
                <td class="px-2 py-2">{{ SOURCE_LABEL[r.source] ?? r.source }}</td>
                <td class="px-2 py-2 tabular-nums">{{ r.source_year ?? "-" }}</td>
                <td class="px-2 py-2 whitespace-normal">{{ r.plant_name }}</td>
                <td class="px-2 py-2 whitespace-normal">{{ [r.city, r.state, r.country].filter(Boolean).join(", ") }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="text-xs text-muted-foreground mt-2">
          NHTSA vPIC 등록 내용을 우선합니다. 그 외 소스는 편제 시점이 달라 소유주 변경이 반영되지 않았을 수 있습니다.
        </p>
      </details>

      <!-- 검수 기록 -->
      <div v-if="signedIn" class="mt-4 pt-3.5 border-t border-border">
        <button
          class="inline-flex items-center gap-1.5 rounded-lg border border-border bg-card px-3 py-2 text-xs font-semibold text-muted-foreground transition-colors hover:text-foreground"
          @click="logOpen = !logOpen"
        >
          <ClipboardCheck :size="14" /> {{ logOpen ? "검수 기록 닫기" : "검수 기록 남기기" }}
        </button>

        <div v-if="logOpen" class="mt-3 space-y-2.5">
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2.5">
            <label class="block text-xs font-semibold text-muted-foreground">PO 번호
              <input v-model="logForm.po_no" class="mt-1 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" type="text" /></label>
            <label class="block text-xs font-semibold text-muted-foreground">컨테이너 번호
              <input v-model="logForm.container_no" class="mt-1 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" type="text" /></label>
            <label class="block text-xs font-semibold text-muted-foreground">규격
              <input v-model="logForm.tire_size" class="mt-1 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" type="text" placeholder="예: 26.5R25" /></label>
            <label class="block text-xs font-semibold text-muted-foreground">PO상 공급 공장
              <input v-model="logForm.expected_plant" class="mt-1 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" type="text" /></label>
          </div>
          <label class="block text-xs font-semibold text-muted-foreground">비고
            <input v-model="logForm.remark" class="mt-1 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" type="text" /></label>

          <p v-if="matched === true" class="rounded-lg border border-success-border bg-success-soft px-3 py-2 text-sm font-semibold text-success">PO상 공장과 일치합니다.</p>
          <p v-if="matched === false" class="rounded-lg border border-destructive/40 bg-destructive/5 px-3 py-2 text-sm font-semibold text-destructive">
            PO상 공장과 일치하지 않습니다. 저장 후 클레임 근거로 사용할 수 있습니다.
          </p>

          <div class="flex items-center gap-2.5">
            <button
              class="rounded-lg border border-primary/40 bg-primary/15 px-4 py-2 text-sm font-semibold text-primary transition-colors hover:bg-primary/20 disabled:opacity-50"
              :disabled="logSaving"
              @click="saveLog"
            >
              {{ logSaving ? "저장 중" : "검수 기록 저장" }}
            </button>
            <span v-if="logSaved" class="text-xs rounded-full bg-success-soft text-success px-2 py-0.5">저장했습니다.</span>
          </div>
        </div>
      </div>
      </div>

      <!-- 미등록 -->
      <div v-else-if="searched">
      <h2 class="text-base font-bold mb-1.5">등록된 공장이 없습니다</h2>
      <p class="text-sm text-muted-foreground mb-2.5">
        입력하신 코드 <strong class="text-foreground font-mono">{{ codeCandidates.join(" / ") }}</strong> 는 데이터베이스에 없습니다.
        각인을 다시 확인하시거나, 아래 유사 코드에서 찾아보세요.
      </p>
      <ul v-if="suggestions.length" class="divide-y divide-border">
        <li v-for="s in suggestions" :key="s.dot_code">
          <button class="block w-full text-left px-1 py-2 rounded-md transition-colors hover:bg-accent" @click="pick(s.dot_code)">
            <span class="font-mono font-semibold">{{ s.dot_code }}</span> {{ s.plant_name }}
            <small class="block text-[11px] text-muted-foreground">{{ [s.city, s.country].filter(Boolean).join(", ") }}</small>
          </button>
        </li>
      </ul>
      <p v-else class="text-xs text-muted-foreground">유사한 코드도 찾지 못했습니다.</p>
      </div>

      <!-- 초기 안내 -->
      <p v-else class="text-sm text-muted-foreground">사이드월 각인을 입력해 조회하면 이곳에 공장 정보가 표시됩니다.</p>
      </div>
      </div>
    </section>

    <!-- 국가별 -->
    <section class="rounded-xl border border-border bg-card p-4">
      <label class="block text-sm font-semibold mb-1.5" for="country">국가별 공장 목록 / Daftar pabrik per negara</label>
      <select id="country" v-model="country" class="w-full sm:w-64 rounded-lg border border-border bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
        <option value="">국가를 선택하세요</option>
        <option v-for="c in PRIORITY_COUNTRIES" :key="c" :value="c">{{ c }}</option>
      </select>

      <p v-if="countryLoading" class="text-xs text-muted-foreground mt-3">불러오는 중</p>
      <div v-else-if="countryDisplay.length" class="overflow-x-auto mt-3.5">
        <table class="w-full text-xs border-collapse whitespace-nowrap">
          <caption class="sr-only">국가별 공장 코드 목록</caption>
          <thead>
            <tr class="text-muted-foreground">
              <th scope="col" class="text-right font-semibold px-2 py-2 border-b border-border bg-muted/40 w-10">NO</th>
              <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">코드</th>
              <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">공장명</th>
              <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">소재지</th>
              <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">소스</th>
              <th scope="col" class="text-left font-semibold px-2 py-2 border-b border-border bg-muted/40">비고</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, i) in countryDisplay" :key="(r.code_current3 || r.dot_code) + r.source" class="border-b border-border/50">
              <td class="px-2 py-2 text-right tabular-nums text-muted-foreground">{{ i + 1 }}</td>
              <td class="px-2 py-2 font-mono font-semibold">{{ r.code_current3 || r.dot_code }}</td>
              <td class="px-2 py-2 whitespace-normal">{{ r.plant_name }}</td>
              <td class="px-2 py-2 whitespace-normal">{{ [r.city, r.state].filter(Boolean).join(", ") }}</td>
              <td class="px-2 py-2">{{ SOURCE_LABEL[r.source] ?? r.source }}</td>
              <td class="px-2 py-2 font-mono text-muted-foreground">{{ legacyNote(r) }}</td>
            </tr>
          </tbody>
        </table>
        <p v-if="countryTruncated" class="text-xs text-muted-foreground mt-2">
          공장이 많아 상위 {{ COUNTRY_LIMIT }}건만 표시했습니다 — 정확한 공장은 위의 DOT 코드 조회를 이용하세요.
        </p>
      </div>
      <p v-if="country && !countryLoading && !countryRows.length" class="text-xs text-muted-foreground mt-3">
        해당 국가의 등록 공장이 없습니다.
      </p>
    </section>

    <footer class="text-xs text-muted-foreground rounded-lg bg-muted/40 p-3">
      본 데이터는 미국 NHTSA vPIC 등록 정보를 기준으로 합니다. 미국 수출 이력이 없는 공장은 등록되지 않아
      조회되지 않을 수 있습니다. 2자리 코드는 2025년까지 단계적으로 폐지되며, 신설 공장은 3자리 코드만 부여받습니다.
    </footer>
  </div>
</template>
