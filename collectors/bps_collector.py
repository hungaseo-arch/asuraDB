"""
인도네시아 물가(CPI) 수집기 — BPS Web API 기반

━━━ 토큰 발급 절차 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. https://webapi.bps.go.id 접속
2. [DAFTAR] 클릭 → 이메일 / 비밀번호 입력 → 가입 완료
3. 로그인 후 [API KEY] 탭 → 키 복사
4. .env 파일에 추가:
       BPS_API_KEY=your_api_key_here
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BPS API 구조:
  Base: https://webapi.bps.go.id/v1/api
  지표: /list/model/data/domain/0000/var/{var_id}/key/{api_key}
  CPI 변수 ID (idn_inflation 관련):
    - 1707 : 인플레이션율 (YoY, %)          ← 기본 사용
    - 1708 : 인플레이션율 (MoM, %)
  응답 형식: JSON  {"datacontent": [{"label": "Jan 2025", "val": "2.96"}, ...]}

실행: uv run python collectors/bps_collector.py
"""
import os
import sys
from datetime import date, datetime

import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from supabase import create_client

_sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

BPS_BASE = "https://webapi.bps.go.id/v1/api"
VAR_INFLATION_YOY = "1707"   # YoY CPI 인플레이션율 (%)
INDICATOR_ID = "idn_inflation"


def _get_api_key() -> str:
    key = os.environ.get("BPS_API_KEY", "")
    if not key:
        print(
            "\n[ERROR] BPS_API_KEY 가 .env 에 없습니다.\n"
            "  → https://webapi.bps.go.id 에서 무료 토큰 발급 후\n"
            "    .env 파일에 BPS_API_KEY=<your_key> 추가\n",
            file=sys.stderr,
        )
        sys.exit(1)
    return key


def fetch_bps_inflation(api_key: str) -> list[tuple[date, float]]:
    """BPS API에서 인플레이션율(YoY) 최근 데이터 반환."""
    url = f"{BPS_BASE}/list/model/data/domain/0000/var/{VAR_INFLATION_YOY}/key/{api_key}"
    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
        payload = resp.json()
    except Exception as e:
        print(f"  [WARN] BPS API 호출 실패: {e}", file=sys.stderr)
        return []

    # datacontent 구조: [{"label": "Januari 2025", "val": "2.96"}, ...]
    # 또는 중첩 dict 형식일 수 있음 — BPS API 버전에 따라 상이
    raw: list[dict] = []
    if isinstance(payload.get("datacontent"), list):
        raw = payload["datacontent"]
    elif isinstance(payload.get("datacontent"), dict):
        # 일부 버전: {"2025": {"1": {"val": "2.96", ...}, ...}}
        for year, months in payload["datacontent"].items():
            if isinstance(months, dict):
                for month, item in months.items():
                    if isinstance(item, dict) and "val" in item:
                        raw.append({"year": year, "month": month, "val": item["val"]})

    results: list[tuple[date, float]] = []
    for item in raw:
        try:
            val = float(str(item.get("val", "")).replace(",", "."))
            # label 기반 날짜 파싱 (예: "Januari 2025")
            label: str = item.get("label", "")
            d = _parse_bps_date(label, item)
            if d:
                results.append((d, val))
        except (ValueError, TypeError):
            continue

    # 최신순 정렬 후 최근 12개월만 반환
    results.sort(key=lambda x: x[0])
    return results[-12:]


_BPS_MONTH_MAP = {
    "Januari": 1, "Februari": 2, "Maret": 3, "April": 4,
    "Mei": 5, "Juni": 6, "Juli": 7, "Agustus": 8,
    "September": 9, "Oktober": 10, "November": 11, "Desember": 12,
    # 약어
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
}


def _parse_bps_date(label: str, item: dict) -> date | None:
    """BPS 레이블 문자열을 date 객체로 변환."""
    # 형식 1: "Januari 2025"
    parts = label.split()
    if len(parts) == 2:
        month_str, year_str = parts
        m = _BPS_MONTH_MAP.get(month_str)
        if m and year_str.isdigit():
            return date(int(year_str), m, 1)
    # 형식 2: item 에 year / month 키가 있는 경우
    year = item.get("year")
    month = item.get("month")
    if year and month:
        try:
            return date(int(year), int(month), 1)
        except (ValueError, TypeError):
            pass
    return None


def upsert_values(rows: list[dict]) -> None:
    if not rows:
        return
    _sb.table("indicator_history").upsert(
        rows, on_conflict="indicator_id,recorded_date"
    ).execute()


def run() -> None:
    today = date.today()
    print(f"\n[bps_collector] {today} 인도네시아 물가 수집 시작")

    api_key = _get_api_key()
    history = fetch_bps_inflation(api_key)

    if not history:
        print("  [FAIL] 데이터 없음 — BPS API 응답 구조 변경 가능성 확인 필요")
        return

    rows = [
        {
            "indicator_id": INDICATOR_ID,
            "value": val,
            "recorded_date": d.isoformat(),
            "note": "BPS YoY CPI",
        }
        for d, val in history
    ]
    upsert_values(rows)

    latest_date, latest_val = history[-1]
    print(f"  인도네시아 물가(YoY)  {latest_val:.2f}%  ({latest_date.strftime('%Y-%m')})")
    print(f"  총 {len(rows)}개 레코드 upsert 완료")

    # 최근 6개월 미니 테이블 출력
    print(f"\n  {'연월':<12} {'YoY (%)':>8}")
    print("  " + "─" * 22)
    for d, v in history[-6:]:
        print(f"  {d.strftime('%Y-%m'):<12} {v:>8.2f}%")

    print(f"\n[bps_collector] 완료\n")

    from heartbeat import record
    record("bps_collector")


if __name__ == "__main__":
    run()
