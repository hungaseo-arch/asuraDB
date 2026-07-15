-- ============================================================
-- tire_imports category CHECK 최종본 v3 (tire_hs_expansion 정독 반영, 2026-07-08)
-- 추가: bc(자전거), aircraft(항공기), other(기타신품), retread(재생), used(중고)
-- 이 스크립트 1회 실행으로 최종 상태(16 category)가 됨. 멱등(재실행 안전).
-- ============================================================
begin;
alter table public.tire_imports drop constraint if exists tire_imports_category_check;
alter table public.tire_imports
  add constraint tire_imports_category_check
  check (category = any (array[
    'pc'::text,            -- Passenger Car (40111000)
    'lt'::text,            -- Light Truck (40112011/12)
    'tb'::text,            -- Truck & Bus (40112013/19/90)
    'mc'::text,            -- Motorcycle (40114000)
    'bc'::text,            -- Bicycle (40115000)              ←신규
    'agr'::text,           -- Agricultural (40117000)
    'ind'::text,           -- Industrial (40118011)
    'mining_truck'::text,  -- Constr/Mining (40118019)
    'otr'::text,           -- OTR rim>61cm (40118021/29 + 40118040 유지)
    'aircraft'::text,      -- Aircraft (40113000)             ←신규
    'other'::text,         -- Other New (40119000)            ←신규
    'retread'::text,       -- Retreaded (40121100/1200/1900)  ←신규
    'used'::text,          -- Used (40122000)                 ←신규
    'solid'::text,         -- Solid (40129016/17)
    'flap'::text,          -- Flap (40129080)
    'tube'::text           -- Inner tubes (4013.xx)
  ]));

comment on column public.tire_imports.category is
  'pc=승용차, lt=경트럭, tb=트럭버스, mc=오토바이, bc=자전거, agr=농업용, ind=산업/지게차, '
  'mining_truck=광산트럭, otr=OTR, aircraft=항공기, other=기타신품, retread=재생, used=중고, '
  'solid=솔리드, tube=이너튜브, flap=플랩';
commit;
