-- 2026-08-03 — 게시판 날짜를 '등록일 / 수정일' 2개로 분리
-- published_on = 등록일(최초 게시), updated_on = 수정일(본문 갱신). 수정 이력이 없으면 null → UI 에서 '—' 표기.
alter table public.doc_posts
  add column if not exists updated_on date;

comment on column public.doc_posts.published_on is '등록일 (최초 게시)';
comment on column public.doc_posts.updated_on  is '수정일 (본문 갱신, 없으면 null)';

-- 오늘(2026-08-03) 디자인 통일 작업으로 본문을 실제 수정한 영어학습 덱 4건
update public.doc_posts
   set updated_on = '2026-08-03'
 where file in (
   'phrasal-verbs-deck-200-v2.html',
   'light-verbs-deck-200.html',
   'sentence-openers-30.html',
   'daily-english-100.html'
 );
