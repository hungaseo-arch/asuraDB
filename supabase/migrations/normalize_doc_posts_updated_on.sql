-- 2026-08-08 — doc_posts.updated_on 정합성 정리
--
-- 배경: add_doc_posts_updated_on.sql 이 2026-08-03 디자인 통일 대상 4건에 updated_on='2026-08-03' 을 넣었는데,
--       그중 daily-english-100.html(id=10) 은 같은 날 최초 등록된 글이어서 등록일 == 수정일 이 됐다.
--       '수정일' 은 등록 이후 본문이 바뀐 날만 의미하므로, 등록일과 같은 값은 null(미수정) 이 맞다.
-- 확인: 2026-08-08 기준 doc_posts 8건 = company 3건(updated_on 전부 null · 미수정) +
--       personal 5건(updated_on 4건 중 3건은 등록일 이후 실제 수정, 1건이 아래 대상).
--       → 목록의 '수정일 —' 은 데이터 누락이 아니라 '수정 이력 없음' 이 정상 표기다.
update public.doc_posts
   set updated_on = null
 where updated_on is not null
   and updated_on = published_on;
