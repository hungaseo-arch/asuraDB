"""
주간 지표 수집기 — 원자재·운임 주간 갱신 (매주 금요일 실행)

수집 대상:
  #5  coal             — 석탄 Newcastle (Trading Economics)
  #6  carbon_black     — 카본블랙 (브렌트유 Proxy 자동 추정 + 수동)
  #7  synthetic_rubber — 합성고무 BD (Trading Economics Butadiene + 수동)
  #8  steel_wire       — 강선 HRC (Trading Economics Steel HRC + 수동)
  #13 scfi             — Shanghai Containerized Freight Index (SSE 공식)

실행: uv run python collectors/weekly_collector.py
cron: 0 10 * * 5  uv run python collectors/weekly_collector.py

소스 우선순위 (#5,#7,#8): Trading Economics → 수동 입력
소스 우선순위 (#6):        DB 브렌트유 Proxy → 수동 입력
소스 우선순위 (#13):       SSE AJAX → SSE HTML → MacroMicro → 수동 입력
"""
import json
import os
import re
import sys
from datetime import date, timedelta
from typing import Optional

import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from supabase import create_client

_sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

TIMEOUT = 25
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

# ── 소스 URL ─────────────────────────────────────────────────
_SSE_URL     = "https://en.sse.net.cn/indices/scfinew.jsp"
_SSE_API     = "https://en.sse.net.cn/indices/scfinew.do"   # AJAX 엔드포인트 (비공식)
_MACRO_URL   = "https://en.macromicro.me/series/7541/china-scfi"
_TE_BASE     = "https://tradingeconomics.com"
_TE_GUEST    = "https://api.tradingeconomics.com/commodity"

# TE 슬러그 및 유효 범위
_TE_CFG: dict[str, tuple[str, float, float]] = {
    # indicator_id: (slug, val_min, val_max)
    "coal":             ("coal-newcastle",  80,   500),   # USD/MT
    "synthetic_rubber": ("butadiene",      500,  3000),   # USD/MT (BD)
    "steel_wire":       ("steel",          300,  2000),   # USD/MT (HRC 기준)
}


# ══════════════════════════════════════════════════════════════
#  공통 유틸
# ══════════════════════════════════════════════════════════════

def upsert(indicator_id: str, record_date: date, value: float, note: str = "") -> None:
    _sb.table("indicator_history").upsert(
        {
            "indicator_id":  indicator_id,
            "value":         value,
            "recorded_date": record_date.isoformat(),
            "note":          note or None,
        },
        on_conflict="indicator_id,recorded_date",
    ).execute()


