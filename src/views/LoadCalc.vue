<script setup lang="ts">
// 하중계산 — 차량별 적정 타이어 적재하중 계산기 (v7 HTML 이식)
// 데이터(타이어 제원·차량 프리셋·LI→kg)는 뷰 내장. DB 이관은 작업지시서(적재하중계산_DB추가구성) 별도 단계.
import { ref, reactive } from 'vue';
import PageHeader from '@/components/PageHeader.vue';

/* ── LI → kg 변환표 (TRA 표준 · 데이터북 p.66) ─────────────────────────────── */
const LI2KG: Record<number, number> = {
  122: 1500, 126: 1700, 146: 3000, 149: 3250, 150: 3350, 152: 3550, 153: 3650,
  154: 3750, 155: 3875, 156: 4000, 160: 4500, 161: 4625, 163: 4875, 164: 5000, 167: 5450, 169: 5800,
  177: 7300, 178: 7500, 180: 8000, 182: 8500, 184: 9000, 185: 9250, 187: 9750, 190: 10600, 193: 11500,
  200: 14000, 201: 14500, 202: 15000, 203: 15500, 204: 16000, 209: 18500, 214: 21800, 216: 22400,
  218: 23600, 223: 27250, 229: 32500,
};
const li = (n: number) => LI2KG[n] ?? null;

/* ── TBR / Bias : LI → 단륜/복륜 최대하중(kg) ──────────────────────────────── */
interface Tbr { brand: string; cat: string; pattern: string; size: string; pr: number; li: string; single: number; dual: number; psi: number }
const TBR: Tbr[] = ([
  ['ASCENDO','TBR','AR525','10.00R20',18,'149/146',3250,3000,135],
  ['ASCENDO','TBR','AR535','7.50R16',14,'122/120',1510,1440,102],
  ['ASCENDO','TBR','AR535','10.00R20',18,'149/146',3250,3000,135],
  ['ASCENDO','TBR','AR535','11.00R20',18,'152/149',3550,3250,135],
  ['ASCENDO','TBR','AR535','12.00R20',20,'156/153',3750,3450,120],
  ['ASCENDO','TBR','AR585','7.50R16',14,'122/120',1510,1440,111],
  ['ASCENDO','TBR','AR585','10.00R20',18,'149/146',3250,3000,135],
  ['ASCENDO','TBR','AR585','11.00R20',18,'152/149',3550,3250,135],
  ['ASCENDO','TBR','AR585','12.00R20',20,'156/153',4000,3650,130],
  ['ASCENDO','TBR','AR585','12.00R24',20,'160/157',4500,4125,130],
  ['ASCENDO','TBR','AR102HD','7.50R16',14,'122/120',1510,1440,102],
  ['ASCENDO','TBR','AR102HD','8.25R16',14,'126/124',1710,1630,91],
  ['ASCENDO','TBR','AR102HD','9.00R20',16,'144/142',2575,2430,115],
  ['ASCENDO','TBR','AR102HD','10.00R20',18,'149/146',3250,3000,135],
  ['ASCENDO','TBR','AR102HD','11.00R20',18,'152/149',3550,3250,135],
  ['ASCENDO','TBR','AR102HD','12.00R20',18,'154/151',3750,3450,120],
  ['ASCENDO','TBR','AR112','7.50R16',14,'122/120',1510,1440,102],
  ['ASCENDO','TBR','AR896','7.50R16',14,'122/120',1500,1400,111],
  ['ASCENDO','TBR','AR896','10.00R20',18,'149/146',3250,3000,135],
  ['ASCENDO','TBR','AR896','11.00R20',16,'150/147',3350,3075,120],
  ['ASCENDO','TBR','AR698','11R22.5',16,'146/143',3000,2725,120],
  ['ASCENDO','TBR','AR316','7.50R16',14,'122/120',1510,1440,102],
  ['ASCENDO','TBR','AR3137','7.50R16',14,'122/120',1510,1440,102],
  ['ASCENDO','TBR','AR3137','10.00R20',18,'149/146',3250,3000,135],
  ['ASCENDO','TBR','AR3137','11.00R20',18,'152/149',3350,3075,120],
  ['ASCENDO','TBR','AR667','11.00R20',18,'152/149',3550,3250,135],
  ['ASCENDO','Bias','AB635','10.00-20',16,'146/144',3000,2800,110],
  ['ASCENDO','Bias','AB635','11.00-20',16,'150/145',3350,2900,110],
  ['ASCENDO','Bias','AB111','7.50-16',14,'122/118',1500,1320,105],
  ['ASCENDO','Bias','AB111','10.00-20',18,'150/145',3350,2900,120],
  ['ASCENDO','Bias','AB313','7.50-16',14,'122/118',1500,1320,105],
  ['ASCENDO','Bias','AB313','10.00-20',18,'150/145',3350,2900,120],
  ['ASCENDO','Bias','AB316','10.00-20',18,'150/145',3350,2900,125],
  ['ASCENDO','Bias','AB112','11.00-20',18,'153/148',3650,3150,125],
  ['ASCENDO','Bias','AB535','11.00-20',18,'153/148',3650,3150,125],
  ['TECHKING','TBR','ETFN U','10.00R20',16,'146/143',3000,2725,120],
  ['TECHKING','TBR','ETFN U','11.00R20',16,'150/147',3350,3075,120],
  ['TECHKING','TBR','ETFN U','12.00R20',20,'156/153',4000,3650,130],
  ['TECHKING','TBR','ETFN U','12.00R24',20,'160/157',4500,4125,130],
  ['TECHKING','TBR','ETOD','7.50R16',14,'122/118',1500,1320,110],
  ['TECHKING','TBR','ETOD','12.00R20',20,'156/153',4000,3650,130],
  ['TECHKING','TBR','ETOT','11.00R20',16,'150/147',3350,3075,120],
  ['TECHKING','TBR','ETOT','12.00R20',20,'156/153',4000,3650,130],
  ['TECHKING','TBR','ETOT','12.00R24',20,'160/156',4500,4000,125],
  ['TECHKING','TBR','ETOT','12.00R24',24,'164/161',5000,4625,130],
  ['TECHKING','TBR','SUPER ETOT','12.00R24',20,'160/157',4500,4125,130],
  ['TECHKING','TBR','SUPER ETOT','13R22.5',18,'154/150',3750,3350,120],
  ['TECHKING','TBR','TKAL','7.50R16',14,'122/118',1500,1320,110],
  ['TECHKING','TBR','TKAL III','10.00R20',16,'146/143',3000,2725,120],
  ['TECHKING','TBR','TKAM S','7.50R16',14,'122/120',1500,1400,110],
  ['TECHKING','TBR','TKAM S','8.25R16',14,'126/122',1700,1500,110],
  ['TECHKING','TBR','TKAM S','11R22.5',16,'146/143',3000,2725,120],
  ['TECHKING','TBR','TKAM HD','10.00R20',18,'149/146',3250,3000,135],
  ['TECHKING','TBR','TKAM II S','11.00R20',16,'150/147',3350,3075,135],
  ['TECHKING','TBR','TKAM III XL','12.00R24',20,'160/157',4500,4125,130],
  ['TECHKING','TBR','TKSH III','295/80R22.5',18,'152/148',3550,3150,120],
  ['TECHKING','TBR','SUPER AM S','10.00R20',16,'146/143',3000,2725,120],
  ['TECHKING','TBR','SUPER AM S','11.00R20',16,'150/147',3350,3075,120],
  ['TECHKING','TBR','TKDM HD','10.00R20',16,'146/143',3000,2725,120],
  ['TECHKING','TBR','TKDM S','7.50R16',14,'122/118',1500,1320,110],
  ['TECHKING','TBR','ETRF','11.00R20',16,'150/147',3350,3075,120],
] as [string,string,string,string,number,string,number,number,number][])
  .map(r => ({ brand: r[0], cat: r[1], pattern: r[2], size: r[3], pr: r[4], li: r[5], single: r[6], dual: r[7], psi: r[8] }));

