# 지표 출처·단위·품질 감사 문서 (2021-09 ~ 2026-08, 60개월)

> 작업지시서 `작업지시서_KPI지표_5년백필_2021-2026.md` 산출물. 실행일 2026-08-24.
> 원칙: 삭제 없음(백업 테이블 선행) · 모든 쓰기는 `upsert on_conflict(indicator_id,
> recorded_date)` · 모든 행에 `note`(출처) + `quality`(실측/파생/추정) · DB 직접 INSERT
> 금지(스크립트 경유) · 추정이 실측을 덮어쓰지 않음 · 단위 환산은 정확히 한 번.
>
> 2026-01~08 구간의 선행 작업은 [`indicator-backfill-audit.md`](indicator-backfill-audit.md),
> 클라우드 수집 구조는 [`cloud-migration-runbook.md`](cloud-migration-runbook.md) 참고.

## 1. 출처 SSOT — `market_indicators` 로 일원화

화면(`Monitor.vue`)에 있던 `INDICATOR_SOURCE` 하드코드 맵을 **삭제**하고, 출처
메타를 DB 컬럼으로 옮겼다. 카드·추이 모달·CSV/XLSX 내보내기가 모두 이 컬럼을 읽는다.

| 컬럼 | 뜻 |
|---|---|
| `source_name` | 1차 소스 이름 (화면 단위줄에 표시) |
| `price_basis` | 가격 기준·산정 방식 (툴팁·모달에 표시) |
| `source_url` | 원본 링크 (모달의 "원본 ↗") |
| `unit_native` | 소스가 발표하는 원 단위 |
| `unit_factor` | **저장값 = 원 단위 값 × unit_factor** |

`grep INDICATOR_SOURCE src/` = **0건** (2026-08-24 확인).

## 2. 지표별 출처·단위 대조표 (60개월 말일 행 기준)

품질 열은 `실측/파생/추정` 행 수.

| 지표 | 이름 | 저장 단위 | 원 단위 ×계수 | 출처(`source_name`) | 품질 |
|---|---|---|---|---|---|
| brent_crude | 브렌트유 | USD/bbl | USD/bbl ×1 | Yahoo Finance (BZ=F) | 60/0/0 |
| nr_rubber | 천연고무 TSR20 | USD/MT | USD/kg ×1000 | World Bank Pink Sheet · Rubber TSR20 | 60/0/0 |
| cpo | 팜유 CPO | USD/MT | USD/MT ×1 | Kemendag · Harga Referensi CPO | 60/0/0 |
| nickel | 니켈 | USD/MT | USD/mt ×1 | World Bank Pink Sheet · Nickel | 60/0/0 |
| coal | 석탄 HBA I | USD/MT | USD/ton ×1 | ESDM · Harga Batubara Acuan (HBA I) | 42/0/18 |
| carbon_black | 카본블랙 | USD/MT | USD/MT ×1 | 브렌트유 × 14.0 환산 (추정) | 6/2/52 |
| synthetic_rubber | 합성고무 BD | USD/MT | USD/MT ×1 | Trading Economics · Butadiene | 5/2/5 |
| steel_wire | 강선 (HRC 연동 추정) | USD/MT | USD/MT ×1 | Trading Economics · Steel HRC (강선 대용) | 0/0/12 |
| scfi | SCFI 컨테이너운임 | Index | Index ×1 | SSE 상하이해운거래소 · SCFI Composite | 42/0/18 |
| usd_idr | USD/IDR | IDR | IDR ×1 | Yahoo Finance (USDIDR=X) | 60/0/0 |
| usd_krw | USD/KRW | KRW | KRW ×1 | Yahoo Finance (USDKRW=X) | 60/0/0 |
| usd_cny | USD/CNY | CNY | CNY ×1 | Yahoo Finance (USDCNY=X) | 60/0/0 |
| krw_idr | KRW/IDR | IDR/KRW | 파생 | 파생 · USD/IDR ÷ USD/KRW (Yahoo Finance) | 0/60/0 |
| bi_rate | BI 기준금리 | % | — | Bank Indonesia · BI-Rate | 18/42/0 |
| idn_inflation | 인도네시아 물가 | % | — | BPS 인도네시아 통계청 · Web API | 31/28/0 |
| idn_pmi | 인도네시아 PMI | Index | — | S&P Global (Trading Economics 경유) | 59/0/0 |

사내 수동 입력 지표 7종(`tbr_sales`·`otr_sales`·`ind_sales`·`agr_sales`·
`competitor_price`·`receivables_ar`·`operating_ratio`)은 외부 소스가 없어
`source_url` 이 비어 있고, `source_name`/`price_basis` 에 사내 근거를 적었다
(`20260824_source_meta_fill.sql`).

