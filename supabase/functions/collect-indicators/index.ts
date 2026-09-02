// collect-indicators — 지표 수집 Edge Function (작업지시서 KPI지표_월별백필_2026 §7)
//
// 로컬 launchd 수집기 4종을 클라우드로 이관한 것. pg_cron → trigger_collector(p_kind)
// → pg_net POST { kind } 로 호출된다 (Authorization: service_role — verify_jwt 통과).
//
//   kind=fx        ← collectors/indicator_collector.py (yfinance → Yahoo chart API)
//   kind=commodity ← collectors/daily_collector.py     (고무·니켈, TE 스크래핑)
//   kind=weekly    ← collectors/weekly_collector.py    (카본블랙·BD·강선·SCFI)
//   kind=monthly   ← collectors/monthly_collector.py   (CPO·석탄·BI금리·물가·PMI·관세)
//
// 로컬 대비 유지한 안전장치:
//   - upsert on_conflict (indicator_id, recorded_date) — 삭제 없음, 멱등
//   - _is_yearlike 연도 오인 필터 + commodity ±25% 이상값 가드 (2026-08-24 CPO 사고 재발 방지)
//   - monthly 는 WIB 기준 말일 가드 + 누락월 catchup
//   - 실행 후 collector_heartbeat 에 edge_<kind> upsert
//
// v2 (2026-08-24, 5년백필 작업지시서 ②③⑤)
//   - 모든 행에 note(출처) + quality(실측/파생/추정) 기록. note 없는 upsert 금지.
//   - nr_rubber: 소스 USc/kg → 저장 USD/MT (×10, 정확히 한 번)
//   - cpo : Bursa FCPO(MYR/MT) → Kemendag Harga Referensi(USD/MT) · commodity → monthly
//   - coal: TE Newcastle → ESDM HBA I(5,300 kcal, USD/MT) · weekly → monthly
//   - idn_inflation: BPS 변수 1707(인터넷 이용률 — 오적용) → 2249(YoY) / 1(MoM 파생)
//   두 이관 지표는 자동 수집 실패 시 옛 소스로 되돌아가지 않고 수동 입력을 요구한다.
//
// BPS_API_KEY 는 Edge Function Secrets 환경변수로 등록 (runbook 참고).

import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const UA_HEADERS: Record<string, string> = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept-Language": "en-US,en;q=0.9",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
};
const FETCH_TIMEOUT_MS = 20_000;

type Row = { d: string; v: number };
type Result = Record<string, unknown>;

// ── 공통 유틸 ─────────────────────────────────────────────────

// pg_cron 은 UTC — 기록 기준일은 로컬 수집기와 동일하게 WIB(UTC+7) 달력으로 계산.
function wibNow(): Date {
  return new Date(Date.now() + 7 * 3600 * 1000); // getUTC* 접근자가 WIB 값을 반환
}
function wibTodayStr(): string {
  return wibNow().toISOString().slice(0, 10);
}
function monthEndStr(y: number, m1: number): string {
  // m1 = 1..12; Date.UTC(y, m1, 0) = 해당 월 말일
  return new Date(Date.UTC(y, m1, 0)).toISOString().slice(0, 10);
}
function toMonthEnd(dateStr: string): string {
  const [y, m] = dateStr.split("-").map(Number);
  return monthEndStr(y, m);
}

