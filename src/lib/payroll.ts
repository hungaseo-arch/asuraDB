// src/lib/payroll.ts
// 인건비(월별) 집계 로더 — Supabase `payroll_monthly`(SSOT) → 인건비 탭 표시 구조(PayrollTab[]).
// 탭 이름·행 라벨·표시 순서는 정적 메타(src/data/payrollMonthly.ts)를 쓰고, 수치만 DB 값으로 덮는다.
// DB 조회 실패·미적재 시에는 null 을 돌려 호출부가 정적 값(fallback)을 그대로 쓰게 한다.
import { sbGetAll } from '@/lib/supabase';
import { PAYROLL_TABS } from '@/data/payrollMonthly';
import type { PayrollTab, PayrollSeries, PayrollAddon } from '@/data/payrollMonthly';

interface Row { tab_key: string; item: string; row_key: string; period: string; value: number | string }

/** 전사 탭 행 라벨 ↔ DB row_key */
const COMPANY_ROW_KEY: Record<string, string> = {
  'HQ 자카르타 (본사)': 'HQ', '찌까랑·까라왕 창고': 'WH', '수라바야': 'SBY', '스마랑': 'SMG',
};
const round1 = (n: number) => Math.round((n + Number.EPSILON) * 10) / 10;
const mean = (a: number[]) => (a.length ? round1(a.reduce((s, v) => s + v, 0) / a.length) : 0);
/** 지점 탭 행 라벨('SALES (영업)') → Section 키('SALES') */
const sectionKey = (label: string) => label.split(' (')[0].trim().toUpperCase();

export interface PayrollData { tabs: PayrollTab[]; months: string[]; updated: string }

export async function loadPayroll(year = 2026): Promise<PayrollData | null> {
  const rows = await sbGetAll<Row>('payroll_monthly?select=tab_key,item,row_key,period,value');
  if (!rows.length) return null;
  const val = new Map<string, number>();
  for (const r of rows) val.set(`${r.tab_key}|${r.item}|${r.row_key}|${r.period}`, Number(r.value));

  // 반영 월 = 전사 인원 합계가 있는 달. 1월부터 끊김 없이 이어진 구간만 쓴다(중간 누락 시 그 앞까지).
  const periods: string[] = [];
  for (let m = 1; m <= 12; m++) {
    const p = `${year}-${String(m).padStart(2, '0')}`;
    if (!val.has(`company|total||${p}`)) break;
    periods.push(p);
  }
  if (!periods.length) return null;
  const baseKey = `${year - 1}-AVG`;

  const series = <T extends PayrollSeries | PayrollAddon>(tab: string, item: string, rowKey: string, fallback: T): T => {
    const m = periods.map(p => val.get(`${tab}|${item}|${rowKey}|${p}`) ?? 0);
    const base = val.get(`${tab}|${item}|${rowKey}|${baseKey}`);
    return { ...fallback, avg2025: base ?? fallback.avg2025, m2026: m, avg2026: mean(m) };
  };

  const tabs = PAYROLL_TABS.map((t): PayrollTab => {
    if (!val.has(`${t.key}|total||${periods[0]}`)) return t;        // 이 탭은 DB 미적재 → 정적 값 유지
    const keyOf = (label: string) => (t.key === 'company' ? COMPANY_ROW_KEY[label] ?? label : sectionKey(label));
    const known = new Set(t.rows.map(r => keyOf(r.label)));
    const rowsOut = t.rows.map(r => ({ ...series(t.key, 'hc', keyOf(r.label), r as PayrollSeries), label: r.label }));
    // 정적 메타에 없는 신규 Section(조직개편 등)은 원본 명칭 그대로 뒤에 붙인다.
    const extra = new Set<string>();
    for (const r of rows) if (r.tab_key === t.key && r.item === 'hc' && !known.has(r.row_key)) extra.add(r.row_key);
    for (const k of [...extra].sort()) {
      rowsOut.push({ ...series(t.key, 'hc', k, { avg2025: 0, m2026: [], avg2026: 0 }), label: k });
    }
    const addon = (item: 'kompensasi' | 'thr' | 'insentif') =>
      series<PayrollAddon>(t.key, item, '', t[item] ?? { avg2025: null, m2026: [], avg2026: 0 });
    return {
      ...t,
      rows: rowsOut,
      total: series(t.key, 'total', '', t.total),
      salary: series(t.key, 'salary', '', t.salary),
      avgcost: series(t.key, 'avgcost', '', t.avgcost),
      kompensasi: addon('kompensasi'),
      thr: addon('thr'),
      insentif: addon('insentif'),
    };
  });
  return { tabs, months: periods.map(p => `${Number(p.slice(5))}월`), updated: periods[periods.length - 1] };
}
