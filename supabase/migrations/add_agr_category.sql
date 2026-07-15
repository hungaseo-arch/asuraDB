-- AGR(농업용 타이어) 카테고리 추가 — tire_imports.category CHECK 제약 갱신
-- 근거: HS 40117000 (Agricultural/forestry) 을 'agr' 로 적재하려면 CHECK 허용값에 포함돼야 함.
--       (프런트엔드 TireImport.vue 는 이미 agr 를 마스터/색상/라벨에 포함하고 있음)
-- 실행: Supabase SQL Editor 에서 1회 실행. 멱등(재실행 안전).

alter table public.tire_imports drop constraint if exists tire_imports_category_check;

alter table public.tire_imports
  add constraint tire_imports_category_check
  check (category in ('lt','tb','ind','mining_truck','otr','agr','solid','tube','flap'));

comment on column public.tire_imports.category is
  'lt=경트럭, tb=트럭버스, ind=산업/지게차, mining_truck=광산트럭, otr=OTR, agr=농업용, solid=솔리드, tube=이너튜브, flap=플랩';
