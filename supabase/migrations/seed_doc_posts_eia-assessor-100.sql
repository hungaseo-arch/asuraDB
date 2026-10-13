insert into public.doc_posts (scope, title, category, published_on, file)
values ('personal', '환경영향평가사 필기 예상문제 100선 · 1~28회 기출분석 + 출제확률순', '자격시험', '2026-09-25', 'eia-assessor-written-exam-100-2026-09-25.html')
on conflict (file) do nothing;
