"""
일일 지표 수집기 — 웹 스크래핑 기반 (yfinance 미지원 원자재)

수집 대상:
  #2  nr_rubber  — 천연고무 TSR20 (Trading Economics) · 저장단위 USD/MT
  #4  nickel     — 니켈 LME (Trading Economics)

2026-08-24 변경 (5년백필 §2 단위·출처 통일)
  · nr_rubber 는 소스가 USc/kg 로 주는 값을 ×10 해 USD/MT 로 저장한다.
    (DB 는 원자재 전 지표를 USD/MT 로 통일. 1 USc/kg = 10 USD/MT)
  · cpo 는 이 수집기에서 제외했다. 출처가 Bursa FCPO(MYR/MT) → Kemendag
    Harga Referensi(USD/MT, 월 1회 고시) 로 바뀌어 monthly_collector 가 맡는다.

실행: uv run python collectors/daily_collector.py
cron: 0 9 * * 1-5  TZ=Asia/Jakarta  uv run python collectors/daily_collector.py
       └─ 인도네시아 서부시간(WIB) 평일 09:00 (Investing.com 갱신 직후)

수집 전략:
  #2  nr_rubber: 1차 TE HTML → 2차 TE API → 3차 Investing.com → 4차 수동
                 (SICOM 공식 도메인 단종 / SGX는 유료 데이터피드 → 자동수집 제외)
  #4  nickel:    1차 LME 공식 → 2차 TE HTML → 3차 TE API → 4차 수동
"""
import json
import os
import re
import sys
from datetime import date
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
    "Referer": "https://tradingeconomics.com/",
}

# ── Trading Economics 설정 ────────────────────────────────────
_TE_BASE    = "https://tradingeconomics.com"
_TE_API     = "https://api.tradingeconomics.com/commodity"

# 지표별 TE URL 슬러그
_TE_SLUGS: dict[str, str] = {
    "nr_rubber": "rubber",
    "nickel":    "nickel",
}

# ── 공식 소스 URL ─────────────────────────────────────────────
# Investing.com TSR20 선물 — 비회원도 현재가 표기는 노출 (CSV는 회원 전용)
_INVESTING_TSR20_URLS = (
    "https://www.investing.com/commodities/rubber-tsr20",
    "https://www.investing.com/commodities/rubber",
)

# 지표별 합리적 값 범위 (이상값 필터) — 소스가 주는 원 단위 기준
_VAL_RANGE: dict[str, tuple[float, float]] = {
    "nr_rubber": (50,   500),    # USc/kg (저장 시 ×10 → USD/MT)
    "nickel":    (5000, 100000), # USD/MT
}

# 소스 단위 → 저장 단위 환산계수 (market_indicators.unit_factor 와 같은 뜻)
_UNIT_FACTOR: dict[str, float] = {
    "nr_rubber": 10.0,   # USc/kg → USD/MT
    "nickel":    1.0,
}


# ══════════════════════════════════════════════════════════════
#  공통 유틸
# ══════════════════════════════════════════════════════════════

def _is_yearlike(v: float) -> bool:
    """연도(2015~2035)로 보이는 정수값 — 페이지 텍스트의 연도 표기가 원자재 가격 범위
    (1000~10000)에 걸려 가격으로 오인되는 사고 방지 (2026-08-24 CPO 에서 실제 발생)."""
    return v == int(v) and 2015 <= v <= 2035


