-- 2026-08-08 — RLS 사각지대 봉쇄 (외부 점검에서 발견)
--
-- 배경: 공개 배포본(GitHub Pages)의 anon 키로 REST 를 직접 호출하면 아래 테이블들이
--       그대로 조회됐다. anon 롤에 SELECT/INSERT/UPDATE/DELETE/TRUNCATE 그랜트까지
--       남아 있어 읽기뿐 아니라 위조 삽입·삭제도 가능한 상태였다.
--       (products·documents·staff 등 나머지 테이블은 이미 `to authenticated` 로 차단됨)
--
-- 조치 ① RLS 미적용 7개 테이블: RLS 활성 + anon 그랜트 회수 → 정책이 없으므로 deny-all.
--        수집기·스크립트는 service_role 로 접속해 RLS 를 우회하므로 영향 없음.
-- 조치 ② tire_imports: `to public USING(true)` 정책 2개 제거.
--        동일 권한의 `tire_imports_auth_all`(to authenticated)가 이미 있어 앱 동작은 유지된다.
--
-- 검증(적용 후): anon 키로 curl 시 위 테이블 전부 0 rows.

-- ── ① RLS 미적용 테이블 (백업 5 + 레거시 스펙 + 대시보드 임시 적재) ─────────────
alter table public.products_price_backup_20260729   enable row level security;
alter table public.products_price_backup_20260804   enable row level security;
alter table public.products_price_backup_20260807   enable row level security;
alter table public.products_price_backup_20260807b  enable row level security;
alter table public.products_backup_20260807b        enable row level security;
alter table public.specs_tbr_legacy                 enable row level security;
alter table public.dash_import                      enable row level security;

revoke all on public.products_price_backup_20260729  from anon;
revoke all on public.products_price_backup_20260804  from anon;
revoke all on public.products_price_backup_20260807  from anon;
revoke all on public.products_price_backup_20260807b from anon;
revoke all on public.products_backup_20260807b       from anon;
revoke all on public.specs_tbr_legacy                from anon;
revoke all on public.dash_import                     from anon;

-- ── ② tire_imports — anon 읽기·쓰기 정책 제거 (authenticated 정책만 남긴다) ─────
drop policy if exists "tire_imports read all"  on public.tire_imports;
drop policy if exists "tire_imports write all" on public.tire_imports;
revoke all on public.tire_imports from anon;
