<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { Download, Upload, Loader2, Pencil, MoreHorizontal } from 'lucide-vue-next';
import PageHeader from '@/components/PageHeader.vue';
import BranchOpsModal from '@/components/BranchOpsModal.vue';
import { exportCsv } from '@/lib/csv';
import { sbGetAll, sbPost, sbDelete } from '@/lib/supabase';

// 인원·인건비·Petty 입력창 (branch_ops_monthly)
const opsOpen = ref(false);

// ⋯ 액션 메뉴 (엑셀·업로드·데이터입력) — 바깥 클릭으로 닫힘
const actMenu = ref(false);
function onDocClick(e: MouseEvent) {
  if (!(e.target as HTMLElement | null)?.closest?.('[data-actmenu]')) actMenu.value = false;
}
onMounted(() => window.addEventListener('click', onDocClick));
onUnmounted(() => window.removeEventListener('click', onDocClick));

// ── 데이터 ───────────────────────────────────────────────────────────────────
// 수치는 DB(branch_sales_monthly 뷰)에서 집계해 만든다. 아래 LEGACY_DATA 는
//  ① 원시 거래행이 없는 기간(수라바야 2025) ② 거래 CSV 에서 도출 불가한 항목(sectionIV 인원·Petty)
//  ③ 지점명·제외 거래처 라벨 의 폴백으로만 쓴다. DB 에 해당 연도 행이 있으면 DB 가 이긴다.
// (SalesDashboard.jsx 이식본 — 수라바야 2025 원시 CSV 입수 시 제거 가능)
type Agg = { v25: (number | null)[]; a25: number | null; v26: (number | null)[]; a26: number | null };
interface MetricRow extends Agg { name: string }
interface Branch {
  name: string;
  m25: string[];
  m26: string[];
  sectionI:   { rows: MetricRow[];   grandTotal: Agg; amount: Agg };
  sectionII:  { rows: MetricRow[];   grandTotal: Agg; amount: Agg };
  sectionIII: { people: MetricRow[]; grandTotal: Agg; amount: Agg };
  sectionIV:  Record<string, Agg>;
  excluded: string[];
}

const LEGACY_DATA: Record<string, Branch> = {"surabaya": {"name": "Surabaya", "m25": ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nop", "Des"], "m26": ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun"], "sectionI": {"rows": [{"name": "RADIAL", "v25": [45, 34, 75, 42, 24, 191, 484, 617, 484, 514, 1109, 121], "a25": 312, "v26": [455, 139, 148, 324, 50, 696], "a26": 302}, {"name": "AGR", "v25": [null, null, null, null, null, null, null, null, null, null, null, null], "a25": null, "v26": [null, 3, 2, 4, 5, 52], "a26": 11}, {"name": "OTR", "v25": [null, null, null, 2, null, null, null, null, null, 25, 8, 1], "a25": 3, "v26": [12, 4, 5, 17, 3, 21], "a26": 10}, {"name": "BIAS", "v25": [398, 224, 224, 269, 311, 217, 343, 303, 382, 349, 312, 254], "a25": 299, "v26": [383, 170, 115, 217, 79, 106], "a26": 178}, {"name": "SOLID", "v25": [null, 2, null, null, 6, null, 14, 28, 50, 23, 48, 64], "a25": 20, "v26": [2, 42, 16, 18, 8, 10], "a26": 16}, {"name": "PNEUMATIC", "v25": [null, null, null, null, null, null, null, null, null, null, null, null], "a25": null, "v26": [10, 4, 2, null, null, null], "a26": 3}, {"name": "TUBE", "v25": [135, 115, 252, 175, 269, 678, 1279, 1795, 1072, 1054, 1793, 1028], "a25": 804, "v26": [1363, 2592, 481, 1195, 285, 1509], "a26": 1238}, {"name": "FLAP", "v25": [127, 495, 188, 168, 230, 416, 697, 848, 843, 987, 1422, 353], "a25": 565, "v26": [1183, 500, 277, 680, 198, 850], "a26": 615}, {"name": "VULKANISIRJADI", "v25": [null, 22, 20, 10, 20, 4, 12, null, 4, null, null, null], "a25": 8, "v26": [null, null, null, null, null, null], "a26": null}], "grandTotal": {"v25": [705, 892, 759, 666, 860, 1506, 2829, 3591, 2835, 2952, 4692, 1821], "a25": 2009, "v26": [3408, 3454, 1046, 2455, 628, 3244], "a26": 2370}, "amount": {"v25": [905, 671, 721, 706, 761, 1023, 2077, 3043, 2440, 2635, 5411, 1138], "a25": 1794, "v26": [2059, 1233, 695, 1413, 371, 2945], "a26": 1453}}, "sectionII": {"rows": [{"name": "RADIAL", "v25": [45, 34, 75, 42, 24, 191, 362, 191, 143, 247, 385, 97], "a25": 153, "v26": [256, 139, 148, 324, 50, 154], "a26": 179}, {"name": "AGR", "v25": [null, null, null, null, null, null, null, null, null, null, null, null], "a25": null, "v26": [null, 3, 2, 4, 5, 32], "a26": 8}, {"name": "OTR", "v25": [null, null, null, 2, null, null, null, null, null, 5, 8, 1], "a25": 1, "v26": [12, 4, 5, 17, 3, 21], "a26": 10}, {"name": "BIAS", "v25": [398, 224, 224, 269, 311, 217, 343, 303, 382, 349, 312, 254], "a25": 299, "v26": [373, 170, 115, 217, 79, 106], "a26": 177}, {"name": "SOLID", "v25": [null, 2, null, null, 6, null, 14, 28, 50, 8, 48, 64], "a25": 18, "v26": [2, 42, 16, 18, 8, 10], "a26": 16}, {"name": "PNEUMATIC", "v25": [null, null, null, null, null, null, null, null, null, null, null, null], "a25": null, "v26": [10, 4, 2, null, null, null], "a26": 3}, {"name": "TUBE", "v25": [135, 115, 252, 175, 269, 382, 961, 743, 531, 647, 698, 658], "a25": 464, "v26": [1154, 2132, 441, 1065, 271, 687], "a26": 958}, {"name": "FLAP", "v25": [127, 495, 188, 148, 230, 416, 605, 360, 484, 585, 728, 353], "a25": 393, "v26": [974, 350, 217, 680, 198, 266], "a26": 448}, {"name": "VULKANISIRJADI", "v25": [null, 22, 20, 10, 20, 4, 12, null, 4, null, null, null], "a25": 8, "v26": [null, null, null, null, null, null], "a26": null}], "grandTotal": {"v25": [705, 892, 759, 646, 860, 1210, 2297, 1625, 1594, 1841, 2179, 1427], "a25": 1336, "v26": [2781, 2844, 946, 2325, 614, 1276], "a26": 1798}, "amount": {"v25": [905, 671, 721, 705, 761, 911, 1679, 1129, 1166, 1156, 2217, 889], "a25": 1076, "v26": [1444, 1046, 674, 1362, 368, 805], "a26": 950}}, "sectionIII": {"people": [{"name": "Arif", "v25": [null, null, 60, null, 39, null, 10, null, null, null, 20, null], "a25": 11, "v26": [208, 6, null, null, null, null], "a26": 36}, {"name": "Farhan", "v25": [null, null, null, null, null, 22, 284, 137, 60, 9, 172, 374], "a25": 88, "v26": [null, null, null, null, null, null], "a26": null}, {"name": "Fiki", "v25": [null, null, null, 4, 1, null, null, null, null, null, null, null], "a25": 0, "v26": [null, null, null, null, null, null], "a26": null}, {"name": "Hanif", "v25": [null, null, 34, null, 20, 112, null, 80, null, 60, 50, null], "a25": 30, "v26": [0, 88, null, null, null, 25], "a26": 19}, {"name": "Hari", "v25": [76, 86, 254, 203, 204, 131, 387, 486, 521, 535, 434, 356], "a25": 306, "v26": [325, 437, 230, 431, 82, 93], "a26": 266}, {"name": "Heris", "v25": [null, null, null, null, null, 17, 116, 5, null, null, null, null], "a25": 12, "v26": [null, null, null, null, null, null], "a26": null}, {"name": "Julmi", "v25": [null, null, null, null, null, null, null, null, null, null, 60, null], "a25": 5, "v26": [null, null, null, null, null, null], "a26": null}, {"name": "Lubis", "v25": [null, null, null, null, null, null, null, null, null, null, 510, null], "a25": 43, "v26": [null, null, 13, null, null, null], "a26": 2}, {"name": "Rendi", "v25": [null, null, null, null, null, null, null, null, null, null, null, null], "a25": null, "v26": [null, null, 40, 49, null, null], "a26": 15}, {"name": "Rio", "v25": [null, null, null, null, null, null, 250, null, null, 126, 129, null], "a25": 42, "v26": [null, null, null, null, null, null], "a26": null}, {"name": "Rizki", "v25": [24, 24, 14, 18, 32, 303, 17, 48, 20, null, 2, 3], "a25": 42, "v26": [260, 154, 104, 117, 7, 71], "a26": 119}, {"name": "Tri", "v25": [null, null, null, null, null, null, null, null, 57, 38, 17, 46], "a25": 13, "v26": [22, 8, null, null, null, null], "a26": 5}, {"name": "Wisnu", "v25": [null, 2, null, 2, null, null, null, 26, 36, null, null, 6], "a25": 6, "v26": [null, null, null, null, null, null], "a26": null}, {"name": "Yono", "v25": [605, 380, 397, 419, 564, 625, 1233, 820, 836, 1045, 764, 642], "a25": 694, "v26": [628, 353, 287, 765, 279, 616], "a26": 488}, {"name": "Yudha", "v25": [null, null, null, null, null, null, null, 23, null, null, 21, null], "a25": 4, "v26": [null, null, null, null, null, null], "a26": null}, {"name": "Yusuf", "v25": [null, 400, null, null, null, null, null, null, 64, 28, null, null], "a25": 41, "v26": [null, null, null, null, null, null], "a26": null}], "grandTotal": {"v25": [705, 892, 759, 646, 860, 1210, 2297, 1625, 1594, 1841, 2179, 1427], "a25": 1336, "v26": [2781, 2844, 946, 2325, 614, 1276], "a26": 1798}, "amount": {"v25": [905, 671, 721, 705, 761, 911, 1679, 1129, 1166, 1156, 2217, 889], "a25": 1076, "v26": [1444, 1046, 674, 1362, 368, 805], "a26": 950}}, "sectionIV": {"Sales": {"v25": [2, 2, 3, 3, 3, 3, 3, 2, 3, 3, 3, 3], "a25": 3, "v26": [3, 4, 3, 3, 2, 2], "a26": 3}, "Admin": {"v25": [2, 2, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2], "a25": 2, "v26": [2, 2, 2, 2, 2, 2], "a26": 2}, "Delivery": {"v25": [1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2], "a25": 1, "v26": [2, 3, 3, 3, 4, 4], "a26": 3}, "Sub. Total": {"v25": [5, 5, 7, 7, 7, 7, 6, 5, 6, 7, 7, 7], "a25": 6, "v26": [7, 9, 8, 8, 8, 8], "a26": 8}, "Petty": {"v25": [10, 11, 11, 10, 14, 11, 14, 16, 18, 15, 19, 13], "a25": 13, "v26": [15, 9, 15, 11, 8, 6], "a26": 11}}, "excluded": ["CV. Arena Ban Indonesia", "CV. Sumber Sakti", "PT. Grand Prix Indoagung", "PT. Jangkar Emas Teguh", "PT. Sumber Sakti Prima Mandiri", "Aneka Roda Kencana"]}, "semarang": {"name": "Semarang", "m25": ["Okt", "Nop", "Des"], "m26": ["Jan", "Feb", "Mar", "Apr", "Mei"], "sectionI": {"rows": [{"name": "RADIAL", "v25": [null, 36, 81], "a25": 39, "v26": [111, 74, 31, 115, 127], "a26": 91.6}, {"name": "BIAS", "v25": [null, null, null], "a25": null, "v26": [null, null, null, 20, null], "a26": 4}, {"name": "SOLID", "v25": [16, 19, 14], "a25": 16, "v26": [22, 42, 14, 81, 7], "a26": 33.2}, {"name": "TUBE", "v25": [null, 41, 111], "a25": 51, "v26": [261, 305, 236, 794, 1039], "a26": 527}, {"name": "FLAP", "v25": [null, 92, 91], "a25": 61, "v26": [191, 120, 111, 389, 437], "a26": 249.6}, {"name": "VULKANISIR JADI", "v25": [null, null, null], "a25": null, "v26": [null, null, null, 5, null], "a26": 1}], "grandTotal": {"v25": [16, 188, 297], "a25": 167, "v26": [585, 541, 392, 1404, 1610], "a26": 906.4}, "amount": {"v25": [25, 109, 145], "a25": 93, "v26": [267, 260, 164, 599, 448], "a26": 347.6}}, "sectionII": {"rows": [{"name": "RADIAL", "v25": [null, 36, 81], "a25": 59, "v26": [111, 74, 31, 115, 127], "a26": 91.6}, {"name": "BIAS", "v25": [null, null, null], "a25": null, "v26": [null, null, null, 20, null], "a26": 4}, {"name": "SOLID", "v25": [null, 2, 2], "a25": 2, "v26": [null, null, 6, 18, 7], "a26": 6.2}, {"name": "TUBE", "v25": [null, 41, 111], "a25": 76, "v26": [261, 305, 236, 790, 1039], "a26": 526.2}, {"name": "FLAP", "v25": [null, 32, 91], "a25": 62, "v26": [171, 120, 111, 355, 437], "a26": 238.8}, {"name": "VULKANISIRJADI", "v25": [null, null, null], "a25": null, "v26": [null, null, null, null, null], "a26": null}], "grandTotal": {"v25": [null, 111, 285], "a25": 198, "v26": [543, 499, 384, 1298, 1610], "a26": 866.8}, "amount": {"v25": [null, 75, 129], "a25": 102, "v26": [232, 201, 148, 485, 448], "a26": 302.8}}, "sectionIII": {"people": [{"name": "Firman", "v25": [null, 90, null], "a25": 45, "v26": [145, 238, 210, 774, 475], "a26": 368.4}, {"name": "Joko", "v25": [null, 21, 283], "a25": 152, "v26": [298, 198, 117, 523, 1133], "a26": 453.8}, {"name": "Putra", "v25": [null, null, null], "a25": null, "v26": [null, null, null, null, 2], "a26": 0.4}, {"name": "Rozzaq", "v25": [null, null, null], "a25": null, "v26": [null, null, null, 1, null], "a26": 0.2}, {"name": "Sam an", "v25": [null, null, 2], "a25": 1, "v26": [null, null, null, null, null], "a26": null}, {"name": "Ugi", "v25": [null, null, null], "a25": null, "v26": [100, 63, 57, null, null], "a26": 44}], "grandTotal": {"v25": [null, 111, 285], "a25": 198, "v26": [543, 499, 384, 1298, 1610], "a26": 866.8}, "amount": {"v25": [null, 75, 129], "a25": 102, "v26": [232, 201, 148, 485, 448], "a26": 302.8}}, "sectionIV": {"Sales": {"v25": [2, 2, 1], "a25": 2, "v26": [3, 4, 4, 3, 3], "a26": 3.4}, "Admin": {"v25": [1, 1, 1], "a25": 1, "v26": [1, 1, 1, 1, 1], "a26": 1}, "Delivery": {"v25": [null, null, null], "a25": null, "v26": [null, null, null, null, null], "a26": null}, "Total (Person)": {"v25": [3, 3, 2], "a25": 3, "v26": [4, 5, 5, 4, 4], "a26": 4.4}, "Petty": {"v25": [0.3, 1, 2.2], "a25": 1.2, "v26": [8.9, 7.5, 5.2, 10.7, 5.4], "a26": 7.5}}, "excluded": ["CV. NASAMED INTI SUKSES", "CV. MAJESTI MITRA SEJATI", "CV. KARYA MAJU BAN", "CV. MASA SEMPURNA", "PT. DIAMOND FAJAR JAYA", "PT. DOA KELUARGA TIGASATUTIGA"]}};

