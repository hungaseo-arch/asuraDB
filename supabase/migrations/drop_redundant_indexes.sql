-- ============================================================
-- 중복 인덱스 정리 (AsuraDB_Development_Guide §5 개선 검토점 반영, 2026-07-08)
-- UNIQUE 제약은 내부적으로 동일 컬럼의 btree 인덱스를 자동 생성한다.
-- 아래 두 명시적 인덱스는 그 제약 인덱스와 동일 컬럼 조합이라 순수 중복 →
-- 쓰기(INSERT/UPSERT) 시 이중 인덱스 유지 비용·디스크만 낭비. 조회 성능 손실 없음.
-- 멱등(IF EXISTS). Supabase SQL Editor 에서 1회 실행.
-- ============================================================

-- kpi_monthly: unique(metric_id, year_month) 와 완전 동일 컬럼·순서 → 완전 중복
drop index if exists public.kpi_monthly_metric_ym;

-- indicator_history: unique(indicator_id, recorded_date) 와 동일 컬럼.
--   기존 인덱스는 (indicator_id, recorded_date DESC) 지만, 선행 컬럼(indicator_id)이
--   등호 필터되는 조회 패턴에선 Postgres 가 unique 인덱스를 역방향 스캔해 동일 효율 →
--   DESC 인덱스는 이점이 없어 중복.
drop index if exists public.indicator_history_indicator_date;

-- 참고(미적용): margin_records_ym_axis (year_month, axis) 는 unique 인덱스
--   margin_records_uniq(year_month, axis, primary_key, coalesce(secondary,'')) 의 프리픽스라
--   기술적으로 중복이나, 프리픽스 전용 스캔이 필요하면 좁은 인덱스가 유리할 수 있어 보존.
--   (제거를 원하면 아래 주석 해제)
-- drop index if exists public.margin_records_ym_axis;
