-- 스마랑 제외 거래처 목록을 2026-07 지점 보고서 기준(최신)으로 정정.
--
-- 근거: branch_sales_rows(2026-01~07, 출처 `Monthly Sales Smg 2026 010826.csv`)와
--       보고서 「II. Net Semarang」의 월별 제외분(All − Net)을 역산 대조한 결과
--         · 4월부터 PT. RAJAWALI DWIPUTRA INDONESIA 가 제외 대상에 추가됨
--         · 5월부터 CV. KARYA MAJU BAN · CV. NASAMED INTI SUKSES 가 제외 대상에서 빠짐
--       (5·6·7월 Net 이 아래 목록으로 정확히 재현됨. 1~4월은 구 기준이라 차이가 남 —
--        목록에 적용시점 컬럼이 없어 최신 기준 하나만 유지한다.)

delete from public.branch_excluded_buyers
 where branch = 'semarang'
   and buyer in ('CV. KARYA MAJU BAN', 'CV. NASAMED INTI SUKSES');

insert into public.branch_excluded_buyers (branch, buyer)
values ('semarang', 'PT. RAJAWALI DWIPUTRA INDONESIA')
on conflict do nothing;