## 3. 단위 통일 (작업지시서 ②)

| 지표 | 변경 전 | 변경 후 | 비고 |
|---|---|---|---|
| nr_rubber | USc/kg (일별 수집기) | **USD/MT** | 환산 ×10 을 **정확히 한 번**. 백필은 Pink Sheet USD/kg ×1000 |
| cpo | Bursa FCPO **MYR/MT** | **USD/MT** — Kemendag Harga Referensi | 통화·기준이 모두 달라 소스 자체를 교체 |
| coal | TE Newcastle | **ESDM HBA I** (5,300 kcal GAR) | 인니 정부 고시가. 참고 지표 `coal_hba_ref`(HBA 6,322 kcal)는 2026-08-24 삭제(§11) |
| brent_crude | USD/bbl | USD/bbl 유지 | 배럴이 표준 — 화면에만 환산 안내(× 7.33 ≈ USD/MT) |

### HBA 규격 이력 (역산 근거)

- **2023-03**: HBA I 도입 (5,200 kcal/kg GAR)
- **2023-08**: 규격 개정 → **5,300 kcal/kg GAR** (현행)
- **2025-03**: 월 2기(1일·15일) 고시 개시 → 월값은 그 달 **마지막 고시**를 채택
- **2021-09 ~ 2023-02** (HBA I 미도입): `HBA × 0.6941` 로 역산 = **추정 18개월**.
  계수는 5,300 kcal 구간(2023-08~)의 `HBA I ÷ HBA` **중앙값**.

## 4. 품질 등급 (작업지시서 ③)

| 등급 | 뜻 |
|---|---|
| **실측** | 1차 공식 소스가 발표한 원본값. 단위 환산만 적용된 값도 실측 유지 |
| **파생** | 규칙으로 산출 (환율 재정, 결정값 유지, M-to-M 누적환산 등) |
| **추정** | Proxy·역산·보간 |

화면 노출 4곳: ① 카드 배지(추정/파생) ② 추이 모달의 **추정 구간 점선** ③ 툴팁의
등급+근거 ④ CSV/XLSX 내보내기의 `품질등급`·`출처(행)` 열.

우선순위 `실측(3) > 파생(2) > 추정(1)` — 백필 플래너가 **등급 하향을 차단**하므로
`--overwrite` 로도 추정이 실측을 덮어쓰지 못한다.

## 5. BPS 물가 변수 정정 (중요)

기존 수집기가 쓰던 **BPS 변수 1707 은 물가지표가 아니다** — "10세 이상 인터넷 이용
인구 비율" 이었고, 그 값이 `idn_inflation` 으로 저장돼 왔다. 실제 변수는:

| 변수 | 이름 | 범위 | 등급 |
|---|---|---|---|
| **2249** | Inflasi Tahunan (Y-on-Y, 2022=100, vervar 151) | 2024-01 ~ | 실측 |
| **1** | Inflasi Bulanan (M-to-M, vervar 9999) | 2020-01 ~ | 12개월 누적환산 → 파생 |

API 사용법: `th`(연도) 파라미터 **필수**, 1회 호출당 **최대 3개년**, 연도 id = 연도 −
1900, `datacontent` 키 = `{vervar}{var}{turvar=0}{tahun_id}{month}`, **월 13 = 연간
집계라 제외**. 로컬 `monthly_collector.py` 와 Edge Function 양쪽에 반영했다.

## 6. 60개월 커버리지 (2026-08-24 검증)

말일 행 **862행**, `note` 누락 0 · `quality` 누락 0 (실측 623 / 파생 134 / 추정 105).
(백필 직후에는 922행이었고, §11 의 `coal_hba_ref` 60행 삭제로 862행이 됐다.)

| 지표 | 보유 | 비고 |
|---|---|---|
| brent_crude · nr_rubber · cpo · nickel · coal · carbon_black · scfi · usd_idr · usd_krw · usd_cny · krw_idr · bi_rate | 60/60 | ✅ |
| idn_inflation · idn_pmi | 59/60 | 2026-08 은 **2026-09-01 발표** 예정 (정당한 공백) |
| synthetic_rubber · steel_wire | 12/60 | 2021-09 ~ 2025-11 **48개월 공백** — 공개 시계열 없음 |

