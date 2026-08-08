-- ─────────────────────────────────────────────────────────────────────────────
-- DOT 타이어 공장코드 조회 모듈 — 스키마 (WO-ASURADB-2026-DOT-01 §4)
--   · dot_plant_codes  : 소스별 원천 행 (PK: dot_code + source)
--   · v_dot_lookup     : 소스 우선순위 병합 조회 뷰 (code_legacy2·code_current3 포함)
--   · v_dot_conflicts  : 소스 간 공장명 불일치 탐지 뷰
--   · dot_inspection_logs : 검수 기록(클레임 근거) · authenticated 전용
-- 표준 PostgreSQL 문법 우선(§9, Neon 이관 대비). auth.uid()만 Supabase 의존.
-- 적용: 1회. 이후 seed_dot_plant_codes_vpic.sql 로 vPIC 데이터 적재.
-- ─────────────────────────────────────────────────────────────────────────────

-- 4.1 원천 테이블 -------------------------------------------------------------
create table if not exists public.dot_plant_codes (
  dot_code      text        not null,   -- 조회 기준 코드 (2자리 구코드 또는 3자리 신코드)
  code_legacy2  text,                   -- 2자리 구코드 (vPIC OldDotCode)
  code_current3 text,                   -- 3자리 신코드 (vPIC DOTCode)
  plant_name    text        not null,
  address       text,
  city          text,
  state         text,
  country       text,
  status        text,                   -- Active / Closed / Unknown
  source        text        not null,   -- vpic | tire_business | casing_jockey | dtw
  source_year   int,
  raw           jsonb,                  -- 원본 응답 보존(선택)
  updated_at    timestamptz not null default now(),
  primary key (dot_code, source)
);

create index if not exists idx_dot_plant_codes_country on public.dot_plant_codes (country);
create index if not exists idx_dot_plant_codes_name    on public.dot_plant_codes using gin (to_tsvector('simple', plant_name));

-- 4.2 조회용 통합 뷰 (소스 우선순위 병합) --------------------------------------
create or replace view public.v_dot_lookup as
select distinct on (dot_code)
  dot_code, code_legacy2, code_current3,
  plant_name, city, state, country, status, source, source_year, updated_at
from public.dot_plant_codes
order by dot_code,
  case source
    when 'vpic'          then 1
    when 'tire_business' then 2
    when 'casing_jockey' then 3
    else 4
  end,
  source_year desc nulls last;

-- 4.3 소스 간 불일치 탐지 뷰 --------------------------------------------------
create or replace view public.v_dot_conflicts as
select dot_code,
       count(distinct plant_name)     as name_variants,
       array_agg(distinct plant_name) as names,
       array_agg(distinct source)     as sources
from public.dot_plant_codes
group by dot_code
having count(distinct plant_name) > 1;

-- 4.4 검수 기록 테이블 (클레임 근거 축적) -------------------------------------
create table if not exists public.dot_inspection_logs (
  id              bigserial primary key,
  inspected_at    date        not null default current_date,
  po_no           text,
  container_no    text,
  tire_size       text,
  dot_code        text        not null,
  week_year_code  text,                  -- 예: '2426'
  expected_plant  text,
  matched         boolean,
  remark          text,
  created_by      uuid        references auth.users(id),
  created_at      timestamptz not null default now()
);

-- 4.5 RLS + 권한 ------------------------------------------------------------
-- 공개 참조 데이터(원가·판매정보 없음) → anon 읽기 허용
alter table public.dot_plant_codes enable row level security;
drop policy if exists dot_plant_codes_read on public.dot_plant_codes;
create policy dot_plant_codes_read on public.dot_plant_codes
  for select to anon, authenticated using (true);

-- 검수 기록 → authenticated 전용 (본인 uid 로 기록, 조회는 로그인 사용자 공통)
alter table public.dot_inspection_logs enable row level security;
drop policy if exists dot_logs_insert on public.dot_inspection_logs;
create policy dot_logs_insert on public.dot_inspection_logs
  for insert to authenticated with check (created_by = auth.uid());
drop policy if exists dot_logs_select on public.dot_inspection_logs;
create policy dot_logs_select on public.dot_inspection_logs
  for select to authenticated using (true);

grant select on public.dot_plant_codes  to anon, authenticated, service_role;
grant select on public.v_dot_lookup      to anon, authenticated, service_role;
grant select on public.v_dot_conflicts   to anon, authenticated, service_role;
grant select, insert on public.dot_inspection_logs to authenticated, service_role;
grant usage, select on sequence public.dot_inspection_logs_id_seq to authenticated, service_role;

-- PostgREST 스키마 캐시 리로드
notify pgrst, 'reload schema';