def _latest_in_db(indicator_id: str) -> Optional[tuple[date, float]]:
    rows = (
        _sb.table("indicator_history")
        .select("value,recorded_date")
        .eq("indicator_id", indicator_id)
        .order("recorded_date", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if rows:
        return date.fromisoformat(rows[0]["recorded_date"]), float(rows[0]["value"])
    return None


_MONTH_MAP = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    "january": 1, "february": 2, "march": 3, "april": 4, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
}


def _parse_date(s: str) -> Optional[date]:
    s = s.strip()
    # YYYY-MM-DD
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", s)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass
    # DD/MM/YYYY
    m = re.match(r"(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})", s)
    if m:
        try:
            return date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
        except ValueError:
            pass
    # "2025/05/23" 또는 "2025.05.23"
    m = re.match(r"(\d{4})[/\.](\d{1,2})[/\.](\d{1,2})", s)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass
    # "23 May 2025"
    m = re.match(r"(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})", s)
    if m:
        mo = _MONTH_MAP.get(m.group(2).lower())
        if mo:
            try:
                return date(int(m.group(3)), mo, int(m.group(1)))
            except ValueError:
                pass
    return None


def _last_friday() -> date:
    """가장 최근 금요일 날짜 반환 (오늘이 금요일이면 오늘)."""
    today = date.today()
    days_back = (today.weekday() - 4) % 7  # 4 = Friday
    return today - timedelta(days=days_back)


# ══════════════════════════════════════════════════════════════
#  Trading Economics 공통 스크래퍼 (daily_collector.py 동일 패턴)
# ══════════════════════════════════════════════════════════════

def _search_json_for_price(
    data: object, val_min: float, val_max: float, depth: int = 0
) -> Optional[float]:
    if depth > 8:
        return None
    if isinstance(data, (int, float)):
        v = float(data)
        if val_min <= v <= val_max:
            return v
    elif isinstance(data, dict):
        for key in ("price", "last", "close", "value", "current", "lastPrice"):
            if key in data:
                v = _search_json_for_price(data[key], val_min, val_max, depth + 1)
                if v is not None:
                    return v
        for v in data.values():
            result = _search_json_for_price(v, val_min, val_max, depth + 1)
            if result is not None:
                return result
    elif isinstance(data, list):
        for item in data[:20]:
            result = _search_json_for_price(item, val_min, val_max, depth + 1)
            if result is not None:
                return result
    return None


def _fetch_te(slug: str, val_min: float, val_max: float) -> Optional[float]:
    """Trading Economics 상품 페이지 스크래핑 (Next.js __NEXT_DATA__ → 메타 → 텍스트)."""
    url = f"{_TE_BASE}/commodity/{slug}"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] TE 접속 실패 ({slug}): {e}", file=sys.stderr)
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    for tag in soup.find_all("script"):
        tag_id   = tag.get("id", "")
        tag_type = tag.get("type", "")
        if tag_id == "__NEXT_DATA__" or "json" in tag_type:
            try:
                data = json.loads(tag.string or "")
                result = _search_json_for_price(data, val_min, val_max)
                if result is not None:
                    return result
            except Exception:
                pass

    for meta in soup.find_all("meta"):
        content = meta.get("content", "")
        for n in re.findall(r"\b(\d{2,6}(?:\.\d{1,4})?)\b", content):
            v = float(n)
            if val_min <= v <= val_max:
                return v

    text = soup.get_text(" ")
    candidates = [
        float(n) for n in re.findall(r"\b(\d{2,6}(?:\.\d{1,4})?)\b", text[:5000])
        if val_min <= float(n) <= val_max
    ]
    if candidates:
        from collections import Counter
        return Counter(candidates).most_common(1)[0][0]

    return None


def _fetch_te_api(slug: str, val_min: float, val_max: float) -> Optional[float]:
    """Trading Economics 게스트 API 백업."""
    try:
        resp = requests.get(
            _TE_GUEST,
            params={"c": "guest:guest", "f": "json", "commodity": slug},
            headers=HEADERS,
            timeout=TIMEOUT,
        )
        if resp.status_code != 200:
            return None
        items = resp.json()
        if not isinstance(items, list):
            items = [items]
        for item in items:
            if not isinstance(item, dict):
                continue
            for key in ("Last", "last", "Price", "price", "Close", "close"):
                if key in item:
                    try:
                        v = float(str(item[key]).replace(",", ""))
                        if val_min <= v <= val_max:
                            return v
                    except (ValueError, TypeError):
                        pass
    except Exception:
        pass
    return None


def _latest_brent_from_db() -> Optional[float]:
    """DB에서 최신 브렌트유 가격(USD/bbl) 조회."""
    rows = (
        _sb.table("indicator_history")
        .select("value")
        .eq("indicator_id", "brent_crude")
        .order("recorded_date", desc=True)
        .limit(1)
        .execute()
        .data
    )
    return float(rows[0]["value"]) if rows else None


# ══════════════════════════════════════════════════════════════
#  #5  석탄 Newcastle (coal)
#  단위: USD/MT  |  소스: Trading Economics Newcastle
# ══════════════════════════════════════════════════════════════

