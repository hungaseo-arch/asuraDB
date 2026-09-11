# AsuraDB 접근제한 감사 — viewer 역할 (경영·성과 전용)

> 2026-08-24 · 작업지시서 「KPI모니터링_접근제한」 이행 기록.
> 목표: 로그인 후 **경영·성과 4탭(KPI `#/monitor` · 마진 `#/margin` · 지점 `#/branch-sales` ·
> 인건비 `#/labor-cost`)만** 볼 수 있는 열람 전용 계정.
> (최초 KPI 단일 탭으로 구축 → 같은 날 경영·성과 4탭으로 확장.)
> 2중 잠금 — ① 라우터 가드(화면), ② Supabase RLS(데이터). GitHub Pages 정적 배포라
> 브라우저 코드만으로는 막을 수 없으므로 **RLS 가 실질 방어선**이다.

---

## 1. 1단계 감사 결과 (현행 인증 구조)

작업지시서의 `profiles` 테이블 · `admin/viewer` 역할명은 **예시**였고, 실제 구조는 다음과 같다.

| 항목 | 실제 구현 |
|---|---|
| 역할 저장 위치 | `auth.users.raw_app_meta_data.role` → JWT 의 `app_metadata.role` 클레임 (`user_metadata` 아님 — self-update 가능해 신뢰 불가) |
| 역할 부여 경로 | `public.user_roles` (user_id·email·role enum `app_role`) upsert → SECURITY DEFINER 트리거 `sync_role_to_auth()` 가 `auth.users` 에 동기화 |
| 기존 역할 | `super_admin`(전체+쓰기) · `staff`(원가 포함 조회) · `distributor`/`end_user`(`/quote`·`/price-compare`만) |
| 프런트 게이팅 | [src/router/index.ts](../src/router/index.ts) `beforeEach` + [src/components/Layout.vue](../src/components/Layout.vue) 내비 분기 + sessionStorage `asura_auth` 캐시 |
| RLS 현황 | public 전 테이블 RLS 활성. 대부분 `to authenticated using(true)` 광역 정책, 일부 역할 제한(products 원가 = super_admin/staff, staff_payroll/staff_private = super_admin) |
| 우회 경로 | definer 뷰 6종(RLS 미적용 실행): `products_sell` · `v_weekly_highlights` · `branch_sales_monthly` · `v_hs_tariff` · `v_cost_indicators` · `v_cost_indicator_history`. SECURITY DEFINER 로 데이터를 반환하는 RPC 는 없음(`hybrid_search`·`next_quote_number` 등 모두 invoker) |
| 제외 대상 | `spb_*` 정책(visits·meetings 등, 타 앱 공유) 불변경 · `dot_plant_codes`(anon 공개, DOT 조회 도구) 유지 · `user_roles`(본인 행만 조회) 유지 · 정책 없는 RLS 테이블(백업·staging)은 기본 거부라 조치 불요 |

## 2. 적용 내용

### DB — [supabase/migrations/20260824_viewer_role_kpi_only_rls.sql](../supabase/migrations/20260824_viewer_role_kpi_only_rls.sql) (MCP `apply_migration` 로 적용 완료)

1. **enum 확장**: `app_role` 에 `viewer` 추가.
2. **모니터링 4테이블** (`kpi_metrics` · `kpi_monthly` · `market_indicators` · `indicator_history`):
   기존 ALL 정책을 viewer 제외로 좁혀 **쓰기 차단**, viewer 용 **SELECT 전용 정책** 신설.
3. **그 외 광역 정책 43개** 의 허용 조건을 `true` → `(((auth.jwt() -> 'app_metadata') ->> 'role') is distinct from 'viewer')` 로 축소.
   `is distinct from` 이므로 **역할 클레임이 없는(null) 기존 계정 포함, viewer 가 아닌 모든 인증 사용자는 종전과 완전히 동일**.
   (ALL 17 + SAP ALL 8 + SELECT 전용 12 + dot_inspection_logs select/insert 2 + 모니터링 4)
4. **definer 뷰 차단**: `branch_sales_monthly` · `v_hs_tariff` · `v_cost_indicators` · `v_cost_indicator_history` 는 `security_invoker = true` 전환(기반 테이블 RLS 적용).
   definer 를 유지해야 하는 `products_sell`(고객용 판매가 — invoker 전환 시 견적 페이지 파손) · `v_weekly_highlights`(spb 멤버십 정책 의존)는 뷰 WHERE 에 viewer 제외 필터를 삽입.

