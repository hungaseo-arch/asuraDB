-- 2026-10-10 — SEO자료실에 「한국 구매 → 인도네시아 판매 차익 조사 보고서」 등록
-- HTML 본문: public/docs/kr-id-resale-margin-report-2026-10-10.html (자체 완결형, 외부 참조 없음)
-- file UNIQUE → 재실행 시 무시
insert into public.doc_posts (scope, title, category, published_on, file)
values
  ('personal',
   '한국 구매 → 인도네시아 판매 차익 조사 · 36품목 가격비교 + 반입규정',
   '사업검토',
   '2026-10-10',
   'kr-id-resale-margin-report-2026-10-10.html')
on conflict (file) do nothing;