async function fetchText(url: string, headers?: Record<string, string>): Promise<string | null> {
  try {
    const r = await fetch(url, {
      headers: { ...UA_HEADERS, ...headers },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (!r.ok) return null;
    return await r.text();
  } catch {
    return null;
  }
}

async function fetchJson(url: string, headers?: Record<string, string>): Promise<unknown> {
  try {
    const r = await fetch(url, {
      headers: { ...UA_HEADERS, Accept: "application/json", ...headers },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (!r.ok) return null;
    return await r.json();
  } catch {
    return null;
  }
}

type Quality = "실측" | "파생" | "추정";

// 모든 행은 출처(note)와 품질 등급(quality)을 갖는다 (5년백필 원칙).
async function upsert(
  indicatorId: string, recordedDate: string, value: number,
  note: string, quality: Quality = "실측",
) {
  if (!note) throw new Error(`note(출처) 없는 행 금지: ${indicatorId}@${recordedDate}`);
  const { error } = await sb.from("indicator_history").upsert(
    { indicator_id: indicatorId, value, recorded_date: recordedDate, note, quality },
    { onConflict: "indicator_id,recorded_date" },
  );
  if (error) throw new Error(`upsert ${indicatorId}@${recordedDate}: ${error.message}`);
}

async function latestInDb(indicatorId: string): Promise<Row | null> {
  const { data, error } = await sb.from("indicator_history")
    .select("value,recorded_date")
    .eq("indicator_id", indicatorId)
    .order("recorded_date", { ascending: false })
    .limit(1);
  if (error || !data?.length) return null;
  return { d: data[0].recorded_date as string, v: Number(data[0].value) };
}

async function heartbeat(source: string) {
  await sb.from("collector_heartbeat").upsert(
    { source, last_run: new Date().toISOString() },
    { onConflict: "source" },
  );
}

// 연도(2015~2035) 오인 필터 — daily_collector._is_yearlike 포팅
function isYearlike(v: number): boolean {
  return v === Math.trunc(v) && v >= 2015 && v <= 2035;
}

// DB 최근값 대비 ±maxDev 초과 이탈 값 폐기 — daily_collector._reject_outlier 포팅
async function rejectOutlier(indicatorId: string, val: number | null, maxDev = 0.25): Promise<number | null> {
  if (val == null) return null;
  const prev = await latestInDb(indicatorId);
  if (prev && prev.v > 0 && Math.abs(val - prev.v) / prev.v > maxDev) {
    console.warn(`[outlier] ${indicatorId}: ${val} vs DB ${prev.v} (${prev.d}) — 폐기`);
    return null;
  }
  return val;
}

// JSON 트리에서 범위 내 가격 재귀 탐색 (연도 제외)
function searchJsonForPrice(data: unknown, lo: number, hi: number, depth = 0): number | null {
  if (depth > 8) return null;
  if (typeof data === "number") {
    if (data >= lo && data <= hi && !isYearlike(data)) return data;
    return null;
  }
  if (Array.isArray(data)) {
    for (const item of data.slice(0, 20)) {
      const r = searchJsonForPrice(item, lo, hi, depth + 1);
      if (r != null) return r;
    }
    return null;
  }
  if (data && typeof data === "object") {
    const obj = data as Record<string, unknown>;
    for (const key of ["price", "last", "close", "value", "current", "lastPrice"]) {
      if (key in obj) {
        const r = searchJsonForPrice(obj[key], lo, hi, depth + 1);
        if (r != null) return r;
      }
    }
    for (const v of Object.values(obj)) {
      const r = searchJsonForPrice(v, lo, hi, depth + 1);
      if (r != null) return r;
    }
  }
  return null;
}

function stripTags(html: string): string {
  return html.replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ");
}

// ── Trading Economics 스크래퍼 (HTML __NEXT_DATA__ → 텍스트 최빈값 → 게스트 API) ──

async function fetchTeHtml(slug: string, lo: number, hi: number): Promise<number | null> {
  const html = await fetchText(`https://tradingeconomics.com/commodity/${slug}`);
  if (!html) return null;

  // 1) __NEXT_DATA__ / application(ld+)json 스크립트
  const scriptRe = /<script[^>]*(?:id="__NEXT_DATA__"|type="application\/(?:ld\+)?json")[^>]*>([\s\S]*?)<\/script>/gi;
  let m: RegExpExecArray | null;
  while ((m = scriptRe.exec(html)) !== null) {
    try {
      const r = searchJsonForPrice(JSON.parse(m[1]), lo, hi);
      if (r != null) return r;
    } catch { /* 다음 스크립트 */ }
  }

  // 2) 메타 태그 content
  const metaRe = /<meta[^>]*content="([^"]*)"[^>]*>/gi;
  while ((m = metaRe.exec(html)) !== null) {
    for (const n of m[1].match(/\b\d{2,6}(?:\.\d{1,4})?\b/g) ?? []) {
      const v = parseFloat(n);
      if (v >= lo && v <= hi && !isYearlike(v)) return v;
    }
  }

  // 3) 본문 텍스트 최빈값
  const text = stripTags(html).slice(0, 5000);
  const counts = new Map<number, number>();
  for (const n of text.match(/\b\d{2,6}(?:\.\d{1,4})?\b/g) ?? []) {
    const v = parseFloat(n);
    if (v >= lo && v <= hi && !isYearlike(v)) counts.set(v, (counts.get(v) ?? 0) + 1);
  }
  let best: number | null = null, bestN = 0;
  for (const [v, n] of counts) if (n > bestN) { best = v; bestN = n; }
  return best;
}

async function fetchTeApi(slug: string, lo: number, hi: number): Promise<number | null> {
  const data = await fetchJson(
    `https://api.tradingeconomics.com/commodity?c=guest:guest&f=json&commodity=${slug}`,
  );
  const items = Array.isArray(data) ? data : data ? [data] : [];
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const obj = item as Record<string, unknown>;
    for (const key of ["Last", "last", "Price", "price", "Close", "close"]) {
      if (key in obj) {
        const v = parseFloat(String(obj[key]).replace(/,/g, ""));
        if (!Number.isNaN(v) && v >= lo && v <= hi && !isYearlike(v)) return v;
      }
    }
  }
  return null;
}

// ══════════════════════════════════════════════════════════════
//  kind=fx — Yahoo Finance chart API (yfinance 대체)
// ══════════════════════════════════════════════════════════════

async function yahooHistory(ticker: string, days: number): Promise<Record<string, number>> {
  const range = days <= 30 ? "1mo" : days <= 92 ? "3mo" : days <= 186 ? "6mo" : "1y";
  const data = await fetchJson(
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}?range=${range}&interval=1d`,
  ) as Record<string, unknown> | null;
  // deno-lint-ignore no-explicit-any
  const res = (data as any)?.chart?.result?.[0];
  const ts: number[] = res?.timestamp ?? [];
  const closes: (number | null)[] = res?.indicators?.quote?.[0]?.close ?? [];
  const out: Record<string, number> = {};
  ts.forEach((t, i) => {
    const c = closes[i];
    if (c != null && Number.isFinite(c)) {
      out[new Date(t * 1000).toISOString().slice(0, 10)] = Math.round(c * 10000) / 10000;
    }
  });
  return out;
}

async function runFx(): Promise<Result[]> {
  const { data: inds, error } = await sb.from("market_indicators")
    .select("id,ticker").eq("source", "yfinance").order("sort_order");
  if (error) throw new Error(`market_indicators 조회 실패: ${error.message}`);

  const series: Record<string, Record<string, number>> = {};
  const results: Result[] = [];

  for (const ind of inds ?? []) {
    if (!ind.ticker) continue; // krw_idr (파생) 은 아래에서 계산
    const last = await latestInDb(ind.id);
    const days = last
      ? Math.min(400, Math.max(5, Math.floor((Date.now() - Date.parse(last.d)) / 86_400_000) + 3))
      : 30;
    const hist = await yahooHistory(ind.ticker, days);
    for (const [d, v] of Object.entries(hist)) {
      await upsert(ind.id, d, v, `Yahoo Finance ${ind.ticker} 종가`);
    }
    series[ind.id] = hist;
    results.push({ id: ind.id, ok: Object.keys(hist).length > 0, rows: Object.keys(hist).length });
  }

  // krw_idr = usd_idr ÷ usd_krw (indicator_collector.derive_krw_idr 포팅)
  const idr = series["usd_idr"] ?? {}, krw = series["usd_krw"] ?? {};
  let derived = 0;
  for (const d of Object.keys(idr)) {
    if (krw[d] > 0) {
      await upsert("krw_idr", d, Math.round((idr[d] / krw[d]) * 100) / 100,
        "파생: USD/IDR ÷ USD/KRW (같은 일자 Yahoo Finance 종가)", "파생");
      derived++;
    }
  }
  results.push({ id: "krw_idr", ok: derived > 0, rows: derived });
  return results;
}

// ══════════════════════════════════════════════════════════════
//  kind=commodity — 고무·니켈 (daily_collector 포팅, ±25% 가드)
//  cpo 는 monthly(Kemendag Harga Referensi) 로 이관해 여기서 제외.
// ══════════════════════════════════════════════════════════════

const TE_DAILY: Record<string, [string, number, number]> = {
  nr_rubber: ["rubber", 50, 500],       // 소스 USc/kg (저장은 ×10 → USD/MT)
  nickel:    ["nickel", 5000, 100000],  // USD/MT
};

// 소스 단위 → 저장 단위 환산계수 (market_indicators.unit_factor 와 같은 뜻)
const UNIT_FACTOR: Record<string, number> = { nr_rubber: 10, nickel: 1 };

async function runCommodity(): Promise<Result[]> {
  const today = wibTodayStr();
  const results: Result[] = [];
  for (const [id, [slug, lo, hi]] of Object.entries(TE_DAILY)) {
    let source = "Trading Economics (edge)";
    let val = await rejectOutlier(id, await fetchTeHtml(slug, lo, hi));
    if (val == null) {
      source = "Trading Economics API (edge)";
      val = await rejectOutlier(id, await fetchTeApi(slug, lo, hi));
    }
    if (val == null) {
      results.push({ id, ok: false, reason: "자동 수집 실패 — 수동 입력 필요" });
      continue;
    }
    const factor = UNIT_FACTOR[id] ?? 1;
    const stored = val * factor;
    const note = factor === 1
      ? `${source} · USD/MT`
      : `${source} · TSR20 ${val.toFixed(2)} USc/kg → 단위환산 USD/MT (×${factor})`;
    await upsert(id, today, stored, note);
    results.push({ id, ok: true, value: stored });
  }
  return results;
}

// ══════════════════════════════════════════════════════════════
//  kind=weekly — 카본블랙·합성고무BD·강선·SCFI (weekly_collector 포팅)
//  coal 은 monthly(ESDM HBA I) 로 이관해 여기서 제외.
// ══════════════════════════════════════════════════════════════

const TE_WEEKLY: Record<string, [string, number, number, string, Quality]> = {
  synthetic_rubber: ["butadiene", 500, 3000, "Trading Economics Butadiene (BD) 시세 · USD/MT", "실측"],
  steel_wire:       ["steel", 300, 2000,
    "추정: Trading Economics Steel HRC 대체 (강선 실가격 아님) · USD/MT", "추정"],
};
const CB_BRENT_FACTOR = 14.0;

function parseDateLoose(s: string): string | null {
  s = s.trim();
  const MONTHS: Record<string, number> = {
    jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
    january: 1, february: 2, march: 3, april: 4, june: 6, july: 7, august: 8,
    september: 9, october: 10, november: 11, december: 12,
    januari: 1, februari: 2, maret: 3, mei: 5, juni: 6, juli: 7, agustus: 8, oktober: 10, desember: 12,
  };
  const pad = (n: number) => String(n).padStart(2, "0");
  const valid = (y: number, m: number, d: number) =>
    y >= 1990 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
  let m: RegExpMatchArray | null;
  if ((m = s.match(/^(\d{4})-(\d{2})-(\d{2})/)))
    return valid(+m[1], +m[2], +m[3]) ? `${m[1]}-${m[2]}-${m[3]}` : null;
  if ((m = s.match(/^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})/)))
    return valid(+m[3], +m[2], +m[1]) ? `${m[3]}-${pad(+m[2])}-${pad(+m[1])}` : null;
  if ((m = s.match(/^(\d{4})[/.](\d{1,2})[/.](\d{1,2})/)))
    return valid(+m[1], +m[2], +m[3]) ? `${m[1]}-${pad(+m[2])}-${pad(+m[3])}` : null;
  if ((m = s.match(/^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})/))) {
    const mo = MONTHS[m[2].toLowerCase()];
    return mo && valid(+m[3], mo, +m[1]) ? `${m[3]}-${pad(mo)}-${pad(+m[1])}` : null;
  }
  if ((m = s.match(/^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})/))) {
    const mo = MONTHS[m[1].toLowerCase()];
    return mo && valid(+m[3], mo, +m[2]) ? `${m[3]}-${pad(mo)}-${pad(+m[2])}` : null;
  }
  if ((m = s.match(/^([A-Za-z]+)\s+(\d{4})/))) {
    const mo = MONTHS[m[1].toLowerCase()];
    return mo ? `${m[2]}-${pad(mo)}-01` : null;
  }
  return null;
}

async function fetchScfi(): Promise<{ d: string; v: number } | null> {
  // 1차: SSE AJAX (비공식 JSON)
  const data = await fetchJson("https://en.sse.net.cn/indices/scfinew.do?t=scfi", {
    Referer: "https://en.sse.net.cn/indices/scfinew.jsp",
    "X-Requested-With": "XMLHttpRequest",
  });
  const series = Array.isArray(data)
    ? data
    // deno-lint-ignore no-explicit-any
    : (data as any)?.data ?? (data as any)?.rows ?? [];
  if (Array.isArray(series) && series.length) {
    let best: { d: string; v: number } | null = null;
    for (const row of series) {
      if (!row || typeof row !== "object") continue;
      const obj = row as Record<string, unknown>;
      let d: string | null = null;
      for (const dk of ["date", "pubdate", "time", "releaseDate"]) {
        if (obj[dk]) { d = parseDateLoose(String(obj[dk])); if (d) break; }
      }
      if (!d) continue;
      for (const vk of ["scfi", "composite", "value", "index"]) {
        const v = parseFloat(String(obj[vk] ?? "").replace(/,/g, ""));
        if (!Number.isNaN(v) && v >= 300 && v <= 6000) {
          if (!best || d > best.d) best = { d, v };
          break;
        }
      }
    }
    if (best) return best;
  }

  // 2차: MacroMicro __NEXT_DATA__ 의 [timestamp, value] 시계열
  const html = await fetchText("https://en.macromicro.me/series/7541/china-scfi");
  if (html) {
    const m = html.match(/<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/i);
    if (m) {
      try {
        const search = (obj: unknown): { d: string; v: number } | null => {
          if (Array.isArray(obj)) {
            const pairs = obj.filter((x) => Array.isArray(x) && x.length === 2 &&
              typeof x[0] === "number" && typeof x[1] === "number") as [number, number][];
            if (pairs.length) {
              const [ts, v] = pairs.reduce((a, b) => (a[0] > b[0] ? a : b));
              if (v >= 300 && v <= 6000 && ts > 1e12) {
                return { d: new Date(ts).toISOString().slice(0, 10), v };
              }
            }
            for (const item of obj) { const r = search(item); if (r) return r; }
          } else if (obj && typeof obj === "object") {
            for (const v of Object.values(obj)) { const r = search(v); if (r) return r; }
          }
          return null;
        };
        const r = search(JSON.parse(m[1]));
        if (r) return r;
      } catch { /* fallthrough */ }
    }
  }
  return null;
}

async function runWeekly(): Promise<Result[]> {
  const today = wibTodayStr();
  const results: Result[] = [];

  for (const [id, [slug, lo, hi, note, quality]] of Object.entries(TE_WEEKLY)) {
    // ±25% 가드 — TE 가 무관한 숫자를 집어오는 사고 방지
    // (2026-08 steel_wire 308~970, synthetic_rubber 1,054↔2,753 실제 발생)
    let val = await rejectOutlier(id, await fetchTeHtml(slug, lo, hi));
    if (val == null) val = await rejectOutlier(id, await fetchTeApi(slug, lo, hi));
    if (val == null) {
      results.push({ id, ok: false, reason: "자동 수집 실패 — 수동 입력 필요" });
      continue;
    }
    await upsert(id, today, val, note, quality);
    results.push({ id, ok: true, value: val });
  }

  // 카본블랙 = DB 브렌트유 × 14 (Proxy)
  const brent = await latestInDb("brent_crude");
  if (brent) {
    const val = Math.round(brent.v * CB_BRENT_FACTOR);
    await upsert("carbon_black", today, val,
      `추정: 브렌트유 Proxy Brent×${CB_BRENT_FACTOR} (Brent=${brent.v.toFixed(2)} USD/bbl)`, "추정");
    results.push({ id: "carbon_black", ok: true, value: val });
  } else {
    results.push({ id: "carbon_black", ok: false, reason: "DB 브렌트유 없음" });
  }

  // SCFI
  const scfi = await fetchScfi();
  if (scfi) {
    await upsert("scfi", scfi.d, scfi.v, "SSE(상하이항운교역소) 공식 SCFI Composite / MacroMicro 대체");
    results.push({ id: "scfi", ok: true, value: scfi.v, date: scfi.d });
  } else {
    results.push({ id: "scfi", ok: false, reason: "SSE/MacroMicro 모두 실패 — 수동 입력 필요" });
  }
  return results;
}

// ══════════════════════════════════════════════════════════════
//  kind=monthly — BI금리·물가·PMI·관세 (monthly_collector 포팅, 말일 가드)
// ══════════════════════════════════════════════════════════════

// DB 최신 월 이후의 신규 월만 upsert (monthly_collector._upsert_new_months 포팅)
async function upsertNewMonths(
  indicatorId: string, rows: Row[], note: string, quality: Quality = "실측",
): Promise<number> {
  const latest = await latestInDb(indicatorId);
  const threshold = latest ? toMonthEnd(latest.d) : "1970-01-31";
  const byMonth = new Map<string, number>();
  for (const { d, v } of rows) {
    const me = toMonthEnd(d);
    if (me > threshold) byMonth.set(me, v);
  }
  for (const [me, v] of [...byMonth.entries()].sort()) await upsert(indicatorId, me, v, note, quality);
  return byMonth.size;
}

function extractAllFromJson(
  data: unknown, dateKeys: string[], valKeys: string[], lo: number, hi: number, sink: Row[] = [],
): Row[] {
  if (Array.isArray(data)) {
    for (const item of data) extractAllFromJson(item, dateKeys, valKeys, lo, hi, sink);
  } else if (data && typeof data === "object") {
    const obj = data as Record<string, unknown>;
    for (const dk of dateKeys) {
      for (const vk of valKeys) {
        if (dk in obj && vk in obj) {
          const d = parseDateLoose(String(obj[dk]));
          const v = parseFloat(String(obj[vk]).replace(/%/g, "").replace(/,/g, "."));
          if (d && !Number.isNaN(v) && v >= lo && v <= hi) sink.push({ d, v });
        }
      }
    }
    for (const v of Object.values(obj)) extractAllFromJson(v, dateKeys, valKeys, lo, hi, sink);
  }
  return sink;
}

// HTML 테이블에서 (날짜, 값) 행 추출 — BeautifulSoup 대체 (정규식 기반)
function extractTableRows(html: string, lo: number, hi: number): Row[] {
  const rows: Row[] = [];
  const trRe = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
  let tr: RegExpExecArray | null;
  while ((tr = trRe.exec(html)) !== null) {
    const cells = [...tr[1].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)]
      .map((c) => stripTags(c[1]).replace(/&nbsp;/g, " ").trim());
    if (cells.length < 2) continue;
    const d = parseDateLoose(cells[0]);
    if (!d) continue;
    const v = parseFloat(cells[1].replace(/%/g, "").replace(/,/g, ".").trim());
    if (!Number.isNaN(v) && v >= lo && v <= hi) rows.push({ d, v });
  }
  return rows;
}

// ── #3 팜유 CPO — Kemendag Harga Referensi (USD/MT, 매월 1일 적용) ──
const CPO_HR_URL = "https://gimni.org/harga-cpo/";     // Kepmendag HR 집계표
const CPO_RANGE: [number, number] = [500, 2500];

const ID_MONTH: Record<string, number> = {
  jan: 1, feb: 2, peb: 2, mar: 3, apr: 4, mei: 5, jun: 6,
  jul: 7, agt: 8, ags: 8, agu: 8, sep: 9, okt: 10, nov: 11, des: 12,
};

// '01 Agt 2026' → '2026-08-01'
function parseIdDate(s: string): string | null {
  const m = s.trim().match(/(\d{1,2})\s+([A-Za-z]+)\.?\s+(\d{4})/);
  if (!m) return null;
  const mo = ID_MONTH[m[2].slice(0, 3).toLowerCase()];
  if (!mo) return null;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${m[3]}-${pad(mo)}-${pad(+m[1])}`;
}

// 'US$ 1.029,51' → 1029.51 (인니 표기: . = 천단위, , = 소수점)
function parseIdNumber(s: string): number | null {
  const m = s.replace(/ /g, " ").match(/([\d.]+,\d+|[\d.]+)/);
  if (!m) return null;
  const v = parseFloat(m[1].replace(/\./g, "").replace(",", "."));
  return Number.isFinite(v) ? v : null;
}

type TableRow = string[];
function htmlTables(html: string): TableRow[][] {
  const tables: TableRow[][] = [];
  for (const t of html.matchAll(/<table[^>]*>([\s\S]*?)<\/table>/gi)) {
    const rows: TableRow[] = [];
    for (const tr of t[1].matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) {
      rows.push([...tr[1].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)]
        .map((c) => stripTags(c[1]).replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim()));
    }
    if (rows.length) tables.push(rows);
  }
  return tables;
}