### DB 2차 — [supabase/migrations/20260824_viewer_perf_tabs_rls.sql](../supabase/migrations/20260824_viewer_perf_tabs_rls.sql) (경영·성과 4탭 확장, 적용 완료)

경영·성과 그룹의 나머지 화면이 읽는 테이블에 viewer SELECT 전용 정책 7개 추가
(쓰기는 기존 `*_auth_all` 정책이 viewer 를 제외하므로 계속 차단):

- **마진(Margin.vue)**: `margin_months` · `margin_records` · `margin_lines` + `v_margin_lines`
  조인용 `sap_partners`(거래처명) · `sap_items`(품명). `v_margin_sap_check` 는 definer 뷰로
  집계값만 반환 — 추가 조치 없이 조회됨.
- **지점(BranchSales.vue)**: `branch_sales_rows`(`branch_sales_monthly` invoker 뷰 기반) ·
  `branch_excluded_buyers`.
- **인건비(LaborCost.vue)**: DB 미사용(차트 데이터가 프런트 상수 `@/data/payrollMonthly`) — 조치 불요.
  급여 명세 원본(`staff_payroll` · `staff_private`)은 **super_admin 전용 그대로**(viewer 0건 확인).

### 프런트엔드

| 파일 | 변경 |
|---|---|
| [src/lib/auth.ts](../src/lib/auth.ts) | `Role` 타입·`ALLOWED_ROLES` 에 `'viewer'` 추가 (5역할 모델) |
| [src/router/index.ts](../src/router/index.ts) | `beforeEach` 에 viewer 분기 — 허용 경로 화이트리스트 `/monitor`·`/margin`·`/branch-sales`·`/labor-cost`, 그 외는 `/monitor` 회송 |
| [src/components/Layout.vue](../src/components/Layout.vue) | viewer 는 그룹 드롭다운 대신 경영·성과 4탭(`NAV_GROUPS` perf 그룹 재사용)만 평면 노출, 역할 뱃지 `Viewer` |
| [src/views/PinLogin.vue](../src/views/PinLogin.vue) | 로그인 직후 landing: viewer → `/monitor` |

## 3. 검증 결과 (2026-08-24)

DB 는 `set local role authenticated` + `request.jwt.claims` 주입으로 각 역할 JWT 를 시뮬레이션했다.

| 시나리오 | 결과 |
|---|---|
| viewer — 모니터링 4테이블 SELECT | ✅ kpi_metrics 20 · kpi_monthly 976 · market_indicators 23 · indicator_history 2,427건 조회됨 |
| viewer — 마진·지점 테이블/뷰 SELECT (`margin_months`·`margin_records`·`branch_sales_monthly`·`v_margin_lines`·`v_margin_lines_check`) | ✅ 실제 viewer 토큰(PostgREST)으로 조회됨 |
| viewer — 업무 테이블 SELECT (`products`·`quotes`·`sap_sales_invoices`·`staff_payroll`) | ✅ 전부 0건 (RLS 차단 — 콘솔에서 `supabase.from(...).select()` 해도 빈 배열) |
| viewer — definer 뷰 (`products_sell`·`v_weekly_highlights`) | ✅ 0건 (뷰 내 필터 차단) |
| viewer 계정 로그인 (auth REST `grant_type=password`) | ✅ 토큰 발급 + JWT `app_metadata.role = viewer` 확인 |
| staff — 종전 동작 | ✅ products 582 · margins 15,658 · quotes 20 · 뷰 3종 모두 종전대로 조회 |
| distributor — 종전 동작 | ✅ products_sell 569 · quotes 20 (price_comparisons 0건은 원래 빈 테이블) |
| `npm run build` | ✅ 타입·빌드 통과 |
| `get_advisors`(security) | ✅ RLS 미활성 테이블 0건. 잔여 항목은 전부 기존 사항(백업 테이블 정책 없음 = 기본 거부, definer 뷰 4종은 의도적 유지, 함수 search_path 경고 등) |

화면 검증(수동): viewer 계정 로그인 → 경영·성과 4탭만 보임 · 주소창 `#/quote` 등 직접 입력 → `/monitor` 회송 · 로그아웃 → `/login`.

## 4. 운영 메모 — viewer 계정 만들기 / 역할 변경

