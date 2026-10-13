-- 2026-10-10 — 자료실 문서 비공개 전환: private 버킷 `docs` + 역할별 열람 정책
-- 본문 HTML 은 Storage(docs/<scope>/<file>) 로 옮기고, doc_posts 는 목록 메타만 보관한다.
-- 접근 규칙(JWT app_metadata.role 기준 — user_metadata 는 self-update 가능해 신뢰 불가):
--   personal  → super_admin
--   company   → super_admin · staff
--   templates → super_admin   (목록 미등록 템플릿 보관용)
-- 업로드·수정·삭제 정책은 만들지 않는다(service_role 전용). 멱등(재실행 안전).
-- ⚠ `supabase db push` 사용 금지 — SQL Editor 또는 service key 로 적용.

insert into storage.buckets (id, name, public)
values ('docs', 'docs', false)
on conflict (id) do update set public = false;

-- ── Storage: 경로 첫 폴더(scope)로 판정 ─────────────────────────────────────
drop policy if exists "docs read by role" on storage.objects;
create policy "docs read by role"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'docs'
    and (
      ((storage.foldername(name))[1] = 'personal'
        and (auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
      or ((storage.foldername(name))[1] = 'company'
        and (auth.jwt() -> 'app_metadata' ->> 'role') in ('super_admin', 'staff'))
      or ((storage.foldername(name))[1] = 'templates'
        and (auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
    )
  );

-- ── doc_posts: 목록 메타도 같은 규칙으로 좁힌다 ──
-- (실DB 확인: 기존 정책 "doc_posts read authenticated" 는 이미 super_admin·staff 로 좁혀져 있었음 — personal 구분만 신설)
-- 기존 정책은 drop 해 permissive OR 로 남지 않게 한다.
drop policy if exists "doc_posts read authenticated" on public.doc_posts;
drop policy if exists "doc_posts read by role" on public.doc_posts;
create policy "doc_posts read by role"
  on public.doc_posts for select
  to authenticated
  using (
    (scope = 'personal' and (auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
    or (scope = 'company' and (auth.jwt() -> 'app_metadata' ->> 'role') in ('super_admin', 'staff'))
  );

-- ── doc_question_views: 본인 행 + 해당 문서가 doc_posts RLS 로 보이는 경우만 ──────
-- exists 서브쿼리는 호출자 권한(RLS)으로 평가 → distributor 등은 personal/company 문서의 열람기록을
-- 만들거나 읽을 수 없다. record_doc_view 는 security invoker 라 같은 정책을 그대로 탄다(함수 수정 불필요).
drop policy if exists "doc_question_views own" on public.doc_question_views;
create policy "doc_question_views own"
  on public.doc_question_views for all
  to authenticated
  using (
    user_id = auth.uid()
    and exists (select 1 from public.doc_posts p where p.file = doc_question_views.file)
  )
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.doc_posts p where p.file = doc_question_views.file)
  );
