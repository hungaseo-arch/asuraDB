-- 2026-10-09 — 회사자료(정리) 게시판: 아센도 조직도 2026 등록
-- 본문 : public/docs/org_chart_ascendo_2026.html (원본 조직도_아센도_20261009.drawio 디자인 재현)
-- 멱등(재실행 안전)
insert into public.doc_posts (title, category, published_on, file, scope)
values ('아센도 조직도 · 2026', '조직·인사', '2026-10-09', 'org_chart_ascendo_2026.html', 'company')
on conflict (file) do update
  set title = excluded.title, category = excluded.category, scope = excluded.scope;
