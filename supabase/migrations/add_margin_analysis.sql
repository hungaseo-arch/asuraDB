-- 마진 분석 (Margin Analysis)
-- 월별 총매출/총마진 + 4개 축(브랜드/제품/고객/SKU) 상세 레코드

create table if not exists public.margin_months (
  year_month    text        primary key,
  total_sales   bigint      not null,
  total_margin  bigint      not null,
  source_file   text,
  created_at    timestamptz not null default now()
);

create table if not exists public.margin_records (
  id           bigserial   primary key,
  year_month   text        not null references public.margin_months(year_month) on delete cascade,
  axis         text        not null check (axis in ('brand','product','customer','item')),
  primary_key  text        not null,
  secondary    text,
  qty          integer,
  sales_idr    bigint      not null,
  margin_idr   bigint      not null,
  created_at   timestamptz not null default now()
);

create unique index if not exists margin_records_uniq
  on public.margin_records (year_month, axis, primary_key, coalesce(secondary, ''));

create index if not exists margin_records_ym_axis
  on public.margin_records (year_month, axis);

create index if not exists margin_records_axis_pk
  on public.margin_records (axis, primary_key);

comment on table  public.margin_months              is '월별 총매출/총마진 요약 (IDR)';
comment on table  public.margin_records             is '월별 4개 축(브랜드/제품/고객/SKU) 상세 매출/마진 (IDR)';
comment on column public.margin_records.axis        is 'brand=브랜드, product=카테고리, customer=고객사, item=SKU';
comment on column public.margin_records.primary_key is '축의 주키 (브랜드명/카테고리/고객명/SKU명)';
comment on column public.margin_records.secondary   is '서브 분류 (product 축에서만 사용: TBR/LTR/TBB 등)';
comment on column public.margin_records.qty         is '판매 수량 (product/item 축에서만)';

-- RLS 정책은 enable_rls_all_tables.sql 에서 일괄 관리 (to authenticated)
