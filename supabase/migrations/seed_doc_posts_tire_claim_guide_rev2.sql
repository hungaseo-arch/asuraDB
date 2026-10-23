-- 2026-10-09 — 회사자료(주요문서) 게시판: 타이어 클레임 점검 가이드북 LTR·TBR Rev.2 등록
-- 본문 : public/docs/tire_claim_inspection_guide_rev2.html (한국어 / Bahasa Indonesia 전환 버튼)
-- 멱등(재실행 안전)
insert into public.doc_posts (title, category, published_on, file, scope)
values ('타이어 클레임 점검 가이드북 · LTR·TBR Rev.2', '기술·품질', '2026-10-09', 'tire_claim_inspection_guide_rev2.html', 'company')
on conflict (file) do update
  set title = excluded.title, category = excluded.category, scope = excluded.scope;