// ── 운영 손익(P&L) 데이터 (250808 수라바야 지점운영 보고 PDF 이식) ──────────────
// 금액 단위: 백만 루피아(M.IDR). 비율(%)·BEP는 PDF 값 그대로. FY24=7~12월, FY25=1~7월.
type PV = { a24: number | null; v25: (number | null)[]; a25: number | null; v26: (number | null)[]; a26: number | null };
type PnlFmt = 'amt' | 'qty' | 'pct' | 'ea';
type PnlKind = 'head' | 'sub' | 'qty' | 'pct' | 'cost' | 'profit' | 'bep';

// 운영 손익 표는 상단 '연도' 드롭다운(2025/2026)을 공유한다.
//  - 선택 연도의 1~12월 + 'Avg', 좌측에 전년 평균 컬럼을 함께 표시('25년 평균 → 26년 월' 순).
//  - 2024년 자료는 월별 상세 없이 '전년 평균'(a24)으로만 반영. 2026년은 입력 대기(–).
const PNL_MONTHS_12 = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nop', 'Des'];
const NULL12 = (): (number | null)[] => Array(12).fill(null);
const pad12 = (a: (number | null)[]): (number | null)[] => [...a, ...Array(Math.max(0, 12 - a.length)).fill(null)];

const PNL_ROWS_META: { key: string; label: string; sub: string; kind: PnlKind; fmt: PnlFmt; indent: number }[] = [
  { key: 'sales',      label: '매출액',        sub: 'Penjualan',     kind: 'head',   fmt: 'amt', indent: 0 },
  { key: 'tireQty',    label: '타이어 수량',   sub: 'Tire Qty',      kind: 'qty',    fmt: 'qty', indent: 1 },
  { key: 'radial',     label: 'TBR',           sub: 'Radial',        kind: 'sub',    fmt: 'qty', indent: 2 },
  { key: 'bias',       label: 'TBB',           sub: 'Bias',          kind: 'sub',    fmt: 'qty', indent: 2 },
  { key: 'etc',        label: 'ETC',           sub: '기타',          kind: 'sub',    fmt: 'qty', indent: 2 },
  { key: 'tube',       label: 'Tube',          sub: '튜브',          kind: 'qty',    fmt: 'qty', indent: 1 },
  { key: 'flap',       label: 'Flap',          sub: '플랩',          kind: 'qty',    fmt: 'qty', indent: 1 },
  { key: 'stock',      label: '기말 재고',     sub: 'Tire Stock',    kind: 'qty',    fmt: 'qty', indent: 1 },
  { key: 'purs',       label: '매출원가',      sub: 'COGS',          kind: 'head',   fmt: 'amt', indent: 0 },
  { key: 'pursPct',    label: '원가율',        sub: '% Sales',       kind: 'pct',    fmt: 'pct', indent: 1 },
  { key: 'margin',     label: '매출총이익',    sub: 'Gross Profit',  kind: 'head',   fmt: 'amt', indent: 0 },
  { key: 'marginPct',  label: '마진율',        sub: '% Sales',       kind: 'pct',    fmt: 'pct', indent: 1 },
  { key: 'opcost',     label: '운영비',        sub: 'Biaya Operasi', kind: 'head',   fmt: 'amt', indent: 0 },
  { key: 'opcostPct',  label: '운영비율',      sub: '% Sales',       kind: 'pct',    fmt: 'pct', indent: 1 },
  { key: 'labor',      label: '인건비',        sub: 'Labor',         kind: 'cost',   fmt: 'amt', indent: 1 },
  { key: 'rent',       label: '임대·공과',     sub: 'Rent & Util.',  kind: 'cost',   fmt: 'amt', indent: 1 },
  { key: 'depr',       label: '감가상각',      sub: 'Depreciation',  kind: 'cost',   fmt: 'amt', indent: 1 },
  { key: 'trans',      label: '운송비',        sub: 'Transport',     kind: 'cost',   fmt: 'amt', indent: 1 },
  { key: 'admin',      label: '기타관리비',    sub: 'Other Admin',   kind: 'cost',   fmt: 'amt', indent: 1 },
  { key: 'opprofit',   label: '영업이익',      sub: 'Laba Operasi',  kind: 'profit', fmt: 'amt', indent: 0 },
  { key: 'opprofitPct',label: '영업이익률',    sub: '% Sales',       kind: 'pct',    fmt: 'pct', indent: 1 },
  // '인원'(emp) 행 삭제 — '인원 및 비용' 탭(섹션 Ⅳ)과 중복이라 그쪽을 단일 출처로 둔다.
  { key: 'bepQty',     label: '손익분기 수량', sub: 'BEP Qty',       kind: 'bep',    fmt: 'qty', indent: 0 },
  { key: 'bepAmt',     label: '손익분기 매출', sub: 'BEP Amt',       kind: 'bep',    fmt: 'amt', indent: 0 },
];

