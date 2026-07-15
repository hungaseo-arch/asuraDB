-- 사업 실적 KPI (Business Performance KPI)
-- Monitor 대시보드 '시장/경쟁'(제품별 판매량·판매금액 USD) + '재무'(재무지표)
--
-- 구조: 지표 정의(kpi_metrics) + 월별 목표/실적(kpi_monthly, target vs actual)
-- 시드: 제공된 Y2026 사업계획 시트 기준 (TARGET = Jan~Dec, ACTUAL = Jan~Apr).
--   ⚠️ 시드 수치는 시트 이미지에서 전사(轉寫)한 값입니다 — 운영 반영 전 검증 권장.

-- ── Schema ───────────────────────────────────────────────────────────────────

create table if not exists public.kpi_metrics (
  id          text primary key,
  grp         text not null check (grp in ('market','internal')),  -- 시장/경쟁 vs 재무
  product     text,                                                -- 시장 지표의 제품군 (TBR/TBB/…), 내부는 null
  kind        text not null check (kind in ('qty','amount','financial')),
  name_ko     text not null,
  name_en     text,
  unit        text not null,                                       -- 'pcs' | 'USD'
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.kpi_monthly (
  id          bigserial primary key,
  metric_id   text not null references public.kpi_metrics(id) on delete cascade,
  year_month  text not null,                                       -- 'YYYY-MM'
  target      numeric,
  actual      numeric,
  created_at  timestamptz not null default now(),
  unique (metric_id, year_month)
);

-- (metric_id, year_month) 조회는 위 UNIQUE 제약이 자동 생성하는 인덱스로 커버됨 → 별도 인덱스 불필요.
-- (구 kpi_monthly_metric_ym 은 중복이라 제거: drop_redundant_indexes.sql)

comment on table public.kpi_metrics is '사업 실적 KPI 지표 정의 (시장/경쟁 + 내부 재무)';
comment on table public.kpi_monthly is '지표별 월간 목표(target)·실적(actual)';

-- ── Seed: 지표 정의 ────────────────────────────────────────────────────────────
-- 시장/경쟁: 8개 제품군 × (판매량 qty, 판매금액 amount)
-- 재무: 재무매출 / 판관비 / 영업이익 / 경상이익

insert into public.kpi_metrics (id, grp, product, kind, name_ko, name_en, unit, sort_order) values
  ('q_tbr','market','TBR','qty','TBR 판매량','TBR Qty','pcs',10),
  ('a_tbr','market','TBR','amount','TBR 판매금액','TBR Amount','USD',11),
  ('q_tbb','market','TBB','qty','TBB 판매량','TBB Qty','pcs',20),
  ('a_tbb','market','TBB','amount','TBB 판매금액','TBB Amount','USD',21),
  ('q_otr','market','OTR','qty','OTR 판매량','OTR Qty','pcs',30),
  ('a_otr','market','OTR','amount','OTR 판매금액','OTR Amount','USD',31),
  ('q_agr','market','AGR','qty','AGR 판매량','AGR Qty','pcs',40),
  ('a_agr','market','AGR','amount','AGR 판매금액','AGR Amount','USD',41),
  ('q_ind','market','IND','qty','IND 판매량','IND Qty','pcs',50),
  ('a_ind','market','IND','amount','IND 판매금액','IND Amount','USD',51),
  ('q_vulkan','market','Vulkan','qty','Vulkan 판매량','Vulkan Qty','pcs',60),
  ('a_vulkan','market','Vulkan','amount','Vulkan 판매금액','Vulkan Amount','USD',61),
  ('q_tube','market','Tube','qty','Tube 판매량','Tube Qty','pcs',70),
  ('a_tube','market','Tube','amount','Tube 판매금액','Tube Amount','USD',71),
  ('q_flap','market','Flap','qty','Flap 판매량','Flap Qty','pcs',80),
  ('a_flap','market','Flap','amount','Flap 판매금액','Flap Amount','USD',81),
  ('fin_sales','internal',null,'financial','재무매출','Total Sales','USD',100),
  ('fin_sga','internal',null,'financial','판관비','SG&A','USD',110),
  ('fin_op','internal',null,'financial','영업이익','Operating Profit','USD',120),
  ('fin_ord','internal',null,'financial','경상이익','Ordinary Profit','USD',130)
on conflict (id) do nothing;

-- ── 월별 목표/실적(kpi_monthly) 데이터 ─────────────────────────────────────────
--
-- 월별 데이터는 연도별 사업계획 CSV(data/kpi/<YYYY>.csv)에서 importer 로 적재합니다.
-- (단일 진실원천 = importer; 연도 간 제품 분류 변화 흡수 + 목표/실적 동시 적재)
--
--   uv run python collectors/kpi_importer.py            # Supabase upsert
--   uv run python collectors/kpi_importer.py --dry-run  # 파싱·검증만
--
-- 즉, 이 마이그레이션은 스키마 + 지표 정의까지만 만들고, 카드 데이터는 importer 실행 후 채워집니다.

-- RLS 정책은 enable_rls_all_tables.sql 에서 일괄 관리
