-- kpi_monthly.source — 값의 출처(월별 잠금)
--
-- 배경: CLAUDE.md §데이터 SSOT 규칙상 `data/kpi/<YYYY>.csv` → kpi_importer.py → kpi_monthly 가
--       진실원천이라, 화면 입력창이 DB 에만 쓰면 importer 재실행 시 **입력값이 되돌아간다**.
--       (브라우저는 로컬 CSV 를 고칠 수 없음)
--
-- 해결: 입력창으로 저장한 행은 source='manual' 로 표시하고, kpi_importer 가 그 행을 건너뛴다.
--       → CSV 이력은 그대로 살아있고, 수기 입력분도 importer 재실행에 지워지지 않는다.
--       CSV 로 되돌리려면 해당 행의 source 를 'csv' 로 바꾸고 importer 재실행.
--
-- 멱등: add column if not exists.

alter table public.kpi_monthly
  add column if not exists source text not null default 'csv';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'kpi_monthly_source_chk') then
    alter table public.kpi_monthly
      add constraint kpi_monthly_source_chk check (source in ('csv', 'manual'));
  end if;
end $$;

comment on column public.kpi_monthly.source is
  'csv=kpi_importer(SSOT: data/kpi/<YYYY>.csv) 적재분 / manual=화면 입력창 저장분(importer 가 건너뜀)';

-- 입력창 저장 시각 추적 (누가·언제 고쳤는지)
alter table public.kpi_monthly
  add column if not exists updated_at timestamptz;

create index if not exists kpi_monthly_source_idx on public.kpi_monthly (source)
  where source = 'manual';