/* ── OTR : 속도-하중 포인트 ([[속도km/h, 최대하중kg], ...]) ─────────────────── */
interface Otr { brand: string; pattern: string; app: string; size: string; pr: number | null; pts: [number, number][] }
const OTR: Otr[] = ([
  ['ASCENDO','AE-803','로더·도저','17.5-25',20,[[10,8250],[50,5000]]],
  ['ASCENDO','AE-803','로더·도저','20.5-25',20,[[10,9500],[50,6000]]],
  ['ASCENDO','AE-803','로더·도저','23.5-25',20,[[10,10900],[50,9500]]],
  ['ASCENDO','AE-803','로더·도저','26.5-25',32,[[10,17000],[50,11200]]],
  ['ASCENDO','AS432','그레이더','13.00-24',14,[[10,6150],[50,3000]]],
  ['ASCENDO','AE-804','덤프·리지드','13.00-25',32,[[10,9750],[50,5375]]],
  ['ASCENDO','AE-804','덤프·리지드','14.00-25',36,[[10,11500],[50,6500]]],
  ['ASCENDO','AE-804','덤프·리지드','16.00-25',40,[[10,14500],[50,8000]]],
  ['TECHKING','PROADT','덤프·ADT','23.5R25',null,[[50,li(185)],[10,li(201)]]],
  ['TECHKING','PROADT','덤프·ADT','26.5R25',null,[[50,li(193)],[10,li(209)]]],
  ['TECHKING','PROADT','덤프·ADT','29.5R25',null,[[50,li(200)],[10,li(218)]]],
  ['TECHKING','ETADT','덤프·ADT','29.5R29',null,[[50,li(202)]]],
  ['TECHKING','ETADT','덤프·ADT 플로테이션','750/65R25',null,[[50,li(190)],[10,li(202)]]],
  ['TECHKING','ETADT','덤프·ADT 플로테이션','875/65R29',null,[[50,li(203)],[10,li(214)]]],
  ['TECHKING','ETOH','덤프·리지드/광산','14.00R25',null,[[50,li(169)],[30,li(184)]]],
  ['TECHKING','ETOH','덤프·리지드/광산','18.00R25',null,[[50,li(190)]]],
  ['TECHKING','ETOH','덤프·리지드/광산','480/95R29',null,[[50,li(190)],[10,li(204)]]],
  ['TECHKING','MATE-S L3','로더·도저','17.5R25',null,[[50,li(167)],[10,li(182)]]],
  ['TECHKING','MATE-S L3','로더·도저','20.5R25',null,[[50,li(177)],[10,li(193)]]],
  ['TECHKING','MATE-S L3','로더·도저','23.5R25',null,[[50,li(185)],[10,li(201)]]],
  ['TECHKING','MATE-S L3','로더·도저','26.5R25',null,[[50,li(193)],[10,li(209)]]],
  ['TECHKING','ETGRADER','그레이더','16.00R24',null,[[40,li(163)]]],
  ['TECHKING','MATE G2','그레이더','14.00R24',null,[[40,li(155)]]],
] as [string,string,string,string,number|null,[number,number|null][]][])
  .map(r => ({ brand: r[0], pattern: r[1], app: r[2], size: r[3], pr: r[4], pts: r[5].filter(p => p[1] != null) as [number, number][] }));

/* ── 농기계 AGR ───────────────────────────────────────────────────────────── */
interface Agr { brand: string; pattern: string; app: string; size: string; pr: number; load: number; psi: number; speed: number }
const AGR: Agr[] = ([
  ['ASCENDO','R-1','트랙터','7.50-16',8,870,54,30],
  ['ASCENDO','R-1','트랙터','7.50-18',8,670,36,30],
  ['ASCENDO','R-1','트랙터','12.4-24',12,1750,48,30],
  ['ASCENDO','R-1','트랙터','13.6-24',12,2180,52,30],
  ['ASCENDO','R-1','트랙터','14.9-24',12,2120,35,30],
  ['ASCENDO','R-1','트랙터','18.4-30',12,3150,33,30],
  ['ASCENDO','R-1','트랙터','18.4-34',12,3375,33,30],
  ['ASCENDO','R-1','콤바인·SH216','16.9-24',12,3250,38,30],
  ['ASCENDO','R-1','콤바인·SH216','16.9-28',12,3550,38,30],
  ['ASCENDO','R-1','트랙터·SH111','20.8-38',12,3850,46,30],
  ['ASCENDO','R4-B','백호','12.5/80-18',12,2650,54,30],
] as [string,string,string,string,number,number,number,number][])
  .map(r => ({ brand: r[0], pattern: r[1], app: r[2], size: r[3], pr: r[4], load: r[5], psi: r[6], speed: r[7] }));

