-- 지표별 이력 보유 구간 뷰 (Monitor 산업 지표 카드의 "이력 미보유" 표기용)
--
-- 배경: synthetic_rubber(합성고무 BD) · steel_wire(강선) 는 2025-03 이전 공개 시계열이
-- 없어 5년 백필에서 의도적으로 비워 두었다(docs/indicator-source-audit.md §6).
-- 카드 스파크라인만 보면 "5년치가 있는데 짧게 보이는 것"으로 오해할 수 있어,
-- 보유 시작일을 화면에 함께 표기하려고 만든 조회 전용 뷰.
--
-- 보안: 기반 테이블 indicator_history 는 RLS 가 켜져 있고 정책이 to authenticated
-- 전용이다. 뷰를 기본값(소유자 권한)으로 두면 그 RLS 를 건너뛰므로, 같은 계열 뷰
-- (v_cost_indicators · v_cost_indicator_history)와 동일하게 security_invoker 로 만들고
-- anon 에는 권한을 주지 않는다.

drop view if exists v_indicator_coverage;

create view v_indicator_coverage
with (security_invoker = true) as
select
  h.indicator_id,
  min(h.recorded_date)                                        as first_date,
  max(h.recorded_date)                                        as last_date,
  count(*)::int                                               as rows,
  count(distinct date_trunc('month', h.recorded_date))::int   as months
from indicator_history h
group by h.indicator_id;

revoke all on v_indicator_coverage from anon;
grant select on v_indicator_coverage to authenticated, service_role;
