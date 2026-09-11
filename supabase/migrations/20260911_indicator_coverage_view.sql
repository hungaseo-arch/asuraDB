-- 지표별 이력 보유 구간 뷰 (Monitor 산업 지표 카드의 "이력 미보유" 표기용)
--
-- 배경: synthetic_rubber(합성고무 BD) · steel_wire(강선) 는 2025-03 이전 공개 시계열이
-- 없어 5년 백필에서 의도적으로 비워 두었다(docs/indicator-source-audit.md §6).
-- 카드 스파크라인만 보면 "5년치가 있는데 짧게 보이는 것"으로 오해할 수 있어,
-- 보유 시작일을 화면에 함께 표기하려고 만든 조회 전용 뷰.

create or replace view v_indicator_coverage as
select
  h.indicator_id,
  min(h.recorded_date)                                        as first_date,
  max(h.recorded_date)                                        as last_date,
  count(*)::int                                               as rows,
  count(distinct date_trunc('month', h.recorded_date))::int   as months
from indicator_history h
group by h.indicator_id;

grant select on v_indicator_coverage to anon, authenticated, service_role;