def upsert(indicator_id: str, value: float, note: str = "", quality: str = "실측") -> None:
    """저장 단위(USD/MT 등)로 환산한 값을 기록. 모든 행에 출처·품질 등급 필수."""
    today = date.today()
    if not note:
        raise ValueError(f"note(출처) 없는 행 금지: {indicator_id}")
    if quality not in ("실측", "파생", "추정"):
        raise ValueError(f"quality 값 오류: {quality}")
    _sb.table("indicator_history").upsert(
        {
            "indicator_id":  indicator_id,
            "value":         value,
            "recorded_date": today.isoformat(),
            "note":          note,
            "quality":       quality,
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


def _reject_outlier(indicator_id: str, val: Optional[float], max_dev: float = 0.25) -> Optional[float]:
    """DB 최근값 대비 ±max_dev 초과 이탈 값은 스크래핑 오인으로 간주하고 버린다.

    TE 페이지의 JSON/텍스트 탐색이 무관한 숫자(연도·타 상품가)를 집어오는 사고 방지
    (2026-08-24 CPO 에서 2,026·7,268 오인 실제 발생). 실제 급등락이라면 수동 입력으로
    반영한다 (--nr-rubber 등 CLI 는 이 검사를 거치지 않음).
    """
    if val is None:
        return None
    prev = _latest_in_db(indicator_id)
    if prev and prev[1] > 0 and abs(val - prev[1]) / prev[1] > max_dev:
        print(
            f"  [WARN] 이상값 의심 — {indicator_id}: {val:,.2f} "
            f"(DB 최근 {prev[1]:,.2f} ({prev[0]}) 대비 ±{max_dev:.0%} 초과) → 저장 안 함",
            file=sys.stderr,
        )
        return None
    return val


def _fmt_change(current: float, prev: Optional[tuple[date, float]]) -> str:
    if prev is None or prev[1] == 0:
        return ""
    pct = (current - prev[1]) / prev[1] * 100
    arrow = "▲" if pct > 0 else ("▼" if pct < 0 else "─")
    return f"  {arrow} {pct:+.2f}% vs {prev[0]}"


# ══════════════════════════════════════════════════════════════
#  Trading Economics 스크래핑 공통 함수
# ══════════════════════════════════════════════════════════════

def _fetch_te_nextdata(slug: str, val_min: float, val_max: float) -> Optional[float]:
    """Next.js __NEXT_DATA__ JSON에서 현재가 추출."""
    url = f"{_TE_BASE}/commodity/{slug}"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] TE 접속 실패 ({slug}): {e}", file=sys.stderr)
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    # 1) __NEXT_DATA__ 스크립트
    script = soup.find("script", id="__NEXT_DATA__")
    if script and script.string:
        try:
            data = json.loads(script.string)
            result = _search_json_for_price(data, val_min, val_max)
            if result is not None:
                return result
        except Exception:
            pass

    # 2) application/json 또는 application/ld+json 스크립트
    for tag in soup.find_all("script", type=re.compile(r"application/(ld\+)?json")):
        try:
            data = json.loads(tag.string or "")
            result = _search_json_for_price(data, val_min, val_max)
            if result is not None:
                return result
        except Exception:
            pass

    # 3) 메타 태그 (og:description 또는 description에 현재가 포함)
    for meta in soup.find_all("meta"):
        content = meta.get("content", "")
        nums = re.findall(r"\b(\d{2,6}(?:\.\d{1,4})?)\b", content)
        for n in nums:
            v = float(n)
            if val_min <= v <= val_max and not _is_yearlike(v):
                return v

    # 4) 페이지 텍스트에서 패턴 매칭
    text = soup.get_text(" ")
    # "TSR20 ... 163.50 USc/kg" 또는 그냥 큰 수 패턴
    nums = re.findall(r"\b(\d{2,6}(?:\.\d{1,4})?)\b", text[:5000])
    candidates = [
        float(n) for n in nums
        if val_min <= float(n) <= val_max and not _is_yearlike(float(n))
    ]
    if candidates:
        # 최빈값(가장 많이 등장하는 값)을 현재가로 간주
        from collections import Counter
        return Counter(candidates).most_common(1)[0][0]

    return None


def _search_json_for_price(
    data: object,
    val_min: float,
    val_max: float,
    depth: int = 0,
) -> Optional[float]:
    """JSON 트리에서 합리적 범위 내 숫자 값을 재귀 탐색."""
    if depth > 8:
        return None
    if isinstance(data, (int, float)):
        v = float(data)
        if val_min <= v <= val_max and not _is_yearlike(v):
            return v
    elif isinstance(data, dict):
        # 우선순위 키: price, last, close, value, current
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
        for item in data[:20]:   # 배열은 앞 20개만
            result = _search_json_for_price(item, val_min, val_max, depth + 1)
            if result is not None:
                return result
    return None


def _fetch_te_api(slug: str, val_min: float, val_max: float) -> Optional[float]:
    """Trading Economics 게스트 API (rate-limit 걸릴 수 있음)."""
    try:
        resp = requests.get(
            _TE_API,
            params={"c": "guest:guest", "f": "json", "commodity": slug},
            headers=HEADERS,
            timeout=TIMEOUT,
        )
        if resp.status_code != 200:
            return None
        data = resp.json()
        items = data if isinstance(data, list) else [data]
        for item in items:
            if not isinstance(item, dict):
                continue
            for key in ("Last", "last", "Price", "price", "Close", "close"):
                if key in item:
                    try:
                        v = float(str(item[key]).replace(",", ""))
                        if val_min <= v <= val_max and not _is_yearlike(v):
                            return v
                    except (ValueError, TypeError):
                        pass
    except Exception:
        pass
    return None


# ══════════════════════════════════════════════════════════════
#  공식 소스 스크래퍼 — 천연고무 TSR20
#  (SICOM 도메인 단종 / SGX 유료 데이터피드 → Investing.com·TE 대체)
# ══════════════════════════════════════════════════════════════

def _fetch_investing_tsr20() -> Optional[float]:
    """Investing.com TSR20 Futures 페이지에서 현재가 (USc/kg) 추출.

    회원가입 후 CSV 다운로드가 공식 경로이지만, 비회원도 페이지 상단에
    'last price' 가 평문/JSON 으로 노출된다. CloudFlare 차단 시 None 반환.
    """
    lo, hi = _VAL_RANGE["nr_rubber"]

    for url in _INVESTING_TSR20_URLS:
        try:
            resp = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
            if resp.status_code != 200:
                continue
        except Exception as e:
            print(f"  [WARN] Investing.com 접속 실패 ({url}): {e}", file=sys.stderr)
            continue

        soup = BeautifulSoup(resp.text, "html.parser")

        # 1) data-test="instrument-price-last" 셀렉터 (Investing.com 표준)
        for el in soup.select('[data-test="instrument-price-last"], .last-price-value, .pid-last'):
            text = el.get_text(strip=True).replace(",", "")
            for n in re.findall(r"\b(\d{2,4}(?:\.\d{1,4})?)\b", text):
                v = float(n)
                if lo <= v <= hi:
                    return v

        # 2) JSON 스크립트 탐색
        for tag in soup.find_all("script", type=re.compile(r"application/(ld\+)?json")):
            try:
                data = json.loads(tag.string or "")
                result = _search_json_for_price(data, lo, hi)
                if result is not None:
                    return result
            except Exception:
                pass

        # 3) 페이지 텍스트 최빈값 (앞 5000자)
        text = soup.get_text(" ")
        candidates = [
            float(n) for n in re.findall(r"\b(\d{2,4}(?:\.\d{1,4})?)\b", text[:5000])
            if lo <= float(n) <= hi
        ]
        if candidates:
            from collections import Counter
            return Counter(candidates).most_common(1)[0][0]

    return None


def collect_nr_rubber() -> bool:
    print("\n── #2 천연고무 TSR20 (nr_rubber) ───────────────────────")

    lo, hi = _VAL_RANGE["nr_rubber"]
    source = ""

    # 1차: Trading Economics __NEXT_DATA__
    print("  1차: Trading Economics 시도...")
    val = _reject_outlier("nr_rubber", _fetch_te_nextdata(_TE_SLUGS["nr_rubber"], lo, hi))
    if val is not None:
        source = "Trading Economics Rubber"

    # 2차: TE 게스트 API
    if val is None:
        print("  TE Next.js 파싱 실패 → TE API 시도...")
        val = _reject_outlier("nr_rubber", _fetch_te_api(_TE_SLUGS["nr_rubber"], lo, hi))
        if val is not None:
            source = "Trading Economics API"

    # 3차: Investing.com TSR20 Futures
    if val is None:
        print("  TE API 실패 → Investing.com 시도...")
        val = _reject_outlier("nr_rubber", _fetch_investing_tsr20())
        if val is not None:
            source = "Investing.com TSR20"

    if val is None:
        latest = _latest_in_db("nr_rubber")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ 1차: https://tradingeconomics.com/commodity/rubber (USc/kg)")
        print("  ▸ 백업: https://www.investing.com/commodities/rubber-tsr20")
        print("  ▸ 유료 공식: SGX TSR20 Futures (https://www.sgx.com/derivatives/products/rubber)")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:.2f} USc/kg  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/daily_collector.py --nr-rubber 163.5")
        return False

    prev = _latest_in_db("nr_rubber")
    stored = val * _UNIT_FACTOR["nr_rubber"]      # USc/kg → USD/MT
    upsert("nr_rubber", stored,
           f"{source} · TSR20 {val:.2f} USc/kg → 단위환산 USD/MT (×10)")
    change = _fmt_change(stored, prev)
    print(f"  TSR20: {stored:,.0f} USD/MT ({val:.2f} USc/kg){change}  [{source}]  ✓")
    return True