/* ── 인도네시아 트럭 분류 (Aptrindo·Kemenhub · 1.1=축당 2본, 2.2=축당 4본) ── */
type GroupKey = 'steer' | 'drive' | 'trailer';
interface TruckClass { name: string; cfg: string; gvw: number; steer: { tires: number; share: number }; drive: { tires: number; dual: boolean; share: number }; trailer?: { tires: number; share: number }; layout: [GroupKey, number][] }
const TRUCKCLASS: Record<string, TruckClass> = {
  engkel:  { name: 'Engkel / CDE', cfg: '4 ban · 1.1-1.1 · 4x2', gvw: 7500,  steer: { tires: 2, share: 0.40 }, drive: { tires: 2, dual: false, share: 0.60 }, layout: [['steer',2],['drive',2]] },
  double:  { name: 'Double / CDD', cfg: '6 ban · 1.1-2.2 · 4x2', gvw: 13000, steer: { tires: 2, share: 0.30 }, drive: { tires: 4, dual: true,  share: 0.70 }, layout: [['steer',2],['drive',4]] },
  tronton: { name: 'Tronton', cfg: '10 ban · 1.1-2.2-2.2 · 6x4', gvw: 26000, steer: { tires: 2, share: 0.25 }, drive: { tires: 8, dual: true,  share: 0.75 }, layout: [['steer',2],['drive',4],['drive',4]] },
  trintin: { name: 'Trintin', cfg: '8 ban · 1.1-1.1-2.2 · 6x2',  gvw: 24000, steer: { tires: 4, share: 0.40 }, drive: { tires: 4, dual: true,  share: 0.60 }, layout: [['steer',2],['steer',2],['drive',4]] },
  trinton: { name: 'Trinton', cfg: '12 ban · 1.1-1.1-2.2-2.2 · 8x4', gvw: 31000, steer: { tires: 4, share: 0.35 }, drive: { tires: 8, dual: true, share: 0.65 }, layout: [['steer',2],['steer',2],['drive',4],['drive',4]] },
  bus: { name: 'Bus', cfg: '6 ban · 1.1-2.2 · 6x2', gvw: 17500, steer: { tires: 2, share: 0.37 }, drive: { tires: 4, dual: true, share: 0.63 }, layout: [['steer',2],['drive',4]] },
  trailer20: { name: 'Trailer 20ft', cfg: '트랙터헤드 6x4 + 세미 2축', gvw: 34000, steer: { tires: 2, share: 0.15 }, drive: { tires: 8, dual: true, share: 0.40 }, trailer: { tires: 8, share: 0.45 }, layout: [['steer',2],['drive',4],['drive',4],['trailer',4],['trailer',4]] },
  trailer: { name: 'Trailer 40ft', cfg: '트랙터헤드 6x4 + 세미 3축', gvw: 45000, steer: { tires: 2, share: 0.15 }, drive: { tires: 8, dual: true, share: 0.35 }, trailer: { tires: 12, share: 0.50 }, layout: [['steer',2],['drive',4],['drive',4],['trailer',4],['trailer',4],['trailer',4]] },
};
/* ── 차량 프리셋 (지게차·중장비·광산·농기계) ─────────────────────────────── */
interface Preset { name: string; axles: number; tires: number; config: string; fill?: Record<string, number | string>; axleLoad?: number; tcnt?: number }
const VEHICLES: Record<string, Preset[]> = {
  forklift: [
    { name: '지게차 2.5t (Toyota 8FG25급)', axles: 2, tires: 4, config: '전축(하중) 2본 + 후축(조향) 2본', fill: { empty: 3900,  payload: 2500,  rear: 2, front: 2, reardist: '15/60', frontdist: '85/40' } },
    { name: '지게차 3t (Komatsu FD30급)',   axles: 2, tires: 4, config: '전축(하중) 2본 + 후축(조향) 2본', fill: { empty: 4500,  payload: 3000,  rear: 2, front: 2, reardist: '15/60', frontdist: '85/40' } },
    { name: '지게차 5t (Komatsu FD50급)',   axles: 2, tires: 4, config: '전축(하중) 2본 + 후축(조향) 2본', fill: { empty: 7900,  payload: 5000,  rear: 2, front: 2, reardist: '15/60', frontdist: '85/40' } },
    { name: '지게차 7t',                    axles: 2, tires: 4, config: '전축(하중) 2본 + 후축(조향) 2본', fill: { empty: 10500, payload: 7000,  rear: 2, front: 2, reardist: '15/60', frontdist: '85/40' } },
    { name: '지게차 10t',                   axles: 2, tires: 6, config: '전축(하중) 4본 + 후축(조향) 2본', fill: { empty: 14500, payload: 10000, rear: 2, front: 4, reardist: '15/60', frontdist: '85/40' } },
  ],
  heavy: [
    { name: '휠로더 3㎥ (Komatsu WA380급)', axles: 2, tires: 4, config: '전축 2본 + 후축 2본', fill: { empty: 18000, payload: 6000, rear: 2, front: 2, reardist: '40/55', frontdist: '60/45' } },
    { name: '휠로더 3.5㎥ (CAT 966급)',     axles: 2, tires: 4, config: '전축 2본 + 후축 2본', fill: { empty: 23000, payload: 7000, rear: 2, front: 2, reardist: '40/55', frontdist: '60/45' } },
    { name: '휠로더 5㎥ (CAT 980급)',       axles: 2, tires: 4, config: '전축 2본 + 후축 2본', fill: { empty: 31000, payload: 9000, rear: 2, front: 2, reardist: '40/55', frontdist: '60/45' } },
    { name: '모터그레이더 (CAT 140급)',     axles: 3, tires: 6, config: '전축 2본 + 후축 4본(탠덤)', fill: { empty: 18000, payload: 0, rear: 4, front: 2, reardist: '55/55', frontdist: '45/45' } },
  ],
  mining: [
    { name: '리지드덤프 ~40t (중형 광산덤프)',      axles: 2, tires: 6, config: '조향 2본 + 구동 4본(복륜)', fill: { empty: 30000, payload: 40000, rear: 4, front: 2, reardist: '67/53', frontdist: '33/47' } },
    { name: '리지드덤프 ~55t (Komatsu HD465급)',   axles: 2, tires: 6, config: '조향 2본 + 구동 4본(복륜)', fill: { empty: 40000, payload: 55000, rear: 4, front: 2, reardist: '67/53', frontdist: '33/47' } },
    { name: '리지드덤프 ~90t (CAT 777급)',         axles: 2, tires: 6, config: '조향 2본 + 구동 4본(복륜)', fill: { empty: 65000, payload: 90000, rear: 4, front: 2, reardist: '67/53', frontdist: '33/47' } },
    { name: 'ADT 굴절식 ~29t (CAT 730급)',         axles: 3, tires: 6, config: '전축 2본 + 후축 4본(2축)', fill: { empty: 22000, payload: 28000, rear: 4, front: 2, reardist: '60/50', frontdist: '40/50' } },
    { name: 'ADT 굴절식 ~39t (Volvo A40급)',       axles: 3, tires: 6, config: '전축 2본 + 후축 4본(2축)', fill: { empty: 31000, payload: 39000, rear: 4, front: 2, reardist: '60/50', frontdist: '40/50' } },
  ],
  agri: [
    { name: '트랙터 90HP (Kubota M9급)', axles: 2, tires: 4, config: '전축 2본 + 후축(구동) 2본', axleLoad: 4000, tcnt: 2 },
    { name: '트랙터 110HP (JD 6110급)',  axles: 2, tires: 4, config: '전축 2본 + 후축(구동) 2본', axleLoad: 5000, tcnt: 2 },
    { name: '트랙터 140HP',              axles: 2, tires: 4, config: '전축 2본 + 후축(구동) 2본', axleLoad: 6000, tcnt: 2 },
    { name: '콤바인 하베스터',           axles: 2, tires: 4, config: '전축(구동) 2본 + 후축(조향) 2본', axleLoad: 3500, tcnt: 2 },
  ],
};

/* ── 상태 ─────────────────────────────────────────────────────────────────── */
type Tab = 'truck' | 'forklift' | 'heavy' | 'mining' | 'agri';
const TABS: { key: Tab; label: string }[] = [
  { key: 'truck',    label: '트럭·버스' },
  { key: 'forklift', label: '지게차' },
  { key: 'heavy',    label: '중장비' },
  { key: 'mining',   label: '광산 덤프' },
  { key: 'agri',     label: '농기계' },
];
const tab = ref<Tab>('truck');

// 타이어 규격 목록 (TBR/Bias 고유 사이즈 · 정렬)
const TBR_SIZES = [...new Set(TBR.map(x => x.size))].sort();
// 총중량 GVW = 공차중량(tare) + 적재량(payload)
const t  = reactive({ cls: '', customName: '', size: 'all', tare: 4500, payload: 8500, st: 2, ss: 30, dt: 4, ds: 70, ddual: '1', brand: 'all',
  cur: 'Rp', price: 3000000, life: 120000, retread: '1', rcost: 1200000, rlife: 90000, rcount: 1, fuelp: 13000, econ: 3, vinfo: '' });
interface TkphState { veh: string; brand: string; empty: number; payload: number; rear: number; front: number; reardist: string; frontdist: string; n: number; l: number; h: number; tkph: number; vinfo: string }
const fk = reactive<TkphState>({ veh: '', brand: 'all', empty: 4200,  payload: 3000,  rear: 2, front: 2, reardist: '15/60', frontdist: '85/40', n: 60, l: 0.3, h: 8,  tkph: 0, vinfo: '' });
const hv = reactive<TkphState>({ veh: '', brand: 'all', empty: 24000, payload: 8000,  rear: 2, front: 2, reardist: '40/55', frontdist: '60/45', n: 80, l: 0.5, h: 10, tkph: 0, vinfo: '' });
const mn = reactive<TkphState>({ veh: '', brand: 'all', empty: 35000, payload: 40000, rear: 4, front: 2, reardist: '67/53', frontdist: '33/47', n: 20, l: 6,   h: 20, tkph: 0, vinfo: '' });
const ag = reactive({ veh: '', axle: 5000, count: 2, cur: 'Rp', price: 2500000, life: 6000, retread: '0', rcost: 900000, rlife: 4000, rcount: 0, fuelp: 13000, econ: 4, vinfo: '' });