async function collectCpo(): Promise<Result> {
  const html = await fetchText(CPO_HR_URL);
  const found: { d: string; v: number; basis: string }[] = [];
  if (html) {
    const [lo, hi] = CPO_RANGE;
    for (const rows of htmlTables(html)) {
      const head = rows[0].map((h) => h.toLowerCase());
      if (!head.some((h) => h.includes("hr") && h.includes("us$"))) continue;
      for (const cells of rows.slice(1)) {
        if (cells.length < 2) continue;
        const d = parseIdDate(cells[0]);
        const v = parseIdNumber(cells[1]);
        if (!d || v == null || v < lo || v > hi) continue;
        found.push({ d, v, basis: (cells[4] ?? "").replace(/\s*↗\s*$/, "").trim() });
      }
    }
  }
  if (!found.length) {
    return { id: "cpo", ok: false,
      reason: `Kemendag HR 자동 수집 실패 — 수동 입력 필요 (${CPO_HR_URL}). ` +
              "옛 소스(Bursa FCPO MYR/MT)로 대체 금지" };
  }

  const latest = await latestInDb("cpo");
  const threshold = latest ? toMonthEnd(latest.d) : "1970-01-31";
  const byMonth = new Map<string, { v: number; basis: string }>();
  for (const f of found) {
    const me = toMonthEnd(f.d);
    if (me > threshold) byMonth.set(me, { v: f.v, basis: f.basis });
  }
  for (const [me, { v, basis }] of [...byMonth.entries()].sort()) {
    const note = `Kemendag Harga Referensi CPO ${me.slice(0, 7)}` +
      (basis ? ` · ${basis.slice(0, 80)}` : "");
    await upsert("cpo", me, v, note);
  }
  return { id: "cpo", ok: true, newMonths: byMonth.size };
}