# ══════════════════════════════════════════════════════════════
#  #4  니켈 (nickel)
#  단위: USD/MT
#  소스: 1차 LME 공식 → 2차 Trading Economics → 3차 수동
# ══════════════════════════════════════════════════════════════

_LME_NICKEL_URL = "https://www.lme.com/Metals/Non-ferrous/LME-Nickel"
_LME_API_URL    = "https://www.lme.com/api/price-data"


def _fetch_lme_nickel() -> Optional[float]:
    """LME 공식 사이트에서 니켈 Cash 현물가 (USD/MT) 추출."""
    lo, hi = _VAL_RANGE["nickel"]

    # 1) LME 내부 API — JSON 응답 시도
    try:
        resp = requests.get(
            _LME_API_URL,
            params={"metal": "NI", "type": "cash"},
            headers={**HEADERS, "Accept": "application/json"},
            timeout=TIMEOUT,
        )
        if resp.status_code == 200:
            data = resp.json()
            result = _search_json_for_price(data, lo, hi)
            if result is not None:
                return result
    except Exception:
        pass

    # 2) LME 공식 상품 페이지 HTML 파싱
    try:
        resp = requests.get(_LME_NICKEL_URL, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] LME 접속 실패: {e}", file=sys.stderr)
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    # 2a) __NEXT_DATA__ or application/json 스크립트
    for tag in soup.find_all("script"):
        tag_id   = tag.get("id", "")
        tag_type = tag.get("type", "")
        if tag_id == "__NEXT_DATA__" or "json" in tag_type:
            try:
                data = json.loads(tag.string or "")
                result = _search_json_for_price(data, lo, hi)
                if result is not None:
                    return result
            except Exception:
                pass

    # 2b) 가격 표기 셀 — LME 테이블 구조: td.price, span[data-price], div.price-value 등
    price_selectors = [
        "td.cash", "span.cash-price", "span.price", "td.price",
        "[data-price]", ".price-value", ".lme-price",
    ]
    for sel in price_selectors:
        for el in soup.select(sel):
            text = el.get_text(" ", strip=True).replace(",", "")
            nums = re.findall(r"\b(\d{4,6}(?:\.\d{1,2})?)\b", text)
            for n in nums:
                v = float(n)
                if lo <= v <= hi:
                    return v

    # 2c) 페이지 전체 텍스트에서 Cash 근방 숫자 추출
    text = soup.get_text(" ")
    # "Cash  16,850" / "Cash Settlement  16850.00" 패턴
    cash_match = re.search(
        r"[Cc]ash\s*[Ss]ettlement?\s*[:\-]?\s*([\d,]+(?:\.\d{1,2})?)", text
    )
    if cash_match:
        try:
            v = float(cash_match.group(1).replace(",", ""))
            if lo <= v <= hi:
                return v
        except ValueError:
            pass

    # 2d) 범위 내 모든 숫자 중 최빈값
    nums = re.findall(r"\b(\d{4,6}(?:\.\d{1,2})?)\b", text[:8000])
    candidates = [float(n.replace(",", "")) for n in nums if lo <= float(n.replace(",", "")) <= hi]
    if candidates:
        from collections import Counter
        return Counter(candidates).most_common(1)[0][0]

    return None