const resultHtml = ref('');
let truckTrailer: { tires: number; share: number } | null = null;
let truckLayout: [GroupKey, number][] | null = null;
let truckName = '';

/* ── 공통 유틸 ─────────────────────────────────────────────────────────────── */
const fmt = (n: number) => Math.round(n).toLocaleString('en-US');
type Cls = 'pass' | 'warn' | 'over';
const STATUS_CLS: Record<Cls, string> = {
  pass: 'text-emerald-500 bg-emerald-500/10', warn: 'text-amber-500 bg-amber-500/10', over: 'text-red-500 bg-red-500/10',
};
const BAR = { pass: '#10b981', warn: '#f59e0b', over: '#ef4444' } as const;

function verdict(load: number, cap: number): { pct: number; cls: Cls; label: string } {
  if (!cap) return { pct: 0, cls: 'over', label: '해당없음' };
  const pct = load / cap * 100;
  if (pct <= 90)  return { pct, cls: 'pass', label: '적합' };
  if (pct <= 100) return { pct, cls: 'warn', label: '주의 (여유부족)' };
  return { pct, cls: 'over', label: '부적합 (초과)' };
}

// OTR 속도-하중 : 운행속도 이상 정격속도 중 최근접(보수적) 하중
function loadAtSpeed(pts: [number, number][], v: number) {
  const s = [...pts].sort((a, b) => a[0] - b[0]);
  const ge = s.filter(p => p[0] >= v);
  if (ge.length) return { kg: ge[0][1], sp: ge[0][0], over: false };
  const top = s[s.length - 1];
  return { kg: top[1], sp: top[0], over: true };
}
function rankOTR(pool: Otr[], per: number, v: number) {
  return pool.map(o => { const L = loadAtSpeed(o.pts, v); return { t: o, cap: L.kg, sp: L.sp, over: L.over }; })
    .sort((a, b) => {
      const af = per <= a.cap ? 0 : 1, bf = per <= b.cap ? 0 : 1;
      if (af !== bf) return af - bf;
      return (per / a.cap) > (per / b.cap) ? -1 : 1;
    });
}
function sortByFit<T extends Record<string, unknown>>(list: T[], load: number, capKey: keyof T) {
  return [...list].sort((a, b) => {
    const ac = a[capKey] as number | null, bc = b[capKey] as number | null;
    if (ac == null && bc == null) return 0;
    if (ac == null) return 1; if (bc == null) return -1;
    const ap = load / ac, bp = load / bc;
    const af = ap <= 1 ? 0 : 1, bf = bp <= 1 ? 0 : 1;
    if (af !== bf) return af - bf;
    return bp - ap;
  });
}

/* ── 결과 HTML 빌더 ───────────────────────────────────────────────────────── */
function tireRow(name: string, sub: string, cap: number, capLabel: string, load: number, meta: string) {
  const v = verdict(load, cap);
  const w = Math.min(v.pct, 100);
  return `<div class="rounded-xl border ${v.cls === 'pass' ? 'border-emerald-500/40 bg-emerald-500/5' : 'border-border bg-card'} p-3 mb-2">
    <div class="flex justify-between items-baseline gap-2">
      <div class="text-sm font-bold">${name} <span class="text-xs font-medium text-muted-foreground ml-1">${sub}</span></div>
      <span class="text-[11px] font-bold px-2 py-0.5 rounded-full ${STATUS_CLS[v.cls]}">${v.label}</span>
    </div>
    <div class="text-xs text-muted-foreground mt-1">${capLabel} <b class="text-foreground tabular-nums">${fmt(cap)}</b> kg · 사용률 <b class="text-foreground tabular-nums">${v.pct ? v.pct.toFixed(0) : '—'}%</b></div>
    <div class="h-2 rounded bg-muted mt-2 overflow-hidden"><i style="display:block;height:100%;width:${w}%;background:${BAR[v.cls]}"></i></div>
    <div class="flex justify-between text-[11px] text-muted-foreground mt-1"><span>하중 ${fmt(load)}kg</span><span>용량 ${fmt(cap)}kg</span></div>
    ${meta ? `<div class="text-[11px] text-muted-foreground mt-1.5">${meta}</div>` : ''}
  </div>`;
}
function renderTires(title: string, rows: string) {
  return `<h3 class="text-xs font-semibold mt-4 mb-2 flex items-center gap-2"><span class="w-3 h-3 rounded bg-primary/30 border border-primary/50"></span>${title}</h3>${rows ||
    '<div class="rounded-xl border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-600 dark:text-amber-500">해당 조건을 충족하는 사이즈가 카탈로그에 없습니다. 입력값을 확인하거나 사이즈 확장을 검토하세요.</div>'}`;
}
function reqBox(k: string, val: number, formula: string, metrics: [string, string][]) {
  const m = metrics.map(x => `<div class="flex-1 min-w-28 rounded-lg border border-border bg-card p-2.5"><div class="text-[11px] text-muted-foreground">${x[0]}</div><div class="text-base font-bold tabular-nums">${x[1]}</div></div>`).join('');
  return `<div class="rounded-xl bg-muted/50 border border-border p-4 mb-4">
    <div class="text-xs font-semibold text-muted-foreground">${k}</div>
    <div class="text-3xl font-extrabold tabular-nums">${fmt(val)} <span class="text-sm font-semibold text-muted-foreground">kg / 본</span></div>
    <div class="text-xs text-muted-foreground mt-1">${formula}</div>
    <div class="flex gap-2 flex-wrap mt-3">${m}</div>
  </div>`;
}
function tkphBox(avgLoadT: number, speed: number, rated: number, note: string) {
  const tkph = avgLoadT * speed;
  let verd = '';
  if (rated > 0) {
    const ok = tkph <= rated, m = (rated - tkph) / rated * 100;
    verd = `<div class="mt-2 px-3 py-2 rounded-lg text-xs font-bold ${ok ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500'}">
      ${ok ? '✔ 적합 (열적 여유 확보)' : '✘ 부적합 (정격 초과 → 발열 위험)'} · 정격 <span class="tabular-nums">${fmt(rated)}</span> vs 운행 <span class="tabular-nums">${tkph.toFixed(0)}</span> · 여유 <span class="tabular-nums">${m.toFixed(0)}%</span></div>`;
  }
  return `<div class="rounded-xl border border-primary/30 bg-primary/5 p-4 mb-4">
    <div class="text-xs font-bold">운행 TKPH (Ton·Kilometer per Hour)</div>
    <div class="text-2xl font-extrabold tabular-nums">${tkph.toFixed(0)} <span class="text-sm font-semibold text-muted-foreground">ton·km/h</span></div>
    <div class="text-[11px] text-muted-foreground mt-1.5">${note}<br>▸ 적정 타이어는 <b>정격 TKPH ≥ 운행 TKPH</b> 여야 열적 안전. 정격값은 데이터북(p.64~65)에서 확인해 입력하세요.</div>
    ${verd}</div>`;
}
function cpkBox(p: { cur: string; price: number; life: number; retread: boolean; rCost: number; rLife: number; rCount: number; fuelP: number; econ: number }) {
  const base = p.life > 0 ? p.price / p.life : 0;
  let cpkTire = base, tl = p.life, save = '';
  if (p.retread && p.rCount > 0 && p.rLife > 0) {
    const tc = p.price + p.rCount * p.rCost; tl = p.life + p.rCount * p.rLife; cpkTire = tc / tl;
    save = `<div class="mt-2 px-3 py-2 rounded-lg bg-emerald-500/10 text-emerald-500 font-bold text-xs">
      ♻ 재생 ${p.rCount}회 적용 → 타이어 CPK <span class="tabular-nums">${((base - cpkTire) / base * 100).toFixed(0)}%</span> 절감 · 총수명 ${fmt(tl)} km</div>`;
  }
  const cpkFuel = p.econ > 0 ? p.fuelP / p.econ : 0;
  const total = cpkTire + cpkFuel;
  const c = (v: number) => p.cur + ' ' + Math.round(v).toLocaleString('en-US');
  return `<div class="rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-4 mb-4">
    <div class="text-xs font-bold">CPK · 주행거리당 비용 (Cost per Kilometer)</div>
    <div class="text-2xl font-extrabold tabular-nums">${c(total)} <span class="text-sm font-semibold text-muted-foreground">/ km</span></div>
    <div class="flex gap-2 flex-wrap mt-3">
      <div class="flex-1 min-w-28 rounded-lg border border-border bg-card p-2.5"><div class="text-[11px] text-muted-foreground">타이어 CPK (마모)</div><div class="text-base font-bold tabular-nums">${c(cpkTire)}</div></div>
      <div class="flex-1 min-w-28 rounded-lg border border-border bg-card p-2.5"><div class="text-[11px] text-muted-foreground">연료비 / km</div><div class="text-base font-bold tabular-nums">${c(cpkFuel)}</div></div>
      <div class="flex-1 min-w-28 rounded-lg border border-border bg-card p-2.5"><div class="text-[11px] text-muted-foreground">${p.retread ? '총수명(재생포함)' : '타이어 수명'}</div><div class="text-base font-bold tabular-nums">${fmt(tl)} km</div></div>
    </div>${save}
    <div class="text-[11px] text-muted-foreground mt-2">타이어 CPK = 총 타이어비용 ÷ 총 주행수명 · 연료비/km = 연료가 ÷ 연비.</div>
  </div>`;
}
function errBox() {
  resultHtml.value = `<div class="rounded-xl border border-border bg-card p-8 text-center text-sm text-muted-foreground">입력값을 확인해 주세요. 필수 항목은 0보다 커야 합니다.</div>`;
}

