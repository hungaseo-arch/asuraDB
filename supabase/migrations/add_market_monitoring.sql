-- KPI 모니터링: 3 tables

create table if not exists public.market_indicators (
  id          text primary key,
  name_ko     text not null,
  name_en     text not null,
  category    text not null check (category in ('commodity','fx','freight','policy','market','internal')),
  alert_level text not null default 'daily' check (alert_level in ('daily','weekly','monthly')),
  unit        text,
  source      text not null default 'manual' check (source in ('yfinance','manual')),
  ticker      text,
  description text,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.indicator_history (
  id           uuid primary key default gen_random_uuid(),
  indicator_id text not null references public.market_indicators(id) on delete cascade,
  value        numeric,
  recorded_date date not null default current_date,
  note         text,
  created_at   timestamptz not null default now(),
  unique (indicator_id, recorded_date)
);

-- (indicator_id, recorded_date) 조회는 위 UNIQUE 제약 인덱스가 커버(선행 등호+역방향 스캔) → 별도 인덱스 불필요.
-- (구 indicator_history_indicator_date 는 중복이라 제거: drop_redundant_indexes.sql)

create table if not exists public.monitoring_reports (
  id          uuid primary key default gen_random_uuid(),
  report_date date not null,
  report_week text,
  content     jsonb not null default '{}',
  raw_markdown text,
  created_at  timestamptz not null default now()
);

-- ── Seed: 25 indicators ──────────────────────────────────────────────────────

insert into public.market_indicators
  (id, name_ko, name_en, category, alert_level, unit, source, ticker, sort_order)
values
  -- 원자재 (commodity)
  ('brent_crude',    '브렌트유',          'Brent Crude Oil',       'commodity', 'daily',   'USD/bbl', 'yfinance', 'BZ=F',     1),
  ('nr_rubber',      '천연고무 SICOM',     'NR Rubber (SICOM)',     'commodity', 'daily',   'USc/kg',  'manual',   null,       2),
  ('cpo',            '팜유 CPO',           'Palm Oil (CPO)',         'commodity', 'daily',   'MYR/MT',  'manual',   null,       3),
  ('nickel',         '니켈',              'Nickel',                'commodity', 'daily',   'USD/MT',  'manual',   null,       4),
  ('coal',           '석탄',              'Thermal Coal',          'commodity', 'weekly',  'USD/MT',  'manual',   null,       5),
  ('carbon_black',   '카본블랙',           'Carbon Black',          'commodity', 'weekly',  'USD/MT',  'manual',   null,       6),
  ('synthetic_rubber','합성고무 BD',        'Butadiene (BD)',         'commodity', 'weekly',  'USD/MT',  'manual',   null,       7),
  ('steel_wire',     '강선',              'Steel Wire Rod',        'commodity', 'weekly',  'USD/MT',  'manual',   null,       8),

  -- 환율 (fx)
  ('usd_idr',        'USD/IDR',           'USD/IDR Exchange Rate', 'fx',        'daily',   'IDR',     'yfinance', 'USDIDR=X', 10),
  ('usd_krw',        'USD/KRW',           'USD/KRW Exchange Rate', 'fx',        'daily',   'KRW',     'yfinance', 'USDKRW=X', 11),
  ('usd_cny',        'USD/CNY',           'USD/CNY Exchange Rate', 'fx',        'daily',   'CNY',     'yfinance', 'USDCNY=X', 12),

  -- 물류/운임 (freight)
  ('scfi',           'SCFI 컨테이너운임',   'SCFI Container Freight','freight',   'weekly',  'Index',   'manual',   null,       20),

  -- 정책/거시경제 (policy)
  ('bi_rate',        'BI 기준금리',         'BI Rate',               'policy',    'monthly', '%',       'manual',   null,       30),
  ('idn_inflation',  '인도네시아 물가',      'IDN CPI Inflation',     'policy',    'monthly', '%',       'manual',   null,       31),
  ('idn_pmi',        '인도네시아 PMI',       'IDN Manufacturing PMI', 'policy',    'monthly', 'Index',   'manual',   null,       32),

  -- 시장/경쟁 (market)
  ('tbr_sales',      'TBR 타이어 판매',      'TBR Tire Sales',        'market',    'weekly',  'units',   'manual',   null,       40),
  ('otr_sales',      'OTR 타이어 판매',      'OTR Tire Sales',        'market',    'weekly',  'units',   'manual',   null,       41),
  ('ind_sales',      'IND 타이어 판매',      'Industrial Tire Sales', 'market',    'weekly',  'units',   'manual',   null,       42),
  ('agr_sales',      'AGR 타이어 판매',      'Agriculture Tire Sales','market',    'weekly',  'units',   'manual',   null,       43),
  ('competitor_price','경쟁사 가격지수',      'Competitor Price Index','market',    'weekly',  'Index',   'manual',   null,       44),

  -- 재무 (internal)
  ('receivables_ar', '매출채권 AR',          'Accounts Receivable',   'internal',  'weekly',  'IDR M',   'manual',   null,       50),
  ('operating_ratio','영업이익률',           'Operating Margin',      'internal',  'monthly', '%',       'manual',   null,       51)
on conflict (id) do nothing;

-- RLS 정책은 enable_rls_all_tables.sql 에서 일괄 관리
