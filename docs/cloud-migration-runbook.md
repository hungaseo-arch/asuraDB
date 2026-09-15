# 지표 수집 클라우드 이관 Runbook (pg_cron + Edge Function)

> 작업지시서 `작업지시서_KPI지표_월별백필_2026.md` §7 산출물. 2026-08-24 구축 완료.
> 로컬 macOS launchd 수집기를 Supabase 클라우드(pg_cron → pg_net → Edge Function)로
> 이관한다. **로컬과 7일 병행 운영 후** 로컬을 내린다(§5 참고).

## 1. 구성 요소

```
pg_cron (UTC 스케줄)
  └─ public.trigger_collector(p_kind)          -- SECURITY DEFINER
       ├─ vault: project_url / service_role_key 조회
       ├─ pg_net: POST {url}/functions/v1/collect-indicators  body={"kind": ...}
       └─ cron_run_log 에 requested 기록
Edge Function collect-indicators (verify_jwt — service_role 토큰으로 통과)
  ├─ kind=fx        환율 4종 + 브렌트유 (Yahoo chart API, yfinance 대체) + krw_idr 파생
  ├─ kind=commodity 고무(USc/kg→USD/MT ×10)·니켈 (TE + 연도필터 + ±25% 가드)
  ├─ kind=weekly    카본블랙(Brent×14)·합성고무BD·강선·SCFI — TE 경로도 ±25% 가드
  ├─ kind=monthly   CPO(Kemendag HR)·석탄(ESDM HBA I/HBA)·BI금리·물가(BPS 2249/1)
  │                 ·PMI·관세 — WIB 말일 가드 + 누락월 catchup
  └─ 실행 후 collector_heartbeat 에 edge_<kind> upsert
public.reap_cron_responses() (10분 주기)
  └─ net._http_response → cron_run_log 상태(ok/error) 회수
```

| 파일 | 내용 |
|---|---|
| `supabase/migrations/20260824_cloud_collectors_infra.sql` | 확장·cron_run_log·trigger_collector·reap |
| `supabase/migrations/20260824_cloud_collectors_vault.sql` | Vault 시크릿 **템플릿** (실값 커밋 금지) |
| `supabase/migrations/20260824_cloud_collectors_schedules.sql` | cron.schedule 5종 |
| `supabase/functions/collect-indicators/index.ts` | Edge Function 본체 (v2, 2026-08-24) |

### Edge Function v2 (2026-08-24 — 5년백필 작업지시서 ②③⑤)

로컬 수집기와 같은 규칙으로 맞췄다. 상세는
[`indicator-source-audit.md`](indicator-source-audit.md).

- 모든 `upsert` 에 **note(출처) 필수 + quality(실측/파생/추정)** — note 없으면 예외
- `nr_rubber` 저장 단위 **USD/MT** (소스 USc/kg ×10, 정확히 한 번)
- `cpo` : Bursa FCPO(MYR/MT) → **Kemendag Harga Referensi(USD/MT)**, commodity → monthly
- `coal`: TE Newcastle → **ESDM HBA I(5,300 kcal)**, weekly → monthly.
  참고 지표 `coal_hba_ref`(HBA 6,322 kcal)는 2026-08-24 삭제 — 저장하지 않는다
- `idn_inflation`: BPS 변수 **1707(인터넷 이용률 — 오적용) → 2249(YoY) / 1(MoM 파생)**
- weekly 의 TE 경로에도 ±25% 이상값 가드 적용
- 이관된 두 지표는 자동 수집 실패 시 **옛 소스로 폴백하지 않고** 수동 입력을 요구한다

> **배포 완료 (2026-08-24)**: `supabase functions deploy collect-indicators
> --project-ref subatvlyfglztdmyexfl` 실행 → **version 3 · ACTIVE**(verify_jwt 유지).
> 스모크 테스트: `{"kind":"ping"}` → HTTP 400 `kind 는 fx|commodity|weekly|monthly …`
> (쓰기 없는 경로로 배포본 응답만 확인).
> 재배포는 같은 명령으로 한다 — 이 프로젝트에는 `supabase/config.toml` 이 없어
> `--project-ref` 가 필수다. (`npm run deploy` 는 프런트엔드 gh-pages 배포로 별개다.)

## 2. 스케줄 (pg_cron = UTC, WIB = UTC+7)

| jobname | UTC | WIB | 대상 |
|---|---|---|---|
| collect-fx | `15 23 * * *` | 매일 06:15 | 환율 4종 + 브렌트 (전영업일 종가 gap-fill) |
| collect-commodity | `0 2 * * 1-5` | 평일 09:00 | 고무·니켈 |
| collect-weekly | `0 3 * * 5` | 금 10:00 | 카본블랙·BD·강선·SCFI |
| collect-monthly | `5 18 * * *` | 매일 01:05 | 월간 6종 (내부 말일 가드로 실제 수집은 말일/catchup 시) |
| reap-cron-responses | `*/10 * * * *` | — | pg_net 응답 회수 |