// ── #5 석탄 — ESDM 고시 (coal = HBA I 5,300 kcal) ──
//    참고용 HBA(6,322 kcal) 지표는 2026-08-24 삭제 — 저장하지 않는다.
const HBA_URL = "https://www.minerba.esdm.go.id/harga_acuan";
const HBA_RANGE: [number, number] = [30, 450];

async function collectCoal(): Promise<Result> {
  const html = await fetchText(HBA_URL);
  const rows: { d: string; v: number }[] = [];
  const maintenance = !!html && (html.includes("Perbaikan") || html.includes("Maintenance"));

  if (html && !maintenance) {
    const [lo, hi] = HBA_RANGE;
    for (const table of htmlTables(html)) {
      const head = table[0].map((h) => h.toUpperCase());
      const colI = head.findIndex((h) => h.includes("HBA I") || h.includes("5.300") || h.includes("5,300"));
      if (colI < 0) continue;
      for (const cells of table.slice(1)) {
        if (cells.length < 2 || colI >= cells.length) continue;
        const d = parseIdDate(cells[0]) ?? parseDateLoose(cells[0]);
        if (!d) continue;
        const v = parseIdNumber(cells[colI]);
        if (v != null && v >= lo && v <= hi) rows.push({ d, v });
      }
    }
  }

  if (!rows.length) {
    return { id: "coal", ok: false,
      reason: (maintenance ? "ESDM 사이트 점검 중 — " : "") +
        `ESDM HBA I 자동 수집 실패 — 수동 입력 필요 (${HBA_URL}). ` +
        "옛 소스(TE Newcastle)로 대체 금지 — 기준 발열량·산정식이 다름" };
  }

  const latest = await latestInDb("coal");
  const threshold = latest ? toMonthEnd(latest.d) : "1970-01-31";
  const byMonth = new Map<string, { d: string; v: number }>();
  for (const r of [...rows].sort((a, b) => a.d.localeCompare(b.d))) {
    const me = toMonthEnd(r.d);
    if (me > threshold) byMonth.set(me, r);   // 같은 달 2기 고시면 나중(15일) 값 채택
  }
  let saved = 0;
  for (const [me, r] of [...byMonth.entries()].sort()) {
    await upsert("coal", me, r.v, `ESDM HBA I(5,300 kcal) ${me.slice(0, 7)} · 고시일 ${r.d}`);
    saved++;
  }
  return { id: "coal", ok: true, newMonths: saved };
}

