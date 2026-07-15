-- ─────────────────────────────────────────────────────────────────────────────
-- market_indicators · source enum 확장 ('scraper' 추가) + 월간 4개 지표 전환
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 배경
--   기존 source CHECK: yfinance / manual.
--   월간 지표 4개(bi_rate, idn_inflation, idn_pmi, import_tariff) 는 yfinance
--   에 없고 manual 도 아닌 별도 스크래핑 경로(monthly_collector.py)로 자동
--   수집되므로, 별도 'scraper' 라벨이 필요. 라벨 분리로 Monitor UI 의 '수동'
--   뱃지와 수동 입력 모달이 정확히 manual 지표에만 적용됨.
--
-- 영향
--   - 4개 지표는 더 이상 사용자가 UI 에서 수동 입력 불가 (자동 수집 전용)
--   - 자동 수집 실패 시 monthly_collector.py 의 CLI override 로만 입력 가능
--   - 다른 지표(yfinance/manual)는 영향 없음
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) CHECK 제약 교체 (drop → add 단계로 분리, 트랜잭션 안전)
alter table market_indicators
  drop constraint if exists market_indicators_source_check;

alter table market_indicators
  add constraint market_indicators_source_check
  check (source in ('yfinance', 'manual', 'scraper'));

-- 2) 월간 자동 수집 대상 4개 지표를 'scraper' 로 전환
update market_indicators
   set source = 'scraper'
 where id in ('bi_rate', 'idn_inflation', 'idn_pmi', 'import_tariff');

-- 3) 검증 쿼리 (실행 후 결과 확인용 — 주석 해제하여 사용)
-- select id, name_ko, category, alert_level, source
--   from market_indicators
--  where source = 'scraper'
--  order by sort_order;
