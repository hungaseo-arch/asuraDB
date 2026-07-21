-- 2026-07-17 — doc_posts 에 scope 추가: 회사 자료('정리') vs 개인 자료실('SEO자료') 분리
-- 같은 게시판 구조(Docs.vue)를 두 메뉴가 공유하고, 이 컬럼으로 목록만 갈라 본다.
-- 멱등(재실행 안전).

alter table public.doc_posts
  add column if not exists scope text not null default 'company';

-- 허용값 제한 — 오타로 문서가 어느 목록에도 안 뜨는 사고 방지
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'doc_posts_scope_check'
  ) then
    alter table public.doc_posts
      add constraint doc_posts_scope_check check (scope in ('company', 'personal'));
  end if;
end $$;

-- 기존 문서는 전부 회사 자료로 유지(기본값과 동일하나 명시적으로 고정)
update public.doc_posts set scope = 'company' where scope is null;

-- 목록은 항상 scope 로 걸러 published_on desc 정렬 → 복합 인덱스
create index if not exists doc_posts_scope_published_idx
  on public.doc_posts (scope, published_on desc);