/* ── 트럭 계산 ────────────────────────────────────────────────────────────── */
function applyTruckClass(key: string) {
  if (!key) { truckTrailer = null; truckLayout = null; truckName = ''; t.vinfo = ''; run(); return; }
  const c = TRUCKCLASS[key];
  // GVW를 공차중량(≈35% 관행 비율) + 적재량으로 분할 채움 — 참고 기본값(수정 가능)
  t.tare = Math.round(c.gvw * 0.35 / 100) * 100;
  t.payload = c.gvw - t.tare;
  t.st = c.steer.tires; t.ss = Math.round(c.steer.share * 100);
  t.dt = c.drive.tires; t.ds = Math.round(c.drive.share * 100);
  t.ddual = c.drive.dual ? '1' : '0';
  truckTrailer = c.trailer ?? null; truckLayout = c.layout; truckName = c.name;
  const tot = c.layout.reduce((s, a) => s + a[1], 0);
  // 표기 순서: 총 타이어 → 축수 → 구성 ('N ban' 접두는 총 타이어와 중복이라 제거)
  const cfgRest = c.cfg.replace(/^\d+ ban · /, '');
  t.vinfo = `<span class="text-muted-foreground">총 타이어 ${tot}본 · 축수 ${c.layout.length} · ${cfgRest}</span>`;
  run();
}
function truckSVG(axles: { group: GroupKey; x: number; util: number; cls: Cls; dual: boolean }[], gvw: number, hasTrailer: boolean) {
  const W = 460, gy = 165;
  const body = hasTrailer
    ? `<rect x="40" y="72" width="58" height="58" rx="4" fill="none" stroke="currentColor" opacity=".5"/>
       <rect x="98" y="120" width="110" height="8" fill="currentColor" opacity=".3"/>
       <rect x="200" y="54" width="248" height="74" rx="4" fill="none" stroke="currentColor" opacity=".5"/>
       <circle cx="198" cy="128" r="4" fill="currentColor" opacity=".6"/>`
    : `<rect x="40" y="74" width="56" height="56" rx="4" fill="none" stroke="currentColor" opacity=".5"/>
       <rect x="100" y="52" width="322" height="78" rx="4" fill="none" stroke="currentColor" opacity=".5"/>`;
  let wheels = '';
  const gname: Record<GroupKey, string> = { steer: '조향', drive: '구동', trailer: '트레일러' };
  axles.forEach(a => {
    wheels += `<circle cx="${a.x}" cy="${gy}" r="15" fill="currentColor" opacity=".75"/><circle cx="${a.x}" cy="${gy}" r="6" fill="currentColor" opacity=".35"/>`;
    if (a.dual) wheels += `<circle cx="${a.x}" cy="${gy}" r="15" fill="none" stroke="currentColor" stroke-width="2.5" stroke-dasharray="2 3" opacity=".6"/>`;
    wheels += `<rect x="${a.x - 16}" y="${gy + 19}" width="32" height="15" rx="3" fill="${BAR[a.cls]}"/>
      <text x="${a.x}" y="${gy + 30}" font-size="10" font-weight="700" fill="#fff" text-anchor="middle">${a.util.toFixed(0)}%</text>
      <text x="${a.x}" y="${gy - 19}" font-size="9" fill="currentColor" opacity=".7" text-anchor="middle">${gname[a.group]}</text>`;
  });
  return `<svg viewBox="0 0 ${W} 210" xmlns="http://www.w3.org/2000/svg" style="width:100%;height:auto">
    <line x1="18" y1="${gy + 19}" x2="${W - 18}" y2="${gy + 19}" stroke="currentColor" opacity=".25" stroke-width="2"/>
    ${body}${wheels}
    <text x="${W - 22}" y="40" font-size="11" fill="currentColor" opacity=".7" text-anchor="end">GVW ${fmt(gvw)} kg</text>
  </svg>`;
}
function calcTruck() {
  const gvw = (+t.tare || 0) + (+t.payload || 0), st = +t.st, ss = +t.ss / 100, dt = +t.dt, ds = +t.ds / 100;
  const ddual = t.ddual === '1';
  if (gvw <= 0 || st <= 0 || dt <= 0) return errBox();
  const groups: { group: GroupKey; label: string; tires: number; share: number; dual: boolean }[] = [
    { group: 'steer', label: '전축(조향)', tires: st, share: ss, dual: false },
    { group: 'drive', label: '후축(구동)', tires: dt, share: ds, dual: ddual },
  ];
  if (truckTrailer) groups.push({ group: 'trailer', label: '트레일러', tires: truckTrailer.tires, share: truckTrailer.share, dual: true });

  // 타이어 규격 선택 시 해당 사이즈만 후보로
  const pool = t.size === 'all' ? TBR : TBR.filter(x => x.size === t.size);
  const utilOf = (x: Tbr) => Math.max(...groups.map(g => (gvw * g.share / g.tires) / (g.dual ? x.dual : x.single) * 100));
  const tier = (u: number) => u <= 90 ? 0 : u <= 100 ? 1 : 2;
  const ranked = pool.map(x => ({ t: x, u: utilOf(x) })).sort((a, b) => {
    const ta = tier(a.u), tb = tier(b.u); if (ta !== tb) return ta - tb;
    return ta === 0 ? b.u - a.u : a.u - b.u;
  });
  const rec = ranked.length ? ranked[0].t : null;

  const gData = groups.map(g => {
    const load = gvw * g.share, perTire = load / g.tires, cap = rec ? (g.dual ? rec.dual : rec.single) : 0;
    const u = cap ? perTire / cap * 100 : 0;
    const cls: Cls = u <= 90 ? 'pass' : u <= 100 ? 'warn' : 'over';
    return { ...g, load, perTire, cap, u, cls };
  });

  const layout = truckLayout ?? ([['steer', st], ['drive', dt]] as [GroupKey, number][]);
  const hasTrailer = !!truckTrailer;
  const axles: { group: GroupKey; x: number; util: number; cls: Cls; dual: boolean }[] = [];
  const dbase = hasTrailer ? 170 : 400;
  layout.filter(a => a[0] === 'steer').forEach((_, i) => axles.push({ group: 'steer', x: 80 + i * 30, util: 0, cls: 'pass', dual: false }));
  layout.filter(a => a[0] === 'drive').forEach((_, i) => axles.push({ group: 'drive', x: dbase - i * 32, util: 0, cls: 'pass', dual: false }));
  layout.filter(a => a[0] === 'trailer').forEach((_, i) => axles.push({ group: 'trailer', x: 300 + i * 40, util: 0, cls: 'pass', dual: false }));
  const gmap: Partial<Record<GroupKey, typeof gData[number]>> = { steer: gData[0], drive: gData[1], trailer: gData[2] };
  axles.forEach(a => { const g = gmap[a.group]; if (g) { a.util = g.u; a.cls = g.cls; a.dual = g.dual; } });

  const rows = gData.map(g => `<tr class="border-b border-border/50"><td class="px-2 py-1.5 text-left font-semibold">${g.label}</td>
    <td class="px-2 py-1.5 text-right tabular-nums">${fmt(g.load)}</td>
    <td class="px-2 py-1.5 text-right tabular-nums">${g.tires}본</td>
    <td class="px-2 py-1.5 text-right tabular-nums">${fmt(g.perTire)}</td>
    <td class="px-2 py-1.5 text-right tabular-nums">${g.cap ? fmt(g.cap) : '-'}</td>
    <td class="px-2 py-1.5 text-right tabular-nums font-bold ${g.cls === 'pass' ? 'text-emerald-500' : g.cls === 'warn' ? 'text-amber-500' : 'text-red-500'}">${g.u ? g.u.toFixed(0) + '%' : '-'}</td></tr>`).join('');
  const oCls: Cls = gData.some(g => g.cls === 'over') ? 'over' : gData.some(g => g.cls === 'warn') ? 'warn' : 'pass';
  const oTxt = oCls === 'over' ? '✘ 하중 초과 → 더 큰 규격 필요' : oCls === 'warn' ? '⚠ 여유 부족 (90% 초과)' : '✔ 적합';

  const cpk = cpkBox({ cur: t.cur, price: +t.price, life: +t.life, retread: t.retread === '1', rCost: +t.rcost, rLife: +t.rlife, rCount: +t.rcount, fuelP: +t.fuelp, econ: +t.econ });
  const drivePer = gvw * groups[1].share / groups[1].tires;
  const alt = ranked.slice(0, 6).map(r => tireRow(`${r.t.pattern} · ${r.t.size}`,
    `${r.t.brand} ${r.t.cat} · ${r.t.pr}PR · LI ${r.t.li}`,
    r.t.dual, '복륜 용량', drivePer, `단륜 ${fmt(r.t.single)} kg · 공기압 ${r.t.psi} psi`)).join('');

  resultHtml.value = `<div class="rounded-xl border border-border bg-card p-4">
    <!-- 권장 타이어(좌 50%) + 차량 다이어그램(우 50%) 1행 -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-3 items-stretch">
      <div class="rounded-xl bg-muted/50 border border-border p-4">
        <div class="text-xs font-semibold text-muted-foreground">권장 타이어 · ${truckName || t.customName.trim() || '수동 입력'}</div>
        <div class="text-xl font-extrabold">${rec ? rec.pattern + ' · ' + rec.size : '적합 규격 없음'}</div>
        ${rec ? `<div class="text-xs text-muted-foreground mt-1">${rec.brand} ${rec.cat} · ${rec.pr}PR · LI ${rec.li} · 단륜 ${fmt(rec.single)} / 복륜 ${fmt(rec.dual)} kg</div>` : ''}
        <div class="mt-2 px-3 py-2 rounded-lg font-bold text-xs ${STATUS_CLS[oCls]}">${oTxt}</div>
      </div>
      <div class="rounded-xl border border-border bg-muted/30 p-3 text-muted-foreground flex items-center">${truckSVG(axles, gvw, hasTrailer)}</div>
    </div>
    <div class="overflow-x-auto"><table class="w-full text-xs border-collapse">
      <tr class="bg-muted text-muted-foreground"><th class="px-2 py-1.5 text-left">축 위치</th><th class="px-2 py-1.5 text-right">축하중</th><th class="px-2 py-1.5 text-right">타이어</th><th class="px-2 py-1.5 text-right">하중/본</th><th class="px-2 py-1.5 text-right">용량</th><th class="px-2 py-1.5 text-right">사용률</th></tr>
      ${rows}
    </table></div>
    ${cpk}
    ${renderTires('대체 후보 · 구동축 복륜 기준', alt)}
  </div>`;
}

