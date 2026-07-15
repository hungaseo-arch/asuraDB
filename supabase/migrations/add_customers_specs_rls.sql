-- ============================================================
-- customers + 스펙 테이블 RLS 정책 — Databases.vue 연동용
-- Supabase SQL Editor 1회 실행(멱등). 테이블 자체는 이미 생성됨.
--   - 스펙(tbr/tbb/otr/agr_specs): 카탈로그성 → 로그인 사용자 읽기, 쓰기는 super_admin
--   - customers: 내부 담당자 정보 포함 → 읽기 super_admin/staff, 쓰기 super_admin
-- ============================================================

-- ── 1. 스펙 테이블: 읽기 authenticated / 쓰기 super_admin ────
do $$
declare t text;
begin
  foreach t in array array['tbr_specs','tbb_specs','otr_specs','agr_specs'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists %I on public.%I;', t || '_read_auth', t);
    execute format('create policy %I on public.%I for select to authenticated using (true);', t || '_read_auth', t);
    execute format('drop policy if exists %I on public.%I;', t || '_write_admin', t);
    execute format(
      $p$create policy %I on public.%I for all to authenticated
        using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
        with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');$p$,
      t || '_write_admin', t);
  end loop;
end $$;

-- ── 2. customers: 읽기 super_admin/staff / 쓰기 super_admin ──
alter table public.customers enable row level security;
drop policy if exists customers_read_staff on public.customers;
create policy customers_read_staff on public.customers
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('super_admin','staff'));
drop policy if exists customers_write_admin on public.customers;
create policy customers_write_admin on public.customers
  for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
