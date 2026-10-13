-- 2026-10-10 — 학습 문서(public/docs/*.html)의 문항별 열람 기록 (횟수·최초/최근 열람일시)
-- 문서는 정적 HTML 이라 Docs.vue 뷰어가 postMessage 브리지로 대신 기록한다. 사용자별 본인 행만 접근.
-- 멱등(재실행 안전).
create table if not exists public.doc_question_views (
  user_id         uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  file            text        not null,              -- doc_posts.file
  q_no            int         not null,              -- 문제 번호
  view_count      int         not null default 1,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at  timestamptz not null default now(),
  primary key (user_id, file, q_no)
);

alter table public.doc_question_views enable row level security;

drop policy if exists "doc_question_views own" on public.doc_question_views;
create policy "doc_question_views own"
  on public.doc_question_views for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 열람 1회 기록 — 원자적 증가(동시 호출에도 횟수 유실 없음). security invoker → RLS 적용.
create or replace function public.record_doc_view(p_file text, p_q int)
returns public.doc_question_views
language sql
security invoker
as $$
  insert into public.doc_question_views (user_id, file, q_no)
  values (auth.uid(), p_file, p_q)
  on conflict (user_id, file, q_no) do update
    set view_count     = public.doc_question_views.view_count + 1,
        last_viewed_at = now()
  returning *;
$$;

revoke all on function public.record_doc_view(text, int) from public, anon;
grant execute on function public.record_doc_view(text, int) to authenticated;
