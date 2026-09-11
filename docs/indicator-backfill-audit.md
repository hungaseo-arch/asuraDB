# KPI 지표 월별 백필 감사 문서 (2026-01 ~ 2026-08)

> **후속 작업 있음 (2026-08-24)**: 이 문서 이후 5년(2021-09~2026-08) 백필과 출처·단위·
> 품질 등급 정비를 수행했다. cpo·coal 의 **출처가 교체**(Bursa FCPO → Kemendag HR,
> TE Newcastle → ESDM HBA I)되고 nr_rubber 저장 단위가 USD/MT 로 바뀌었으므로,
> 아래 §2 표의 값·단위는 **당시 기준**으로 읽어야 한다. 현행 기준은
> [`indicator-source-audit.md`](indicator-source-audit.md) 를 본다.

> 작업지시서 `작업지시서_KPI지표_월별백필_2026.md` 산출물. 실행일 2026-08-24.
> 원칙: 기존 일별 데이터 삭제 없음 · 말일(month-end) 행 **추가만** · 모든 쓰기는
> `upsert on_conflict(indicator_id, recorded_date)` · 추정/파생값은 `note` 에 근거 명기 ·
> DB 직접 INSERT 금지(스크립트 경유) · 멱등 실행.

## 1. 최종 커버리지 매트릭스 (말일 행 기준, 2026-08-24 검증)

| 지표 | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 |
|---|---|---|---|---|---|---|---|---|
| nr_rubber | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| cpo | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| nickel | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| coal | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| carbon_black | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| synthetic_rubber | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| steel_wire | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| scfi | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| bi_rate | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| idn_inflation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⏳ |
| idn_pmi | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⏳ |

**미해결 2건 (정당한 공백)**: `idn_inflation` `idn_pmi` 의 2026-08 은 **2026-09-01
발표** 예정 — 발표 후 monthly 수집기(클라우드/로컬)가 자동 보충하며, 실패 시
`monthly_backfill.py` 재실행으로 채운다. yfinance 지표 5종(brent·환율)은 일별
시계열이 이미 연속이라 백필 대상에서 제외했다.

## 2. 백필 방법·값 (총 32행 upsert)

우선순위: **기존 행 skip → ① 월내 일별값 파생 → ② CSV 확정값 → 미해결 목록화**.
파생 규칙: 해당 월의 마지막 일별값을 말일로 정규화, note `derived: <YYYY-MM> 월내 최종가 (<MM-DD>)`.

### ① 파생 (derived, 8행)
DB 에 이미 있던 월내 일별값에서 도출. 이 중 steel_wire·synthetic_rubber 파생값은
§5 데이터 품질 플래그 참고.

### ② CSV 확정값 (`data/backfill_2026.csv`, 24행) — 근거 요약

| 지표 | 월 | 값 | 근거(note) |
|---|---|---|---|
| nr_rubber | 07 / 08 | 231.50 / 234.50 | SICOM TSR20 (작업지시 확인값) |
| cpo | 07 / 08 | 4,480 / 4,961 | 작업지시 / MPOC 일별가 08-20 |
| nickel | 07 / 08 | 17,100 / 17,044 | Westmetall LME cash 07-31 / TE 08-21 |
| scfi | 07 / 08 | 3,355.24 / 3,409.63 | SSE (작업지시 확인값) |
| bi_rate | 07 / 08 | 5.75 / 5.75 | BI 동결 발표 |
| idn_inflation | 07 | 2.88 | BPS YoY CPI |
| idn_pmi | 02 | 53.8 | S&P Global |
| carbon_black | 01·02·04·05 | 1,080 / 1,100 / 1,035 / 1,000 | ChemAnalyst RMB 환산·FOB Qingdao 보간 (추정) |
| synthetic_rubber | 01·02·04·05 | 1,670 / 1,750 / 2,000 / 2,200 | CFR SE Asia 보간 (추정) |
| steel_wire | 01·02·04·05 | 810 / 815 / 825 / 830 | FOB Qingdao 보간: 3월 820 ↔ 6월 835 (추정) |

## 3. 검증 결과 (2026-08-24)

