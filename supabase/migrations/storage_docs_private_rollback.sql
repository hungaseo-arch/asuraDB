-- 2026-10-10 — storage_docs_private.sql 롤백 (적용 직전 실DB pg_policies 기준으로 복원)
-- ⚠ storage.buckets 직접 delete 는 차단될 수 있다 — 버킷/객체 삭제는 Storage API(대시보드 또는 service key)로 할 것.
--    (객체를 먼저 비워야 버킷 삭제 가능. 아래 마지막 delete 는 참고용이며 실패하면 API 로 대체)

-- doc_question_views: 본인 행만
drop policy if exists "doc_question_views own" on public.doc_question_views;
create policy "doc_question_views own"
  on public.doc_question_views for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- doc_posts: 적용 전 상태(super_admin·staff 전체)
drop policy if exists "doc_posts read by role" on public.doc_posts;
drop policy if exists "doc_posts read authenticated" on public.doc_posts;
create policy "doc_posts read authenticated"
  on public.doc_posts for select
  to authenticated
  using (((auth.jwt() -> 'app_metadata') ->> 'role') = any (array['super_admin', 'staff']));

-- storage: docs 정책·버킷 제거
drop policy if exists "docs read by role" on storage.objects;
delete from storage.buckets where id = 'docs';
