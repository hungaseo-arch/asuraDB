# 📊 PT Ascendo KPI 24종 수집 가이드

> **작성 목적**: 타이어 수입판매업 의사결정 핵심 지표 24종의 무료/유료 데이터 소스, 자동화 가능 여부, 수집 주기를 정리하여 통합 대시보드 구축의 기반자료로 활용
>
> **작성일**: 2026년 5월 24일 (최초 2026-05-23 → 수집기 전체 리뷰 후 갱신)
> **대상 회사**: PT Ascendo International (타이어 수입·유통)
> **데이터 기준**: 2026년 5월 최신 공개 정보

---

## 📑 목차

1. [원자재 — 원유 및 고무 계열 (1~4번)](#1-원자재--원유-및-고무-계열-14번)
2. [원자재 — 에너지 및 화학 (5~8번)](#2-원자재--에너지-및-화학-58번)
3. [환율 (9~12번)](#3-환율-912번)
4. [물류 운임 (#13 SCFI)](#4-물류-운임-13-scfi)
5. [인도네시아 거시경제 (14~17번)](#5-인도네시아-거시경제-1417번)
6. [자사 영업 데이터 (18~24번)](#6-자사-영업-데이터-1824번--내부-erpcrm에서-추출)
7. [통합 수집 시스템 설계 권장사항](#7-통합-수집-시스템-설계-권장사항)
8. [면책 및 유의사항](#-면책-및-유의사항)

---

## 🛢️ 1. 원자재 — 원유 및 고무 계열 (1~4번)

### #1 `brent_crude` 브렌트유 (Brent Crude Oil)

- **현황**: ✅ yfinance 자동 수집 (`BZ=F`)
- **수집 코드**:
  ```python
  import yfinance as yf
  brent = yf.Ticker("BZ=F").history(period="1d")["Close"].iloc[-1]
  ```
- **백업 소스**: EIA(미국에너지정보청) — <https://www.eia.gov/petroleum/data.php>
- **활용**: 합성고무·카본블랙·운송비의 선행지표 (4~8주 lag)

---

### #2 `nr_rubber` 천연고무 TSR20 (Natural Rubber TSR20)

- **현황**: ✅ `daily_collector.py` 자동 수집 구현 (yfinance 미지원)
- **1차 소스**: Trading Economics HTML — <https://tradingeconomics.com/commodity/rubber>
  - 메타 설명에 `"Rubber fell to XXX.XX USD Cents / Kg"` 형식으로 일일 갱신
- **2차 소스**: Trading Economics 게스트 API (`?c=guest:guest&commodity=rubber`)
- **3차 소스**: Investing.com TSR20 Futures — <https://www.investing.com/commodities/rubber-tsr20>
  - 비회원: 페이지 현재가 스크래핑 / 회원: CSV 다운로드
  - ⚠ CloudFlare 차단 가능 — 이용약관 확인 필요
- **유료 공식 (참고)**: SGX TSR20 Futures — <https://www.sgx.com/derivatives/products/rubber> (자동수집 미적용)
  - ⚠ SICOM(`www.sicom.com.sg`) 도메인은 단종 — 수집기에서 제외
- **단위**: USc/kg | **유효 범위**: 50 ~ 500
- **수집 주기**: 평일 09:00 WIB (`daily_collector.py`, cron `0 9 * * 1-5 TZ=Asia/Jakarta`)
- **수동 입력 권장 시각**: 09:00 WIB (자동수집 실패 시 30초 소요)

```bash
uv run python collectors/daily_collector.py              # 자동
uv run python collectors/daily_collector.py --nr-rubber 163.5  # 수동 (USc/kg)
```

---

### #3 `cpo` 팜유 CPO (Crude Palm Oil)

- **현황**: ✅ `daily_collector.py` 자동 수집 구현
- **1차 소스**: Bursa Malaysia FCPO 공식 — <https://www.bursamalaysia.com/market_information/derivatives_prices>
- **2차 소스**: Trading Economics — <https://tradingeconomics.com/commodity/palm-oil>
- **3차 소스**: Trading Economics 게스트 API
- **단위**: MYR/MT | **유효 범위**: 1,000 ~ 10,000
- **참고**: USD 환산 시 `× KRW/MYR 또는 USD/MYR` 환율 곱하기
- **수집 주기**: 평일 매일 (`daily_collector.py`)

```bash
uv run python collectors/daily_collector.py           # 자동
uv run python collectors/daily_collector.py --cpo 3850  # 수동 (MYR/MT)
```

---

### #4 `nickel` 니켈 (Nickel)

- **현황**: ✅ `daily_collector.py` 자동 수집 구현
- **1차 소스**: LME 공식 — <https://www.lme.com/Metals/Non-ferrous/LME-Nickel> (Cash Settlement)
- **2차 소스**: Trading Economics — <https://tradingeconomics.com/commodity/nickel>
- **3차 소스**: Trading Economics 게스트 API
- **인도네시아 특화**: Kementerian ESDM HMA 월간 발표 — <https://www.esdm.go.id>
- **단위**: USD/MT | **유효 범위**: 5,000 ~ 100,000
- **수집 주기**: 평일 매일 (`daily_collector.py`)

```bash
uv run python collectors/daily_collector.py             # 자동
uv run python collectors/daily_collector.py --nickel 17500  # 수동 (USD/MT)
```

---

## ⚡ 2. 원자재 — 에너지 및 화학 (5~8번)

### #5 `coal` 석탄 (Thermal Coal)

- **현황**: ✅ `weekly_collector.py` 자동 수집 구현
- **1차 소스**: Trading Economics Newcastle Coal → `tradingeconomics.com/commodity/coal-newcastle`
- **2차 소스**: Trading Economics 게스트 API
- **3차**: 수동 입력 (HBA 참고: <https://www.minerba.esdm.go.id/harga_acuan>)
- **단위**: USD/MT | **유효 범위**: 80 ~ 500
- **수집 주기**: 매주 금요일 `weekly_collector.py`

```bash
# 수동 입력
uv run python collectors/weekly_collector.py --coal 135.0
```

---

### #6 `carbon_black` 카본블랙 (Carbon Black, 炭素ブラック)

- **현황**: ✅ `weekly_collector.py` Proxy 자동 추정 구현
- **공개 시세 없음** — 공급사 견적(Cabot, Birla Carbon)이 유일 실측 소스
- **Proxy 로직**: DB의 최신 브렌트유(USD/bbl) × 14.0 → 카본블랙 USD/MT 추정
  - 브렌트유 80 USD/bbl → 카본블랙 ≈ 1,120 USD/MT (역사적 환산 계수)
  - ⚠ 분기별 공급사 견적으로 실측값 덮어쓰기 권장
- **인도네시아 시장**: PT Cabot Indonesia (Cilegon), PT Continental Carbon Indonesia
- **단위**: USD/MT | **수집 주기**: 매주 금요일 (Proxy 자동 / 견적 수령 시 수동)

```bash
# 공급사 견적 수령 시 수동 입력 (Proxy 값 덮어씀)
uv run python collectors/weekly_collector.py --carbon-black 1050
```

---

### #7 `synthetic_rubber` 합성고무 BD (Butadiene-based SBR/BR)

- **현황**: ✅ `weekly_collector.py` 자동 수집 구현 (TE Butadiene)
- **1차 소스**: Trading Economics Butadiene → `tradingeconomics.com/commodity/butadiene`
- **2차 소스**: Trading Economics 게스트 API
- **3차**: 수동 입력 (공급사: Kumho Petrochemical, LANXESS, Sinopec)
- **단위**: USD/MT | **유효 범위**: 500 ~ 3,000
- **수집 주기**: 매주 금요일 `weekly_collector.py`

> 💡 **실무 팁**: NR/SR spread가 -5% 이하로 축소되면 합성고무 사용량 증가 검토

```bash
uv run python collectors/weekly_collector.py --synthetic-rubber 1200
```

---

### #8 `steel_wire` 강선 (Steel Cord / Bead Wire)

- **현황**: ✅ `weekly_collector.py` 자동 수집 구현 (TE Steel HRC Proxy)
- **1차 소스**: Trading Economics Steel HRC → `tradingeconomics.com/commodity/steel`
  - ⚠ HRC 가격 = 강선의 Proxy (실제 강선 시세는 공급사 견적 우선)
- **2차 소스**: Trading Economics 게스트 API
- **3차**: 수동 입력 (공급사: Bekaert, Hyosung Advanced Materials, Jiangsu Xingda)
- **단위**: USD/MT | **유효 범위**: 300 ~ 2,000
- **수집 주기**: 매주 금요일 `weekly_collector.py`

```bash
uv run python collectors/weekly_collector.py --steel-wire 650
```

---

## 💱 3. 환율 (9~12번)

### #9~12 USD/IDR, USD/KRW, USD/CNY, KRW/IDR

- **현황**: ✅ **전부 yfinance 자동 수집 가능**
- **수집 코드**:
  ```python
  import yfinance as yf

  pairs = {
      "usd_idr": "USDIDR=X",
      "usd_krw": "USDKRW=X",
      "usd_cny": "USDCNY=X",
      "krw_idr": "KRWIDR=X"
  }
  rates = {k: yf.Ticker(v).history(period="1d")["Close"].iloc[-1]
           for k, v in pairs.items()}
  ```
- **백업 Primary (공식)**: Bank Indonesia 공식 환율 — **JISDOR (Jakarta Interbank Spot Dollar Rate)**
  - URL: <https://www.bi.go.id/en/statistik/informasi-kurs/jisdor-sub.aspx>
- **회계용 환율**: 매월 말 **Kurs Pajak** (Kementerian Keuangan PMK) — 부가세 신고에 사용
- **권장**: 일일 모니터링은 yfinance, 월말 결산은 Kurs Pajak 별도 기록

---

## 🚢 4. 물류 운임 (#13 SCFI)

### #13 `scfi` SCFI 컨테이너운임 (Shanghai Containerized Freight Index)

- **현황**: ✅ `weekly_collector.py` 자동 수집 구현
- **1차 소스**: SSE AJAX 엔드포인트 — <https://en.sse.net.cn/indices/scfinew.jsp>
- **2차 소스**: SSE 공식 HTML 테이블 파싱
- **3차 소스**: MacroMicro 백업 — <https://en.macromicro.me/series/7541/china-scfi>
- **갱신 주기**: **매주 금요일** (Shanghai Shipping Exchange 발표 기준)
- **타이어 특화 노선**: Shanghai → Jakarta (Southeast Asia route) 집중 추적

```bash
uv run python collectors/weekly_collector.py            # 자동
uv run python collectors/weekly_collector.py --scfi 1234.5  # 수동
```

---

## 🏦 5. 인도네시아 거시경제 (14~17번)

### #14 `bi_rate` BI 기준금리 (BI-Rate)

- **공식 Primary**: Bank Indonesia 공식 BI-Rate 페이지
  - URL: <https://www.bi.go.id/en/fungsi-utama/moneter/bi-rate/default.aspx>
- **갱신 주기**: **매월 RDG(이사회) 회의 후** — 보통 매월 셋째 주 화·수요일
- **현재 수준**: 2026년 5월 기준 BI-Rate **5.25%**
- **수집 방식**: ✅ `monthly_collector.py` 자동 수집 (HTML 파싱 → BI API 폴백 → 수동 입력)
  ```bash
  uv run python collectors/monthly_collector.py            # 자동
  uv run python collectors/monthly_collector.py --bi-rate 5.25  # 수동
  ```

> 💡 **실무 팁**: 금리 인하 시 → 자동차 할부 수요 ↑ → 교체용 타이어 시장 6~9개월 후 회복

---

### #15 `idn_inflation` 인도네시아 물가 (Indonesia CPI)

- **공식 Primary**: BPS (Badan Pusat Statistik) — **매월 1~5일 발표**
  - URL: <https://www.bps.go.id>
- **API**: BPS Web API 제공 (등록 필요) — <https://webapi.bps.go.id>
  - 변수 ID `1707` = 인플레이션율 YoY (%), `1708` = MoM (%)
- **수집 방식**: ✅ 두 가지 수집기 구현 완료
  - `monthly_collector.py` — 월간 통합 실행 시 BPS API 포함
  - `bps_collector.py` — BPS 전용 독립 수집기 (12개월 일괄 upsert + 최근 6개월 미니 리포트 출력)
  ```bash
  # .env 에 BPS_API_KEY=<발급키> 필요
  uv run python collectors/bps_collector.py                  # BPS 전용 독립 실행
  uv run python collectors/monthly_collector.py              # 월간 통합 실행 (bi_rate + inflation + pmi)
  uv run python collectors/monthly_collector.py --inflation 2.42  # 수동
  ```
  - BPS API 키 발급: <https://webapi.bps.go.id> → [DAFTAR] → 이메일 가입 → API KEY 탭

---

### #16 `idn_pmi` 인도네시아 PMI (Manufacturing PMI)

- **공식 Primary**: **S&P Global Indonesia Manufacturing PMI** — 매월 첫 영업일 09:00 WIB 발표
  - URL: <https://www.pmi.spglobal.com>
- **무료 Secondary**: Trading Economics 백업
- **임계값 해석**:
  - 50.0 **초과** = 제조업 확장 → 타이어 수요 ↑
  - 50.0 **미만** = 위축 → 재고 조정 필요
- **수집 방식**: ✅ `monthly_collector.py` 자동 수집 (S&P Global API → HTML → Trading Economics 폴백)
  ```bash
  uv run python collectors/monthly_collector.py           # 자동 (3단계 폴백)
  uv run python collectors/monthly_collector.py --pmi 52.1  # 수동
  ```

---

### #17 `import_tariff` 수입관세율 (Import Tariff)

- **공식 Primary**: **INSW (Indonesia National Single Window)** — <https://www.insw.go.id>
- **타이어 HS Code별 조회**:
  - 4011.10 (승용차용 PCR)
  - 4011.20 (버스·트럭용 TBR)
  - 4011.70 (농업용 AGR)
- **MFN Rate 외 추가 부과**:
  - PPN (VAT) **11%**
  - PPh 22 (수입 소득세) **2.5%** (API 보유시) 또는 **7.5%** (미보유시)
  - **Anti-Dumping Duty** (BMAD) — 중국산 PCR 타이어 등 일부 품목 적용
- **갱신 주기**: PERMENDAG/PMK 발표 시 (수시) → **분기 1회 점검 권장**
- **수집 방식**: 분기 1회 INSW 수동 조회 + 무역협회(APBI, ABI) 회보 구독

---

## 🛞 6. 자사 영업 데이터 (18~24번) — 내부 ERP/CRM에서 추출

### #18~21 타이어 카테고리별 판매 (TBR / OTR / IND / AGR)

- **소스**: 자사 ERP (Quotation System 연동)
- **수집 방식**: SQL 쿼리 자동화 권장
  ```sql
  -- 예시: 주간 카테고리별 판매
  SELECT category, SUM(quantity) AS units
  FROM sales_orders
  WHERE sale_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
  GROUP BY category;
  ```
- **카테고리 정의 표준화 필수**:

| 코드 | 한국명 | Indonesia 명칭 | 주요 SKU 예시 |
|------|--------|----------------|----------------|
| TBR | 트럭·버스용 | Truk & Bus | 11R22.5, 295/80R22.5 |
| OTR | 중장비용 | Off-The-Road | 17.5R25, 23.5R25 |
| IND | 산업용 | Industri (Forklift dll.) | 7.00-12, 6.50-10 |
| AGR | 농경용 | Pertanian | 18.4-34, 14.9-28 |

---

### #22 `competitor_price` 경쟁사 가격지수

- **소스**: 수동 시장조사 — Tokopedia, Shopee, Bukalapak의 경쟁 브랜드 가격
- **주요 경쟁 브랜드**: GT Radial, Achilles, Forceum, Bridgestone, Michelin, Hankook, Dunlop, BKT, Trelleborg
- **수집 방식**: 🟡 `competitor_sku_list.py` 스크립트 지원 (가격 입력 → 지수 자동 계산 → DB 저장)
  - 매주 금요일 직원이 Tokopedia/Shopee에서 가격 조회 후 스크립트 배열에 입력
  - 크롤링 자동화는 마켓플레이스 ToS 문제로 권장하지 않음 (수동 조회 유지)
  ```bash
  uv run python collectors/competitor_sku_list.py   # SKU 목록 출력 + 지수 저장
  ```
- **SKU 마스터**: 30개 사전 정의 완료

  | 카테고리 | SKU 수 | 예시 |
  |---------|-------|------|
  | TBR | 10개 | GT Radial GT978+ vs Bridgestone R-150F (11R22.5) |
  | OTR | 8개 | GT Radial XT7 vs Bridgestone VRTS (23.5R25) |
  | IND | 6개 | Forceum Solid F1 vs Trelleborg T900 (6.00-9) |
  | AGR | 6개 | GT Farm GT30 vs BKT Agrimax (12.4-28) |

- **지수 산출**: `(자사평균가 / 경쟁사평균가) × 100`
  - 100 미만 → 자사가 저렴 (가격경쟁력 우위)
  - 100 초과 → 자사가 비쌈 (가격경쟁력 약화)
  - 최소 5개 SKU 이상 입력 시 지수 산출 및 DB 저장

---

### #23 `receivables_ar` 매출채권 AR (Accounts Receivable)

- **소스**: 자사 회계시스템 (Accurate, Jurnal, SAP 등)
- **수집 방식**: Aging Report 자동 생성

  | 구간 | 0~30일 | 31~60일 | 61~90일 | 90일 초과 |
  |------|--------|---------|---------|-----------|
  | 분류 | 정상 | 주의 | 경고 | 손실 검토 |

- **KPI**:
  - **DSO (Days Sales Outstanding)** = AR / 일평균매출
  - 산업 평균 **45~60일** / 90일 초과는 손실 처리 검토
- **알림 임계값**: 전월 대비 +10% 증가 시 자동 알림

---

### #24 `operating_ratio` 영업이익률 (Operating Margin)

- **소스**: 월간 결산 P&L
- **계산식**: `(매출총이익 - 판관비) / 매출액 × 100`
- **수집 방식**: 결산 마감 후 (보통 익월 5~10일) 수동 입력
- **타이어 도매업 벤치마크**: **3~7%** (인도네시아 시장 기준)

---

## 🔧 7. 통합 수집 시스템 설계 권장사항

### 자동화 구현 현황 (2026-05 기준)

| 상태 | 항목 | Collector | 비고 |
|------|------|-----------|------|
| ✅ 완전 자동 | #1, #9~12 | `indicator_collector.py` | yfinance — 평일 매일 |
| ✅ 완전 자동 | #2 nr_rubber | `daily_collector.py` | TE HTML → TE API → Investing.com |
| ✅ 완전 자동 | #3 cpo | `daily_collector.py` | Bursa Malaysia → TE → TE API |
| ✅ 완전 자동 | #4 nickel | `daily_collector.py` | LME → TE → TE API |
| ✅ 완전 자동 | #5 coal | `weekly_collector.py` | TE Newcastle → TE API |
| ✅ 완전 자동 | #7 synthetic_rubber | `weekly_collector.py` | TE Butadiene → TE API |
| ✅ 완전 자동 | #8 steel_wire | `weekly_collector.py` | TE Steel HRC (Proxy) → TE API |
| ✅ 완전 자동 | #13 scfi | `weekly_collector.py` | SSE AJAX → HTML → MacroMicro |
| ✅ 완전 자동 | #14 bi_rate | `monthly_collector.py` | BI 공식 HTML → BI API 폴백 |
| ✅ 완전 자동 | #15 idn_inflation | `monthly_collector.py` / `bps_collector.py` | BPS Web API (var 1707) |
| ✅ 완전 자동 | #16 idn_pmi | `monthly_collector.py` | S&P Global API → HTML → TE |
| 🟡 Proxy 자동 | #6 carbon_black | `weekly_collector.py` | 브렌트유 × 14 추정 / 분기 실측 갱신 권장 |
| 🟡 스크립트 지원 | #22 competitor_price | `competitor_sku_list.py` | 30개 SKU 마스터 · 지수 자동 계산 / 가격 조회는 수동 |
| ❌ 수동 필요 | #17 import_tariff | — | 분기 1회 INSW 수동 조회 |
| ❌ 수동 필요 | #18~21 판매량 | — | ERP 미연동 (SQL 연동 시 자동화 가능) |
| ❌ 수동 필요 | #23 receivables_ar | — | 회계시스템 미연동 |
| ❌ 수동 필요 | #24 operating_ratio | — | 월말 결산 후 수동 입력 |

### Collector 파일 목록

| 파일 | 역할 | 실행 주기 |
|------|------|---------|
| `indicator_collector.py` | #1 브렌트유, #9~12 환율 (yfinance) | 평일 매일 |
| `daily_collector.py` | #2 천연고무, #3 팜유, #4 니켈 (웹 스크래핑) | 평일 매일 |
| `weekly_collector.py` | #5~8 원자재 주간, #13 SCFI | 매주 금요일 |
| `monthly_collector.py` | #14 BI금리, #15 물가, #16 PMI | 매월 5일 이후 |
| `bps_collector.py` | #15 인도네시아 물가 전용 (12개월 upsert + 리포트) | 필요 시 단독 실행 |
| `competitor_sku_list.py` | #22 경쟁사 가격지수 (30개 SKU 마스터 · 지수 계산) | 매주 금요일 수동 |
| `heartbeat.py` | 각 collector 실행 완료 시 `collector_heartbeat` 테이블 기록 | (내부 호출) |

> 💡 **heartbeat 모니터링**: 모든 collector는 실행 완료 후 `collector_heartbeat` 테이블에 `source`, `last_run` 을 upsert한다. Supabase 대시보드에서 마지막 실행 시각을 한눈에 확인할 수 있다.

### AI 레이어 구현 현황 (2026-05 기준)

| 파일 / 엔드포인트 | AI 엔진 | 역할 |
|------------------|---------|------|
| `api/search.py` — `/ai-search` | **Claude** (`claude-haiku-4-5-20251001`) | RAG 기반 지식 DB 검색 — 질문 → 유사 문서 검색 → 답변 스트리밍 |
| `api/search.py` — `/report/generate` | **Claude** (`claude-haiku-4-5-20251001`) | 내부 문서 5개 쿼리 → 타이어 시장 동향 레포트 자동 생성 |
| `scripts/generate_monitoring_report.py` | **Claude** (`claude-sonnet-4-6`) | 24개 지표 주간 스냅샷 → 경영진용 JSON 리포트 생성 |
**환경변수 설정 (`.env`)**

```
ANTHROPIC_API_KEY=sk-ant-...          # Claude API 공통 키 (검색·리포트 모두 사용)
CLAUDE_MODEL=claude-haiku-4-5-20251001  # ai-search / report 모델 (기본값)
CLAUDE_MODEL_AGENT=claude-sonnet-4-6    # 주간 모니터링 리포트 모델
```

> ✅ 모든 AI 추론(검색 답변 · 리포트)은 **Claude API(Haiku/Sonnet)로 통합**되어 있습니다. HyperCLOVA / Ollama 경로는 제거됨. AI 회의록 기능은 2026-06에 제거됨.

### 권장 기술 스택

```
데이터 수집 : Python (yfinance, requests, BeautifulSoup)
스케줄링    : APScheduler 또는 Linux cron
데이터베이스 : PostgreSQL / Supabase (벡터 검색 포함)
AI 분석    : Claude API — RAG 검색, 주간 리포트
대시보드   : Metabase (무료) 또는 Grafana
알림      : Telegram Bot API (인도네시아 사용 빈도 높음)
```

### 알림 주기 재검토 제안

| 항목 | 기존 | 변경 권장 | 사유 |
|------|------|----------|------|
| #5 석탄 | 주간 🟡 | 격주 (월 2회) | HBA 발표 = 월 1·15일 |
| #22 경쟁사 가격 | 주간 🟡 | 주간 유지 (단, 핵심 SKU만) | 전수조사 불필요 |

---

## 📋 지표별 데이터 소스 요약표

> 2026-05 기준 | ✅ 자동화 구현 완료 | 🟡 Proxy 자동 추정 | ❌ 수동 입력 필요

| # | ID | 상태 | 1차 소스 | Collector | 주기 |
|---|-----|:----:|----------|-----------|------|
| 1 | brent_crude | ✅ | yfinance `BZ=F` | `indicator_collector.py` | 일일 |
| 2 | nr_rubber | ✅ | TE HTML → TE API → Investing.com | `daily_collector.py` | 일일 (09:00 WIB) |
| 3 | cpo | ✅ | Bursa Malaysia → TE | `daily_collector.py` | 일일 |
| 4 | nickel | ✅ | LME 공식 → TE | `daily_collector.py` | 일일 |
| 5 | coal | ✅ | TE Newcastle Coal | `weekly_collector.py` | 주간 |
| 6 | carbon_black | 🟡 | 브렌트유 × 14 Proxy | `weekly_collector.py` | 주간 |
| 7 | synthetic_rubber | ✅ | TE Butadiene | `weekly_collector.py` | 주간 |
| 8 | steel_wire | ✅ | TE Steel HRC (Proxy) | `weekly_collector.py` | 주간 |
| 9 | usd_idr | ✅ | yfinance `USDIDR=X` | `indicator_collector.py` | 일일 |
| 10 | usd_krw | ✅ | yfinance `USDKRW=X` | `indicator_collector.py` | 일일 |
| 11 | usd_cny | ✅ | yfinance `USDCNY=X` | `indicator_collector.py` | 일일 |
| 12 | krw_idr | ✅ | yfinance `KRWIDR=X` | `indicator_collector.py` | 일일 |
| 13 | scfi | ✅ | SSE AJAX → HTML → MacroMicro | `weekly_collector.py` | 주간 (금) |
| 14 | bi_rate | ✅ | BI 공식 HTML → BI API | `monthly_collector.py` | 월 (RDG 후) |
| 15 | idn_inflation | ✅ | BPS Web API (var 1707) | `monthly_collector.py` | 월 (1~5일) |
| 16 | idn_pmi | ✅ | S&P Global → TE | `monthly_collector.py` | 월 (첫 영업일) |
| 17 | import_tariff | ❌ | INSW 수동 조회 | — | 분기 |
| 18 | tbr_sales | ❌ | 자사 ERP (미연동) | — | 주간 |
| 19 | otr_sales | ❌ | 자사 ERP (미연동) | — | 주간 |
| 20 | ind_sales | ❌ | 자사 ERP (미연동) | — | 주간 |
| 21 | agr_sales | ❌ | 자사 ERP (미연동) | — | 주간 |
| 22 | competitor_price | 🟡 | 수동 조회 + `competitor_sku_list.py` 지수 계산 | `competitor_sku_list.py` | 주간 |
| 23 | receivables_ar | ❌ | 회계시스템 (미연동) | — | 주간 |
| 24 | operating_ratio | ❌ | 월간 결산 P&L | — | 월 |

**자동화 집계**: ✅ 15개 / 🟡 2개 / ❌ 7개 (전체 24개)

---

## ⚠️ 면책 및 유의사항

- 본 가이드는 **공개 출처 기반 정보** 정리이며, 실제 거래·재무 의사결정은 법무·세무·재무 전문가 자문을 권장합니다.
- 일부 무료 데이터 소스(Trading Economics, MacroMicro 등)는 **상업적 자동 스크래핑 시 이용약관 검토 필수**입니다.
- BI Rate, 인플레이션 등 정부 발표 데이터는 **공식 소스(BI, BPS) 우선** 사용을 권장합니다.
- 본 문서의 수치(BI-Rate 5.25%, 인플레이션 2.42% 등)는 2026년 5월 기준이며, 최신 데이터로 갱신이 필요합니다.

---

## 📞 다음 단계 제안

| 상태 | 항목 |
|------|------|
| ✅ 완료 | yfinance 기반 일일 자동 수집 스크립트 (`indicator_collector.py`) |
| ✅ 완료 | BPS API 연동 (`bps_collector.py` + `monthly_collector.py`) |
| ✅ 완료 | 경쟁사 가격 모니터링 SKU 마스터 30개 설계 (`competitor_sku_list.py`) |
| 🔲 잔여 | ERP 연동을 통한 #18~21 판매량 자동 수집 (SQL 쿼리 자동화) |
| 🔲 잔여 | #23 매출채권 Aging Report 회계시스템 연동 |
| 🔲 잔여 | 전체 24개 지표 통합 대시보드 설계 (Metabase / Grafana) |
| 🔲 잔여 | Telegram Bot 알림 연동 (임계값 초과 시 자동 경보) |

---

*문서 끝 | Generated for PT Ascendo International | 2026.05.24 (수집기 전체 리뷰 기준)*
