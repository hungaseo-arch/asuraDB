-- 2026-08-24 — 지표 수집 클라우드 이관 3/3: pg_cron 스케줄 (UTC = WIB−7h)
select cron.schedule('collect-fx',        '15 23 * * *',   $$select public.trigger_collector('fx')$$);
select cron.schedule('collect-commodity', '0 2 * * 1-5',   $$select public.trigger_collector('commodity')$$);
select cron.schedule('collect-weekly',    '0 3 * * 5',     $$select public.trigger_collector('weekly')$$);
select cron.schedule('collect-monthly',   '5 18 * * *',    $$select public.trigger_collector('monthly')$$);
select cron.schedule('reap-cron-responses', '*/10 * * * *', $$select public.reap_cron_responses()$$);