def collect_coal() -> bool:
    print("\n── #5 석탄 Newcastle (coal) ─────────────────────────────")
    slug, lo, hi = _TE_CFG["coal"]

    print("  1차: Trading Economics Newcastle 시도...")
    val = _fetch_te(slug, lo, hi)

    if val is None:
        print("  TE 파싱 실패 → TE API 시도...")
        val = _fetch_te_api(slug, lo, hi)

    if val is None:
        latest = _latest_in_db("coal")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ Newcastle: https://tradingeconomics.com/commodity/coal-newcastle (USD/MT)")
        print("  ▸ HBA 인도네시아: https://www.minerba.esdm.go.id/harga_acuan")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:.2f} USD/MT  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/weekly_collector.py --coal 135.0")
        return False

    today = date.today()
    prev  = _latest_in_db("coal")
    upsert("coal", today, val, "Trading Economics Newcastle Coal")
    change = ""
    if prev and prev[1] != 0:
        pct    = (val - prev[1]) / prev[1] * 100
        arrow  = "▲" if pct > 0 else ("▼" if pct < 0 else "─")
        change = f"  {arrow} {pct:+.2f}% vs {prev[0]}"
    print(f"  석탄: {val:.2f} USD/MT{change}  ✓")
    return True


# ══════════════════════════════════════════════════════════════
#  #6  카본블랙 (carbon_black)
#  단위: USD/MT  |  소스: 브렌트유 DB Proxy (수동 우선)
# ══════════════════════════════════════════════════════════════

# 카본블랙 ≈ 브렌트유(USD/bbl) × 13~15 (역사적 평균 환산 계수)
_CB_BRENT_FACTOR = 14.0


def collect_carbon_black() -> bool:
    print("\n── #6 카본블랙 (carbon_black) ───────────────────────────")

    brent = _latest_brent_from_db()
    if brent is not None:
        val    = round(brent * _CB_BRENT_FACTOR, 0)
        today  = date.today()
        prev   = _latest_in_db("carbon_black")
        upsert("carbon_black", today, val, f"Proxy: Brent×{_CB_BRENT_FACTOR} (Brent={brent:.2f})")
        change = ""
        if prev and prev[1] != 0:
            pct    = (val - prev[1]) / prev[1] * 100
            arrow  = "▲" if pct > 0 else ("▼" if pct < 0 else "─")
            change = f"  {arrow} {pct:+.2f}% vs {prev[0]}"
        print(f"  카본블랙: {val:,.0f} USD/MT (Proxy, Brent={brent:.2f}){change}  ✓")
        print("  ⚠ 분기별 공급사 견적으로 실측값 갱신 권장")
        return True

    latest = _latest_in_db("carbon_black")
    print("  [INFO] DB에 브렌트유 데이터 없음 — 수동 입력 필요")
    print("  ▸ Proxy: 브렌트유 가격 × 14 ≈ 카본블랙 USD/MT (Cabot, Birla Carbon 견적 확인)")
    if latest:
        print(f"  ▸ DB 최근값: {latest[1]:,.0f} USD/MT  ({latest[0]})")
    print("  ▸ 수동 실행: uv run python collectors/weekly_collector.py --carbon-black 1050")
    return False


# ══════════════════════════════════════════════════════════════
#  #7  합성고무 BD (synthetic_rubber)
#  단위: USD/MT  |  소스: Trading Economics Butadiene → 수동
# ══════════════════════════════════════════════════════════════