// 값은 branch별 key→PV. 미보유 지점/항목은 빌더가 null로 채움(스캐폴드).
const PNL_VALUES: Record<string, Record<string, PV>> = {
  // v25 = 2025년 1~12월(요약 2025 확정본), v26 = 2026년 1~5월(이후 입력 대기). a24 = 2024년 평균(전년 평균).
  // a26 = null → pnlAvgOf가 입력된 월의 단순평균을 자동 계산(부분연도). 2025는 TBB+ETC 통합치(etc=–).
  surabaya: {
    sales:      { a24: 845,  v25: [905, 671, 721, 706, 761, 1023, 1625, 1078, 1166, 1156, 1253, 889], a25: 996,  v26: pad12([1398, 1046, 674, 1362, 368]), a26: null },
    tireQty:    { a24: 402,  v25: [443, 282, 320, 323, 363, 412, 731, 499, 579, 609, 583, 416],       a25: 463,  v26: pad12([638, 362, 288, 580, 145]), a26: null },
    radial:     { a24: 32,   v25: [45, 34, 75, 42, 24, 191, 362, 168, 143, 249, 215, 97],             a25: 137,  v26: pad12([25, 41, 40, 33, 2]), a26: null },
    bias:       { a24: 370,  v25: [398, 248, 245, 281, 339, 221, 369, 331, 436, 360, 368, 319],       a25: 326,  v26: pad12([75, 63, 25, 68, 32]), a26: null },
    etc:        { a24: null, v25: NULL12(),                                                           a25: null, v26: pad12([538, 258, 223, 479, 111]), a26: null },
    tube:       { a24: 212,  v25: [135, 115, 252, 175, 269, 678, 961, 743, 531, 647, 528, 658],       a25: 474,  v26: pad12([1154, 2132, 441, 1065, 271]), a26: null },
    flap:       { a24: 159,  v25: [127, 495, 188, 168, 230, 416, 605, 360, 484, 585, 558, 353],       a25: 381,  v26: pad12([974, 350, 217, 680, 198]), a26: null },
    stock:      { a24: null, v25: [null, null, null, null, null, null, null, 1201, 1075, 944, 943, null], a25: 1041, v26: NULL12(), a26: null },
    purs:       { a24: 757,  v25: [816, 594, 620, 623, 692, 905, 1418, 909, 1019, 991, 1079, 771],    a25: 870,  v26: pad12([1146, 891, 579, 1143, 296]), a26: null },
    pursPct:    { a24: 89.6, v25: [90.2, 88.5, 86.0, 88.3, 91.0, 88.5, 87.2, 84.3, 87.4, 85.7, 86.2, 86.7], a25: 87.3, v26: pad12([82.0, 85.1, 85.9, 83.9, 80.4]), a26: null },
    margin:     { a24: 88,   v25: [89, 77, 101, 83, 69, 118, 208, 169, 147, 165, 173, 118],           a25: 126,  v26: pad12([252, 155, 95, 219, 72]), a26: null },
    marginPct:  { a24: 10.4, v25: [9.8, 11.5, 14.0, 11.7, 9.0, 11.5, 12.8, 15.7, 12.6, 14.3, 13.8, 13.3], a25: 12.7, v26: pad12([18.0, 14.9, 14.1, 16.1, 19.6]), a26: null },
    opcost:     { a24: 33,   v25: [43, 43, 48, 64, 67, 84, 70, 66, 68, 67, 78, 76],                   a25: 64,   v26: pad12([79, 70, 79, 75, 70]), a26: null },
    opcostPct:  { a24: 4.0,  v25: [4.7, 6.5, 6.7, 9.0, 8.8, 8.2, 4.3, 6.1, 5.9, 5.8, 6.2, 8.6],       a25: 6.5,  v26: pad12([5.6, 6.7, 11.7, 5.5, 18.9]), a26: null },
    labor:      { a24: 23,   v25: [29, 29, 34, 39, 39, 39, 38, 38, 35, 41, 43, 47],                   a25: 38,   v26: pad12([49, 46, 49, 49, 47]), a26: null },
    rent:       { a24: null, v25: [0, 0, 0, 11, 11, 11, 11, 11, 11, 11, 11, 11],                      a25: 9,    v26: pad12([11, 11, 11, 11, 11]), a26: null },
    depr:       { a24: null, v25: [0, 0, 0, 0, 0, 20, 0, 0, 0, 0, 0, 0],                              a25: 2,    v26: pad12([0, 0, 0, 0, 0]), a26: null },
    trans:      { a24: 3,    v25: [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3],                               a25: 3,    v26: pad12([3, 3, 3, 3, 3]), a26: null },
    admin:      { a24: 7,    v25: [10, 11, 11, 10, 13, 10, 17, 13, 18, 12, 19, 14],                   a25: 13,   v26: pad12([15, 9, 15, 11, 8]), a26: null },
    opprofit:   { a24: 57,   v25: [46, 34, 52, 19, 1, 34, 138, 103, 79, 98, 96, 42],                  a25: 62,   v26: pad12([173, 85, 16, 144, 2]), a26: null },
    opprofitPct:{ a24: 6.5,  v25: [6.8, 4.7, 7.4, 2.7, 0.2, 3.4, 8.5, 9.5, 6.8, 8.5, 7.7, 4.7],       a25: 6.2,  v26: pad12([16.6, 12.6, 1.1, 10.6, 0.6]), a26: null },
    emp:        { a24: 4.3,  v25: [5, 5, 6, 7, 7, 7, 7, 7, 8, 8, 8, 8],                               a25: 6,    v26: pad12([7, 9, 8, 8, 8]), a26: null },
    bepQty:     { a24: 143,  v25: [214, 159, 154, 249, 356, 292, 245, 195, 269, 248, 261, 268],       a25: 238,  v26: pad12([200, 164, 241, 198, 140]), a26: null },
    bepAmt:     { a24: 298,  v25: [438, 378, 347, 543, 746, 725, 544, 421, 541, 470, 560, 572],       a25: 531,  v26: pad12([437, 474, 563, 466, 356]), a26: null },
  },
  semarang: {}, // 데이터 준비중 — 동일 양식 빈 표(–)로 표시
};

// ── 상태 ────────────────────────────────────────────────────────────────────
const branchKey = ref<'surabaya' | 'semarang'>('surabaya');
const YEARS = [2025, 2026] as const;
const year = ref<2025 | 2026>(2026); // 기간: 연도별 선택

// ── DB 로드 ──────────────────────────────────────────────────────────────────
// branch_sales_monthly 뷰 = 지점×연×월×카테고리×담당자×제외여부 별 qty/so_amt.
// 금액 기준은 so_amt(PPN 11% 제외분) — 기존 화면값과 대조 검증된 기준이다.
interface MonthlyRow {
  branch: string; year: number; month: number; category: string;
  pic: string; is_excluded: boolean; qty: number; so_amt: number;
}
// 인원·Petty·인건비 — 거래 CSV 에서 도출 불가한 값(branch_ops_monthly)
interface OpsRow {
  branch: string; year: number; month: number;
  sales_hc: number | null; admin_hc: number | null; deliv_hc: number | null;
  salary: number | null; petty: number | null;
}
const MON_ABBR = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nop', 'Des'];
// 표에 노출할 카테고리 순서 (그 외 값은 뒤에 등장순으로 붙음)
const CAT_ORDER = ['RADIAL', 'AGR', 'OTR', 'BIAS', 'SOLID', 'PNEUMATIC', 'TUBE', 'FLAP', 'VULKANISIRJADI'];

// 매출 표의 표시 지표 — 카테고리/담당자 행을 수량으로 볼지 금액(M.IDR)으로 볼지.
// DB 원시행에 so_amt 가 있어 두 벌을 모두 만들어 두고 토글로 바꾼다.
const METRICS = [{ k: 'qty', label: '수량' }, { k: 'amt', label: '금액' }] as const;
const metric = ref<'qty' | 'amt'>('qty');

const DATA = ref<Record<string, Branch>>(LEGACY_DATA);      // 수량 기준
const DATA_AMT = ref<Record<string, Branch> | null>(null);  // 금액 기준 (DB 있을 때만)
const loading = ref(false);
const loadError = ref('');

// 평균 = 입력된 월 합 ÷ 월 개수 (null 은 0 취급) — 기존 하드코딩 값의 산출 방식과 동일함을 확인
const avgOfArr = (a: (number | null)[]): number | null =>
  a.length ? Math.round((a.reduce((s: number, v) => s + (v ?? 0), 0) / a.length) * 10) / 10 : null;

/** 지점 1곳의 DB 행 → Branch 구조. 해당 연도 행이 없으면 legacy 값을 그대로 둔다. */
function buildBranch(rows: MonthlyRow[], legacy: Branch, ops: OpsRow[] = [], metric: 'qty' | 'amt' = 'qty'): Branch {
  const out: Branch = JSON.parse(JSON.stringify(legacy));

  for (const y of [2025, 2026] as const) {
    const yr = rows.filter(r => r.year === y);
    if (!yr.length) {
      // 원시행 없음(예: 수라바야 2025) → 수량은 legacy 유지.
      // 단 금액 모드에서는 legacy 의 '수량' 값이 금액인 척 표시되므로 반드시 비운다.
      if (metric === 'amt') {
        const vK = y === 2025 ? 'v25' : 'v26';
        const aK = y === 2025 ? 'a25' : 'a26';
        const blank = (o: Agg) => { (o as unknown as Record<string, unknown>)[vK] = []; (o as unknown as Record<string, unknown>)[aK] = null; };
        for (const s of [out.sectionI, out.sectionII] as const) { s.rows.forEach(blank); blank(s.grandTotal); blank(s.amount); }
        out.sectionIII.people.forEach(blank); blank(out.sectionIII.grandTotal); blank(out.sectionIII.amount);
      }
      continue;
    }

    const monthsN = [...new Set(yr.map(r => r.month))].sort((a, b) => a - b);
    const mKey = y === 2025 ? 'm25' : 'm26';
    const vKey = y === 2025 ? 'v25' : 'v26';
    const aKey = y === 2025 ? 'a25' : 'a26';
    (out as unknown as Record<string, string[]>)[mKey] = monthsN.map(m => MON_ABBR[m - 1]);

    // (필터 적용된 행) → { rows: MetricRow[], grandTotal, amount }
    // metric='qty' → 카테고리 행이 수량, 'amt' → 카테고리 행이 금액(M.IDR)
    const section = (src: MonthlyRow[], by: 'category' | 'pic', metric: 'qty' | 'amt' = 'qty') => {
      const names = [...new Set(src.map(r => r[by]))];
      names.sort((a, b) => {
        if (by === 'pic') return a.localeCompare(b, 'ko');
        const ia = CAT_ORDER.indexOf(a), ib = CAT_ORDER.indexOf(b);
        return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
      });
      const cell = (rs: MonthlyRow[]) => metric === 'qty'
        ? Math.round(rs.reduce((s, r) => s + Number(r.qty), 0))
        : Math.round(rs.reduce((s, r) => s + Number(r.so_amt), 0) / 1e5) / 10;
      const mk = (name: string): number[] =>
        monthsN.map(m => cell(src.filter(r => r[by] === name && r.month === m)));
      const list = names.map(name => {
        const v = mk(name).map(n => (n === 0 ? null : n));
        return { name, v25: [], a25: null, v26: [], a26: null, [vKey]: v, [aKey]: avgOfArr(v) } as unknown as MetricRow;
      });
      const gt = monthsN.map(m => {
        const n = cell(src.filter(r => r.month === m));
        return n === 0 ? null : n;
      });
      const am = monthsN.map(m => {
        const n = src.filter(r => r.month === m).reduce((s, r) => s + Number(r.so_amt), 0) / 1e6;
        return n === 0 ? null : Math.round(n * 10) / 10;
      });
      return {
        rows: list,
        grandTotal: { v25: [], a25: null, v26: [], a26: null, [vKey]: gt, [aKey]: avgOfArr(gt) } as unknown as Agg,
        amount:     { v25: [], a25: null, v26: [], a26: null, [vKey]: am, [aKey]: avgOfArr(am) } as unknown as Agg,
      };
    };

    const net = yr.filter(r => !r.is_excluded);
    const mx = metric;                     // 'qty' | 'amt' — 카테고리/담당자 행의 표시 지표
    const s1 = section(yr, 'category', mx);   // Section I  전체매출
    const s2 = section(net, 'category', mx);  // Section II 순매출 (제외 거래처 차감)
    const s3 = section(net, 'pic', mx);       // Section III 담당자별 (순매출 기준)

    // 다른 연도 값은 legacy/기존 빌드분을 보존하고 이번 연도 슬롯만 덮어쓴다
    const merge = (dst: MetricRow[] | undefined, src: MetricRow[]): MetricRow[] => {
      const byName = new Map((dst ?? []).map(r => [r.name, r]));
      const outRows: MetricRow[] = [];
      for (const r of src) {
        const prev = byName.get(r.name);
        outRows.push({ ...(prev ?? { name: r.name, v25: [], a25: null, v26: [], a26: null }),
                       [vKey]: (r as unknown as Record<string, unknown>)[vKey],
                       [aKey]: (r as unknown as Record<string, unknown>)[aKey] } as MetricRow);
        byName.delete(r.name);
      }
      for (const left of byName.values()) outRows.push({ ...left, [vKey]: [], [aKey]: null } as MetricRow);
      return outRows;
    };
    const mergeAgg = (dst: Agg, src: Agg): Agg =>
      ({ ...dst, [vKey]: (src as unknown as Record<string, unknown>)[vKey],
                 [aKey]: (src as unknown as Record<string, unknown>)[aKey] } as Agg);

    out.sectionI   = { rows: merge(out.sectionI.rows, s1.rows),     grandTotal: mergeAgg(out.sectionI.grandTotal, s1.grandTotal),     amount: mergeAgg(out.sectionI.amount, s1.amount) };
    out.sectionII  = { rows: merge(out.sectionII.rows, s2.rows),    grandTotal: mergeAgg(out.sectionII.grandTotal, s2.grandTotal),    amount: mergeAgg(out.sectionII.amount, s2.amount) };
    out.sectionIII = { people: merge(out.sectionIII.people, s3.rows), grandTotal: mergeAgg(out.sectionIII.grandTotal, s3.grandTotal), amount: mergeAgg(out.sectionIII.amount, s3.amount) };

    // 섹션 Ⅳ(인원·인건비·Petty) — branch_ops_monthly 기준. 해당 연도 ops 행이 없으면 legacy 유지.
    const opsY = ops.filter(o => o.year === y);
    if (opsY.length) {
      const pick = (f: (o: OpsRow) => number | null) =>
        monthsN.map(m => { const o = opsY.find(x => x.month === m); return o ? f(o) : null; });
      const agg = (v: (number | null)[]): Agg =>
        ({ v25: [], a25: null, v26: [], a26: null, [vKey]: v, [aKey]: avgOfArr(v) } as unknown as Agg);
      const hc = monthsN.map(m => {
        const o = opsY.find(x => x.month === m);
        if (!o) return null;
        const s = (o.sales_hc ?? 0) + (o.admin_hc ?? 0) + (o.deliv_hc ?? 0);
        return s || null;
      });
      const totalKey = out.sectionIV['Total (Person)'] ? 'Total (Person)' : 'Sub. Total';
      const s4next: Record<string, Agg> = {
        Sales:        agg(pick(o => o.sales_hc)),
        Admin:        agg(pick(o => o.admin_hc)),
        Delivery:     agg(pick(o => o.deliv_hc)),
        [totalKey]:   agg(hc),
        Salary:       agg(pick(o => o.salary)),   // 추후 입력 — 현재 전부 null → '–'
        Petty:        agg(pick(o => o.petty)),
      };
      for (const [k, v] of Object.entries(s4next)) {
        const prev = out.sectionIV[k];
        out.sectionIV[k] = prev
          ? ({ ...prev, [vKey]: (v as unknown as Record<string, unknown>)[vKey],
                        [aKey]: (v as unknown as Record<string, unknown>)[aKey] } as Agg)
          : v;
      }
    }
  }
  return out;
}