async function collectBiRate(): Promise<Result> {
  const html = await fetchText("https://www.bi.go.id/en/fungsi-utama/moneter/bi-rate/default.aspx");
  let rows: Row[] = html ? extractTableRows(html, 0.5, 25.0) : [];
  if (!rows.length) {
    for (const url of ["https://www.bi.go.id/id/api/content/birate", "https://www.bi.go.id/en/api/content/birate"]) {
      const data = await fetchJson(url);
      if (data) {
        rows = extractAllFromJson(data, ["effectiveDate", "date", "tanggal", "period"],
          ["biRate", "rate", "value", "bi_rate"], 0.5, 25.0);
        if (rows.length) break;
      }
    }
  }
  if (!rows.length) return { id: "bi_rate", ok: false, reason: "BI 스크래핑 실패 — 수동 입력 필요" };
  const saved = await upsertNewMonths("bi_rate", rows, "Bank Indonesia BI-Rate 공식 페이지 고시값");
  return { id: "bi_rate", ok: true, newMonths: saved };
}

// BPS 월별 시계열 — 변수 1707(인터넷 이용률) 오적용을 2026-08-24 정정.
//   2249 = Inflasi Tahunan (Y-on-Y, 2022=100)  · 2024-01 이후
//   1    = Inflasi Bulanan (M-to-M)            · 2020-01 이후
// Y-on-Y 가 없는 월은 M-to-M 12개월 누적환산으로 산출한다(등급 = 파생).
const BPS_VAR_YOY = "2249";
const BPS_VAR_MOM = "1";