- **갭 매트릭스**: 2026-01~07 전 지표 누락 0 행, 08 은 발표 전 2건만 잔존(§1) ✅
- **멱등성**: 본 실행 32 upsert 후 재실행 → 0 upsert / 86 skip ✅
- **note 누락**: 백필이 쓴 32행 전부 note 보유 ✅. 검증 쿼리에서 나온 note-null 2행
  (bi_rate·idn_inflation 2026-02-28)은 **백필 이전부터 있던 구 수집기 행**
  (당시 컨벤션이 note 미기록) — 삭제 금지 원칙에 따라 그대로 둠.
- **삭제 없음**: 백필은 insert/update(upsert)만 수행, delete 경로 자체가 없음 ✅

## 4. 함께 수행한 수집기 수정 (2026-08-24)

1. **`--` 중복 버그**: daily/weekly_collector 의 실패 안내가 `----nr-rubber` 로 출력
   (cmd 문자열에 이미 `--` 포함) → `--{cmd}` → `{cmd}` 수정. monthly 는 정상이라 미변경.
2. **연도 오인 필터 `_is_yearlike()`**: CPO 스크래핑이 페이지의 "2026" 을 가격으로
   저장한 사고(▼-59%) → 2015~2035 정수를 모든 후보 경로에서 제외.
3. **이상값 가드 `_reject_outlier()`**: TE JSON 트리 첫 매칭이 무관한 숫자 7,268 을
   집어온 사고(▲+46%) → DB 최근값 대비 ±25% 초과 값은 소스별 시도 단계에서 폐기
   (체인 폴스루), CLI 수동 입력은 검사 미적용. 당일 오염 행은 허용 경로(수집기 CLI
   `--cpo 4961`)로 정정 완료.
4. **스케줄러 정비**: `com.asuradb.commodity`(평일 09:00)·`com.asuradb.weekly`(금 10:00)
   plist 신설·bootstrap·kickstart 로그 검증, launcher `POST /collect/commodity` 매핑 추가,
   자동수집 8종 `market_indicators.source='scraper'` 정정
   (`20260824_fix_indicator_source.sql`).
5. **클라우드 이관(§7)**: pg_cron + pg_net + Edge Function `collect-indicators` 구축 —
   상세는 [`cloud-migration-runbook.md`](cloud-migration-runbook.md).

## 5. 데이터 품질 플래그 (후속 확인 권장)

- **steel_wire 파생 07=500 / 08=933.51**: TE Steel HRC 프록시의 일별값이 매우 불안정
  (308~977 진폭)해, 월간 시계열의 기준(FOB Qingdao 추정, 3월 820·6월 835)과 기준이
  다르다. 파생 규칙은 작업지시대로 적용했으나 값 신뢰도 낮음 — 공급사 견적으로
  정정 권장.
- **synthetic_rubber 파생값**: TE Butadiene 일별(646~2,888 진폭)과 월간 기준(CFR SE
  Asia, 3월 1,840·6월 2,400)의 기준 불일치 — 동일 사유로 확인 권장.
- **carbon_black**: 일별은 Brent×14 프록시, 월간은 FOB Qingdao 계열로 기준 혼재 —
  분기별 공급사 견적으로 실측 보정 권장.

> 2026-08-24 후속: 위 3건의 원인인 **weekly TE 경로에 이상값 가드가 없던 문제**를
> `_reject_outlier()`(±25%) 추가로 막았다(로컬 + Edge Function). 이미 저장된
> steel_wire 07/08 행은 삭제 금지 원칙에 따라 유지 — [`indicator-source-audit.md`](indicator-source-audit.md) §8.

## 6. 재실행 방법

```bash
# dry-run (쓰기 없음)
~/.venvs/asuradb/bin/python collectors/monthly_backfill.py --dry-run
# 특정 지표·구간만
~/.venvs/asuradb/bin/python collectors/monthly_backfill.py --only idn_inflation --from 2026-08
# CSV 확정값 반영
~/.venvs/asuradb/bin/python collectors/monthly_backfill.py --from-csv data/backfill_2026.csv
```