def collect_nickel() -> bool:
    print("\n── #4 니켈 (nickel) ────────────────────────────────────")

    lo, hi = _VAL_RANGE["nickel"]
    source = ""

    # 1차: LME 공식
    print("  1차: LME 공식 사이트 시도...")
    val = _reject_outlier("nickel", _fetch_lme_nickel())
    if val is not None:
        source = "LME Cash Settlement"

    # 2차: Trading Economics __NEXT_DATA__
    if val is None:
        print("  LME 파싱 실패 → Trading Economics 시도...")
        val = _reject_outlier("nickel", _fetch_te_nextdata(_TE_SLUGS["nickel"], lo, hi))
        if val is not None:
            source = "Trading Economics (LME)"

    # 3차: Trading Economics 게스트 API
    if val is None:
        print("  TE Next.js 파싱 실패 → TE API 시도...")
        val = _reject_outlier("nickel", _fetch_te_api(_TE_SLUGS["nickel"], lo, hi))
        if val is not None:
            source = "Trading Economics API"

    if val is None:
        latest = _latest_in_db("nickel")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ 공식 LME: https://www.lme.com/Metals/Non-ferrous/LME-Nickel (USD/MT)")
        print("  ▸ 백업: https://tradingeconomics.com/commodity/nickel")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:,.0f} USD/MT  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/daily_collector.py --nickel 17500")
        return False

    prev = _latest_in_db("nickel")
    upsert("nickel", val, source)
    change = _fmt_change(val, prev)
    print(f"  니켈: {val:,.0f} USD/MT{change}  [{source}]  ✓")
    return True