// th(연도) 파라미터 필수 · 1회 3개년까지 · 연도 id = 연도 − 1900 · 월 13(연간) 제외
async function bpsSeries(varId: string, years: number[], key: string): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (let i = 0; i < years.length; i += 3) {
    const win = years.slice(i, i + 3);
    const th = win.length > 1 ? `${win[0] - 1900}:${win[win.length - 1] - 1900}` : `${win[0] - 1900}`;
    const p = await fetchJson(
      `https://webapi.bps.go.id/v1/api/list/model/data/domain/0000/var/${varId}/th/${th}/key/${key}`,
    ) as Record<string, unknown> | null;
    if (!p || p["data-availability"] !== "available") continue;
    // deno-lint-ignore no-explicit-any
    const nat = ((p["vervar"] as any[]) ?? [])
      .find((v) => String(v?.label ?? "").trim().toUpperCase() === "INDONESIA")?.val;
    if (nat == null) continue;
    const yrs: Record<string, number> = {};
    // deno-lint-ignore no-explicit-any
    for (const t of ((p["tahun"] as any[]) ?? [])) yrs[String(t.val)] = parseInt(String(t.label));
    const prefix = `${nat}${varId}0`;
    for (const [k, v] of Object.entries((p["datacontent"] as Record<string, unknown>) ?? {})) {
      if (!k.startsWith(prefix)) continue;
      const rest = k.slice(prefix.length);
      const yid = rest.slice(0, 3), mm = rest.slice(3);
      const mo = parseInt(mm);
      if (!(yid in yrs) || !/^\d+$/.test(mm) || mo < 1 || mo > 12) continue;
      const num = Number(v);
      if (Number.isFinite(num)) out[`${yrs[yid]}-${String(mo).padStart(2, "0")}`] = num;
    }
  }
  return out;
}