`synthetic_rubber`·`steel_wire` 의 48개월은 **채우지 않았다**. 근거 있는 값이 없어
보간하면 그 자체가 허위 시계열이 되기 때문이다. 공급사 견적(Kumho·LANXESS /
Bekaert·Hyosung) 또는 유료 시계열(ICIS·SteelOrbis) 확보 시 CSV(T5) 경로로 반영한다.

### 6.1 소스 재조사 (2026-09-11) — 결론 유지

공백 2종(2021-09 ~ 2025-02, **각 42개월**)을 채울 공개 소스를 다시 뒤졌고, **채우지 않는
결정을 유지**한다.

| 후보 소스 | 결과 |
|---|---|
| FRED (`fredgraph.csv`, 키 불필요) | **연결 불가** — 이 네트워크에서 `http 000` |
| Trading Economics 상품 페이지 | 현재값만 공개. 페이지에 과거 시계열 미포함(2021 문자열 0건), 이력은 유료 API |
| World Bank Pink Sheet (캐시 보유) | 71개 계열에 **HRC·부타디엔 없음**. 철광석(`$/dmtu`)·천연고무만 해당 |
| Yahoo `HRC=F` (CME 열연코일 선물) | ✅ **실측 확보** — 2020-10 ~ 2026-09 월봉 63개, USD/short ton |

`HRC=F` 는 실측이지만 **그대로 쓸 수 없다**. 겹치는 구간(2025-03 ~ 2026-08)으로 환산비를
검증한 결과:

| 지표 | 드라이버 | 환산비 범위 | 변동계수 |
|---|---|---|---|
| steel_wire | HRC=F (USD/MT 환산) | 0.381 ~ 0.913 | **19.5%** |
| synthetic_rubber | Brent | 17.5 ~ 32.9 | **17.7%** |

즉 프록시 환산으로 42개월을 생성하면 **월별 ±20~30% 오차**가 섞인다. 또 `HRC=F` 는 미국
내수(CME) 기준이라 현 DB 값(TE·중국 기준, 2026-08 = 933.51)보다 약 **+40% 높은 가격대**
여서, 과거 구간에 이어 붙이면 2025-03 지점에 인위적 단차가 생긴다. `carbon_black =
Brent×14.0` 같은 프록시 선례가 있긴 하나, 그쪽은 전 구간이 **한 가지 방법**으로 일관된
반면 이 경우는 구간마다 소스·시장이 갈린다.

**대신 취한 조치** — 카드 스파크라인이 짧은 것을 "데이터 누락"으로 오해하지 않도록,
`v_indicator_coverage` 뷰(`supabase/migrations/20260911_indicator_coverage_view.sql`)를
만들어 `Monitor.vue` 산업 지표 카드에 **보유 시작 연월(`이력 2025-03~`)** 을 표기했다
(60개월 미만 지표에만 노출 → 현재 이 2종만 해당).

## 7. ±50% MoM 변동 검토 (8건, 전부 판정 완료)

| 지표 | 구간 | 판정 |
|---|---|---|
| brent_crude | 2026-02 72.48 → 03 118.35 (+63%) | **실제 급등** — 일별 종가가 3월 내내 연속 상승(77→118), 오류 아님 |
| idn_inflation | 2024-12~2025-04 4건 | **비율 왜곡** — 값 자체가 % 이고 0 근처(-0.09)라 상대변화율이 무의미 |
| scfi | 2023-11→12 (+77%), 2024-04→05 (+57%) | **실제 급등** — 홍해 사태·컨테이너 운임 급등기 |
| steel_wire | 2026-07 500 → 08 933.51 (+87%) | **소스 노이즈** — 아래 §8 |

## 8. 데이터 품질 플래그 (후속 확인)

- **steel_wire / synthetic_rubber 의 TE 일별값**: 2026-07~08 에 steel_wire 가
  308~977, synthetic_rubber 가 1,054~2,753 을 오갔다. TE 페이지 파싱이 무관한
  숫자를 집는 사고로, 그 달 말일 파생값(steel_wire 07=500 · 08=933.51)의 신뢰도가
  낮다. **조치**: `weekly_collector._reject_outlier()` (±25%) 를 TE 경로에 추가하고
  Edge Function `runWeekly` 에도 같은 가드를 넣었다(이전에는 daily 에만 있었다).
  기존 두 행은 삭제 금지 원칙에 따라 **그대로 두고 여기 기록**한다 — 공급사 견적
  수령 시 CLI(`--steel-wire`)로 정정.
- **carbon_black**: 전 구간 브렌트유 ×14 Proxy(추정 52/60). 분기별 공급사 견적으로
  실측 보정 권장.
