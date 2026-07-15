-- ============================================================
-- staff 마스터에 레벨(grade)·직급(position=Jabatan) 추가 + 값 입력
-- 출처: Rekap Gaji Ascendo Internasional, Priode Jun 2026.xls (HQ+지점3, 62명)
-- grade=레벨(L-07 등), position=직급(TEAM LEADER 등). Supabase SQL Editor 1회 실행(멱등).
-- ============================================================

alter table public.staff add column if not exists grade    text;   -- 레벨 (L-07, G-12 …)
alter table public.staff add column if not exists position text;   -- 직급 (Jabatan)
comment on column public.staff.grade    is '레벨 (급여표 Grade)';
comment on column public.staff.position is '직급 (급여표 Jabatan)';

update public.staff s set grade = v.grade, position = v.jabatan
from (values
  ('20140036','L-07','TEAM LEADER'),
  ('20150001','G-12','GENERAL MANAGER'),
  ('20150038','L-10','TEAM LEADER'),
  ('20190202','SS-03','SENIOR SUPERVISOR'),
  ('20191101','L-06','TEAM LEADER'),
  ('20200703','SS-01','SENIOR SUPERVISOR'),
  ('20201001','M-03','MANAGER'),
  ('20210302','L-01','TEAM LEADER'),
  ('20210403','L-03','TEAM LEADER'),
  ('20210901','S-08','STAFF'),
  ('20220708','G-12','GENERAL MANAGER'),
  ('20221201','SS-04','SENIOR SUPERVISOR'),
  ('20230703','L-03','TEAM LEADER'),
  ('20230704','S-07','STAFF'),
  ('20230902','L-01','TEAM LEADER'),
  ('20230903','JS-03','JUNIOR SUPERVISOR'),
  ('20231102','S-07','STAFF'),
  ('20231202','JS-04','JUNIOR SUPERVISOR'),
  ('20240501','S-01','SOPIR'),
  ('20240703','S-03','STAFF'),
  ('20240704','S-03','STAFF'),
  ('20240705','S-03','STAFF'),
  ('20240801','S-01','STAFF'),
  ('20240802','S-01','SOPIR'),
  ('20241002','S-05','STAFF'),
  ('20241201','S-03','STAFF'),
  ('20241202','S-08','STAFF'),
  ('20250803','L-03','TEAM LEADER'),
  ('20251101','S-03','STAFF'),
  ('20251203','L-01','TEAM LEADER'),
  ('20260103','JM-04','SUPERVISOR'),
  ('20260201','S-01','STAFF'),
  ('20260206','S-01','SOPIR'),
  ('220180012','S-01','SOPIR'),
  ('20160624','S-01','NON STAFF'),
  ('20170408','S-03','STAFF'),
  ('20180180','JS-01','JUNIOR SUPERVISOR'),
  ('20180719','S-03','STAFF'),
  ('20190122','S-01','NON STAFF'),
  ('20200901','S-01','NON STAFF'),
  ('20210404','S-01','NON STAFF'),
  ('20210501','S-01','NON STAFF'),
  ('20220702','JM-10','MANAGER'),
  ('20231002','S-01','NON STAFF'),
  ('20231103','S-01','NON STAFF'),
  ('20240706','S-01','NON STAFF'),
  ('20240707','S-01','NON STAFF'),
  ('20240708','S-01','NON STAFF'),
  ('20260503','S-01','STAFF'),
  ('20240711','S-06','BRANCH HEAD'),
  ('20240713','S-01','DRIVER'),
  ('20240714','L-10','TEAM LEADER'),
  ('20241001','L-08','TEAM LEADER'),
  ('20250301','S-01','STAFF'),
  ('20251001','S-01','DRIVER'),
  ('20260203','S-06','STAFF'),
  ('20260502','S-01','STAFF'),
  ('20250802','JS-04','JUNIOR SUPERVISOR'),
  ('20251003','S-01','BRANCH HEAD'),
  ('20251004','L-03','TEAM LEADER'),
  ('20260501','S-01','STAFF'),
  ('20260504','S-01','STAFF')
) as v(nik, grade, jabatan)
where s.nik = v.nik;