async function loadData() {
  loading.value = true; loadError.value = '';
  try {
    const [rows, excl, ops] = await Promise.all([
      sbGetAll<MonthlyRow>('branch_sales_monthly?select=*'),
      sbGetAll<{ branch: string; buyer: string }>('branch_excluded_buyers?select=*').catch(() => []),
      sbGetAll<OpsRow>('branch_ops_monthly?select=*').catch(() => [] as OpsRow[]),
    ]);
    if (!rows.length) { loadError.value = 'DB에 지점 판매 데이터가 없습니다 — 기존 값으로 표시합니다.'; return; }
    const next: Record<string, Branch> = {};
    const nextAmt: Record<string, Branch> = {};
    for (const key of Object.keys(LEGACY_DATA)) {
      const legacy = LEGACY_DATA[key];
      const mine = rows.filter(r => r.branch === key);
      const myOps = ops.filter(o => o.branch === key);
      const ex = excl.filter(e => e.branch === key).map(e => e.buyer);

      const b = buildBranch(mine, legacy, myOps, 'qty');
      if (ex.length) b.excluded = ex;
      next[key] = b;

      const bAmt = buildBranch(mine, legacy, myOps, 'amt');
      if (ex.length) bAmt.excluded = ex;
      nextAmt[key] = bAmt;
    }
    DATA.value = next;
    DATA_AMT.value = nextAmt;
  } catch (e) {
    loadError.value = `DB 조회 실패 — 기존 값으로 표시합니다. (${(e as Error).message})`;
  } finally {
    loading.value = false;
  }
}
onMounted(loadData);

const BRANCH_LABEL: Record<string, string> = { surabaya: 'Surabaya', semarang: 'Semarang' };
const branch = computed(() => DATA.value[branchKey.value]);
const bn = computed(() => BRANCH_LABEL[branchKey.value]);
// 제외 거래처 목록 2분할 기준
const exclHalf = computed(() => Math.ceil(branch.value.excluded.length / 2));

// 선택 연도 기준 접근자
const months = computed(() => (year.value === 2025 ? branch.value.m25 : branch.value.m26));
function valsOf(r: Agg): (number | null)[] { return year.value === 2025 ? r.v25 : r.v26; }
function avgOf(r: Agg): number | null { return year.value === 2025 ? r.a25 : r.a26; }
// 전년(Y-1) 월평균 — 데이터는 2025만 보유하므로 2026 선택 시에만 표시
const hasPrev = computed(() => year.value === 2026);
function prevAvgOf(r: Agg): number | null { return year.value === 2026 ? r.a25 : null; }

function fmt(n: number | null | undefined): string {
  return n === null || n === undefined ? '–' : Number(n).toLocaleString('en-US', { maximumFractionDigits: 1 });
}

// 월 라벨 → 한국어(1월~12월). 데이터의 월 약어(Jan·Mei·Agu·Okt·Nop·Des 등)를 변환.
const MONTH_KO: Record<string, string> = {
  Jan: '1월', Feb: '2월', Mar: '3월', Apr: '4월', Mei: '5월', Jun: '6월',
  Jul: '7월', Agu: '8월', Sep: '9월', Okt: '10월', Nop: '11월', Des: '12월',
};
function monthKo(m: string): string { return MONTH_KO[m] ?? m; }

// 타이어 카테고리만 (Tube · Flap · Vulkanisir 제외)
function isTire(name: string): boolean {
  const n = name.toUpperCase().replace(/\s+/g, '');
  return n !== 'TUBE' && n !== 'FLAP' && !n.startsWith('VULKANISIR');
}

// 행 집합의 월별 합 / 평균 합 (null=미입력은 0으로, 전부 null이면 null)
function colSum(rows: MetricRow[], get: (r: MetricRow) => (number | null)[], len: number): (number | null)[] {
  return Array.from({ length: len }, (_, i) => {
    let s = 0, any = false;
    for (const r of rows) { const v = get(r)[i]; if (v !== null && v !== undefined) { s += v; any = true; } }
    return any ? s : null;
  });
}
function avgSum(rows: MetricRow[], get: (r: MetricRow) => number | null): number | null {
  let s = 0, any = false;
  for (const r of rows) { const v = get(r); if (v !== null && v !== undefined) { s += v; any = true; } }
  return any ? s : null;
}

// ── KPI ──────────────────────────────────────────────────────────────────────
const kpi = computed(() => {
  const b = branch.value, y = year.value;
  const ms = y === 2025 ? b.m25 : b.m26;

  // 최근월 = grandTotal 기준 마지막 데이터 월
  const gArr = y === 2025 ? b.sectionI.grandTotal.v25 : b.sectionI.grandTotal.v26;
  const gIdx: number[] = [];
  gArr.forEach((v, i) => { if (v !== null && v !== undefined) gIdx.push(i); });
  const last = gIdx[gIdx.length - 1];
  const prev = gIdx[gIdx.length - 2];

  // 판매량(Qty): 타이어 한정 월별 합
  const tireRows = b.sectionI.rows.filter(r => isTire(r.name));
  const tireMonthly = ms.map((_, i) => {
    let sum = 0, any = false;
    for (const r of tireRows) {
      const v = (y === 2025 ? r.v25 : r.v26)[i];
      if (v !== null && v !== undefined) { sum += v; any = true; }
    }
    return any ? sum : null;
  });
  const present = tireMonthly.filter((v): v is number => v !== null);
  const qNow = last !== undefined ? tireMonthly[last] : null;
  const qPrev = prev !== undefined ? tireMonthly[prev] : null;
  const mom = qNow !== null && qPrev ? ((qNow - qPrev) / qPrev) * 100 : null;
  const qtyAvg = present.length ? Math.round(present.reduce((a, c) => a + c, 0) / present.length) : null;

  // 매출(M.IDR): 전체 기준 (sectionI.amount)
  const amtArr = y === 2025 ? b.sectionI.amount.v25 : b.sectionI.amount.v26;
  const amtAvg = y === 2025 ? b.sectionI.amount.a25 : b.sectionI.amount.a26;
  const amtNow = last !== undefined ? amtArr[last] : null;
  const amtPrev = prev !== undefined ? amtArr[prev] : null;
  const amtMom = amtNow !== null && amtNow !== undefined && amtPrev ? ((amtNow - amtPrev) / amtPrev) * 100 : null;

  // 전년 대비(YoY): 월평균 — 현재 연도 평균 vs 직전 연도(2025) 평균. (2025 선택 시 비교 연도 없음)
  const amtAvgPrev = y === 2026 ? b.sectionI.amount.a25 : null;
  const amtYoy = amtAvg && amtAvgPrev ? ((amtAvg - amtAvgPrev) / amtAvgPrev) * 100 : null;

  // 판매량 직전 연도(2025) 타이어 월평균 → 전년 대비
  let qtyAvgPrev: number | null = null;
  if (y === 2026) {
    const prevPresent: number[] = [];
    b.m25.forEach((_, i) => {
      let sum = 0, any = false;
      for (const r of tireRows) {
        const v = r.v25[i];
        if (v !== null && v !== undefined) { sum += v; any = true; }
      }
      if (any) prevPresent.push(sum);
    });
    qtyAvgPrev = prevPresent.length ? Math.round(prevPresent.reduce((a, c) => a + c, 0) / prevPresent.length) : null;
  }
  const qtyYoy = qtyAvg && qtyAvgPrev ? ((qtyAvg - qtyAvgPrev) / qtyAvgPrev) * 100 : null;

  return {
    monthLabel: last !== undefined ? `${y} ${monthKo(ms[last])}` : '-',
    qtyNow: qNow, qtyAvg, mom,
    amtNow, amtAvg, amtMom, amtYoy, qtyYoy,
  };
});

// 증감(델타) 표시 헬퍼 — 색상/화살표/텍스트 (null=데이터 없음)
function deltaClass(v: number | null | undefined): string {
  return v === null || v === undefined ? 'text-muted-foreground' : v >= 0 ? 'text-emerald-600 font-semibold' : 'text-red-600 font-semibold';
}
function deltaText(v: number | null | undefined): string {
  return v === null || v === undefined ? '–' : `${v >= 0 ? '▲' : '▼'} ${Math.abs(v).toFixed(1)}%`;
}

// ── 표 행 빌드 ───────────────────────────────────────────────────────────────
type Row = { label: string; kind: 'cat' | 'subtotal' | 'total' | 'amount' } & Agg;

function buildRows(section: { rows?: MetricRow[]; people?: MetricRow[]; grandTotal?: Agg; amount?: Agg }, kind: 'cat' | 'person'): Row[] {
  let list = kind === 'person' ? section.people ?? [] : section.rows ?? [];
  // 담당자별: 선택 연도에 판매 이력이 없는(전부 null) 직원 행 제거
  if (kind === 'person') list = list.filter(r => valsOf(r).some(v => v !== null && v !== undefined));
  const cat: Row[] = list.map(r => ({ label: r.name, kind: 'cat', v25: r.v25, a25: r.a25, v26: r.v26, a26: r.a26 }));

  // 소계는 '표시된 값'을 더한다(colSum). 원값 합을 따로 반올림하면 화면상 덧셈이 안 맞는다
  // (예: 타이어 1,091.7 + TUBE 237.0 + FLAP 69.7 = 1,398.4 인데 원값합 반올림은 1,398.5).
  if (kind === 'cat') {
    const nLen = (r: MetricRow) => ({ v25: r.v25.length, v26: r.v26.length });
    const mkSub = (label: string, src: MetricRow[]): Row | null => {
      if (!src.length) return null;
      const n = nLen(src[0]);
      return {
        label, kind: 'subtotal',
        v25: colSum(src, r => r.v25, n.v25), a25: avgSum(src, r => r.a25),
        v26: colSum(src, r => r.v26, n.v26), a26: avgSum(src, r => r.a26),
      };
    };
    // 타이어 합계 — 마지막 타이어 행 뒤에 삽입
    const tire = list.filter(r => isTire(r.name));
    const sub = mkSub('타이어 합계', tire);
    if (sub) {
      let lastTire = -1;
      list.forEach((r, i) => { if (isTire(r.name)) lastTire = i; });
      cat.splice(lastTire + 1, 0, sub);
    }
    // 기타 합계 — 비타이어(TUBE·FLAP·VULKANISIRJADI) 소계
    const etc = mkSub('기타 합계', list.filter(r => !isTire(r.name)));
    if (etc) cat.push(etc);
    // 전체 합계 — 타이어+기타. 소계와 동일하게 '표시된 값'을 더하므로 화면 덧셈이 맞는다.
    const all = mkSub('전체 합계', list);
    if (all) cat.push({ ...all, kind: 'total' });
    return cat;
  }

  // 담당자별: 소계 구분이 없으므로 합계 한 줄만
  const rows: Row[] = [...cat];
  if (section.grandTotal) rows.push({ label: '합계', kind: 'total', ...section.grandTotal });
  return rows;
}

