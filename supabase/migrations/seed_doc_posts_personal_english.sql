-- 2026-08-03 — 개인 자료실(SEO자료) 영어학습 자료 3건 추가 + 구동사 학습덱 v2 교체
-- 본문은 public/docs/<file> 정적 HTML, 이 테이블은 목록/검색/분류 메타만 보관.
-- 제목은 각 HTML 의 <title> 과 동일하게 맞춘다. 멱등(재실행 안전).

-- 1) 신규 3건 (file UNIQUE → 재실행 시 무시)
insert into public.doc_posts (scope, title, category, published_on, file)
values
  ('personal', '경동사 학습덱 · 12 이미지 + 연어 200',              '영어학습', '2026-08-02', 'light-verbs-deck-200.html'),
  ('personal', '앞대가리 공식 30 · 문장 여는 덩어리',                '영어학습', '2026-08-02', 'sentence-openers-30.html'),
  ('personal', '일상 영어 100문장 · 상황 카드 10장 + 문장 100개',    '영어학습', '2026-08-03', 'daily-english-100.html')
on conflict (file) do nothing;

-- 2) 구동사 학습덱 → v2 파일로 교체 (기존 행의 file 포인터만 갱신)
--    구버전 파일(public/docs/phrasal-verbs-deck-200.html)은 롤백용으로 남겨둔다.
update public.doc_posts
   set file         = 'phrasal-verbs-deck-200-v2.html',
       published_on = '2026-08-02'
 where scope = 'personal'
   and file  = 'phrasal-verbs-deck-200.html';