def collect_synthetic_rubber() -> bool:
    print("\n── #7 합성고무 BD (synthetic_rubber) ────────────────────")
    slug, lo, hi = _TE_CFG["synthetic_rubber"]

    print("  1차: Trading Economics Butadiene 시도...")
    val = _fetch_te(slug, lo, hi)

    if val is None:
        print("  TE 파싱 실패 → TE API 시도...")
        val = _fetch_te_api(slug, lo, hi)

    if val is None:
        latest = _latest_in_db("synthetic_rubber")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ ICIS Butadiene: https://tradingeconomics.com/commodity/butadiene (USD/MT)")
        print("  ▸ 공급사 견적: Kumho Petrochemical, LANXESS, Sinopec")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:,.0f} USD/MT  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/weekly_collector.py --synthetic-rubber 1200")
        return False

    today = date.today()
    prev  = _latest_in_db("synthetic_rubber")
    upsert("synthetic_rubber", today, val, "Trading Economics Butadiene (BD)")
    change = ""
    if prev and prev[1] != 0:
        pct    = (val - prev[1]) / prev[1] * 100
        arrow  = "▲" if pct > 0 else ("▼" if pct < 0 else "─")
        change = f"  {arrow} {pct:+.2f}% vs {prev[0]}"
    print(f"  합성고무 BD: {val:,.0f} USD/MT{change}  ✓")
    return True


# ══════════════════════════════════════════════════════════════
#  #8  강선 HRC (steel_wire)
#  단위: USD/MT  |  소스: Trading Economics Steel HRC → 수동
# ══════════════════════════════════════════════════════════════

def collect_steel_wire() -> bool:
    print("\n── #8 강선 HRC (steel_wire) ─────────────────────────────")
    slug, lo, hi = _TE_CFG["steel_wire"]

    print("  1차: Trading Economics Steel HRC 시도...")
    val = _fetch_te(slug, lo, hi)

    if val is None:
        print("  TE 파싱 실패 → TE API 시도...")
        val = _fetch_te_api(slug, lo, hi)

    if val is None:
        latest = _latest_in_db("steel_wire")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ HRC 참고: https://tradingeconomics.com/commodity/steel (USD/MT)")
        print("  ▸ SteelOrbis: https://www.steelorbis.com/steel-prices")
        print("  ▸ 공급사 견적: Bekaert, Hyosung, Jiangsu Xingda")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:,.0f} USD/MT  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/weekly_collector.py --steel-wire 650")
        return False

    today = date.today()
    prev  = _latest_in_db("steel_wire")
    upsert("steel_wire", today, val, "Trading Economics Steel HRC (Proxy)")
    change = ""
    if prev and prev[1] != 0:
        pct    = (val - prev[1]) / prev[1] * 100
        arrow  = "▲" if pct > 0 else ("▼" if pct < 0 else "─")
        change = f"  {arrow} {pct:+.2f}% vs {prev[0]}"
    print(f"  강선 HRC: {val:,.0f} USD/MT{change}  ✓")
    return True


# ══════════════════════════════════════════════════════════════
#  #13  SCFI 수집 함수
# ══════════════════════════════════════════════════════════════

def _fetch_sse_ajax() -> Optional[tuple[date, float]]:
    """SSE AJAX 엔드포인트 시도 (Composite SCFI)."""
    try:
        # SSE 사이트가 내부적으로 사용하는 JSON API
        resp = requests.get(
            _SSE_API,
            params={"t": "scfi"},
            headers={**HEADERS, "Referer": _SSE_URL, "X-Requested-With": "XMLHttpRequest"},
            timeout=TIMEOUT,
        )
        if resp.status_code != 200:
            return None
        data = resp.json()

        # 응답 구조 탐색: [{"date":"2025-05-23","scfi":1234.56,...}, ...]
        series = data if isinstance(data, list) else data.get("data", data.get("rows", []))
        if not isinstance(series, list) or not series:
            return None

        latest = max(
            series,
            key=lambda x: x.get("date", x.get("pubdate", x.get("time", ""))),
        )
        for date_key in ("date", "pubdate", "time", "releaseDate"):
            if date_key in latest:
                d = _parse_date(str(latest[date_key]))
                if d:
                    break
        else:
            return None

        for val_key in ("scfi", "composite", "value", "index", "综合指数"):
            v = latest.get(val_key)
            if v is not None:
                try:
                    val = float(str(v).replace(",", ""))
                    if 300 <= val <= 6000:   # SCFI 역사적 범위
                        return d, val
                except ValueError:
                    pass
    except Exception:
        pass
    return None


