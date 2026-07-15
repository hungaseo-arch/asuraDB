-- 2026-07-01 — 지표 카드 완전 제거: KRW/IDR 환율(krw_idr), 수입관세율(import_tariff)
-- indicator_history 는 market_indicators FK ON DELETE CASCADE 로 자동 삭제됨.
delete from public.market_indicators where id in ('krw_idr', 'import_tariff');
