-- 뷰 security_invoker 점검 조치 (2026-09-11)
--
-- 배경: v_indicator_coverage 를 만들며 security_invoker 를 빠뜨려 RLS 를 우회했던 건을 계기로
-- public 스키마의 전체 뷰 30개를 점검했다. 기본값(소유자 권한) 뷰는 기반 테이블의 RLS 를
-- 건너뛰므로, 그 뷰에 anon SELECT 권한이 붙어 있으면 프론트 번들에 실려 나가는 anon 키만으로
-- 데이터를 읽을 수 있다.
--
-- 점검 결과 security_invoker 가 없던 뷰는 6개.
--   · products_sell              : anon 으로 569행(판매가) 조회됨          → 조치
--   · v_weekly_indicator_summary : anon 으로 1,224행 조회됨                → 조치
--   · v_sheet_factory_brand      : anon 으로 26행 조회됨                   → 조치
--   · v_weekly_highlights        : 현재 0행(visits·meetings 가 비어 있음).
--                                  staff·customers·방문메모가 들어오는 즉시 노출 → 선제 조치
--   · v_dot_lookup / v_dot_conflicts : 기반 테이블 dot_plant_codes 의 정책이
--                                  `to anon, authenticated using (true)` 로 **의도적 공개**.
--                                  (add_dot_plant_codes.sql 에서 anon grant 를 명시) → 현행 유지
--
-- 조치 후에도 앱 동작은 그대로다. products_sell 은 Quote.vue 가 distributor/end_user 로 읽는데,
-- 두 역할 모두 products·products_price 의 `role IS DISTINCT FROM 'viewer'` 정책을 통과한다.
-- (그 정책 자체의 범위 문제는 별건으로 docs/auth-audit.md 에 기록)

alter view public.products_sell              set (security_invoker = true);
alter view public.v_weekly_indicator_summary set (security_invoker = true);
alter view public.v_sheet_factory_brand      set (security_invoker = true);
alter view public.v_weekly_highlights        set (security_invoker = true);

revoke all on public.products_sell              from anon;
revoke all on public.v_weekly_indicator_summary from anon;
revoke all on public.v_sheet_factory_brand      from anon;
revoke all on public.v_weekly_highlights        from anon;

grant select on public.products_sell              to authenticated, service_role;
grant select on public.v_weekly_indicator_summary to authenticated, service_role;
grant select on public.v_sheet_factory_brand      to authenticated, service_role;
grant select on public.v_weekly_highlights        to authenticated, service_role;
