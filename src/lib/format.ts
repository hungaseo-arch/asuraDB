// 공용 숫자/증감 포맷터. 뷰 간 중복을 줄이기 위한 공유 모듈.
// (Monitor/Margin/BranchSales 는 자체 변형을 갖고 있어 시각 QA 후 개별 이관 권장 —
//  래더·0 처리·소수자리·unit 파라미터가 달라 강제 통합 시 렌더가 바뀔 수 있음.)

// ─────────────────────────────────────────────────────────────────────────────
// 앱 표준 숫자 표기 (한국표기법 · ko-KR) — SSOT
//   · 기본  : 천단위 콤마 + 정수형   → fmtInt
//   · 퍼센트: 소수점 한자리 + '%'    → fmtPct
//   · FOB   : 소수점 두자리          → fmtFob
//   · 중량  : 소수점 한자리          → fmtWeight
// 결측(null·undefined·NaN)·0(제품 데이터 관례상 '미입력')은 '—'. (fmtPct 의 0 은 0.0% 로 표기)
// 주의: '경영·성과' 그룹(Monitor·Margin·BranchSales·LaborCost)은 현행 표기 유지 — 본 표준 미적용.
// ─────────────────────────────────────────────────────────────────────────────
const KO = 'ko-KR';
const EMPTY = '—';
const isEmpty = (n?: number | null): boolean => n == null || Number.isNaN(n) || n === 0;

/** 기본 숫자: 천단위 콤마 · 정수(반올림). 결측·0 → '—' */
export function fmtInt(n?: number | null): string {
  return isEmpty(n) ? EMPTY : Math.round(n as number).toLocaleString(KO);
}

/** 중량: 소수점 한자리 고정. 결측·0 → '—' */
export function fmtWeight(n?: number | null): string {
  return isEmpty(n)
    ? EMPTY
    : (n as number).toLocaleString(KO, { minimumFractionDigits: 1, maximumFractionDigits: 1 });
}

/** FOB: 소수점 두자리 고정. 결측·0 → '—' */
export function fmtFob(n?: number | null): string {
  return isEmpty(n)
    ? EMPTY
    : (n as number).toLocaleString(KO, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** 퍼센트: 소수점 한자리 + '%'. 0 은 0.0% 로 표기, 결측만 '—'. sign:true 면 양수에 '+' */
export function fmtPct(n?: number | null, opts: { sign?: boolean } = {}): string {
  if (n == null || Number.isNaN(n)) return EMPTY;
  const sign = opts.sign && n > 0 ? '+' : '';
  return `${sign}${n.toLocaleString(KO, { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
}

/** 값을 '보기 좋은' 상한으로 올림 (차트 y축 최대값). 래더: 1/2/3/5/7/10. */
export function niceCeil(v: number): number {
  if (v <= 0) return 1;
  const mag = Math.pow(10, Math.floor(Math.log10(v)));
  const norm = v / mag;
  const nice =
    norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 3 ? 3 : norm <= 5 ? 5 : norm <= 7 ? 7 : 10;
  return nice * mag;
}

/** 증감률 색상 클래스 (표준 컨벤션: 양수=초록, 음수=빨강, null=muted). */
export function deltaClass(v: number | null | undefined): string {
  if (v === null || v === undefined) return 'text-muted-foreground';
  return v > 0 ? 'text-emerald-600' : v < 0 ? 'text-red-600' : 'text-muted-foreground';
}

/** 증감률 텍스트. 기본 "+14.5%" / "-3.2%" / "—". arrow=true 면 "▲ 14.5%" / "▼ 3.2%" / "─ 0.0%". */
export function deltaText(v: number | null | undefined, opts: { arrow?: boolean } = {}): string {
  if (v === null || v === undefined) return '—';
  if (opts.arrow) {
    const a = v > 0 ? '▲' : v < 0 ? '▼' : '─';
    return `${a} ${Math.abs(v).toFixed(1)}%`;
  }
  const sign = v > 0 ? '+' : '';
  return `${sign}${v.toFixed(1)}%`;
}