/* ── TKPH 공통 계산 (지게차·중장비·광산) ─────────────────────────────────── */
function calcTKPHTab(s: TkphState, poolPred: ((o: Otr) => boolean) | null, noPoolMsg: string) {
  const empty = +s.empty, pay = +s.payload, rc = +s.rear, fc = +s.front, n = +s.n, l = +s.l, h = +s.h, rated = +s.tkph;
  if (empty <= 0 || rc <= 0 || fc <= 0 || h <= 0) return errBox();
  const gross = empty + pay;
  const [rL, rE] = s.reardist.split('/').map(Number);
  const [fL, fE] = s.frontdist.split('/').map(Number);
  const rearLoaded = (gross * (rL / 100)) / rc, rearEmpty = (empty * (rE / 100)) / rc;
  const frontLoaded = (gross * (fL / 100)) / fc, frontEmpty = (empty * (fE / 100)) / fc;
  const rearAvg = (rearLoaded + rearEmpty) / 2 / 1000, frontAvg = (frontLoaded + frontEmpty) / 2 / 1000;
  const govPos = rearAvg >= frontAvg ? '후축' : '전축';
  const govAvg = Math.max(rearAvg, frontAvg);
  const govLoaded = rearAvg >= frontAvg ? rearLoaded : frontLoaded;
  const speed = (n * l) / h;

  const req = reqBox(`${govPos} 적재 시 1본당 하중`, govLoaded, `최고부하 위치(${govPos}) 기준`, [
    ['총중량', fmt(gross) + ' kg'],
    ['평균 타이어하중', govAvg.toFixed(1) + ' t'],
    ['평균 주행속도', speed.toFixed(1) + ' km/h'],
  ]);
  const tk = tkphBox(govAvg, speed, rated,
    `TKPH = 평균 타이어하중(${govAvg.toFixed(1)} t) × 평균속도(${speed.toFixed(1)} km/h) · 평균속도 = N(${n})×L(${l})÷H(${h})`);

  let tires = '';
  if (poolPred) {
    const pool = OTR.filter(poolPred);
    const ranked = rankOTR(pool, govLoaded, speed).slice(0, 10);
    const rows = ranked.map(r => tireRow(
      `${r.t.pattern} · ${r.t.size}`,
      `${r.t.brand} · ${r.t.app}${r.t.pr ? ` · ${r.t.pr}PR` : ''}`,
      r.cap, `최대하중 @${r.sp}km/h`, govLoaded,
      r.over ? '⚠ 정격속도 초과 → 데이터북 확인' : '')).join('');
    tires = renderTires(`적정 OTR 추천 · 운행속도 ${speed.toFixed(0)} km/h`, rows);
  } else {
    tires = noPoolMsg;
  }
  resultHtml.value = `<div class="rounded-xl border border-border bg-card p-4">${req}${tk}${tires}</div>`;
}
const calcForklift = () => calcTKPHTab(fk, null,
  `<div class="rounded-xl border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-600 dark:text-amber-500"><b>지게차 IND 타이어 카탈로그 미첨부</b><br>산출된 전축 하중을 충족하는 지게차 라인(TKPORTH·ETPORTM·4KLIFT-D 등)은 해당 카탈로그 확보 시 자동 매칭됩니다.</div>`);
