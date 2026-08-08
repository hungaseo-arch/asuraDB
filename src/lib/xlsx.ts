// 표 데이터를 진짜 엑셀(.xlsx)로 내보내기 — 경영·성과 페이지 공용.
// SheetJS(xlsx) 사용. exportCsv(@/lib/csv)와 시그니처를 맞춰 드롭인 교체가 쉽도록 했다.
import * as XLSX from 'xlsx';

export type Cell = string | number | null | undefined;
export interface SheetSpec { name: string; headers: Cell[]; rows: Cell[][] }

// 시트명 규칙: 31자 이내 + : \ / ? * [ ] 금지 (엑셀 제약)
function safeSheetName(name: string): string {
  return (name || 'Sheet1').replace(/[:\\/?*[\]]/g, ' ').slice(0, 31) || 'Sheet1';
}

// 열 너비 자동 맞춤(한글·CJK 는 약 2배 폭으로 가중)
function autoCols(headers: Cell[], rows: Cell[][]) {
  const width = (v: Cell) => {
    const s = v == null ? '' : String(v);
    let w = 0;
    for (const ch of s) w += ch.charCodeAt(0) > 0x2e80 ? 2 : 1; // CJK 대략 2배
    return w;
  };
  return headers.map((h, c) => {
    let max = width(h);
    for (const r of rows) max = Math.max(max, width(r[c]));
    return { wch: Math.min(Math.max(max + 2, 6), 42) };
  });
}

function makeSheet(s: SheetSpec) {
  const ws = XLSX.utils.aoa_to_sheet([s.headers, ...s.rows]);
  ws['!cols'] = autoCols(s.headers, s.rows);
  return ws;
}

const withExt = (filename: string) => (filename.endsWith('.xlsx') ? filename : `${filename}.xlsx`);

/** 단일 시트 내보내기 (exportCsv 시그니처 호환). */
export function exportXlsx(filename: string, headers: Cell[], rows: Cell[][], sheetName = 'Sheet1'): void {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, makeSheet({ name: sheetName, headers, rows }), safeSheetName(sheetName));
  XLSX.writeFile(wb, withExt(filename));
}

/** 다중 시트 내보내기 (시트명 중복 시 자동 구분). */
export function exportXlsxSheets(filename: string, sheets: SheetSpec[]): void {
  const wb = XLSX.utils.book_new();
  const used = new Set<string>();
  sheets.forEach((s, i) => {
    let nm = safeSheetName(s.name || `Sheet${i + 1}`);
    while (used.has(nm.toLowerCase())) nm = safeSheetName(`${nm}_${i + 1}`);
    used.add(nm.toLowerCase());
    XLSX.utils.book_append_sheet(wb, makeSheet(s), nm);
  });
  XLSX.writeFile(wb, withExt(filename));
}