## 3. 시크릿 (최초 1회 — 완료됨 2026-08-24)

- **Vault** (`trigger_collector` 가 사용) — SQL Editor 에서 1회 실행, git 커밋 금지:
  - `project_url` = `https://<PROJECT_REF>.supabase.co`
  - `service_role_key` = service_role JWT (로컬 `.env` 의 `SUPABASE_SERVICE_KEY`)
  - 템플릿·회전 방법: `supabase/migrations/20260824_cloud_collectors_vault.sql` 주석 참고
- **Edge Function Secrets** (함수 환경변수):
  - `BPS_API_KEY` — `supabase secrets set --project-ref <REF> BPS_API_KEY=<key>` (등록 완료)
  - `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` 는 Supabase 가 자동 주입

**service_role 키 회전 시**: Vault `service_role_key` 를 `vault.update_secret` 으로 갱신
(템플릿 파일 주석의 SQL). Edge Function 은 자동 주입이라 조치 불필요.

## 4. 상태 확인 / 수동 실행

```sql
-- 실행 이력 (최근 20건)
select kind, status, left(detail,200), requested_at from cron_run_log order by id desc limit 20;

-- cron 잡 목록·최근 실행
select jobname, schedule, active from cron.job;
select jobname, status, start_time from cron.job_run_details
  join cron.job using (jobid) order by start_time desc limit 20;

-- 하트비트 (edge_* = 클라우드, *_collector = 로컬)
select * from collector_heartbeat order by last_run desc;

-- 수동 트리거 (즉시 1회)
select public.trigger_collector('fx');        -- fx | commodity | weekly | monthly
select public.reap_cron_responses();          -- 응답 즉시 회수
```

Edge Function 로그: Dashboard → Edge Functions → collect-indicators → Logs
(이상값 가드 발동 시 `[outlier] cpo: ...` 경고가 여기 남는다).

monthly 강제 실행(말일 가드 우회)은 SQL 로는 불가 — 대시보드/curl 로
`{"kind":"monthly","force":true}` POST (Authorization: service_role).

## 5. 병행 운영 → 로컬 종료 절차

**2026-08-24 ~ 08-31 (7일)**: 로컬 launchd 4종( com.asuradb.daily / commodity /
weekly / monthly )과 클라우드를 병행. 같은 (indicator_id, recorded_date) upsert 라
이중 실행해도 중복이 생기지 않는다(멱등).

매일 점검 (병행 기간):
```sql
select kind, status, requested_at from cron_run_log
 where requested_at > now() - interval '1 day' order by id desc;   -- error 없어야 함
```

**7일 후 이상 없으면 로컬 launchd 종료**:
```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.daily.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.commodity.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.weekly.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.monthly.plist
```
plist 파일은 **삭제하지 않고 보존**한다(`scripts/*.plist` + `~/Library/LaunchAgents/`)
— 롤백 시 재-bootstrap 용.

## 6. 롤백 (클라우드 중단 → 로컬 복귀)

```sql
-- 클라우드 수집만 정지 (스키마·로그는 보존)
select cron.unschedule('collect-fx');
select cron.unschedule('collect-commodity');
select cron.unschedule('collect-weekly');
select cron.unschedule('collect-monthly');
select cron.unschedule('reap-cron-responses');
```
```bash
# 로컬 launchd 재가동
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.daily.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.commodity.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.weekly.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.asuradb.monthly.plist
```
데이터는 upsert 멱등이므로 전환 중 이중/공백 실행 모두 안전. 공백이 생기면
`collectors/monthly_backfill.py` 로 말일 보충 가능.

## 7. 알려진 제약

- **cpo·nickel TE 스크래핑**: 클라우드 IP 에서 TE 파싱이 로컬보다 자주 실패할 수
  있다(첫 시험에서 nr_rubber 만 성공). 실패 시 값이 기록되지 않을 뿐 잘못된 값이
  들어가지는 않음(±25% 가드) — 로컬 CLI `--cpo <값>` 수동 입력으로 보충.
- **SCFI**: 로컬과 동일하게 SSE/MacroMicro 취약 (작업지시 알려진 이슈 #9).
- **BI/BPS/PMI**: 소스 구조 변경 시 graceful fail — cron_run_log detail 로 확인.
- Edge Function 실행 상한(기본 150s) — 소스 타임아웃 20s×체인이라 통상 여유.
