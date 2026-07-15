// ============================================================
// bps-parser.mjs — BPS EXIM 교차표(XLSX) → tire_imports 레코드 변환
// Node 전용 모듈(HS 마스터를 fs로 로드). ingest-bps-file.mjs 에서 import.
//   import { parseBpsWorkbook, buildUpsertPayload, HS_MASTER } from "./bps-parser.mjs";
//
// 의존성: xlsx (SheetJS)   →  npm i -D xlsx
// 원천: https://www.bps.go.id/id/exim 에서 내려받은 교차표
//   구조: 국가(Negara)×항구(Pelabuhan)×월(Bulan)이 컬럼 → 월별 합산. Totals 행·열 제외.
// ============================================================
import { readFileSync } from "node:fs";
import * as XLSX from "xlsx";

// ── HS 코드 마스터 (32종·16 category) ──
// 단일 소스: src/data/hsMaster.json — TireImport.vue·collectors/bps_import_collector.py 와 공유(드리프트 방지).
// 근거: AHTN 2022(=BTKI 2022 8자리), SNI Wajib Ban(Permenperin 11/2012).
// 데이터 없는 코드도 등록(합 0, 초과 등록 무해) — 통계 공백만 제거.
const _hsRows = JSON.parse(readFileSync(new URL("../src/data/hsMaster.json", import.meta.url), "utf8"));
export const HS_MASTER = Object.fromEntries(_hsRows.map((r) => [r.hs, [r.label, r.category]]));
export const ALLOWED = [...new Set(_hsRows.map((r) => r.category))];
export const HS_CATEGORY = Object.fromEntries(_hsRows.map((r) => [r.hs, r.category]));

// ── 내부 유틸 ───────────────────────────────────────────────────
const trim = (x) => String(x ?? "").trim();
const num = (x) => {
  if (typeof x === "number") return x;
  if (x == null) return 0;
  let s = String(x).trim().replace(/\s/g, ""); if (!s) return 0;
  const d = s.includes("."), c = s.includes(",");
  if (d && c) s = s.lastIndexOf(",") > s.lastIndexOf(".") ? s.replace(/\./g, "").replace(",", ".") : s.replace(/,/g, "");
  else if (c) s = s.replace(/,/g, "");
  const n = parseFloat(s); return Number.isFinite(n) ? n : 0;
};
const extractHs = (v) => {
  const s = String(v); const b = s.match(/\[(\d{6,10})\]/); if (b) return b[1];
  const m = s.match(/\b\d{8}\b/) || s.match(/\d{6,10}/); return m ? (m[1] || m[0]) : s.trim();
};
const forwardFill = (row, startCol) => {
  const out = {}; let cur = null;
  for (let c = startCol; c < row.length; c++) { const v = trim(row[c]); if (v) cur = v; out[c] = cur; }
  return out;
};

/**
 * BPS EXIM 교차표를 tire_imports 레코드로 변환.
 * @param {ArrayBuffer|Uint8Array|object} input  파일 바이트(ArrayBuffer) 또는 SheetJS workbook
 * @param {object} opts
 *   metric       "value" | "weight"        (기본 "value")
 *   byCountry    true=국가별 / false=ALL   (기본 true)
 *   year         파일에 연도 없을 때 폴백
 *   countryAlias { "UNITED STATES":"USA" } 기존 DB 국가표기 정규화
 * @returns {{ rows, countries, skipped, hsFound }}
 *   rows: [{ year, month, hs_code, category, country, value_usd|null, weight_kg|null }]
 */