- **ESDM 사이트 점검 중**: 2026-08-24 기준 `minerba.esdm.go.id` 가
  "Sistem Sedang Dalam Perbaikan" 상태라 HBA 자동 수집이 실패한다. 수집기는 옛
  소스로 되돌아가지 않고 **수동 입력을 요구**하도록 만들었다 (`--coal`).

## 9. 수집기·클라우드 정합 (작업지시서 ⑤)

| 파일 | 변경 |
|---|---|
| `collectors/daily_collector.py` | cpo 수집 경로 삭제(Bursa 스크래퍼·CLI 포함) · nr_rubber 저장값 ×10 (USD/MT) · `upsert(quality=)` |
| `collectors/weekly_collector.py` | coal 수집 경로 삭제 · `upsert(quality=)` · TE 경로에 `_reject_outlier` · carbon_black/steel_wire = 추정 |
| `collectors/monthly_collector.py` | **cpo(Kemendag HR)·coal(ESDM HBA I) 신규 수집** · BPS 2249/1 정정 · `upsert(quality=)` |
| `supabase/functions/collect-indicators/index.ts` | 위 4가지를 그대로 포팅한 **v2** (note 필수 + quality, 단위 환산, 소스 이관, 이상값 가드) |

두 이관 지표(cpo·coal)는 자동 수집 실패 시 **옛 소스로 폴백하지 않는다**. 단위·기준이
다른 값이 같은 시계열에 섞이는 것이 결측보다 나쁘기 때문이다.

```bash
# 수동 입력 (월간)
~/.venvs/asuradb/bin/python collectors/monthly_collector.py --cpo 996.52
~/.venvs/asuradb/bin/python collectors/monthly_collector.py --coal 96.92
```

## 10. 재실행 방법

```bash
# dry-run (쓰기 없음)
~/.venvs/asuradb/bin/python collectors/history_backfill.py --dry-run
# 티어·지표·구간 지정
~/.venvs/asuradb/bin/python collectors/history_backfill.py --tier 3 --only coal --from 2021-09
# 수기 확정값 (T5) — 헤더: indicator_id,year_month,value,unit,quality,source_note
#   source_note 없는 행·등급 오기·단위 불일치 행은 자동으로 무시된다.
~/.venvs/asuradb/bin/python collectors/history_backfill.py --tier 5 --from-csv data/backfill_history.csv
```

T3 근거 CSV(`data/research/cpo_hr_kemendag.csv`·`hba_esdm.csv`)는 `--from-csv` 가 아니라
티어 3 실행 시 자동으로 읽힌다 — 값을 고칠 때는 이 파일이 SSOT 다.

## 11. 지표 삭제 — `coal_hba_ref` (석탄 HBA 기준가, 2026-08-24)

석탄 원가 기준을 **HBA I(5,300 kcal)** 하나로 확정하면서, 참고용으로 함께 저장하던
HBA(6,322 kcal) 지표 `coal_hba_ref` 를 **삭제**했다(운영 요청). 대시보드에 실제 원가와
무관한 카드·추이가 하나 더 노출되는 문제 해소.

| 대상 | 조치 |
|---|---|
| 백업 | `indicator_history_backup_coal_hba_ref_20260824`(60행) · `market_indicators_backup_coal_hba_ref_20260824`(1행) — 생성·대조 완료(차이 0) |
| DB 삭제 | `supabase/migrations/20260824_drop_coal_hba_ref.sql` (이력 60행 + 지표 정의 1행) — **실행 완료**(잔여 0행 확인) |
| `collectors/monthly_collector.py` | `_fetch_hba()` 가 HBA I 열만 파싱 · `--coal-hba` CLI 제거 |
| `collectors/history_backfill.py` | T3 목록·`planner.add` 제거. HBA 원계열은 **역산 계수 산출용으로만** 읽는다 |
| `supabase/functions/collect-indicators/index.ts` | `collectCoal()` 이 HBA I 만 저장 (v2, `deno check` 통과) |
| `src/views/Monitor.vue` | `INDICATOR_INFO` 항목 제거 |

**역산 근거는 유지된다** — HBA I 도입 전(2021-09~2023-02) coal 추정 구간의 계수
(HBA × 0.6941)는 각 행 `note` 와 원자료 `data/research/hba_esdm.csv` 에 그대로 남는다.

복구가 필요하면 백업 테이블에서 되돌린다:

```sql
insert into public.market_indicators  select * from public.market_indicators_backup_coal_hba_ref_20260824;
insert into public.indicator_history select * from public.indicator_history_backup_coal_hba_ref_20260824;
```
