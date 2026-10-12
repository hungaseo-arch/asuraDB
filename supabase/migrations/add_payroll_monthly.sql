-- 2026-10-12 — 인건비(월별) 집계 테이블 payroll_monthly 신설 (적용 완료 · Supabase MCP apply_migration)
--
-- 배경: 경영·성과 > 인건비 탭이 정적 파일(src/data/payrollMonthly.ts)을 읽어, 월 반영마다 빌드·배포가 필요했음.
--       집계값을 DB 로 승격해 월 반영을 upsert 만으로 끝내도록 변경(재배포 불필요). 화면 로더: src/lib/payroll.ts.
-- 내용: 집계값만 저장(개인정보 없음). 단위 — 인원=명, 금액=백만 IDR(Juta).
-- 시드: 2025-AVG(기준선) + 2026-01~09, 54개 계열 525행 — payrollMonthly.ts 값 그대로(sum(value)=14201.0 대조 일치).
--       월별 적재는 scripts/payroll_monthly.py run 리포트의 payroll_monthly.sql 사용.

create table public.payroll_monthly (
  tab_key    text not null,
  item       text not null check (item in ('hc','total','salary','avgcost','kompensasi','thr','insentif')),
  row_key    text not null default '',
  period     text not null check (period ~ '^\d{4}-(0[1-9]|1[0-2]|AVG)$'),
  value      numeric not null,
  updated_at timestamptz not null default now(),
  primary key (tab_key, item, row_key, period)
);
comment on table public.payroll_monthly is '인건비 월별 집계(인원·인건비·보상비·THR·상여금). 원천: HR 월간 Rekap Gaji. scripts/payroll_monthly.py 로 적재';
comment on column public.payroll_monthly.tab_key is 'company | HQ Jakarta | Cikarang/Karawang WH | Surabaya | Semarang';
comment on column public.payroll_monthly.row_key is 'item=hc 일 때 Section(대문자) 또는 전사 탭의 HQ/WH/SBY/SMG, 그 외 빈 문자열';
comment on column public.payroll_monthly.period is 'YYYY-MM 또는 YYYY-AVG(연평균 기준선)';

-- RLS: kpi_monthly 와 동일 규약(super_admin·staff 전체, viewer 조회)
alter table public.payroll_monthly enable row level security;
create policy payroll_monthly_auth_all on public.payroll_monthly for all to authenticated
  using (((auth.jwt() -> 'app_metadata') ->> 'role') = any (array['super_admin','staff']))
  with check (((auth.jwt() -> 'app_metadata') ->> 'role') = any (array['super_admin','staff']));
create policy payroll_monthly_select_viewer on public.payroll_monthly for select to authenticated
  using (((auth.jwt() -> 'app_metadata') ->> 'role') = 'viewer');