const S4_LABEL: Record<string, string> = {
  Sales: 'Sales (영업)', Admin: 'Admin (관리)', Delivery: 'Delivery (배송)',
  'Sub. Total': 'Total (인원/Person)', 'Total (Person)': 'Total (인원/Person)',
  Salary: 'Salary Total (M.IDR)', Petty: 'Petty Cost (M.IDR)',
};
const s4rows = computed<Row[]>(() => {
  const s4 = branch.value.sectionIV;
  const totalKey = branchKey.value === 'semarang' ? 'Total (Person)' : 'Sub. Total';
  // Total(인원) 하부에 Salary Total → Petty 순
  const order = ['Sales', 'Admin', 'Delivery', totalKey, 'Salary', 'Petty'];
  return order.filter(k => s4[k]).map(k => ({
    label: S4_LABEL[k] ?? k,
    kind: (k === 'Petty' || k === 'Salary' ? 'amount' : k.includes('Total') ? 'total' : 'cat') as Row['kind'],
    v25: s4[k].v25, a25: s4[k].a25, v26: s4[k].v26, a26: s4[k].a26,
  }));
});

// 매출 하위탭(전체/순매출/담당자별)
const TABS = [
  { n: 'I',   label: '전체매출' },
  { n: 'II',  label: '순매출' },
  { n: 'III', label: '담당자별 매출' },
] as const;
const activeTab = ref<'I' | 'II' | 'III'>('I');
// 매출 표에만 금액/수량 토글을 적용한다.
// (KPI 카드·P&L·인원 탭은 항상 수량 기준 DATA 를 쓴다 — branch computed 를 바꾸면 그쪽까지 오염됨)
const salesBranch = computed<Branch>(() =>
  metric.value === 'amt' && DATA_AMT.value ? DATA_AMT.value[branchKey.value] : branch.value);

const activeRows = computed<Row[]>(() => {
  const b = salesBranch.value;
  return activeTab.value === 'I' ? buildRows(b.sectionI, 'cat')
    : activeTab.value === 'II' ? buildRows(b.sectionII, 'cat')
    : buildRows(b.sectionIII, 'person');
});

// 상위 3개 탭: 매출 / 운영 손익 / 인원 및 비용
const MAIN_TABS = [
  { k: 'sales', label: '매출' },
  { k: 'pnl',   label: '운영 손익' },
  { k: 'cost',  label: '인원 및 비용' },
] as const;
const mainTab = ref<'sales' | 'pnl' | 'cost'>('sales');
// 활성 상위탭에 표시할 표 행(매출=선택 하위탭 / 비용=섹션 Ⅳ)
const tabRows = computed<Row[]>(() =>
  mainTab.value === 'sales' ? activeRows.value
  : mainTab.value === 'cost' ? s4rows.value
  : []);

// ── 담당자별 표 정렬 (실적순) ────────────────────────────────────────────────
// 매트릭스 표 중 '담당자별 매출'만 컬럼(월/Avg) 클릭 정렬. 합계·금액 행은 하단 고정.
const isPersonTab = computed(() => mainTab.value === 'sales' && activeTab.value === 'III');
const sortCol = ref<number | 'avg' | null>(null);
const sortDir = ref<'asc' | 'desc'>('desc');
function toggleSort(col: number | 'avg') {
  if (!isPersonTab.value) return;
  if (sortCol.value === col) sortDir.value = sortDir.value === 'desc' ? 'asc' : 'desc';
  else { sortCol.value = col; sortDir.value = 'desc'; }
}
// 탭·연도 변경 시 정렬 초기화(존재하지 않는 월 기준 정렬 방지)
watch([activeTab, year], () => { sortCol.value = null; });
const displayRows = computed<Row[]>(() => {
  const rows = tabRows.value;
  if (!isPersonTab.value || sortCol.value === null) return rows;
  const getv = (r: Row) => (sortCol.value === 'avg' ? avgOf(r) : valsOf(r)[sortCol.value as number]);
  const mult = sortDir.value === 'asc' ? 1 : -1;
  const cats = rows.filter(r => r.kind === 'cat')
    .sort((a, b) => ((getv(a) ?? -Infinity) - (getv(b) ?? -Infinity)) * mult);
  const rest = rows.filter(r => r.kind !== 'cat');
  return [...cats, ...rest];
});

// 인원 및 비용 탭 요약 KPI — 섹션 Ⅳ(인원·Petty) 기준, 최근 데이터 월
const costKpi = computed(() => {
  const s4 = branch.value.sectionIV;
  const totalKey = branchKey.value === 'semarang' ? 'Total (Person)' : 'Sub. Total';
  const total = s4[totalKey];
  const ms = months.value;
  const tv = total ? valsOf(total) : [];
  const idx: number[] = [];
  tv.forEach((x, i) => { if (x !== null && x !== undefined) idx.push(i); });
  const last = idx.length ? idx[idx.length - 1] : -1;
  const prev = idx.length >= 2 ? idx[idx.length - 2] : -1;
  const at = (a?: Agg) => (a && last >= 0 ? valsOf(a)[last] : null);
  const atPrev = (a?: Agg) => (a && prev >= 0 ? valsOf(a)[prev] : null);
  const pct = (now: number | null | undefined, was: number | null | undefined) =>
    (now !== null && now !== undefined && was !== null && was !== undefined && was !== 0) ? ((now - was) / Math.abs(was)) * 100 : null;
  const yoy = (a?: Agg) => pct(a ? avgOf(a) : null, a ? prevAvgOf(a) : null);
  return {
    label: last >= 0 ? `${year.value} ${monthKo(ms[last])}` : '-',
    totalNow: at(total), totalMom: pct(at(total), atPrev(total)),
    sales: at(s4['Sales']), admin: at(s4['Admin']), delivery: at(s4['Delivery']),
    pettyNow: at(s4['Petty']), pettyMom: pct(at(s4['Petty']), atPrev(s4['Petty'])),
    totalAvg: total ? avgOf(total) : null, totalAvgYoy: yoy(total),
    pettyAvg: s4['Petty'] ? avgOf(s4['Petty']) : null, pettyAvgYoy: yoy(s4['Petty']),
  };
});

function rowCls(kind: Row['kind']): string {
  if (kind === 'total') return 'font-bold bg-muted/40 [&>td]:border-t-2 [&>td]:border-border';
  if (kind === 'amount') return 'bg-teal-500/15 text-teal-700 font-semibold';
  if (kind === 'subtotal') return 'font-semibold [&>td]:border-t [&>td]:border-teal-500/40';
  return '';
}

// ── 운영 손익(P&L) — 상단 '연도'(2025/2026)·'지점' 드롭다운 공유 ─────────────────
// 선택 연도에 입력된 마지막 월까지만 표시(빈 6~12월 컬럼 숨김 → 매출 표와 동일)
const pnlMonths = computed(() => {
  const rec = PNL_VALUES[branchKey.value];
  if (!rec) return PNL_MONTHS_12;
  let last = -1;
  for (const k in rec) {
    const v = year.value === 2026 ? rec[k].v26 : rec[k].v25;
    for (let i = 0; i < v.length; i++) if (v[i] !== null && v[i] !== undefined && i > last) last = i;
  }
  return last >= 0 ? PNL_MONTHS_12.slice(0, last + 1) : PNL_MONTHS_12;
});
const hasPnl = computed(() => Object.keys(PNL_VALUES[branchKey.value] ?? {}).length > 0);

// 특정 연도(2024/2025/2026)의 월별 배열
function pnlMonthlyOf(key: string, y: number): (number | null)[] {
  const rec = PNL_VALUES[branchKey.value]?.[key];
  if (!rec) return NULL12();
  return y === 2026 ? rec.v26 : rec.v25; // 2024는 월별 미보유 → 평균만 사용
}
// 선택 연도(year ref) 기준 월별 값
function pnlValsOf(key: string): (number | null)[] { return pnlMonthlyOf(key, year.value); }
// 입력된 월의 단순평균(null 제외) — 보고서 평균 미제공 시 사용
function pnlMean(arr: (number | null)[]): number | null {
  const xs = arr.filter((x): x is number => x !== null && x !== undefined);
  return xs.length ? xs.reduce((a, c) => a + c, 0) / xs.length : null;
}
// 선택 연도 평균 (2026은 보고서 평균이 없으면 입력 월의 부분연도 평균을 계산)
function pnlAvgOf(key: string): number | null {
  const rec = PNL_VALUES[branchKey.value]?.[key];
  if (!rec) return null;
  return year.value === 2026 ? (rec.a26 ?? pnlMean(rec.v26)) : rec.a25;
}
// 전년 평균 (2026→2025 평균, 2025→2024 평균)
function pnlPrevAvgOf(key: string): number | null {
  const rec = PNL_VALUES[branchKey.value]?.[key];
  if (!rec) return null;
  return year.value === 2026 ? rec.a25 : rec.a24;
}

type PnlRow = (typeof PNL_ROWS_META)[number] & { v: (number | null)[]; a: number | null; prev: number | null };
// 비율 행은 저장값을 쓰지 않고 분자÷매출로 계산한다.
//   저장된 PNL_VALUES 의 *Pct 값에 실제 오류가 있었다(2026-01 영업이익률 표기 16.6% vs 계산 12.4%,
//   2026-02 12.6% vs 8.1%, 2026-03 1.1% vs 2.4%, 2025-01 6.8% vs 5.1%).
//   분자·분모가 이미 있으므로 계산하면 이런 불일치가 원천적으로 생기지 않는다.
const PCT_NUMERATOR: Record<string, string> = {
  pursPct: 'purs', marginPct: 'margin', opcostPct: 'opcost', opprofitPct: 'opprofit',
};
const pct = (n: number | null | undefined, d: number | null | undefined): number | null =>
  n === null || n === undefined || !d ? null : Math.round((n / d) * 1000) / 10;

const pnlRows = computed<PnlRow[]>(() => PNL_ROWS_META.map(m => {
  const num = PCT_NUMERATOR[m.key];
  if (!num) return { ...m, v: pnlValsOf(m.key), a: pnlAvgOf(m.key), prev: pnlPrevAvgOf(m.key) };
  const nv = pnlValsOf(num), sv = pnlValsOf('sales');
  return {
    ...m,
    v: nv.map((x, i) => pct(x, sv[i])),
    a: pct(pnlAvgOf(num), pnlAvgOf('sales')),
    prev: pct(pnlPrevAvgOf(num), pnlPrevAvgOf('sales')),
  };
}));

