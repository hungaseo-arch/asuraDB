-- 2026-10-09 — 회사자료(정리) 게시판: 보고서 작성 가이드라인 통합본 등록
-- 본문 : public/docs/report_writing_guideline_ascendo.html (원본 HWPX 2026.10.05 개정 통합본)
-- 멱등(재실행 안전)
insert into public.doc_posts (title, category, published_on, file, scope)
values ('보고서 작성 가이드라인 · 통합본 (2026.10 개정)', '문서 표준', '2026-10-09', 'report_writing_guideline_ascendo.html', 'company')
on conflict (file) do update
  set title = excluded.title, category = excluded.category, scope = excluded.scope;
