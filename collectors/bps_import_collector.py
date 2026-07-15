"""
인도네시아 월간 타이어 수입 통계 수집기 — BPS WebAPI dataexim 기반 (자동 API 적재)

기존 TireImport.vue 는 BPS EXIM 포털에서 XLSX 를 내려받아 수동 CSV 붙여넣기로 입력했다.
이 수집기는 BPS WebAPI 의 dataexim 엔드포인트를 직접 호출해 32종 타이어 HS 코드의
월별·국가별 수입 데이터를 받아 `tire_imports` 테이블에 upsert 한다. (자동화)

━━━ 사전 준비 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. https://webapi.bps.go.id 가입 → [API KEY] 탭에서 키 복사
2. .env 에 추가:   BPS_API_KEY=your_api_key_here
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BPS dataexim API (https://webapi.bps.go.id/documentation/#exim)
  Base : https://webapi.bps.go.id/v1/api/dataexim/
  파라미터:
    sumber=2      수입(impor)   [1=수출]
    periode=1     월별(bulanan) [2=연간]
    jenishs=2     Full HS Code
    kodehs=...    HS 코드(다중은 ';' 구분)
    tahun=YYYY    연도
    key=...       API 키
  응답: { "status":"OK", "data":[ {value, netweight, kodehs, ctr, bulan, ...}, ... ] }
        value=US$(수입금액), netweight=KG, ctr=국가(인니어), bulan=월(1~12)

실행:
  uv run python collectors/bps_import_collector.py            # 올해
  uv run python collectors/bps_import_collector.py 2024 2025  # 특정 연도들
  uv run python collectors/bps_import_collector.py 2025 --dry-run   # 미리보기(적재 안 함)
"""
import os
import re
import sys
from collections import defaultdict
from datetime import date

import json

import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from supabase import create_client

_sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

BPS_EXIM = "https://webapi.bps.go.id/v1/api/dataexim/"
TIMEOUT = 30

# ── HS 코드 마스터 (32종·16 category): code → category ───────────────────────
# 단일 소스: src/data/hsMaster.json — TireImport.vue·scripts/bps-parser.mjs 와 공유(드리프트 방지).
# 근거: AHTN 2022(=BTKI 2022 8자리), SNI Wajib Ban(Permenperin 11/2012).
# 데이터 없는 코드도 등록(합 0, 초과 등록 무해) — 통계 공백만 제거.
with open(os.path.join(os.path.dirname(__file__), "..", "src", "data", "hsMaster.json"), encoding="utf-8") as _hf:
    HS_CATEGORY: dict[str, str] = {r["hs"]: r["category"] for r in json.load(_hf)}

# BPS 국가명(영문 대문자, 일부 인니어) → 기존 DB(영문) 표기 정규화. 미등록 국가는 Title Case 로 저장.
# (UNIQUE 키의 일부이므로 기존 입력 표기와 일치시켜야 국가 랭킹이 합쳐진다)
# 단일 소스: data/country_alias.json — scripts/ingest-bps-file.mjs 와 공유(드리프트 방지).
with open(os.path.join(os.path.dirname(__file__), "..", "data", "country_alias.json"), encoding="utf-8") as _f:
    COUNTRY_ALIAS: dict[str, str] = {k: v for k, v in json.load(_f).items() if not k.startswith("_")}

def _get_api_key() -> str:
    key = os.environ.get("BPS_API_KEY", "")
    if not key:
        print(
            "\n[ERROR] BPS_API_KEY 가 .env 에 없습니다.\n"
            "  → https://webapi.bps.go.id 에서 무료 토큰 발급 후 .env 에\n"
            "    BPS_API_KEY=<your_key> 추가\n",
            file=sys.stderr,
        )
        sys.exit(1)
    return key


def _num(x) -> float:
    """BPS 수치(문자/숫자)를 float 로. 실패 시 0."""
    if isinstance(x, (int, float)):
        return float(x)
    if x is None:
        return 0.0
    s = str(x).strip().replace(" ", "")
    if not s:
        return 0.0
    # BPS 는 소수점 '.' 사용 (예: "1015060.142"). 천단위 콤마가 있으면 제거.
    if s.count(",") and s.count("."):
        s = s.replace(",", "")
    elif s.count(","):
        s = s.replace(",", "") if s.rfind(",") < len(s) - 3 else s.replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return 0.0


def _extract_hs(kodehs) -> str | None:
    """kodehs 필드에서 8자리 HS 코드 추출. 예: "[40112011] Ban ..." → "40112011"."""
    s = str(kodehs)
    m = re.search(r"\[(\d{6,10})\]", s) or re.search(r"\b(\d{8})\b", s)
    return (m.group(1) if m else None)


def _extract_month(rec: dict) -> int | None:
    """BPS 월별 응답의 'bulan' 파싱. 실측 형식: "[05] Mei" (브래킷+월명).
    ※ 'periode'(요청 파라미터 에코)·기타 키는 월로 오인 위험이 있어 'bulan'만 사용.
       미인식 형식은 None → 상위에서 no_month 로 집계·경고(무손실 스킵)."""
    v = rec.get("bulan")
    if v in (None, ""):
        return None
    if isinstance(v, (int, float)) and 1 <= int(v) <= 12:
        return int(v)
    s = str(v).strip()
    b = re.match(r"\[(\d{1,2})\]", s)          # "[05] Mei"
    if b and 1 <= int(b.group(1)) <= 12:
        return int(b.group(1))
    if s.isdigit() and 1 <= int(s) <= 12:
        return int(s)
    return None


HS_CHUNK = 16          # BPS 제한: "Maximum of 20 HS-Code" / 요청 → 여유 두고 16종씩 분할
_HEADERS = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}  # WAF 회피