const calcHeavy  = () => calcTKPHTab(hv, o => o.app.includes('로더') || o.app.includes('그레이더'), '');
const calcMining = () => calcTKPHTab(mn, o => o.app.includes('덤프'), '');

/* ── 농기계 계산 ─────────────────────────────────────────────────────────── */
function calcAgri() {
  const axle = +ag.axle, cnt = +ag.count;
  if (axle <= 0 || cnt <= 0) return errBox();
  const per = axle / cnt;
  const list = sortByFit(AGR as unknown as Record<string, unknown>[], per, 'load').slice(0, 10) as unknown as Agr[];
  const rows = list.map(x => tireRow(
    `${x.pattern} · ${x.size}`, `${x.app} · ${x.pr}PR`,
    x.load, '최대하중', per,
    `공기압 ${x.psi} psi · ${x.speed} km/h`)).join('');
  const req = reqBox('타이어 1본당 필요 하중', per, `축하중 ${fmt(axle)} kg ÷ ${cnt}본`, [
    ['차종', '농용 트랙터/작업기'], ['비교 기준', 'AGR 최대하중'],
  ]);
  const cpk = cpkBox({ cur: ag.cur, price: +ag.price, life: +ag.life, retread: ag.retread === '1', rCost: +ag.rcost, rLife: +ag.rlife, rCount: +ag.rcount, fuelP: +ag.fuelp, econ: +ag.econ });
  resultHtml.value = `<div class="rounded-xl border border-border bg-card p-4">${req}${cpk}${renderTires('적정 농기계 타이어 추천', rows)}</div>`;
}

/* ── 프리셋 적용 · 실행 ───────────────────────────────────────────────────── */
function applyPreset(tb: Tab, idx: string) {
  const state = tb === 'forklift' ? fk : tb === 'heavy' ? hv : tb === 'mining' ? mn : null;
  if (tb === 'agri') {
    if (idx === '') { ag.vinfo = ''; return; }
    const v = VEHICLES.agri[+idx];
    ag.axle = v.axleLoad!; ag.count = v.tcnt!;
    ag.vinfo = `<span class="text-muted-foreground">축수 ${v.axles} · 총 타이어 ${v.tires}본 · ${v.config} · 구동축 하중 ${fmt(v.axleLoad!)} kg</span>`;
    run(); return;
  }
  if (!state) return;
  if (idx === '') { state.vinfo = ''; return; }
  const v = VEHICLES[tb][+idx];
  Object.assign(state, v.fill);
  state.vinfo = `<span class="text-muted-foreground">축수 ${v.axles} · 총 타이어 ${v.tires}본 · ${v.config} · 공차 ${fmt(v.fill!.empty as number)} kg · 적재 ${fmt(v.fill!.payload as number)} kg</span>`;
  run();
}
function run() {
  ({ truck: calcTruck, forklift: calcForklift, heavy: calcHeavy, mining: calcMining, agri: calcAgri })[tab.value]();
}
function switchTab(k: Tab) { tab.value = k; resultHtml.value = ''; }
</script>