async function collectIdnInflation(): Promise<Result> {
  const apiKey = Deno.env.get("BPS_API_KEY") ?? "";
  if (!apiKey) return { id: "idn_inflation", ok: false, reason: "BPS_API_KEY 환경변수 미등록" };

  const now = wibNow();
  const y = now.getUTCFullYear();
  const yoy = await bpsSeries(BPS_VAR_YOY, [y - 1, y], apiKey);
  const mom = await bpsSeries(BPS_VAR_MOM, [y - 2, y - 1, y], apiKey);
  if (!Object.keys(yoy).length && !Object.keys(mom).length) {
    return { id: "idn_inflation", ok: false, reason: "BPS 응답 데이터 없음" };
  }

  // M-to-M 12개월 누적 → Y-on-Y 환산 (파생)
  const yoyFromMom = (yy: number, mm: number): number | null => {
    let acc = 1;
    for (let i = 0; i < 12; i++) {
      let m2 = mm - i, y2 = yy;
      while (m2 <= 0) { m2 += 12; y2 -= 1; }
      const v = mom[`${y2}-${String(m2).padStart(2, "0")}`];
      if (v == null) return null;
      acc *= 1 + v / 100;
    }
    return (acc - 1) * 100;
  };

  const latest = await latestInDb("idn_inflation");
  const threshold = latest ? toMonthEnd(latest.d) : "1970-01-31";
  const months = new Set([...Object.keys(yoy), ...Object.keys(mom)]);
  let saved = 0, newest: { d: string; v: number } | null = null;
  for (const ym of [...months].sort()) {
    const [yy, mm] = ym.split("-").map(Number);
    const me = monthEndStr(yy, mm);
    if (me <= threshold) continue;
    let v = yoy[ym], note = `BPS Inflasi Tahunan (Y-on-Y, 변수 ${BPS_VAR_YOY}) ${ym}`;
    let quality: Quality = "실측";
    if (v == null) {
      const derived = yoyFromMom(yy, mm);
      if (derived == null) continue;
      v = Math.round(derived * 100) / 100;
      quality = "파생";
      note = `파생: BPS 월별 M-to-M(변수 ${BPS_VAR_MOM}) 12개월 누적 환산 ${ym}`;
    }
    await upsert("idn_inflation", me, v, note, quality);
    saved++;
    newest = { d: me, v };
  }
  if (!saved) return { id: "idn_inflation", ok: true, newMonths: 0, reason: "신규 월 없음" };
  return { id: "idn_inflation", ok: true, newMonths: saved, latest: newest?.d, value: newest?.v };
}

