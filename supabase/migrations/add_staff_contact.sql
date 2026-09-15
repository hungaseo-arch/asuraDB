-- ============================================================
-- staff 마스터에 연락처(email·phone) 추가
-- 직원 상세 모달(StaffDetailModal.vue)에서 조회·수정한다.
-- Supabase SQL Editor 1회 실행(멱등).
-- ※ PII 이므로 staff 테이블의 기존 RLS(super_admin/staff 화이트리스트)를 그대로 따른다.
-- ============================================================

alter table public.staff add column if not exists email text;   -- 회사/개인 이메일
alter table public.staff add column if not exists phone text;   -- 휴대전화 (+62…)
comment on column public.staff.email is '이메일 (연락처, PII)';
comment on column public.staff.phone is '전화번호 (연락처, PII)';
