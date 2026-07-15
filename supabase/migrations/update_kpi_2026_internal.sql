-- 2026 재무(재무지표 4종: 재무매출·판관비·영업이익·경상이익) Jan~May 목표·실적 갱신
-- 출처: 사업계획 대비 실적분석.csv (Jan~Apr 실적 개정 + May 신규 포함)
-- 멱등: (metric_id, year_month) 충돌 시 target/actual 갱신 — 재실행 안전

insert into public.kpi_monthly (metric_id, year_month, target, actual) values
  ('fin_sales', '2026-01', 1912132, 1530538),
  ('fin_sales', '2026-02', 1895912, 1482365),
  ('fin_sales', '2026-03', 1302212, 1258439),
  ('fin_sales', '2026-04', 2100594, 2233188),
  ('fin_sales', '2026-05', 2232970, 1340632),
  ('fin_sga', '2026-01', 226842, 199216),
  ('fin_sga', '2026-02', 213236, 181439),
  ('fin_sga', '2026-03', 169224, 173946),
  ('fin_sga', '2026-04', 206625, 169666),
  ('fin_sga', '2026-05', 210657, 130501),
  ('fin_op', '2026-01', 42088, 36360),
  ('fin_op', '2026-02', 43892, 2403),
  ('fin_op', '2026-03', 812, -12670),
  ('fin_op', '2026-04', 85215, 97678),
  ('fin_op', '2026-05', 101469, 51519),
  ('fin_ord', '2026-01', 37088, 29185),
  ('fin_ord', '2026-02', 38892, -5294),
  ('fin_ord', '2026-03', -4188, -16877),
  ('fin_ord', '2026-04', 80215, 83285),
  ('fin_ord', '2026-05', 96469, 46944)
on conflict (metric_id, year_month) do update set
  target = excluded.target,
  actual = excluded.actual;
