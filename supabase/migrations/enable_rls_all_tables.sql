-- 전체 테이블 RLS 활성화 (인증 사용자만 허용)
--
-- 정책: 로그인한 사용자(Supabase Auth JWT, role=authenticated)만 읽기/쓰기 허용.
-- anon 키만으로는(비로그인) 모든 테이블 차단 → 외부 노출로부터 사업 데이터 보호.
-- service_role(Edge Function)은 RLS를 우회하므로 영향 없음.
--
-- 정책 이름: <table>_auth_all · 모든 동작(for all) 허용 · 재실행 안전(idempotent)

do $$
declare
  t text;
  tables text[] := array[
    'documents', 'document_links', 'products', 'quotes', 'quote_items', 'tire_sales',
    'margin_months', 'margin_records', 'market_indicators', 'indicator_history',
    'monitoring_reports', 'tire_imports', 'collector_heartbeat',
    'kpi_metrics', 'kpi_monthly'
  ];
begin
  foreach t in array tables loop
    -- 존재하지 않는 테이블은 건너뜀
    if to_regclass('public.' || t) is null then
      continue;
    end if;

    execute format('alter table public.%I enable row level security;', t);
    -- 이전 허용 정책(anon 포함)이 있으면 제거
    execute format('drop policy if exists %I on public.%I;', t || '_anon_all', t);
    execute format('drop policy if exists %I on public.%I;', t || '_auth_all', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true);',
      t || '_auth_all', t
    );
  end loop;
end $$;
