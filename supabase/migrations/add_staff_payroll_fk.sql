-- staff(nik, primary) ← staff_payroll(nik, foreign) 연결
--
-- 배경: staff 마스터는 6월 급여표(62명) 기준, staff_payroll 은 2026-05 한 달치(64명).
--       5월엔 급여를 받았으나 6월 명부에 없는 3명(5~6월 사이 퇴사)이 고아 행으로 남아
--       FK 를 그대로 걸면 실패한다. 이들의 성명·소속·레벨·직급은
--       'Rekap Gaji Ascendo Internasional, Priode Mei 2026.xls' 에서 확인해 채운다.
-- 멱등: insert .. on conflict do nothing / if not exists 로 재실행 안전.

-- 1) 퇴사자 3명을 staff 마스터에 보강 (is_active=false)
insert into public.staff (nik, name, location, grade, position, is_active) values
  ('20210102', 'AGUS FAUZIANSAH',     'Karawang', 'S-09', 'STAFF', false),
  ('20251006', 'AKHMAD SOFAN SOFYAN', 'Jakarta',  'S-01', 'SOPIR', false),
  ('20260204', 'RENDI BUDI SETIAWAN', 'Surabaya', 'S-01', 'STAFF', false)
on conflict (nik) do nothing;

-- 2) staff_payroll 복합 기본키 (nik, periode) — 같은 사람·같은 달 중복 입력 차단
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.staff_payroll'::regclass and contype = 'p'
  ) then
    alter table public.staff_payroll add constraint staff_payroll_pkey primary key (nik, periode);
  end if;
end $$;

-- 3) 외래키 staff_payroll.nik → staff.nik
--    on delete restrict: 급여 이력이 남은 직원은 staff 에서 삭제 불가(이력 보호)
--    on update cascade : NIK 정정 시 급여 행도 함께 따라감
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'staff_payroll_nik_fkey'
  ) then
    alter table public.staff_payroll
      add constraint staff_payroll_nik_fkey foreign key (nik)
      references public.staff (nik) on update cascade on delete restrict;
  end if;
end $$;