**운영 중인 viewer 계정**: `viewer@ptascendo.com` (2026-08-24 SQL 로 생성 — `auth.users` +
`auth.identities` insert 후 `user_roles` 를 `viewer` 로 갱신, 로그인·역할 클레임 검증 완료).

1. Supabase 대시보드 Authentication → Add user 로 이메일·비밀번호 계정 생성 (또는 기존 계정 사용).
2. 역할 부여는 SQL 1줄 (`user_roles` upsert → 트리거가 JWT 클레임에 자동 동기화):

```sql
insert into public.user_roles (user_id, email, role)
select id, email, 'viewer' from auth.users where email = '<대상 이메일>'
on conflict (user_id) do update set role = excluded.role, updated_at = now();
```

3. **이미 로그인 중인 세션의 JWT 에는 즉시 반영되지 않음** — 대상자가 로그아웃 후 재로그인해야 새 역할 적용.
4. 역할 회수(viewer → staff 등)도 같은 SQL 에서 `'viewer'` 만 바꾸면 된다.
5. 신규 계정에 역할을 넣지 않으면 라우터는 `/quote` 로 제한하고 RLS 광역 정책은 통과되므로, **외부인 계정은 반드시 역할을 지정**할 것.

---

## 5. 뷰 `security_invoker` 전수 점검 (2026-09-11)

`v_indicator_coverage` 를 `security_invoker` 없이 만들어 RLS 를 우회했던 건을 계기로
public 스키마 뷰 **30개 전수**를 점검했다. (기본값 뷰는 소유자 권한으로 실행되어 기반 테이블의
RLS 를 건너뛴다. 그 뷰에 anon SELECT 가 붙어 있으면 프런트 번들에 실려 나가는 anon 키만으로 읽힌다.)

### 결과 — 누락 6개

| 뷰 | anon 조회 결과 | 판정 | 조치 |
|---|---|---|---|
| `products_sell` | **569행** (판매가) | 노출 | `security_invoker` + anon 회수 |
| `v_weekly_indicator_summary` | **1,224행** | 노출 | 〃 |
| `v_sheet_factory_brand` | **26행** | 노출 | 〃 |
| `v_weekly_highlights` | 0행 (`visits`·`meetings` 가 아직 비어 있어서) | 잠재 노출 | 〃 (선제) |
| `v_dot_lookup` | 2,174행 | 정상 | 현행 유지 — 기반 `dot_plant_codes` 정책이 `to anon, authenticated using (true)` 로 **의도적 공개** |
| `v_dot_conflicts` | 0행 | 정상 | 현행 유지 (같은 사유) |

- 조치: [supabase/migrations/20260911_view_security_invoker_audit.sql](../supabase/migrations/20260911_view_security_invoker_audit.sql) (MCP `apply_migration` 적용 완료)
- 검증: anon → `permission denied for view products_sell`. distributor JWT → `products_sell` 569행 유지
  (Quote.vue 의 distributor/end_user 경로 영향 없음).
- 나머지 24개 뷰는 이미 `security_invoker=true`(또는 `=on`). 점검 시 `reloptions` 를
  `like 'security_invoker=%true%'` 로만 보면 **`=on` 표기를 놓친다** — 두 표기 모두 확인할 것.

### 별건 — `role IS DISTINCT FROM 'viewer'` 정책의 범위 (미조치, 결정 필요)

- 현재 RLS 정책 다수가 `((auth.jwt()->'app_metadata')->>'role') IS DISTINCT FROM 'viewer'` 형태다.
  이 조건은 `viewer` 만 막으므로 **`distributor`·`end_user` 는 통과**한다.
- 실측(2026-09-11, distributor JWT 시뮬레이션): `products` 582행 · `products_price` 582행(FOB·도매원가) ·
  `margin_records` 15,658행 · `sap_purchase_invoice_lines` 21,706행이 그대로 읽혔다.
- 라우터(`src/router/index.ts`)는 distributor/end_user 를 `/quote`·`/price-compare` 로 제한하지만,
  **PostgREST 는 같은 토큰으로 직접 호출 가능**하므로 화면 게이팅만으로는 막히지 않는다.
- 해당 패턴을 쓰는 테이블은 **42개**. 정책을 `= ANY(ARRAY['super_admin','staff'])` 화이트리스트로
  바꾸는 것이 정석이나, 범위가 넓어 수집기·PWA 포함 회귀 확인이 필요하다. 별도 작업으로 분리.