def _fetch_sse_html() -> Optional[tuple[date, float]]:
    """SSE 공식 페이지 HTML 테이블 스크래핑."""
    try:
        resp = requests.get(_SSE_URL, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] SSE 접속 실패: {e}", file=sys.stderr)
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    # SSE 페이지 구조: 테이블 첫 행에 날짜, 두 번째 컬럼에 Composite Index
    for table in soup.find_all("table"):
        rows = table.find_all("tr")
        for row in rows:
            cols = [td.get_text(strip=True) for td in row.find_all(["td", "th"])]
            if len(cols) < 2:
                continue
            d = _parse_date(cols[0])
            if d is None:
                continue
            # Composite SCFI = 첫 번째 숫자 열
            for col in cols[1:]:
                try:
                    val = float(col.replace(",", "").replace(" ", ""))
                    if 300 <= val <= 6000:
                        return d, val
                except ValueError:
                    continue
    return None


def _fetch_macromicro() -> Optional[tuple[date, float]]:
    """MacroMicro 백업 소스 스크래핑."""
    try:
        resp = requests.get(_MACRO_URL, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] MacroMicro 접속 실패: {e}", file=sys.stderr)
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    # MacroMicro는 Next.js 기반 — __NEXT_DATA__ 스크립트에 시계열 데이터 포함
    script = soup.find("script", id="__NEXT_DATA__")
    if script and script.string:
        try:
            ndata = json.loads(script.string)
            # props.pageProps.data.series 또는 비슷한 경로
            def _search(obj: object) -> Optional[tuple[date, float]]:
                if isinstance(obj, list):
                    # [timestamp_ms, value] 쌍 리스트 탐색
                    pairs = [x for x in obj if isinstance(x, (list, tuple)) and len(x) == 2]
                    if pairs:
                        latest = max(pairs, key=lambda x: x[0])
                        try:
                            import datetime as dt
                            d = dt.date.fromtimestamp(latest[0] / 1000)
                            val = float(latest[1])
                            if 300 <= val <= 6000:
                                return d, val
                        except Exception:
                            pass
                    for item in obj:
                        r = _search(item)
                        if r:
                            return r
                elif isinstance(obj, dict):
                    for v in obj.values():
                        r = _search(v)
                        if r:
                            return r
                return None
            result = _search(ndata)
            if result:
                return result
        except Exception:
            pass

    # Fallback: 텍스트에서 숫자 패턴
    text = soup.get_text(" ")
    matches = re.findall(r"\b([3-5]\d{2,3}(?:\.\d{1,2})?)\b", text)
    date_matches = re.findall(r"\d{4}-\d{2}-\d{2}", text)
    if matches and date_matches:
        d = _parse_date(date_matches[0])
        if d:
            try:
                return d, float(matches[0])
            except ValueError:
                pass
    return None


def collect_scfi() -> bool:
    """SCFI 컨테이너운임지수 수집. 성공 시 True 반환."""
    print("\n── #13 SCFI 컨테이너운임 (scfi) ────────────────────────")
    print(f"  발표 기준일: {_last_friday()} (금요일)")

    # 1차: SSE AJAX API
    result = _fetch_sse_ajax()

    # 2차: SSE HTML 파싱
    if result is None:
        print("  SSE API 실패 → HTML 스크래핑 시도...")
        result = _fetch_sse_html()

    # 3차: MacroMicro 백업
    if result is None:
        print("  SSE HTML 실패 → MacroMicro 백업 시도...")
        result = _fetch_macromicro()

    if result is None:
        latest = _latest_in_db("scfi")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ 최신값 확인: https://en.sse.net.cn/indices/scfinew.jsp")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:.1f}  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/weekly_collector.py --scfi 1234.5")
        return False

    record_date, idx = result
    upsert("scfi", record_date, idx, "SSE / MacroMicro")

    # 전주 대비 변화
    latest = _latest_in_db("scfi")
    if latest and latest[0] != record_date:
        pct = (idx - latest[1]) / latest[1] * 100
        arrow = "▲" if pct > 0 else ("▼" if pct < 0 else "─")
        change = f"  {arrow} {pct:+.2f}% vs {latest[0]}"
    else:
        change = ""

    print(f"  SCFI Composite: {idx:,.1f}  ({record_date}){change}  ✓")
    return True