async function collectIdnPmi(): Promise<Result> {
  // 1차: S&P Global 공식 API
  let rows: Row[] = [];
  const api = await fetchJson(
    "https://www.pmi.spglobal.com/api/pmi/CompositeGetTimeSeriesData?CountryCode=IDN&SeriesCode=Manufacturing&Frequency=Monthly",
  );
  if (api) {
    // deno-lint-ignore no-explicit-any
    const series = Array.isArray(api) ? api : (api as any)?.data ?? (api as any)?.series ?? [];
    if (Array.isArray(series)) {
      for (const row of series) {
        if (!row || typeof row !== "object") continue;
        const obj = row as Record<string, unknown>;
        const d = parseDateLoose(String(obj["date"] ?? ""));
        const v = parseFloat(String(obj["value"] ?? obj["pmi"] ?? obj["val"] ?? "").replace(/,/g, "."));
        if (d && !Number.isNaN(v) && v >= 30 && v <= 70) rows.push({ d, v });
      }
    }
  }
  // 2차: Trading Economics 페이지 텍스트
  if (!rows.length) {
    const html = await fetchText("https://tradingeconomics.com/indonesia/manufacturing-pmi");
    if (html) {
      const text = stripTags(html).slice(0, 3000);
      const m = text.match(
        /(?:Manufacturing PMI|PMI)[^\d]*([3-6]\d\.?\d?)[\s\S]*?(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})/i,
      );
      if (m) {
        const d = parseDateLoose(`${m[2]} ${m[3]}`);
        const v = parseFloat(m[1]);
        if (d && v >= 30 && v <= 70) rows.push({ d, v });
      }
    }
  }
  if (!rows.length) return { id: "idn_pmi", ok: false, reason: "S&P/TE 모두 실패 — 수동 입력 필요" };
  const saved = await upsertNewMonths("idn_pmi", rows,
    "S&P Global Indonesia Manufacturing PMI (TE 백업)");
  return { id: "idn_pmi", ok: true, newMonths: saved };
}

async function collectImportTariff(): Promise<Result> {
  const pat = /(?:Tarif\s+rata[- ]rata|Average\s+tariff|MFN\s+average)[^\d]{0,40}(\d{1,2}(?:[.,]\d{1,2})?)\s*%?/i;
  for (const url of [
    "https://www.kemendag.go.id/statistik/perdagangan-luar-negeri",
    "https://www.beacukai.go.id/arsip/pab/buku-tarif-kepabeanan-indonesia-btki-2022.html",
  ]) {
    const html = await fetchText(url);
    if (!html) continue;
    const m = stripTags(html).match(pat);
    if (m) {
      const v = parseFloat(m[1].replace(",", "."));
      if (v >= 0.5 && v <= 30) {
        const saved = await upsertNewMonths("import_tariff", [{ d: wibTodayStr(), v }],
          "Kemendag/beacukai 고시 스크래핑 (평균 수입관세율 %)");
        return { id: "import_tariff", ok: true, newMonths: saved, value: v };
      }
    }
  }
  return { id: "import_tariff", ok: false, reason: "스크래핑 실패 — 정책 미변경 시 기존값 유효" };
}

async function needsMonthlyCatchup(): Promise<boolean> {
  const now = wibNow();
  // 직전 월의 말일 (WIB 기준)
  const prevMonthEnd = monthEndStr(now.getUTCFullYear(), now.getUTCMonth()); // getUTCMonth()=0-based → 직전 월
  for (const id of ["cpo", "coal", "bi_rate", "idn_inflation", "idn_pmi"]) {
    const latest = await latestInDb(id);
    if (!latest || toMonthEnd(latest.d) < prevMonthEnd) return true;
  }
  return false;
}

async function runMonthly(force: boolean): Promise<Result[]> {
  const now = wibNow();
  const tomorrowIsFirst =
    new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).getUTCDate() === 1;
  const catchup = await needsMonthlyCatchup();
  if (!tomorrowIsFirst && !catchup && !force) {
    return [{ skipped: true, reason: "말일 아님 + 월간 지표 최신 보유 (force 로 강제 실행 가능)" }];
  }
  return [
    await collectCpo(),
    await collectCoal(),
    await collectBiRate(),
    await collectIdnInflation(),
    await collectIdnPmi(),
    await collectImportTariff(),
  ];
}

// ══════════════════════════════════════════════════════════════
//  Entry point
// ══════════════════════════════════════════════════════════════

Deno.serve(async (req: Request) => {
  let kind = "", force = false;
  try {
    const body = await req.json();
    kind = String(body?.kind ?? "");
    force = Boolean(body?.force);
  } catch { /* body 없음 */ }

  const json = (status: number, payload: unknown) =>
    new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });

  if (!["fx", "commodity", "weekly", "monthly"].includes(kind)) {
    return json(400, { ok: false, error: "kind 는 fx|commodity|weekly|monthly 중 하나여야 합니다" });
  }

  try {
    let results: Result[];
    switch (kind) {
      case "fx":        results = await runFx(); break;
      case "commodity": results = await runCommodity(); break;
      case "weekly":    results = await runWeekly(); break;
      default:          results = await runMonthly(force); break;
    }
    await heartbeat(`edge_${kind}`);
    const ok = results.every((r) => r.ok !== false);
    return json(200, { ok, kind, at: new Date().toISOString(), results });
  } catch (e) {
    console.error(`[collect-indicators] ${kind} 실패:`, e);
    return json(500, { ok: false, kind, error: String(e) });
  }
});
