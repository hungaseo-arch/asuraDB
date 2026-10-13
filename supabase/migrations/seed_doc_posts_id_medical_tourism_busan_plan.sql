-- 개인자료(#/seo-docs)에 「인도네시아 대상 한국(부산) 의료관광 사업 실행안」 등록 (2026-10-10 적용, 기록용)
insert into public.doc_posts (scope, title, category, published_on, file, sort_order)
values ('personal', '인도네시아 대상 한국(부산) 의료관광 사업 실행안', '사업검토', '2026-10-03', 'id-medical-tourism-busan-plan-2026-10-03.html', 0)
on conflict (file) do nothing;