# ══════════════════════════════════════════════════════════════
#  CLI 수동 입력
#  예) uv run python collectors/weekly_collector.py --scfi 1234.5
#      uv run python collectors/weekly_collector.py --coal 135.0
#      uv run python collectors/weekly_collector.py --carbon-black 1050 --steel-wire 650
# ══════════════════════════════════════════════════════════════

_CLI_MAP = {
    "--coal":             ("coal",             "USD/MT",  "{:.2f}"),
    "--carbon-black":     ("carbon_black",     "USD/MT",  "{:,.0f}"),
    "--synthetic-rubber": ("synthetic_rubber", "USD/MT",  "{:,.0f}"),
    "--steel-wire":       ("steel_wire",       "USD/MT",  "{:,.0f}"),
    "--scfi":             ("scfi",             "Index",   "{:,.1f}"),
}


def _handle_cli(args: list[str]) -> bool:
    friday  = _last_friday()
    today   = date.today()
    handled = False
    i = 0
    while i < len(args):
        flag = args[i]
        if flag in _CLI_MAP and i + 1 < len(args):
            ind_id, unit, fmt = _CLI_MAP[flag]
            val = float(args[i + 1])
            record_date = friday if ind_id == "scfi" else today
            upsert(ind_id, record_date, val, "수동 입력")
            print(f"  {ind_id} 수동 저장: {fmt.format(val)} {unit}  ({record_date})")
            handled = True; i += 2
        else:
            i += 1
    return handled


# ══════════════════════════════════════════════════════════════
#  Entry point
# ══════════════════════════════════════════════════════════════

def run() -> None:
    today = date.today()
    print(f"\n[weekly_collector] {today} 주간 지표 수집 시작")
    print("=" * 52)

    if len(sys.argv) > 1:
        if _handle_cli(sys.argv[1:]):
            print("\n[weekly_collector] 수동 입력 완료")
            return

    ok_coal   = collect_coal()
    ok_cb     = collect_carbon_black()
    ok_sr     = collect_synthetic_rubber()
    ok_sw     = collect_steel_wire()
    ok_scfi   = collect_scfi()

    print("\n" + "=" * 52)
    results = [
        ("#5  석탄 Newcastle",  ok_coal,  "--coal <USD/MT>"),
        ("#6  카본블랙",         ok_cb,    "--carbon-black <USD/MT>"),
        ("#7  합성고무 BD",      ok_sr,    "--synthetic-rubber <USD/MT>"),
        ("#8  강선 HRC",        ok_sw,    "--steel-wire <USD/MT>"),
        ("#13 SCFI 컨테이너운임", ok_scfi, "--scfi <지수값>"),
    ]
    success = sum(1 for _, ok, _ in results if ok)
    for name, ok, _ in results:
        print(f"  {name:<24} {'✓' if ok else '✗ 수동 입력 필요'}")

    print(f"\n[weekly_collector] 완료: {success}/{len(results)} 성공")

    failed = [(name, cmd) for name, ok, cmd in results if not ok]
    if failed:
        print("\n수동 입력 명령어:")
        for _, cmd in failed:
            print(f"  uv run python collectors/weekly_collector.py --{cmd}")

    from heartbeat import record
    record("weekly_collector")


if __name__ == "__main__":
    run()
