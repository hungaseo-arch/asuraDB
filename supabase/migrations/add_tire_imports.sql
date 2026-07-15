-- 인도네시아 월간 타이어 수입량 (BPS EXIM 기반)
--
-- ⭐ 이 파일이 tire_imports 의 최신 스냅샷(category CHECK v3, 16종)이다.
--    신규 설치는 이 파일만 실행하면 된다. 별도 마이그레이션 add_agr_category.sql /
--    add_pc_mc_categories.sql / alter_categories_v3.sql 는 기존 DB 를 단계적으로
--    올리기 위한 이력(누적 적용 완료)이며 신규 설치에는 불필요.

create table if not exists public.tire_imports (
  id            uuid      primary key default gen_random_uuid(),
  year          int       not null check (year >= 2020 and year <= 2099),
  month         int       not null check (month >= 1 and month <= 12),
  hs_code       text      not null,
  category      text      not null check (category in (
                  'pc','lt','tb','mc','bc','agr','ind','mining_truck','otr',
                  'aircraft','other','retread','used','solid','flap','tube')),
  country       text      not null default 'ALL',
  value_usd     numeric   default 0,
  weight_kg     numeric   default 0,
  created_at    timestamptz not null default now(),
  unique (year, month, hs_code, country)
);

create index if not exists tire_imports_ym      on public.tire_imports (year desc, month desc);
create index if not exists tire_imports_cat     on public.tire_imports (category);
create index if not exists tire_imports_country on public.tire_imports (country);

comment on table  public.tire_imports               is 'BPS EXIM 월간 타이어 수입 데이터 (HS Code 단위)';
comment on column public.tire_imports.category      is 'pc=승용차, lt=경트럭, tb=트럭버스, mc=오토바이, bc=자전거, agr=농업용, ind=산업/지게차, mining_truck=광산트럭, otr=OTR, aircraft=항공기, other=기타신품, retread=재생, used=중고, solid=솔리드, flap=플랩, tube=이너튜브';
comment on column public.tire_imports.country       is '원산지 국가명 (ALL=합계)';
comment on column public.tire_imports.value_usd     is '수입금액 (USD)';
comment on column public.tire_imports.weight_kg     is '수입중량 (KG)';
