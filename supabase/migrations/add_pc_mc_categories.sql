-- 승용차(pc)·오토바이(mc) 카테고리 추가 — tire_imports.category CHECK 제약 갱신
-- 근거: HS 4종 추가 적재 (40111000 승용차, 40114000 오토바이 → 신규 category,
--       40131011 PC&LT 튜브, 40139020 오토바이 튜브 → 기존 'tube')
-- 실행: Supabase SQL Editor 에서 1회 실행. 멱등(재실행 안전).

alter table public.tire_imports drop constraint if exists tire_imports_category_check;

alter table public.tire_imports
  add constraint tire_imports_category_check
  check (category in ('pc','lt','tb','mc','ind','mining_truck','otr','agr','solid','tube','flap'));

comment on column public.tire_imports.category is
  'pc=승용차, lt=경트럭, tb=트럭버스, mc=오토바이, ind=산업/지게차, mining_truck=광산트럭, otr=OTR, agr=농업용, solid=솔리드, tube=이너튜브, flap=플랩';