def fetch_year(api_key: str, year: int) -> list[dict]:
    """해당 연도의 32종 HS 월별 수입 데이터를 dataexim 에서 받아온다 (16종씩 분할 호출)."""
    codes = list(HS_CATEGORY.keys())
    records: list[dict] = []
    for i in range(0, len(codes), HS_CHUNK):
        chunk = codes[i:i + HS_CHUNK]
        params = {
            "sumber": 2,                # 수입
            "periode": 1,               # 월별
            "jenishs": 2,               # Full HS Code
            "kodehs": ";".join(chunk),  # ≤16종 (BPS 한도 20)
            "tahun": str(year),
            "key": api_key,
        }
        resp = requests.get(BPS_EXIM, params=params, timeout=TIMEOUT, headers=_HEADERS)
        resp.raise_for_status()
        payload = resp.json()

        status = str(payload.get("status", "")).upper()
        if status and status != "OK":
            # 데이터 없음(tidak tersedia)은 정상 상황일 수 있어 경고만 남기고 계속
            print(f"  [WARN] {year} chunk{i // HS_CHUNK + 1}: BPS status={payload.get('status')} "
                  f"msg={payload.get('message', '')} avail={payload.get('data-availability')}",
                  file=sys.stderr)
            continue

        data = payload.get("data")
        if isinstance(data, dict):      # 일부 응답이 {index: record} 형태일 수 있음
            data = list(data.values())
        if isinstance(data, list):
            records.extend(data)
    return records


def build_rows(records: list[dict], year: int) -> tuple[list[dict], set[str], int]:
    """BPS 레코드를 (year,month,hs,country) 단위로 집계해 tire_imports 행 생성."""
    agg: dict[tuple, dict] = defaultdict(lambda: {"value": 0.0, "weight": 0.0})
    skipped_hs: set[str] = set()
    no_month = 0

    for rec in records:
        if not isinstance(rec, dict):
            continue
        hs = _extract_hs(rec.get("kodehs"))
        category = HS_CATEGORY.get(hs or "")
        if not category:
            if hs:
                skipped_hs.add(hs)
            continue
        month = _extract_month(rec)
        if month is None:
            no_month += 1
            continue
        raw_ctr = str(rec.get("ctr", "")).strip()
        if not raw_ctr or raw_ctr.upper() in ("TOTAL", "TOTALS", "SEMUA NEGARA"):
            country = "ALL"
        else:
            country = COUNTRY_ALIAS.get(raw_ctr.upper(), raw_ctr.title())

        cell = agg[(year, month, hs, country)]
        cell["value"] += _num(rec.get("value"))
        cell["weight"] += _num(rec.get("netweight"))

    rows = [
        {
            "year": y, "month": m, "hs_code": hs,
            "category": HS_CATEGORY[hs], "country": ctr,
            "value_usd": round(v["value"], 2),
            "weight_kg": round(v["weight"], 2),
        }
        for (y, m, hs, ctr), v in sorted(agg.items())
    ]
    return rows, skipped_hs, no_month


def upsert_rows(rows: list[dict]) -> None:
    for i in range(0, len(rows), 200):
        _sb.table("tire_imports").upsert(
            rows[i:i + 200], on_conflict="year,month,hs_code,country"
        ).execute()


def run(years: list[int], dry_run: bool = False) -> None:
    api_key = _get_api_key()
    total = 0
    for year in years:
        print(f"\n[bps_import] {year} 수입 통계 수집…", flush=True)
        try:
            records = fetch_year(api_key, year)
        except Exception as e:  # noqa: BLE001
            print(f"  [FAIL] {year}: API 호출 실패 — {e}", file=sys.stderr)
            continue

        rows, skipped, no_month = build_rows(records, year)
        if skipped:
            print(f"  · 마스터 미등록 HS {len(skipped)}종 건너뜀: {sorted(skipped)[:6]}…")
        if no_month:
            print(f"  · 월 정보 없는 레코드 {no_month}건 건너뜀 (periode=1 확인 필요)")
        if not rows:
            print(f"  [주의] {year}: 적재할 행 없음 (data-availability / 키 권한 확인)")
            continue

        # 요약: 카테고리별 합계
        by_cat: dict[str, float] = defaultdict(float)
        for r in rows:
            by_cat[r["category"]] += r["value_usd"]
        months = sorted({r["month"] for r in rows})
        print(f"  · {len(rows)}행 · 월 {months[0]}~{months[-1]} · "
              f"국가 {len({r['country'] for r in rows})}개")
        for cat, usd in sorted(by_cat.items(), key=lambda x: -x[1]):
            print(f"      {cat:<13} ${usd:>18,.0f}")

        if dry_run:
            print(f"  [dry-run] {year}: {len(rows)}행 (적재 안 함)")
            continue

        upsert_rows(rows)
        total += len(rows)
        print(f"  ✓ {year}: {len(rows)}행 upsert 완료")

    if not dry_run and total:
        try:
            try:
                from collectors.heartbeat import record   # 패키지로 import된 경우(api/search.py 등)
            except ImportError:
                from heartbeat import record               # 스크립트로 직접 실행된 경우
            record("bps_import_collector")
        except Exception:  # noqa: BLE001
            pass
    print(f"\n[bps_import] 완료 — 총 {total}행 적재\n")


def default_years() -> list[int]:
    """수집 대상 기본 연도. BPS는 ~2개월 지연 발표·소급 수정하므로
    연초(1~3월)엔 전년도 발표분까지 포함해 공백/수정 누락을 막는다."""
    today = date.today()
    return [today.year - 1, today.year] if today.month <= 3 else [today.year]


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    dry = "--dry-run" in sys.argv or "-n" in sys.argv
    yrs = [int(a) for a in args if a.isdigit()] or default_years()
    run(yrs, dry_run=dry)
