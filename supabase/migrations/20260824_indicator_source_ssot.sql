alter table public.market_indicators
  add column if not exists source_name  text,
  add column if not exists price_basis  text,
  add column if not exists source_url   text,
  add column if not exists unit_native  text,
  add column if not exists unit_factor  numeric default 1;

comment on column public.market_indicators.price_basis is
  '가격 기준. 예: "FOB Newcastle, 6,000 kcal/kg GAR", "LME Cash Settlement"';
comment on column public.market_indicators.unit_factor is
  'indicator_history.value 는 unit 기준으로 저장. 원 소스값 × unit_factor = 저장값';

update public.market_indicators set
  source_name = 'Yahoo Finance (BZ=F)',
  price_basis = 'ICE Brent 선물 일일 종가',
  source_url  = 'https://finance.yahoo.com/quote/BZ%3DF',
  unit_native = 'USD/bbl', unit_factor = 1
where id = 'brent_crude';

update public.market_indicators set
  source_name = 'World Bank Pink Sheet · Rubber TSR20',
  price_basis = 'TSR20, 월평균, 싱가포르/말레이시아산',
  source_url  = 'https://www.worldbank.org/en/research/commodity-markets',
  unit_native = 'USD/kg', unit_factor = 1000
where id = 'nr_rubber';

update public.market_indicators set
  source_name = 'Kemendag · Harga Referensi CPO',
  price_basis = '인도네시아 CPO 수출 기준가(HR), 월 1회 고시, 수출세·수출부담금 산정 기준',
  source_url  = 'https://gimni.org/harga-cpo',
  unit_native = 'USD/MT', unit_factor = 1
where id = 'cpo';

update public.market_indicators set
  source_name = 'World Bank Pink Sheet · Nickel',
  price_basis = 'LME Cash Settlement, 월평균',
  source_url  = 'https://www.worldbank.org/en/research/commodity-markets',
  unit_native = 'USD/mt', unit_factor = 1
where id = 'nickel';

update public.market_indicators set
  name_ko     = '석탄 HBA I',
  source_name = 'ESDM · Harga Batubara Acuan (HBA I)',
  price_basis = 'HBA I · 5,300 kcal/kg GAR · 매월 2기(15일) 고시가 · USD/ton FOB Indonesia',
  source_url  = 'https://www.minerba.esdm.go.id/harga_acuan',
  unit_native = 'USD/ton', unit_factor = 1
where id = 'coal';

update public.market_indicators set
  source_name = '브렌트유 × 14.0 환산 (추정)',
  price_basis = '공개 시세 없음 · 브렌트유 대용 추정. 공급사 견적 수령 시 대체',
  source_url  = null,
  unit_native = 'USD/MT', unit_factor = 1
where id = 'carbon_black';

update public.market_indicators set
  source_name = 'Trading Economics · Butadiene',
  price_basis = 'Butadiene 국제 시세 (CFR 동남아 견적 수령 시 대체)',
  source_url  = 'https://tradingeconomics.com/commodity/butadiene',
  unit_native = 'USD/MT', unit_factor = 1
where id = 'synthetic_rubber';

update public.market_indicators set
  name_ko     = '강선 (HRC 연동 추정)',
  source_name = 'Trading Economics · Steel HRC (강선 대용)',
  price_basis = '열연강판(HRC) 시세를 강선 대용지표로 사용. 실제 강선은 공급사 견적 우선 · 전 구간 추정',
  source_url  = 'https://tradingeconomics.com/commodity/steel',
  unit_native = 'USD/MT', unit_factor = 1
where id = 'steel_wire';

update public.indicator_history
   set quality = '추정'
 where indicator_id = 'steel_wire';

update public.market_indicators set
  source_name = 'SSE 상하이해운거래소 · SCFI Composite',
  price_basis = 'SCFI 종합지수 (2009-10 = 1,000), 매주 금요일 발표',
  source_url  = 'https://en.sse.net.cn/indices/scfinew.jsp',
  unit_native = 'Index', unit_factor = 1
where id = 'scfi';

update public.market_indicators set
  source_name = 'Bank Indonesia · BI-Rate',
  price_basis = 'RDG 이사회 결정 정책금리. 미변경 월은 직전 결정값 유지',
  source_url  = 'https://www.bi.go.id/en/fungsi-utama/moneter/bi-rate/default.aspx'
where id = 'bi_rate';

update public.market_indicators set
  source_name = 'BPS 인도네시아 통계청 · Web API',
  price_basis = 'CPI 전년동월비(YoY, %), 변수 ID 1707',
  source_url  = 'https://webapi.bps.go.id'
where id = 'idn_inflation';

update public.market_indicators set
  source_name = 'S&P Global (Trading Economics 경유)',
  price_basis = 'Indonesia Manufacturing PMI, 50 = 확장/수축 경계',
  source_url  = 'https://tradingeconomics.com/indonesia/manufacturing-pmi'
where id = 'idn_pmi';

update public.market_indicators set
  source_name = 'Yahoo Finance (' || coalesce(ticker,'파생') || ')',
  price_basis = case when id = 'krw_idr'
                     then '파생: USD/IDR ÷ USD/KRW'
                     else '일일 종가' end,
  unit_native = unit, unit_factor = 1
where category = 'fx';
