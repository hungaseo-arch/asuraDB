// src/data/payrollMonthly.ts
// 인건비(월별) 집계 데이터 — 경영·성과 › 인건비 탭 SSOT(정적).
// 출처: Rekap Gaji Ascendo Internasional 월별 파일(2025-01~2026-07, Google Drive).
// 인건비 = TOTAL GAJI GROSS(기본급+수당+회사부담 BPJS, 세전). 단위: 인원=명, 인건비=백만 IDR(Juta).
// 구분(rows.label) = 원본 월시트 Section(Divisi) 그대로. 평균인건비 = 인건비 ÷ 인원(천 단위).
// ⚠ 갱신: 신규 월마감 시 각 tab의 m2026 배열 다음 값 추가 + avg2026 재계산(또는 뷰에서 자동 평균).
//   중기적으로는 Supabase payroll_monthly 테이블 + importer로 승격 권장(작업지시서 §8 참고).

export interface PayrollSeries { avg2025: number; m2026: number[]; avg2026: number }
export interface PayrollRow extends PayrollSeries { label: string }
export interface PayrollTab {
  key: string;
  name: string;
  rows: PayrollRow[];      // 지점 탭=Section별, 전사 탭=지점별 (인원)
  total: PayrollSeries;    // 인원 합계(명)
  salary: PayrollSeries;   // 인건비 Gross(백만 IDR)
  avgcost: PayrollSeries;  // 평균 인건비(백만 IDR/인)
}

export const PAYROLL_MONTHS_2026 = ['1월', '2월', '3월', '4월', '5월', '6월', '7월'];

export const PAYROLL_UPDATED = '2026-07';   // 최신 반영월