# ══════════════════════════════════════════════════════════════
#  CLI 수동 입력
#  예) uv run python collectors/daily_collector.py --nr-rubber 163.5
#      uv run python collectors/daily_collector.py --nickel 17500
# ══════════════════════════════════════════════════════════════

# 값은 "소스 단위" 로 입력받아 저장 단위로 환산한다 (nr_rubber: USc/kg 입력)
_CLI_MAP = {
    "--nr-rubber": ("nr_rubber", "USc/kg",  "{:.2f}"),
    "--nickel":    ("nickel",    "USD/MT",  "{:,.0f}"),
}


def _handle_cli(args: list[str]) -> bool:
    handled = False
    i = 0
    while i < len(args):
        if args[i] in _CLI_MAP and i + 1 < len(args):
            ind_id, unit, fmt = _CLI_MAP[args[i]]
            val = float(args[i + 1])
            stored = val * _UNIT_FACTOR.get(ind_id, 1.0)
            upsert(ind_id, stored, f"수동 입력 ({fmt.format(val)} {unit})")
            print(f"  {ind_id} 수동 저장: {fmt.format(val)} {unit}  ({date.today()})")
            handled = True; i += 2
        else:
            i += 1
    return handled


# ══════════════════════════════════════════════════════════════
#  Entry point
# ══════════════════════════════════════════════════════════════

def run() -> None:
    today = date.today()
    print(f"\n[daily_collector] {today} 일일 원자재 수집 시작")
    print("=" * 52)

    if len(sys.argv) > 1:
        if _handle_cli(sys.argv[1:]):
            print("\n[daily_collector] 수동 입력 완료")
            return

    ok_rubber = collect_nr_rubber()
    ok_nickel = collect_nickel()

    print("\n" + "=" * 52)
    results = [
        ("#2  천연고무 TSR20", ok_rubber, "--nr-rubber <USc/kg>"),
        ("#4  니켈",           ok_nickel, "--nickel <USD/MT>"),
    ]
    success = sum(1 for _, ok, _ in results if ok)
    for name, ok, _ in results:
        print(f"  {name:<22} {'✓' if ok else '✗ 수동 입력 필요'}")

    print(f"\n[daily_collector] 완료: {success}/{len(results)} 성공")

    failed = [cmd for _, ok, cmd in results if not ok]
    if failed:
        print("\n수동 입력 명령어:")
        for cmd in failed:
            print(f"  uv run python collectors/daily_collector.py {cmd}")

    from heartbeat import record
    record("daily_collector")


if __name__ == "__main__":
    run()