<template>
  <div class="p-6 space-y-4 max-w-300 mx-auto">
    <PageHeader title="하중계산" subtitle="차량별 적정 타이어 적재하중 · TKPH · CPK 통합 분석 (ASCENDO + TECHKING)" />

    <!-- 탭 -->
    <div class="flex gap-2 flex-wrap">
      <button
        v-for="tb in TABS" :key="tb.key"
        class="flex-1 min-w-28 text-center rounded-xl border px-3 py-2.5 text-sm font-semibold transition-colors"
        :class="tab === tb.key ? 'bg-primary/15 border-primary/40 text-primary' : 'bg-card border-border text-muted-foreground hover:bg-accent'"
        @click="switchTab(tb.key)"
      >
        {{ tb.label }}
      </button>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[380px_1fr] gap-4 items-start">
      <!-- 입력 -->
      <section class="rounded-xl border border-border bg-card p-5 space-y-3 text-sm">
        <!-- 트럭·버스 -->
        <template v-if="tab === 'truck'">
          <h2 class="font-semibold">트럭·버스 (TBR / Bias)</h2>
          <p class="text-xs text-muted-foreground">차량 분류·차종을 선택하면 축수·타이어수·GVW가 자동 입력되어 선호도 하중과 초과율을 계산합니다.</p>
          <label class="block text-xs font-semibold">차량 분류
            <select v-model="t.cls" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="applyTruckClass(t.cls)">
              <option value="">— 직접 입력 (수동) —</option>
              <option value="engkel">Engkel / CDE</option>
              <option value="double">Double / CDD</option>
              <option value="tronton">Tronton</option>
              <option value="trintin">Trintin</option>
              <option value="trinton">Trinton</option>
              <option value="bus">Bus</option>
              <option value="trailer20">Trailer 20ft</option>
              <option value="trailer">Trailer 40ft</option>
            </select>
          </label>
          <!-- 직접 입력 선택 시: 차량명 텍스트 입력창 -->
          <label v-if="!t.cls" class="block text-xs font-semibold">차량명 (직접 입력)
            <input v-model="t.customName" type="text" placeholder="예) Hino FG 235 커스텀" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run" />
          </label>
          <div v-if="t.vinfo" class="px-1 text-xs" v-html="t.vinfo" />
          <div class="grid grid-cols-2 gap-2">
            <label class="block text-xs font-semibold">공차중량 (kg)<input v-model.number="t.tare" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run" /></label>
            <label class="block text-xs font-semibold">적재량 (kg)<input v-model.number="t.payload" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run" /></label>
          </div>
          <div class="text-[11px] text-muted-foreground">총중량 GVW = 공차중량 + 적재량 = <b class="text-foreground tabular-nums">{{ ((+t.tare || 0) + (+t.payload || 0)).toLocaleString('en-US') }}</b> kg</div>
          <div class="grid grid-cols-2 gap-2">
            <label class="block text-xs font-semibold">전축(조향) 타이어수<input v-model.number="t.st" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run" /></label>
            <label class="block text-xs font-semibold">전축 하중분배 %<input v-model.number="t.ss" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run" /></label>
            <label class="block text-xs font-semibold">후축(구동) 타이어수<input v-model.number="t.dt" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run" /></label>
            <label class="block text-xs font-semibold">후축 하중분배 %<input v-model.number="t.ds" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run" /></label>
            <label class="block text-xs font-semibold">후축 복륜 여부
              <select v-model="t.ddual" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run"><option value="1">복륜(Dual)</option><option value="0">단륜(Single)</option></select>
            </label>
            <label class="block text-xs font-semibold">타이어 규격
              <select v-model="t.size" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="run">
                <option value="all">전체 규격</option>
                <option v-for="sz in TBR_SIZES" :key="sz" :value="sz">{{ sz }}</option>
              </select>
            </label>
          </div>
          <div class="text-[11px] font-bold text-muted-foreground pt-2">—— CPK 비용 분석 (구매가·연비·재생) ——</div>
          <div class="grid grid-cols-2 gap-2">
            <label class="block text-xs font-semibold">타이어 구매가 /본 (Rp)<input v-model.number="t.price" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">신품 수명 (km)<input v-model.number="t.life" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">재생 가능 여부
              <select v-model="t.retread" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary"><option value="1">재생 가능</option><option value="0">재생 불가</option></select>
            </label>
            <label class="block text-xs font-semibold">재생 비용 /회<input v-model.number="t.rcost" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">재생 후 수명 (km)<input v-model.number="t.rlife" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">재생 횟수<input v-model.number="t.rcount" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">연료가 /L<input v-model.number="t.fuelp" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
          </div>
          <label class="block text-xs font-semibold">연비 (km/L)<input v-model.number="t.econ" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
        </template>

        <!-- 지게차 / 중장비 / 광산 (TKPH 공통 폼) -->
        <template v-else-if="tab !== 'agri'">
          <template v-for="cfg in [tab === 'forklift' ? { s: fk, title: '지게차 (Forklift) · TKPH', desc: '자중·정격하중과 전/후 하중분배로 전축 하중과 TKPH를 산출합니다.', brand: false, eLab: '자중(서비스 중량)', pLab: '정격 적재하중' } : tab === 'heavy' ? { s: hv, title: '중장비 · 로더/도저/그레이더 · TKPH', desc: '장비 공차중량·버킷 적재량과 하중분배로 축하중·TKPH를 산출합니다.', brand: true, eLab: '장비 공차중량', pLab: '버킷 적재량' } : { s: mn, title: '광산 덤프트럭 · TKPH', desc: '공차/적재 중량과 운행 사이클로 하중 및 TKPH를 산출합니다.', brand: true, eLab: '공차중량', pLab: '적재량(페이로드)' }]" :key="tab">
            <h2 class="font-semibold">{{ cfg.title }}</h2>
            <p class="text-xs text-muted-foreground">{{ cfg.desc }}</p>
            <label class="block text-xs font-semibold">차량 선택 (프리셋)
              <select v-model="cfg.s.veh" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="applyPreset(tab, cfg.s.veh)">
                <option value="">— 직접 입력 (수동) —</option>
                <option v-for="(v, i) in VEHICLES[tab]" :key="i" :value="String(i)">{{ v.name }}</option>
              </select>
            </label>
            <div v-if="cfg.s.vinfo" class="px-1 text-xs" v-html="cfg.s.vinfo" />
            <label class="block text-xs font-semibold">{{ cfg.eLab }} (kg)<input v-model.number="cfg.s.empty" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">{{ cfg.pLab }} (kg)<input v-model.number="cfg.s.payload" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <div class="grid grid-cols-2 gap-2">
              <label class="block text-xs font-semibold">후축 타이어 수<input v-model.number="cfg.s.rear" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
              <label class="block text-xs font-semibold">전축 타이어 수<input v-model.number="cfg.s.front" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
              <label class="block text-xs font-semibold">후축 하중비율 <span class="font-medium text-muted-foreground">적재/공차 %</span><input v-model="cfg.s.reardist" type="text" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
              <label class="block text-xs font-semibold">전축 하중비율 <span class="font-medium text-muted-foreground">적재/공차 %</span><input v-model="cfg.s.frontdist" type="text" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            </div>
            <div class="text-[11px] font-bold text-muted-foreground pt-2">—— TKPH 발열 분석 (사이클) ——</div>
            <div class="grid grid-cols-2 gap-2">
              <label class="block text-xs font-semibold">1일 왕복횟수 N<input v-model.number="cfg.s.n" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
              <label class="block text-xs font-semibold">왕복거리 L (km)<input v-model.number="cfg.s.l" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
              <label class="block text-xs font-semibold">가동시간 H (h/일)<input v-model.number="cfg.s.h" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
              <label class="block text-xs font-semibold">정격 TKPH <span class="font-medium text-muted-foreground">데이터북</span><input v-model.number="cfg.s.tkph" type="number" placeholder="p.64 TKPH표" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            </div>
          </template>
        </template>

        <!-- 농기계 -->
        <template v-else>
          <h2 class="font-semibold">농기계 (AGR · 트랙터)</h2>
          <p class="text-xs text-muted-foreground">축하중과 타이어 수로 농용 타이어 하중용량과 비교합니다.</p>
          <label class="block text-xs font-semibold">차량 선택 (프리셋)
            <select v-model="ag.veh" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" @change="applyPreset('agri', ag.veh)">
              <option value="">— 직접 입력 (수동) —</option>
              <option v-for="(v, i) in VEHICLES.agri" :key="i" :value="String(i)">{{ v.name }}</option>
            </select>
          </label>
          <div v-if="ag.vinfo" class="px-1 text-xs" v-html="ag.vinfo" />
          <label class="block text-xs font-semibold">축 하중 (kg)<input v-model.number="ag.axle" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
          <label class="block text-xs font-semibold">축당 타이어 수<input v-model.number="ag.count" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
          <div class="text-[11px] font-bold text-muted-foreground pt-2">—— CPK 비용 분석 ——</div>
          <div class="grid grid-cols-2 gap-2">
            <label class="block text-xs font-semibold">타이어 구매가 /본 (Rp)<input v-model.number="ag.price" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">신품 수명 (km)<input v-model.number="ag.life" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">재생 가능 여부
              <select v-model="ag.retread" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary"><option value="0">재생 불가</option><option value="1">재생 가능</option></select>
            </label>
            <label class="block text-xs font-semibold">재생 비용 /회<input v-model.number="ag.rcost" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">재생 후 수명 (km)<input v-model.number="ag.rlife" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">재생 횟수<input v-model.number="ag.rcount" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
            <label class="block text-xs font-semibold">연료가 /L<input v-model.number="ag.fuelp" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
          </div>
          <label class="block text-xs font-semibold">연비 (km/L)<input v-model.number="ag.econ" type="number" class="mt-1 w-full h-9 bg-muted border border-border rounded-lg px-2 text-xs focus:outline-none focus:ring-1 focus:ring-primary" /></label>
        </template>

        <button class="w-full mt-2 py-3 rounded-xl bg-primary/10 text-primary border border-primary/20 hover:bg-primary/20 font-bold text-sm transition-colors" @click="run">적정 타이어 계산</button>
      </section>

      <!-- 결과 -->
      <section>
        <div v-if="!resultHtml" class="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">
          차량 선택과 제원을 입력한 뒤 「적정 타이어 계산」을 눌러 주세요.
        </div>
        <div v-else v-html="resultHtml" />
      </section>
    </div>

    <!-- 각주 -->
    <div class="rounded-xl border border-border bg-muted/20 p-4 text-[11px] text-muted-foreground space-y-1">
      <p><b class="text-foreground">계산 근거 및 주의</b></p>
      <p>· 하중지수(LI)→최대하중(kg) 및 단륜/복륜 용량: ASCENDO 카탈로그 제원 기준. TECHKING OTR 하중은 데이터북 LI/SS를 표준 LI→kg표(p.66)로 변환.</p>
      <p>· <b>적정성 판정</b>: 사용률 = 필요하중 ÷ 타이어용량. 90% 이하 '적합'(연속사용 발열 여유), 90~100% '주의', 100% 초과 '부적합'.</p>
      <p>· <b>TKPH</b> = 평균 타이어하중(t) × 평균속도(km/h), 평균 타이어하중 = (적재+공차)/2. 정격 TKPH ≥ 운행 TKPH 여야 열적 안전. 정격값은 데이터북 p.64~65에서 확인 후 입력(안전 직결 — 자동 추정 배제).</p>
    <p>· <b>CPK</b> = 총 타이어비용 ÷ 총 주행수명(재생 포함) + 연료비/km. 인도네시아 트럭 분류(Aptrindo·Kemenhub): 1.1=축당 2본, 2.2=축당 4본.</p>
      <p>· 차량 프리셋은 참고 기본값이며 실제 사양으로 수정해 사용하세요. 타이어 제원·프리셋의 DB(Supabase) 이관은 별도 작업(작업지시서) 예정.</p>
    </div>
  </div>
</template>
