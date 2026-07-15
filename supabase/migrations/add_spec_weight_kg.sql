-- ============================================================
-- 스펙 테이블 중량 컬럼 추가 — Databases.vue '스펙' 탭 중량 열
-- Supabase SQL Editor 1회 실행(멱등).
-- 배경: products.weight_kg 는 전부 NULL 이고 SKU 체계가 스펙 테이블과 달라(예:
--   tbr_specs 'R1-10002052518' vs products '1100R20SUPERETOT18M') 조인 불가.
--   → 중량은 각 스펙 테이블이 직접 보유하도록 컬럼 추가(값은 추후 입력).
-- ============================================================

alter table public.tbr_specs add column if not exists weight_kg numeric;
alter table public.tbb_specs add column if not exists weight_kg numeric;
alter table public.otr_specs add column if not exists weight_kg numeric;
alter table public.agr_specs add column if not exists weight_kg numeric;

comment on column public.tbr_specs.weight_kg is '타이어 1본 중량(kg)';
comment on column public.tbb_specs.weight_kg is '타이어 1본 중량(kg)';
comment on column public.otr_specs.weight_kg is '타이어 1본 중량(kg)';
comment on column public.agr_specs.weight_kg is '타이어 1본 중량(kg)';
