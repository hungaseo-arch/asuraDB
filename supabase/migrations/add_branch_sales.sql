-- 지점 판매 현황(BranchSales) DB화 + 마스터 테이블 연결
--
-- 배경: BranchSales.vue 는 DB 연결 없이 전 데이터가 파일 내 하드코딩 상수였다.
--       월별 CSV 업로드로 갱신하려면 원시 거래행이 필요하므로 원시행 테이블을 SSOT 로 둔다.
--       화면 수치는 이 테이블에서 집계한다. 집계 규칙은 기존 화면값과 대조 검증 완료:
--         · 전체매출(Section I)  = 전 행, category별 qty 합 / 금액은 so_amt(PPN 11% 제외분)
--         · 순매출(Section II)   = branch_excluded_buyers 차감
--         · 담당자별(Section III) = pic 기준 집계
--
-- ※ FK(sku/customer_code/staff_nik)를 nullable 로 둔 이유 — 실측 커버리지:
--     Buyer→customers  스마랑 28/43, 수라바야 50/55 (미등록 거래처 CV. RICH TIRE 등 실재)
--     SKU →products    스마랑 50/57, 수라바야 104/118 (엑셀이 파괴한 '1.01101E+16' 등 포함)
--     PIC →staff       ROZZAQ·WISNU·LUBIS·RIZKI 는 staff 에 없음
--   필수 FK 로 걸면 적재 자체가 실패한다. 링크는 매칭될 때만 채우고 원문(buyer/pic/sku_raw)은 항상 보존한다.
--
-- 멱등: create/alter .. if not exists 로 재실행 안전.

create table if not exists public.branch_sales_rows (
  id             bigserial primary key,
  branch         text not null check (branch in ('surabaya', 'semarang')),
  so             text,
  delivery_date  date not null,

  -- 원문 보존 (집계·검증의 근거는 항상 이 값)
  pic            text,
  buyer          text,
  sku_raw        text,
  destination    text,
  category       text not null,
  description    text,

  -- 마스터 링크 (매칭 실패 시 null — 위 주석의 커버리지 참고)
  sku            text references public.products (sku)          on update cascade on delete set null,
  customer_code  text references public.customers (customer_code) on update cascade on delete set null,
  staff_nik      text references public.staff (nik)             on update cascade on delete set null,

  -- 링크 근거: exact=원문 정확일치, alias=별칭표(JOKO→DJOKO 등), so_derived=SO번호로 추정, none=미매칭
  link_note      text,

  unit_price     numeric,
  qty            numeric not null default 0,
  so_amt         numeric not null default 0,   -- PPN 제외 (화면 Amount 기준)
  tax_amt        numeric,
  total_amt      numeric,
  source_file    text,
  created_at     timestamptz not null default now()
);

create index if not exists branch_sales_rows_branch_date_idx on public.branch_sales_rows (branch, delivery_date);
create index if not exists branch_sales_rows_cat_idx         on public.branch_sales_rows (branch, category);
create index if not exists branch_sales_rows_sku_idx         on public.branch_sales_rows (sku);
create index if not exists branch_sales_rows_cust_idx        on public.branch_sales_rows (customer_code);
create index if not exists branch_sales_rows_staff_idx       on public.branch_sales_rows (staff_nik);

-- 제외 거래처: 순매출(Net) 계산에서 차감
create table if not exists public.branch_excluded_buyers (
  branch text not null check (branch in ('surabaya', 'semarang')),
  buyer  text not null,
  primary key (branch, buyer)
);

-- 인원·Petty 등 거래 CSV 에서 도출 불가한 월별 값
create table if not exists public.branch_ops_monthly (
  branch    text not null check (branch in ('surabaya', 'semarang')),
  year      smallint not null,
  month     smallint not null check (month between 1 and 12),
  sales_hc  numeric,
  admin_hc  numeric,
  deliv_hc  numeric,
  petty     numeric,
  primary key (branch, year, month)
);

alter table public.branch_sales_rows      enable row level security;
alter table public.branch_excluded_buyers enable row level security;
alter table public.branch_ops_monthly     enable row level security;

-- 가이드 §11: 데이터 보호는 RLS `to authenticated` + 사용자 JWT
do $$
begin
  if not exists (select 1 from pg_policies where tablename='branch_sales_rows' and policyname='branch_sales_rows_auth_all') then
    create policy branch_sales_rows_auth_all on public.branch_sales_rows
      for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='branch_excluded_buyers' and policyname='branch_excluded_buyers_auth_all') then
    create policy branch_excluded_buyers_auth_all on public.branch_excluded_buyers
      for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='branch_ops_monthly' and policyname='branch_ops_monthly_auth_all') then
    create policy branch_ops_monthly_auth_all on public.branch_ops_monthly
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- 제외 거래처 초기값 (화면 하드코딩 목록 이관)
insert into public.branch_excluded_buyers (branch, buyer) values
  ('semarang', 'CV. NASAMED INTI SUKSES'),
  ('semarang', 'CV. MAJESTI MITRA SEJATI'),
  ('semarang', 'CV. KARYA MAJU BAN'),
  ('semarang', 'CV. MASA SEMPURNA'),
  ('semarang', 'PT. DIAMOND FAJAR JAYA'),
  ('semarang', 'PT. DOA KELUARGA TIGASATUTIGA'),
  ('surabaya', 'CV. Arena Ban Indonesia'),
  ('surabaya', 'CV. Sumber Sakti'),
  ('surabaya', 'PT. Grand Prix Indoagung'),
  ('surabaya', 'PT. Jangkar Emas Teguh'),
  ('surabaya', 'PT. Sumber Sakti Prima Mandiri'),
  ('surabaya', 'Aneka Roda Kencana')
on conflict (branch, buyer) do nothing;
