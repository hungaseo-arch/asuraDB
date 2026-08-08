-- ============================================================
-- 타이어 세트 가격비교 (Price Comparison) — PriceCompare.vue
-- 작업지시서_가격비교상세페이지.md §5 반영. Supabase SQL Editor 1회 실행(멱등).
-- 세트 = 타이어(Ban) + 튜브(Ban Dalam) + 플랩(Flap). 동일 고객등급 기준 비교.
-- ============================================================

-- ── 1. 헤더 ─────────────────────────────────────────────────
create table if not exists public.price_comparisons (
  id             uuid primary key default gen_random_uuid(),
  compare_no     text,                                   -- 'PC-YYYY-NNNN' (next_compare_number)
  created_date   date        not null default current_date,
  customer_name  text,
  customer_grade text,                                   -- 수입상/대리점/서브딜러/타이어판매점/최종소비자
  spec           text,                                   -- 제품 규격 (예: 11.00R20)
  ppn_rate       numeric     not null default 0.11,
  ppn_basis      text        not null default 'excl' check (ppn_basis in ('excl','incl')),
  status         text        not null default 'draft' check (status in ('draft','final')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ── 2. 비교 대상 열 (자사·경쟁사) ───────────────────────────
create table if not exists public.price_comparison_columns (
  id            uuid primary key default gen_random_uuid(),
  comparison_id uuid not null references public.price_comparisons(id) on delete cascade,
  col_no        int  not null default 0,                 -- 0=자사
  is_self       boolean not null default false,
  company_name  text,
  tire_price    numeric not null default 0,
  tube_price    numeric not null default 0,
  flap_price    numeric not null default 0,
  tire_code     text,
  tube_code     text,
  flap_code     text,
  tire_brand    text,                                    -- 브랜드(자사=제품 자동, 경쟁사=수동)
  tube_brand    text,
  flap_brand    text,
  landed_cost   numeric not null default 0,              -- 내부용(권한 조회)
  note          text
);

-- 브랜드 컬럼 (기존 테이블에도 멱등 추가)
alter table public.price_comparison_columns add column if not exists tire_brand text;
alter table public.price_comparison_columns add column if not exists tube_brand text;
alter table public.price_comparison_columns add column if not exists flap_brand text;
-- PPN 적용 여부 (경쟁사 열 토글 · 자사는 항상 true)
alter table public.price_comparison_columns add column if not exists apply_ppn boolean not null default true;
-- 최종 판매가 직접입력(목표가). null = 품목단가·할인 기준 자동계산
-- 자사: 목표가 입력 시 차액만큼 '추가 할인'을 역산해 가격을 맞춤 / 경쟁사: 총액 견적 입력
alter table public.price_comparison_columns add column if not exists final_override numeric;
comment on column public.price_comparison_columns.final_override is '최종 판매가 직접입력 목표가(PPN 포함가). null이면 tire/tube/flap + 프로모션 기준 자동계산. 자사는 차액을 추가 할인으로 역산';

-- ── 3. 프로모션 다건 ────────────────────────────────────────
create table if not exists public.price_comparison_promos (
  id            uuid primary key default gen_random_uuid(),
  column_id     uuid not null references public.price_comparison_columns(id) on delete cascade,
  promo_no      int  not null default 0,
  description   text,
  discount_rate numeric not null default 0               -- % (합산 적용)
);

-- 목표 최종가 맞추기용 자동 프로모션 표시 (불러올 때 final_override 기준 재계산 · 중복 생성 방지)
alter table public.price_comparison_promos add column if not exists is_auto boolean not null default false;
comment on column public.price_comparison_promos.is_auto is 'true = 최종 판매가 목표값(final_override)에서 역산된 「가격 조정 할인」. 할인율은 자동 계산';

-- FK 조회 인덱스 (UNIQUE 중복 없음)
create index if not exists price_comparison_columns_cmp on public.price_comparison_columns (comparison_id);
create index if not exists price_comparison_promos_col  on public.price_comparison_promos (column_id);

comment on table public.price_comparisons        is '타이어 세트 가격비교 헤더 (동일 고객등급 기준)';
comment on table public.price_comparison_columns is '비교 대상 열 (col_no=0/is_self=자사, 나머지 경쟁사)';
comment on table public.price_comparison_promos  is '열별 프로모션 다건 (discount_rate % 합산)';

-- ── 4. updated_at 자동 갱신 (기존 set_updated_at 재사용) ─────
create or replace trigger trg_price_comparisons_updated_at
  before update on public.price_comparisons
  for each row execute function set_updated_at();

-- ── 5. 채번 함수 (Quote next_quote_number 패턴) ─────────────
-- 호출: select next_compare_number();  → 'PC-2026-0001'
create or replace function next_compare_number()
returns text language plpgsql as $$
declare
  yr  text := to_char(now(), 'YYYY');
  seq int;
begin
  select count(*) + 1 into seq
    from public.price_comparisons
   where compare_no like 'PC-' || yr || '-%';
  return 'PC-' || yr || '-' || lpad(seq::text, 4, '0');
end;
$$;

-- ── 6. RLS (로그인 사용자만 · enable_rls_all_tables 패턴) ────
do $$
declare t text;
begin
  foreach t in array array['price_comparisons','price_comparison_columns','price_comparison_promos'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists %I on public.%I;', t || '_auth_all', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true);',
      t || '_auth_all', t);
  end loop;
end $$;