// 아코디언: 주요 5개 섹션을 헤더로, 하위 항목은 접기/펼치기. 인원·BEP는 항상 표시.
const PNL_GROUPS: { head: string; children: string[] }[] = [
  { head: 'sales',    children: ['tireQty', 'radial', 'bias', 'etc', 'tube', 'flap', 'stock'] },
  { head: 'purs',     children: ['pursPct'] },
  { head: 'margin',   children: ['marginPct'] },
  { head: 'opcost',   children: ['opcostPct', 'labor', 'rent', 'depr', 'trans', 'admin'] },
  { head: 'opprofit', children: ['opprofitPct'] },
];
const PNL_STANDALONE = ['bepQty', 'bepAmt'];   // 'emp' 제거 — '인원 및 비용' 탭과 중복

const openSections = ref<Set<string>>(new Set()); // 기본: 모두 접힘
function toggleSection(key: string) {
  const s = new Set(openSections.value);
  s.has(key) ? s.delete(key) : s.add(key);
  openSections.value = s;
}

type PnlVisRow = PnlRow & { _head: boolean; _open: boolean; _hasChildren: boolean };
const pnlVisibleRows = computed<PnlVisRow[]>(() => {
  const byKey: Record<string, PnlRow> = {};
  for (const r of pnlRows.value) byKey[r.key] = r;
  const out: PnlVisRow[] = [];
  for (const g of PNL_GROUPS) {
    const head = byKey[g.head];
    if (!head) continue;
    const open = openSections.value.has(g.head);
    out.push({ ...head, _head: true, _open: open, _hasChildren: g.children.length > 0 });
    if (open) for (const ck of g.children) if (byKey[ck]) out.push({ ...byKey[ck], _head: false, _open: false, _hasChildren: false });
  }
  for (const sk of PNL_STANDALONE) if (byKey[sk]) out.push({ ...byKey[sk], _head: false, _open: false, _hasChildren: false });
  return out;
});

function pnlFmt(n: number | null | undefined, fmt: PnlFmt): string {
  if (n === null || n === undefined) return '–';
  if (fmt === 'pct') return Number(n).toFixed(1) + '%';   // 비율: 소수 첫째자리
  return Math.round(Number(n)).toLocaleString('en-US');    // 금액·수량·평균: 정수
}

function pnlRowCls(kind: PnlKind): string {
  if (kind === 'profit') return 'font-bold bg-teal-500/15 text-teal-700 [&>td]:border-t-2 [&>td]:border-teal-500/40';
  if (kind === 'head') return 'font-bold [&>td]:border-t [&>td]:border-border/60';
  if (kind === 'pct') return 'text-[11px] text-muted-foreground/80';
  if (kind === 'bep') return 'text-foreground/75 [&>td]:border-t [&>td]:border-border/40';
  if (kind === 'sub') return 'text-muted-foreground';
  return '';
}

// P&L KPI — 선택 연도의 마지막 데이터 월. 없으면 전년 마지막 월로 폴백.
const pnlKpi = computed(() => {
  const idxOf = (arr: (number | null)[]) => { const out: number[] = []; arr.forEach((x, i) => { if (x !== null && x !== undefined) out.push(i); }); return out; };
  let y = year.value;
  let idx = idxOf(pnlMonthlyOf('sales', y));
  if (!idx.length) { y = year.value - 1; idx = idxOf(pnlMonthlyOf('sales', y)); }
  if (!idx.length) return { has: false, label: '-' };
  const last = idx[idx.length - 1];
  const prev = idx.length >= 2 ? idx[idx.length - 2] : -1;
  const pick = (k: string) => pnlMonthlyOf(k, y)[last];
  const pickPrev = (k: string) => prev >= 0 ? pnlMonthlyOf(k, y)[prev] : null;
  const mom = (now: number | null | undefined, was: number | null | undefined) =>
    (now !== null && now !== undefined && was !== null && was !== undefined && was !== 0) ? ((now - was) / Math.abs(was)) * 100 : null;
  return {
    has: true,
    label: `${y} ${monthKo(PNL_MONTHS_12[last])}`,
    sales: pick('sales'), salesMom: mom(pick('sales'), pickPrev('sales')),
    margin: pick('margin'), marginPct: pick('marginPct'), marginMom: mom(pick('margin'), pickPrev('margin')),
    opprofit: pick('opprofit'), opprofitPct: pick('opprofitPct'), opprofitMom: mom(pick('opprofit'), pickPrev('opprofit')),
    bepAmt: pick('bepAmt'), bepMom: mom(pick('bepAmt'), pickPrev('bepAmt')),
  };
});

// ── CSV 내보내기 (현재 탭 표) ─────────────────────────────────────────────────
function downloadCurrentCsv() {
  const yr = year.value, b = bn.value;
  if (mainTab.value === 'pnl') {
    const ms = pnlMonths.value;
    const headers = ['ITEM', `${yr - 1} 평균`, ...ms.map(monthKo), `${yr} 평균`];
    const rows = pnlRows.value.map(r => [
      r.label, r.prev, ...ms.map((_, i) => r.v[i]), r.a,
    ]);
    exportCsv(`지점손익_${b}_${yr}`, headers, rows);
    return;
  }
  const ms = months.value, hp = hasPrev.value;
  const headers = ['Category', ...(hp ? [`${yr - 1} 평균`] : []), ...ms.map(monthKo), 'Avg'];
  const rows = displayRows.value.map(r => [
    r.label, ...(hp ? [prevAvgOf(r)] : []), ...ms.map((_, i) => valsOf(r)[i]), avgOf(r),
  ]);
  const tag = mainTab.value === 'cost' ? '인원비용'
    : activeTab.value === 'I' ? '전체매출' : activeTab.value === 'II' ? '순매출' : '담당자별매출';
  exportCsv(`지점${tag}_${b}_${yr}`, headers, rows);
}

// ── CSV 업로드 (지점 월별 판매 원본 → branch_sales_rows 전량 교체) ──────────
// ⚠ 지점마다 CSV 열 구성이 다르다: 스마랑엔 'Brand 2' 열이 있고 수라바야엔 없어
//   7번 이후 인덱스가 한 칸 밀린다. 따라서 컬럼은 반드시 헤더명으로 찾는다(고정 인덱스 금지).
const uploading = ref(false);
const uploadMsg = ref('');
const fileInput = ref<HTMLInputElement | null>(null);

const MON_IDX: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
  mei: 5, agu: 8, okt: 10, nop: 11, des: 12,   // 인니어 약어
};
const normKey = (s: string) => (s ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
function csvNum(s: string): number {
  const t = (s ?? '').trim().replace(/,/g, '');
  if (!t || t === '-' || t === '–') return 0;
  const n = Number(t);
  return isNaN(n) ? 0 : n;
}
function csvDate(s: string): string | null {
  const m = /^(\d{1,2})-([A-Za-z]{3})-(\d{2})$/.exec((s ?? '').trim());
  if (!m) return null;
  const mo = MON_IDX[m[2].toLowerCase()];
  return mo ? `20${m[3]}-${String(mo).padStart(2, '0')}-${m[1].padStart(2, '0')}` : null;
}
/** 따옴표·줄바꿈을 포함한 CSV 파싱 */
function parseCsv(text: string): string[][] {
  const out: string[][] = []; let row: string[] = [], cur = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; }
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); out.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur || row.length) { row.push(cur); out.push(row); }
  return out;
}

async function onUpload(e: Event) {
  const f = (e.target as HTMLInputElement).files?.[0];
  if (!f) return;
  uploading.value = true; uploadMsg.value = '';
  try {
    const grid = parseCsv(await f.text());
    const hi = grid.findIndex(r => {
      const j = r.join(',').toUpperCase();
      return j.includes('QTY') && j.includes('BUYER');
    });
    if (hi < 0) throw new Error('헤더 행(QTY·BUYER 포함)을 찾지 못했습니다.');
    const hdr = grid[hi].map(h => h.trim().toUpperCase());
    const col = (...names: string[]) => {
      for (const n of names) { const i = hdr.indexOf(n); if (i >= 0) return i; }
      return -1;
    };
    const ix = {
      so: col('SO'), date: col('DELIVERY DATE'), pic: col('PIC'), buyer: col('BUYER'),
      dest: col('DESTINATION'), cat: col('CATEGORY'), sku: col('NO. ITEM'), desc: col('DESCRIPTION'),
      unit: col('DISCOUNTED UNIT', 'UNIT (IDR)'), qty: col('QTY'),
      soamt: col('SO AMT (IDR)'), tax: col('TAX AMT (IDR)'), total: col('TOTAL AMT (IDR)'),
    };
    const miss = Object.entries(ix).filter(([, v]) => v < 0).map(([k]) => k);
    if (miss.length) throw new Error(`필수 컬럼 없음: ${miss.join(', ')}`);

    // 마스터 조회 → 링크 해석 (미매칭은 null, 원문은 항상 보존)
    const [prods, custs, staffs, excl] = await Promise.all([
      sbGetAll<{ sku: string }>('products?select=sku'),
      sbGetAll<{ customer_code: string; customer_name: string }>('customers?select=customer_code,customer_name'),
      sbGetAll<{ nik: string; name: string }>('staff?select=nik,name'),
      sbGetAll<{ branch: string; buyer: string }>('branch_excluded_buyers?select=*').catch(() => []),
    ]);
    void excl;
    const skuMap = new Map(prods.map(p => [normKey(p.sku), p.sku]));
    const custMap = new Map(custs.map(c => [normKey(c.customer_name), c.customer_code]));
    const staffMap = new Map<string, string[]>();
    for (const s of staffs) {
      const k = normKey((s.name || '').split(' ')[0]);
      staffMap.set(k, [...(staffMap.get(k) ?? []), s.nik]);
    }
    const PIC_ALIAS: Record<string, string> = { JOKO: 'DJOKO', UGI: 'UGIH', YONO: 'SUSYONO', SAMAN: 'SANAM' };
    const SO_BUYER: Record<string, string> = {
      NIS: 'CV. NASAMED INTI SUKSES', TBSA: 'PT. TUGU BETON SEMESTA ABADI', BPT: 'PT. BAMBOO PUTRA TRANSINDO',
    };

    const payload: Record<string, unknown>[] = [];
    let skipped = 0, soFix = 0;
    for (const r of grid.slice(hi + 1)) {
      if (r.length <= ix.qty || !(r[0] ?? '').trim()) continue;
      const d = csvDate(r[ix.date]);
      if (!d) { skipped++; continue; }
      const so = (r[ix.so] ?? '').trim();
      const notes: string[] = [];

      // Buyer 열이 제품명으로 깨진 행 → SO 번호의 거래처 코드로 보정
      let buyer = (r[ix.buyer] ?? '').trim();
      if (!/^(PT|CV)[.\s]/i.test(buyer)) {
        for (const [code, name] of Object.entries(SO_BUYER)) {
          if (new RegExp(`[/-]${code}[/-]`, 'i').test(so) || so.toUpperCase().startsWith(`PO/${code}`)) {
            buyer = name; notes.push('buyer=so_derived'); soFix++; break;
          }
        }
      }
      const cust = custMap.get(normKey(buyer)) ?? null;
      if (!cust) notes.push('customer=none');
      const skuRaw = (r[ix.sku] ?? '').trim();
      const sku = skuMap.get(normKey(skuRaw)) ?? null;
      if (!sku) notes.push('sku=none');
      const picRaw = (r[ix.pic] ?? '').trim();
      const hits = staffMap.get(PIC_ALIAS[normKey(picRaw)] ?? normKey(picRaw)) ?? [];
      const nik = hits.length === 1 ? hits[0] : null;
      if (!nik) notes.push(hits.length ? 'staff=ambiguous' : 'staff=none');

      payload.push({
        branch: branchKey.value, so: so || null, delivery_date: d,
        pic: picRaw || null, buyer: buyer || null, sku_raw: skuRaw || null,
        destination: (r[ix.dest] ?? '').trim().toLowerCase() || null,
        category: (r[ix.cat] ?? '').trim().toUpperCase(),
        description: (r[ix.desc] ?? '').trim() || null,
        sku, customer_code: cust, staff_nik: nik,
        link_note: notes.join(',') || 'exact',
        unit_price: csvNum(r[ix.unit]) || null,
        qty: csvNum(r[ix.qty]), so_amt: csvNum(r[ix.soamt]),
        tax_amt: csvNum(r[ix.tax]) || null, total_amt: csvNum(r[ix.total]) || null,
        source_file: f.name,
      });
    }
    if (!payload.length) throw new Error('적재할 행이 없습니다. 날짜 형식(예: 5-Jan-26)을 확인하세요.');

    const label = BRANCH_LABEL[branchKey.value];
    if (!confirm(`${label} 지점의 기존 데이터를 삭제하고 ${payload.length}행으로 교체합니다.\n(파일: ${f.name})\n계속할까요?`)) {
      uploadMsg.value = '취소했습니다.';
      return;
    }
    await sbDelete(`branch_sales_rows?branch=eq.${branchKey.value}`);
    for (let i = 0; i < payload.length; i += 500) await sbPost('branch_sales_rows', payload.slice(i, i + 500));
    await loadData();
    uploadMsg.value = `${label} ${payload.length}행 적재 완료`
      + (skipped ? ` · 날짜 인식 실패 ${skipped}행 제외` : '')
      + (soFix ? ` · Buyer 깨짐 ${soFix}행 SO번호로 보정` : '');
  } catch (err) {
    uploadMsg.value = `업로드 실패: ${(err as Error).message}`;
  } finally {
    uploading.value = false;
    if (fileInput.value) fileInput.value.value = '';
  }
}
</script>

