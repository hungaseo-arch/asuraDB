-- 2026-10-10 — 원본 HTML 이 없는 doc_posts 3건 삭제 (id 18·19·20)
-- 목록에는 보이나 public/docs 에 파일이 없어 열리지 않던 행. 원본을 찾으면 삭제하지 말고 업로드할 것.
-- ⚠ 사용자 확인 후에만 실행.
delete from public.doc_posts
where id in (18, 19, 20)
  and file in ('org_chart_ascendo_2026.html', 'report_writing_guideline_ascendo.html', 'tire_claim_inspection_guide_rev2.html');