export const PAYROLL_TABS: PayrollTab[] = [
  {
    key: 'company',
    name: '전사 (Company)',
    rows: [
      { label: 'HQ 자카르타 (본사)', avg2025: 37.3, m2026: [34, 36, 37, 37, 35, 34, 36], avg2026: 35.6 },
      { label: '찌카랑·까라왕 창고',  avg2025: 19.0, m2026: [21, 16, 16, 16, 16, 15, 15], avg2026: 16.4 },
      { label: '수라바야',           avg2025: 6.9,  m2026: [8, 9, 8, 8, 9, 8, 8],         avg2026: 8.3 },
      { label: '스마랑',             avg2025: 0.9,  m2026: [5, 6, 6, 6, 4, 5, 5],         avg2026: 5.3 },
    ],
    total:   { avg2025: 64.2,  m2026: [68, 67, 67, 67, 64, 62, 64],                              avg2026: 65.6 },
    salary:  { avg2025: 476.2, m2026: [494.5, 488.4, 522.1, 518.6, 479.6, 475.7, 491.9],         avg2026: 495.8 },
    avgcost: { avg2025: 7.4,   m2026: [7.3, 7.3, 7.8, 7.7, 7.5, 7.7, 7.7],                        avg2026: 7.6 },
  },
  {
    key: 'HQ Jakarta',
    name: 'HQ 자카르타 (본사)',
    rows: [
      { label: 'SALES&MARKETING (영업·마케팅)',      avg2025: 13.2, m2026: [13, 14, 14, 14, 13, 13, 13], avg2026: 13.4 },
      { label: 'SALES ADMIN (영업관리)',             avg2025: 9.3,  m2026: [1, 1, 1, 1, 1, 1, 1],         avg2026: 1.0 },
      { label: 'SALES FINANCE&ADMIN (영업재무·관리)', avg2025: 5.2,  m2026: [7, 7, 7, 7, 7, 7, 7],         avg2026: 7.0 },
      { label: 'GA (총무)',                          avg2025: 3.5,  m2026: [4, 4, 5, 5, 5, 4, 4],         avg2026: 4.4 },
      { label: 'ACCOUNTING (회계)',                  avg2025: 3.0,  m2026: [3, 3, 3, 3, 3, 3, 4],         avg2026: 3.1 },
      { label: 'PURCHASING (구매)',                  avg2025: 1.0,  m2026: [6, 6, 6, 6, 5, 5, 6],         avg2026: 5.7 },
      { label: 'ADMIN EXIM (수출입관리)',            avg2025: 0.8,  m2026: [0, 0, 0, 0, 0, 0, 0],         avg2026: 0.0 },
      { label: 'EXIM SALES&ADMIN (수출입영업·관리)', avg2025: 0.7,  m2026: [0, 0, 0, 0, 0, 0, 0],         avg2026: 0.0 },
      { label: 'IT (전산)',                          avg2025: 0.0,  m2026: [0, 1, 1, 1, 1, 1, 1],         avg2026: 0.9 },
      { label: 'LOCAL SALES (국내영업)',             avg2025: 0.5,  m2026: [0, 0, 0, 0, 0, 0, 0],         avg2026: 0.0 },
    ],
    total:   { avg2025: 37.3,  m2026: [34, 36, 37, 37, 35, 34, 36],                        avg2026: 35.6 },
    salary:  { avg2025: 355.8, m2026: [320.6, 329.1, 355.9, 354.5, 337.3, 331.2, 338.2],   avg2026: 338.1 },
    avgcost: { avg2025: 9.5,   m2026: [9.4, 9.1, 9.6, 9.6, 9.6, 9.7, 9.4],                  avg2026: 9.5 },
  },
  {
    key: 'Cikarang/Karawang WH',
    name: '찌카랑·까라왕 창고',
    rows: [
      { label: 'DAILY WORKER (일용직)', avg2025: 15.0, m2026: [15, 10, 10, 10, 10, 10, 8], avg2026: 10.4 },
      { label: 'WAREHOUSE (창고)',      avg2025: 4.0,  m2026: [6, 6, 6, 6, 6, 5, 7],        avg2026: 6.0 },
    ],
    total:   { avg2025: 19.0, m2026: [21, 16, 16, 16, 16, 15, 15],                    avg2026: 16.4 },
    salary:  { avg2025: 80.4, m2026: [108.6, 91.8, 93.3, 92.6, 80.4, 76.3, 84.7],     avg2026: 89.7 },
    avgcost: { avg2025: 4.2,  m2026: [5.2, 5.7, 5.8, 5.8, 5.0, 5.1, 5.6],             avg2026: 5.5 },
  },
  {
    key: 'Surabaya',
    name: '수라바야',
    rows: [
      { label: 'SALES (영업)',        avg2025: 2.9, m2026: [3, 4, 3, 3, 4, 3, 3], avg2026: 3.3 },
      { label: 'WAREHOUSE (창고)',    avg2025: 1.2, m2026: [2, 3, 3, 3, 3, 3, 3], avg2026: 2.9 },
      { label: 'ADMIN (관리)',        avg2025: 1.3, m2026: [1, 1, 1, 1, 1, 1, 1], avg2026: 1.0 },
      { label: 'BRANCH HEAD (지점장)', avg2025: 1.0, m2026: [1, 1, 1, 1, 1, 1, 1], avg2026: 1.0 },
      { label: 'DAILY WORKER (일용직)', avg2025: 0.4, m2026: [1, 0, 0, 0, 0, 0, 0], avg2026: 0.1 },
    ],
    total:   { avg2025: 6.9,  m2026: [8, 9, 8, 8, 9, 8, 8],                      avg2026: 8.3 },
    salary:  { avg2025: 37.6, m2026: [44.9, 46.3, 48.9, 48.9, 47.2, 48.9, 48.7], avg2026: 47.7 },
    avgcost: { avg2025: 5.5,  m2026: [5.6, 5.1, 6.1, 6.1, 5.2, 6.1, 6.1],        avg2026: 5.8 },
  },
  {
    key: 'Semarang',
    name: '스마랑',
    rows: [
      { label: 'SALES (영업)',        avg2025: 1.7, m2026: [3, 4, 4, 4, 2, 3, 3], avg2026: 3.3 },
      { label: 'BRANCH HEAD (지점장)', avg2025: 1.0, m2026: [1, 1, 1, 1, 1, 1, 1], avg2026: 1.0 },
      { label: 'ADMIN (관리)',        avg2025: 1.0, m2026: [1, 1, 1, 1, 1, 1, 1], avg2026: 1.0 },
    ],
    total:   { avg2025: 3.7, m2026: [5, 6, 6, 6, 4, 5, 5],                      avg2026: 5.3 },
    salary:  { avg2025: 9.5, m2026: [20.4, 21.2, 24.1, 22.6, 14.7, 19.3, 20.2], avg2026: 20.4 },
    avgcost: { avg2025: 2.5, m2026: [4.1, 3.5, 4.0, 3.8, 3.7, 3.9, 4.0],        avg2026: 3.9 },
  },
];