<template>
  <div class="p-6 space-y-6 max-w-300 mx-auto">
    <!-- 헤더 + 컨트롤 -->
    <PageHeader
      title="지점 판매 관리"
      :subtitle="`단위: 본/EA, 매출 백만 루피아`"
    >
      <template #controls>
        <div class="inline-flex items-center gap-1.5 self-end bg-card rounded-lg border border-border pl-3 pr-1 focus-within:ring-1 focus-within:ring-teal-400">
          <span class="text-[11px] font-semibold text-muted-foreground shrink-0">지점</span>
          <select
            v-model="branchKey"
            class="text-xs font-semibold bg-transparent text-foreground py-2 pr-6 focus:outline-none cursor-pointer"
          >
            <option v-for="b in (['surabaya','semarang'] as const)" :key="b" :value="b">{{ BRANCH_LABEL[b] }}</option>
          </select>
        </div>
        <div class="inline-flex items-center gap-1.5 self-end bg-card rounded-lg border border-border pl-3 pr-1 focus-within:ring-1 focus-within:ring-teal-400">
          <span class="text-[11px] font-semibold text-muted-foreground shrink-0">연도</span>
          <select
            v-model.number="year"
            class="text-xs font-semibold tabular-nums bg-transparent text-foreground py-2 pr-6 focus:outline-none cursor-pointer"
          >
            <option v-for="y in YEARS" :key="y" :value="y">{{ y }}</option>
          </select>
        </div>
        <!-- 상위 탭 + 매출 하위 선택 -->
        <div class="inline-flex bg-muted rounded-lg p-1 gap-1 self-end">
          <button
            v-for="t in MAIN_TABS" :key="t.k"
            :class="['text-xs font-semibold px-4 py-2 rounded-md transition-colors', mainTab === t.k ? 'bg-card text-teal-600 shadow-sm' : 'text-muted-foreground hover:text-foreground']"
            @click="mainTab = t.k"
          >{{ t.label }}</button>
        </div>
      </template>
      <template #actions>
        <!-- 자주 쓰지 않는 동작은 ⋯ 하나로 묶는다 -->
        <input ref="fileInput" type="file" accept=".csv,text/csv" class="hidden" @change="onUpload" />
        <div class="relative" data-actmenu>
          <button
            :disabled="uploading"
            class="inline-flex items-center justify-center h-9 w-9 rounded-lg border border-border text-muted-foreground hover:text-foreground hover:bg-accent transition-colors disabled:opacity-50"
            title="엑셀 · 업로드 · 데이터 입력"
            @click="actMenu = !actMenu"
          >
            <Loader2 v-if="uploading" :size="15" class="animate-spin" />
            <MoreHorizontal v-else :size="16" />
          </button>
          <div
            v-if="actMenu"
            class="absolute right-0 top-full mt-1 z-30 w-52 rounded-lg border border-border bg-card shadow-lg py-1"
          >
            <button
              class="w-full flex items-center gap-2 px-3 py-2 text-xs text-foreground hover:bg-accent text-left"
              @click="actMenu = false; downloadCurrentCsv()"
            >
              <Download :size="14" class="text-muted-foreground" /> 엑셀 내려받기
            </button>
            <button
              class="w-full flex items-center gap-2 px-3 py-2 text-xs text-foreground hover:bg-accent text-left"
              @click="actMenu = false; fileInput?.click()"
            >
              <Upload :size="14" class="text-muted-foreground" />
              <span>판매 CSV 업로드<span class="block text-[10px] text-muted-foreground">{{ bn }} 데이터 전량 교체</span></span>
            </button>
            <button
              v-if="mainTab === 'cost'"
              class="w-full flex items-center gap-2 px-3 py-2 text-xs text-foreground hover:bg-accent text-left"
              @click="actMenu = false; opsOpen = true"
            >
              <Pencil :size="14" class="text-muted-foreground" />
              <span>인원 · 인건비 입력<span class="block text-[10px] text-muted-foreground">CSV 에서 안 나오는 값</span></span>
            </button>
          </div>
        </div>
      </template>
    </PageHeader>

    <BranchOpsModal
      v-if="opsOpen"
      :branch="branchKey" :branch-label="bn" :year="year"
      @close="opsOpen = false"
      @saved="loadData"
    />

    <!-- 로드/업로드 상태 -->
    <p v-if="loading" class="text-xs text-muted-foreground">DB에서 불러오는 중…</p>
    <p v-if="loadError" class="text-xs text-amber-700 bg-amber-50/60 border border-amber-200 rounded-lg px-3 py-2">
      {{ loadError }}
    </p>
    <p
      v-if="uploadMsg"
      class="text-xs rounded-lg px-3 py-2 border"
      :class="uploadMsg.startsWith('업로드 실패') ? 'text-red-700 bg-red-50/60 border-red-200' : 'text-emerald-700 bg-emerald-50/60 border-emerald-200'"
    >
      {{ uploadMsg }}
    </p>

    <!-- ════════════ 매출 탭 ════════════ -->
    <!-- KPI 카드 -->
    <div v-if="mainTab === 'sales'" class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">최근월 판매량 · 타이어 ({{ kpi.monthLabel }})</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(kpi.qtyNow) }}<span class="text-xs font-medium text-muted-foreground ml-1">EA</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          전월 대비
          <span v-if="kpi.mom === null">–</span>
          <span v-else :class="kpi.mom >= 0 ? 'text-emerald-600 font-semibold' : 'text-red-600 font-semibold'">
            {{ kpi.mom >= 0 ? '▲' : '▼' }} {{ Math.abs(kpi.mom).toFixed(1) }}%
          </span>
        </div>
      </div>
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">최근월 매출 ({{ kpi.monthLabel }})</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(kpi.amtNow) }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          전월 대비 <span :class="deltaClass(kpi.amtMom)">{{ deltaText(kpi.amtMom) }}</span>
        </div>
      </div>
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">{{ year }} 월평균 판매량 · 타이어</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(kpi.qtyAvg) }}<span class="text-xs font-medium text-muted-foreground ml-1">EA</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          전년 대비 <span :class="deltaClass(kpi.qtyYoy)">{{ deltaText(kpi.qtyYoy) }}</span>
        </div>
      </div>
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">{{ year }} 월평균 매출</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(kpi.amtAvg) }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          전년 대비 <span :class="deltaClass(kpi.amtYoy)">{{ deltaText(kpi.amtYoy) }}</span>
        </div>
      </div>
    </div>


    <!-- 인원 및 비용 탭 요약 KPI -->
    <div v-if="mainTab === 'cost'" class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">최근월 총 인원 ({{ costKpi.label }})</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(costKpi.totalNow) }}<span class="text-xs font-medium text-muted-foreground ml-1">명</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          영업 {{ fmt(costKpi.sales) }} · 관리 {{ fmt(costKpi.admin) }} · 배송 {{ fmt(costKpi.delivery) }}
          · 전월 대비 <span :class="deltaClass(costKpi.totalMom)">{{ deltaText(costKpi.totalMom) }}</span>
        </div>
      </div>
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">최근월 Petty Cost · 소액경비 ({{ costKpi.label }})</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(costKpi.pettyNow) }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          전월 대비 <span :class="deltaClass(costKpi.pettyMom)">{{ deltaText(costKpi.pettyMom) }}</span>
        </div>
      </div>
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">{{ year }} 월평균 인원</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(costKpi.totalAvg) }}<span class="text-xs font-medium text-muted-foreground ml-1">명</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          영업·관리·배송 합 · 전년 대비 <span :class="deltaClass(costKpi.totalAvgYoy)">{{ deltaText(costKpi.totalAvgYoy) }}</span>
        </div>
      </div>
      <div class="rounded-xl border bg-card p-4">
        <div class="text-[11px] text-muted-foreground font-semibold">{{ year }} 월평균 Petty Cost</div>
        <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ fmt(costKpi.pettyAvg) }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
        <div class="text-[11px] mt-1 text-muted-foreground">
          전년 대비 <span :class="deltaClass(costKpi.pettyAvgYoy)">{{ deltaText(costKpi.pettyAvgYoy) }}</span>
        </div>
      </div>
    </div>

    <!-- 섹션 표 (매출=선택 하위탭 / 인원및비용=섹션 Ⅳ) -->
    <div v-if="mainTab !== 'pnl'" class="space-y-2">
      <!-- 표 설정: 매출 구분 + 수량/금액. 표를 보면서 바꾸는 값이라 표 바로 위에 둔다. -->
      <div v-if="mainTab === 'sales'" class="flex items-center justify-between gap-2 flex-wrap">
        <div class="inline-flex bg-muted/40 rounded-lg p-0.5">
          <button
            v-for="t in TABS" :key="t.n"
            :class="['text-xs font-semibold px-3 py-1.5 rounded-md transition-colors',
                     activeTab === t.n ? 'bg-card text-teal-600 shadow-sm' : 'text-muted-foreground hover:text-foreground']"
            @click="activeTab = t.n"
          >{{ t.label }}</button>
        </div>
        <div class="inline-flex bg-muted/40 rounded-lg p-0.5">
          <button
            v-for="mt in METRICS" :key="mt.k"
            :class="['text-xs font-semibold px-3 py-1.5 rounded-md transition-colors',
                     metric === mt.k ? 'bg-card text-teal-600 shadow-sm' : 'text-muted-foreground hover:text-foreground']"
            @click="metric = mt.k"
          >{{ mt.label }}</button>
        </div>
      </div> 
      <div class="overflow-x-auto border rounded-xl bg-card">
        <table class="w-full table-fixed text-xs border-collapse whitespace-nowrap">
          <colgroup>
            <col class="w-44" />                                  <!-- Category -->
            <col v-if="hasPrev" class="w-20" />                   <!-- 전년 평균 -->
            <col v-for="m in months" :key="'c'+m" />              <!-- 당해 월 (균등 분배) -->
            <col />                                                <!-- Avg -->
          </colgroup>
          <thead>
            <tr>
              <th rowspan="2" class="sticky left-0 z-10 bg-card text-left px-2.5 py-1.5 font-semibold text-foreground min-w-30 shadow-[1px_0_0_var(--border)]">Category</th>
              <th v-if="hasPrev" class="px-2 py-1.5 bg-indigo-500/20 text-indigo-700 font-semibold text-center border-b border-border/50 tabular-nums">{{ year - 1 }}</th>
              <th :colspan="months.length + 1" class="px-2 py-1.5 bg-teal-500/12 text-teal-700 font-semibold text-center border-b border-border/50 tabular-nums">{{ year }}</th>
            </tr>
            <tr>
              <th v-if="hasPrev" class="px-2 py-1 bg-indigo-500/10 text-indigo-700 font-semibold text-right border-b border-border/50">평균</th>
              <th
                v-for="(m, mi) in months" :key="'h'+m"
                class="px-2 py-1 bg-teal-500/10 text-teal-700 font-medium text-right border-b border-border/50"
                :class="isPersonTab ? 'cursor-pointer select-none hover:bg-teal-500/20' : ''"
                @click="toggleSort(mi)"
              >{{ monthKo(m) }}<span v-if="isPersonTab && sortCol === mi" class="ml-0.5">{{ sortDir === 'desc' ? '▾' : '▴' }}</span></th>
              <th
                class="px-2 py-1 bg-teal-500/20 text-teal-700 font-semibold text-right border-b border-border/50"
                :class="isPersonTab ? 'cursor-pointer select-none hover:bg-teal-500/30' : ''"
                @click="toggleSort('avg')"
              >Avg<span v-if="isPersonTab && sortCol === 'avg'" class="ml-0.5">{{ sortDir === 'desc' ? '▾' : '▴' }}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, ri) in displayRows" :key="ri" :class="rowCls(r.kind)">
              <td :class="['sticky left-0 z-10 text-left px-2.5 py-1.5 font-medium min-w-30 shadow-[1px_0_0_var(--border)] border-b border-border/40', r.kind === 'amount' ? 'bg-teal-500/15 text-teal-700' : r.kind === 'total' ? 'bg-muted/40 text-foreground' : r.kind === 'subtotal' ? 'bg-teal-500/15 text-teal-700' : 'bg-card text-foreground/90']">{{ r.label }}</td>
              <td v-if="hasPrev" :class="['px-2 py-1.5 text-right tabular-nums font-semibold border-b border-r border-border/40', r.kind === 'amount' ? '' : 'bg-indigo-500/10 text-indigo-700']">
                <span v-if="prevAvgOf(r) === null || prevAvgOf(r) === undefined" class="text-muted-foreground/30">–</span><template v-else>{{ fmt(prevAvgOf(r)) }}</template>
              </td>
              <td v-for="(_, i) in months" :key="'v'+i" :class="['px-2 py-1.5 text-right tabular-nums border-b border-border/40', r.kind === 'amount' ? '' : r.kind === 'subtotal' ? 'bg-teal-500/15 text-teal-800' : 'bg-teal-500/5 text-foreground']">
                <span v-if="valsOf(r)[i] === null || valsOf(r)[i] === undefined" class="text-muted-foreground/30">–</span><template v-else>{{ fmt(valsOf(r)[i]) }}</template>
              </td>
              <td :class="['px-2 py-1.5 text-right tabular-nums font-semibold border-b border-border/40', r.kind === 'amount' ? '' : r.kind === 'subtotal' ? 'bg-teal-500/25 text-teal-700' : 'bg-teal-500/15 text-teal-700']">
                <span v-if="avgOf(r) === null || avgOf(r) === undefined" class="text-muted-foreground/30">–</span><template v-else>{{ fmt(avgOf(r)) }}</template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- ════════════ 운영 손익 (P&L) 탭 ════════════ -->
    <div v-if="mainTab === 'pnl'" class="space-y-4">

      <!-- 데이터 준비중 안내 (값 미보유 지점) -->
      <div v-if="!hasPnl" class="rounded-lg border border-dashed border-amber-500/30 bg-amber-500/5 px-4 py-2.5">
        <p class="text-xs text-amber-700/90">
          <b>{{ bn }}</b> 손익 데이터는 준비중입니다. 아래는 입력 대기 양식(–)이며 추후 보고서 수신 시 채워집니다.
        </p>
      </div>

      <!-- P&L KPI -->
      <div v-if="hasPnl" class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="rounded-xl border bg-card p-4">
          <div class="text-[11px] text-muted-foreground font-semibold">최근월 매출 ({{ pnlKpi.label }})</div>
          <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ pnlFmt(pnlKpi.sales, 'amt') }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
          <div class="text-[11px] mt-1 text-muted-foreground">
            전월 대비 <span :class="deltaClass(pnlKpi.salesMom)">{{ deltaText(pnlKpi.salesMom) }}</span>
          </div>
        </div>
        <div class="rounded-xl border bg-card p-4">
          <div class="text-[11px] text-muted-foreground font-semibold">매출총이익 · 마진율</div>
          <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ pnlFmt(pnlKpi.margin, 'amt') }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
          <div class="text-[11px] mt-1 text-muted-foreground">
            <span class="text-teal-700 font-semibold">{{ pnlFmt(pnlKpi.marginPct, 'pct') }}</span>
            · 전월 대비 <span :class="deltaClass(pnlKpi.marginMom)">{{ deltaText(pnlKpi.marginMom) }}</span>
          </div>
        </div>
        <div class="rounded-xl border bg-card p-4">
          <div class="text-[11px] text-muted-foreground font-semibold">영업이익 · 이익률</div>
          <div class="text-2xl font-bold mt-1.5 tabular-nums" :class="(pnlKpi.opprofit ?? 0) >= 0 ? 'text-foreground' : 'text-red-600'">{{ pnlFmt(pnlKpi.opprofit, 'amt') }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
          <div class="text-[11px] mt-1 text-muted-foreground">
            <span class="font-semibold" :class="(pnlKpi.opprofitPct ?? 0) >= 0 ? 'text-emerald-600' : 'text-red-600'">{{ pnlFmt(pnlKpi.opprofitPct, 'pct') }}</span>
            · 전월 대비 <span :class="deltaClass(pnlKpi.opprofitMom)">{{ deltaText(pnlKpi.opprofitMom) }}</span>
          </div>
        </div>
        <div class="rounded-xl border bg-card p-4">
          <div class="text-[11px] text-muted-foreground font-semibold">손익분기 매출(BEP)</div>
          <div class="text-2xl font-bold mt-1.5 tabular-nums text-foreground">{{ pnlFmt(pnlKpi.bepAmt, 'amt') }}<span class="text-xs font-medium text-muted-foreground ml-1">M.IDR</span></div>
          <div class="text-[11px] mt-1 text-muted-foreground">
            전월 대비 <span :class="deltaClass(pnlKpi.bepMom)">{{ deltaText(pnlKpi.bepMom) }}</span>
          </div>
        </div>
      </div>

      <!-- P&L 표 -->
      <div class="overflow-x-auto border rounded-xl bg-card">
        <table class="w-full table-fixed text-xs border-collapse whitespace-nowrap">
          <colgroup>
            <col class="w-48" />                                  <!-- ITEM -->
            <col class="w-20" />                                  <!-- 전년 평균 -->
            <col v-for="m in pnlMonths" :key="'pc'+m" />          <!-- 당해 월 (균등 분배) -->
            <col class="w-20" />                                  <!-- 당해 평균 -->
          </colgroup>
          <thead>
            <tr>
              <th rowspan="2" class="sticky left-0 z-10 bg-card text-left px-2.5 py-1.5 font-semibold text-foreground min-w-32 shadow-[1px_0_0_var(--border)]">ITEM</th>
              <th class="px-2 py-1.5 bg-indigo-500/20 text-indigo-700 font-semibold text-center border-b border-border/50 tabular-nums">{{ year - 1 }}</th>
              <th :colspan="pnlMonths.length + 1" class="px-2 py-1.5 bg-amber-500/12 text-amber-700 font-semibold text-center border-b border-border/50 tabular-nums">{{ year }}</th>
            </tr>
            <tr>
              <th class="px-2 py-1 bg-indigo-500/10 text-indigo-700 font-semibold text-right border-b border-border/50">평균</th>
              <th v-for="m in pnlMonths" :key="'ph'+m" class="px-2 py-1 bg-amber-500/10 text-amber-700/90 font-medium text-right border-b border-border/50">{{ monthKo(m) }}</th>
              <th class="px-2 py-1 bg-amber-500/20 text-amber-700 font-semibold text-right border-b border-border/50">평균</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(r, ri) in pnlVisibleRows" :key="ri"
              :class="[pnlRowCls(r.kind), r._head && r._hasChildren ? 'cursor-pointer select-none hover:bg-muted/30' : '']"
              @click="r._head && r._hasChildren ? toggleSection(r.key) : null"
            >
              <td :class="['sticky left-0 z-10 text-left px-2.5 py-1.5 min-w-32 shadow-[1px_0_0_var(--border)] border-b border-border/40', r.kind === 'profit' ? 'bg-teal-500/15 text-teal-700 font-bold' : r.kind === 'head' ? 'bg-card text-foreground font-bold' : 'bg-card']" :style="{ paddingLeft: (10 + r.indent * 12) + 'px' }">
                <span v-if="r._head && r._hasChildren" class="inline-block w-3 mr-1 text-muted-foreground transition-transform" :class="r._open ? 'rotate-90' : ''">▸</span>
                {{ r.label }}
              </td>
              <td class="px-2 py-1.5 text-right tabular-nums font-semibold border-b border-r border-border/40 bg-indigo-500/10 text-indigo-700">
                <span v-if="r.prev === null || r.prev === undefined" class="text-muted-foreground/30">–</span><template v-else>{{ pnlFmt(r.prev, r.fmt) }}</template>
              </td>
              <td v-for="(_, i) in pnlMonths" :key="'pv'+i" class="px-2 py-1.5 text-right tabular-nums border-b border-border/40">
                <span v-if="r.v[i] === null || r.v[i] === undefined" class="text-muted-foreground/30">–</span><template v-else>{{ pnlFmt(r.v[i], r.fmt) }}</template>
              </td>
              <td class="px-2 py-1.5 text-right tabular-nums font-semibold border-b border-l border-border/40 bg-amber-500/5">
                <span v-if="r.a === null || r.a === undefined" class="text-muted-foreground/30">–</span><template v-else>{{ pnlFmt(r.a, r.fmt) }}</template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 제외 거래처 (매출 탭) — 3분할: 제목 | 내용1 | 내용2 -->
    <div v-if="mainTab === 'sales'" class="rounded-xl border bg-card p-4 grid grid-cols-1 md:grid-cols-3 gap-4 md:gap-6">
      <!-- ① 제목 -->
      <div class="min-w-0">
        <h4 class="text-sm font-bold text-foreground mb-1">제외 거래처</h4>
        <p class="text-[11px] text-muted-foreground">순매출(Net) 계산에서 차감되는 거래처 — {{ branch.excluded.length }}개사</p>
      </div>
      <!-- ② 내용1 -->
      <ul class="m-0 p-0 list-none self-center">
        <li v-for="(d, i) in branch.excluded.slice(0, exclHalf)" :key="i" class="text-xs py-0.5 text-foreground/80">
          {{ i + 1 }}. <b v-if="branchKey === 'semarang' && i === 2" class="text-red-600">{{ d }}</b><template v-else>{{ d }}</template>
        </li>
      </ul>
      <!-- ③ 내용2 -->
      <ul class="m-0 p-0 list-none self-center">
        <li v-for="(d, i) in branch.excluded.slice(exclHalf)" :key="i" class="text-xs py-0.5 text-foreground/80">
          {{ exclHalf + i + 1 }}. <b v-if="branchKey === 'semarang' && exclHalf + i === 2" class="text-red-600">{{ d }}</b><template v-else>{{ d }}</template>
        </li>
      </ul>
    </div>
  </div>
</template>