export function parseBpsWorkbook(input, opts = {}) {
  const { metric = "value", byCountry = true, year: cliYear = null, countryAlias = {} } = opts;
  const wb = input && input.Sheets ? input : XLSX.read(input, { type: "array" });
  const grid = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, defval: null });

  const headerRow = grid.findIndex((r) => trim(r[0]) === "Kode HS");
  const bulanRow  = grid.findIndex((r) => r.some((c) => trim(c) === "Bulan"));
  const negaraRow = grid.findIndex((r) => r.some((c) => trim(c) === "Negara/Wilayah/Entitas Tertentu"));
  let totalsCol = -1;
  for (const idx of [negaraRow, bulanRow].filter((i) => i >= 0))
    grid[idx].forEach((c, ci) => { if (trim(c) === "Totals") totalsCol = ci; });

  const monthByCol = {};
  if (bulanRow >= 0) grid[bulanRow].forEach((c, ci) => {
    const m = trim(c).match(/\[(\d{1,2})\]/); if (m && ci !== totalsCol) monthByCol[ci] = parseInt(m[1], 10);
  });
  const countryByCol = byCountry && negaraRow >= 0 ? forwardFill(grid[negaraRow], 3) : null;
  const hasMonths = Object.keys(monthByCol).length > 0;
  if (!hasMonths) throw new Error("월(Bulan) 차원이 없습니다. 월별 표로 다운로드하세요.");

  const normCountry = (c) => countryAlias[c] || c;
  const agg = new Map();
  const start = headerRow >= 0 ? headerRow + 1 : bulanRow + 2;
  const skipped = new Set();
  // 다년(multi-year) 표: HS 코드는 첫 연도 행에만 있고 이후 연도 행은 첫 컬럼이 빈칸
  // → HS 를 아래 행으로 forward-fill 하며 행별 연도(col1)로 읽는다.
  let curHs = null;
  for (let r = start; r < grid.length; r++) {
    const c0 = grid[r][0];
    if (trim(c0) === "Totals") break;
    if (c0 != null && trim(c0)) {
      const hs = extractHs(c0);
      if (/^\d{6,10}$/.test(hs)) {
        const category = HS_CATEGORY[hs];
        if (!category || !ALLOWED.includes(category)) { skipped.add(hs); curHs = null; }
        else curHs = hs;
      } else curHs = null;
    }
    const hs = curHs; if (!hs) continue;
    const category = HS_CATEGORY[hs];
    // 연도 칸(col1)이 'Totals'(HS별/전체 소계 행)면 스킵 — cliYear 폴백으로 오적재되는 것 방지.
    const yCell = trim(grid[r][1]);
    if (/totals/i.test(yCell)) continue;
    const year = parseInt(yCell.replace(/\D/g, ""), 10) || cliYear;
    if (!year || year < 2000 || year > 2099) continue;   // 유효 연도 아니면 스킵
    for (const [ci, mon] of Object.entries(monthByCol)) {
      const v = num(grid[r][ci]); if (!v) continue;
      let country = byCountry ? (countryByCol?.[ci] || "ALL") : "ALL";
      if (country === "Totals") continue;
      country = normCountry(country);
      const key = `${year}|${mon}|${hs}|${country}`;
      const cur = agg.get(key) ?? { year, month: mon, hs_code: hs, category, country, value: 0 };
      cur.value += v; agg.set(key, cur);
    }
  }

  const rows = [...agg.values()].map((a) => ({
    year: a.year, month: a.month, hs_code: a.hs_code, category: a.category, country: a.country,
    value_usd: metric === "value" ? Math.round(a.value * 100) / 100 : null,
    weight_kg: metric === "weight" ? Math.round(a.value * 100) / 100 : null,
  }));
  const countries = [...new Set(rows.map((r) => r.country))].sort();
  const hsFound = [...new Set(rows.map((r) => r.hs_code))];
  return { rows, countries, skipped: [...skipped], hsFound };
}

/**
 * 기존 행과 병합하여 upsert payload 생성 (value/weight 상호 미덮어쓰기).
 * @param {Array} rows      parseBpsWorkbook().rows
 * @param {Array} existing  DB 기존행 [{year,month,hs_code,country,value_usd,weight_kg}]
 */
export function buildUpsertPayload(rows, existing = []) {
  const ex = new Map(existing.map((e) => [`${e.year}|${e.month}|${e.hs_code}|${e.country}`, e]));
  return rows.map((r) => {
    const e = ex.get(`${r.year}|${r.month}|${r.hs_code}|${r.country}`);
    return {
      year: r.year, month: r.month, hs_code: r.hs_code, category: r.category, country: r.country,
      value_usd: r.value_usd ?? (e ? Number(e.value_usd) : 0),
      weight_kg: r.weight_kg ?? (e ? Number(e.weight_kg) : 0),
    };
  });
}
