-- 2026-08-24 — market_indicators.source 정정 (작업지시서 KPI지표_월별백필_2026 §3)
update market_indicators
   set source = 'scraper'
 where id in ('coal', 'carbon_black', 'synthetic_rubber', 'steel_wire',
              'scfi', 'nr_rubber', 'cpo', 'nickel')
   and source is distinct from 'scraper';
