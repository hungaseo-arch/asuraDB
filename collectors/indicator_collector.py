"""
KPI 수집기 — yfinance 기반 자동 수집 (#1 브렌트유, #9~12 환율)
실행: uv run python collectors/indicator_collector.py
"""
import os
import sys
from datetime import date, timedelta

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

try:
    import yfinance as yf
except ImportError:
    print("yfinance 미설치. uv sync 실행 후 재시도하세요.", file=sys.stderr)
    sys.exit(1)

from supabase import create_client

_sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def fetch_history(ticker: str, days: int = 5) -> list[tuple[date, float]]:
    """최근 N일 (종가, 날짜) 리스트 반환. 시장 휴장일 자동 제외."""
    try:
        data = yf.Ticker(ticker).history(period=f"{days}d")
        if data.empty:
            return []
        return [
            (ts.date(), float(row["Close"]))
            for ts, row in data.iterrows()
        ]
    except Exception as e:
        print(f"  [WARN] {ticker}: {e}", file=sys.stderr)
        return []


def upsert_values(rows: list[dict]) -> None:
    if not rows:
        return
    _sb.table("indicator_history").upsert(
        rows, on_conflict="indicator_id,recorded_date"
    ).execute()


def get_last_date(indicator_id: str) -> date | None:
    """해당 지표의 최신 recorded_date (gap 채우기용). 없으면 None."""
    rows = (
        _sb.table("indicator_history")
        .select("recorded_date")
        .eq("indicator_id", indicator_id)
        .order("recorded_date", desc=True)
        .limit(1)
        .execute()
        .data
    )
    return date.fromisoformat(rows[0]["recorded_date"]) if rows else None


def get_prev_value(indicator_id: str) -> float | None:
    """DB에서 오늘 직전 최근 값 조회 (변화율 계산용)."""
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    rows = (
        _sb.table("indicator_history")
        .select("value,recorded_date")
        .eq("indicator_id", indicator_id)
        .lte("recorded_date", yesterday)
        .order("recorded_date", desc=True)
        .limit(1)
        .execute()
        .data
    )
    return float(rows[0]["value"]) if rows else None


def fmt_change(current: float, prev: float | None) -> str:
    if prev is None or prev == 0:
        return ""
    pct = (current - prev) / prev * 100
    arrow = "▲" if pct > 0 else ("▼" if pct < 0 else "─")
    return f"  {arrow} {pct:+.2f}%"


def derive_krw_idr() -> None:
    """파생 지표 KRW/IDR(1 KRW당 IDR) = USD/IDR ÷ USD/KRW.
    최근 usd_idr·usd_krw 값을 날짜별로 맞춰 계산·upsert."""
    def recent(ind_id: str) -> dict[str, float]:
        rows = (
            _sb.table("indicator_history")
            .select("value,recorded_date")
            .eq("indicator_id", ind_id)
            .order("recorded_date", desc=True)
            .limit(10)
            .execute()
            .data
        )
        return {r["recorded_date"]: float(r["value"]) for r in rows}

    idr, krw = recent("usd_idr"), recent("usd_krw")
    rows = [
        {"indicator_id": "krw_idr", "value": round(idr[d] / krw[d], 2), "recorded_date": d}
        for d in sorted(set(idr) & set(krw)) if krw[d]
    ]
    if rows:
        upsert_values(rows)
        print(f"  {'KRW/IDR (파생)':<20} {rows[-1]['value']:>10.2f} IDR/KRW")


def run() -> None:
    today = date.today()
    print(f"\n[indicator_collector] {today} 수집 시작")
    print(f"{'지표':<22} {'값':>12}  {'전일대비'}")
    print("─" * 50)

    indicators = (
        _sb.table("market_indicators")
        .select("id,name_ko,ticker,unit")
        .eq("source", "yfinance")
        .order("sort_order")
        .execute()
        .data
    )

    success = 0
    for ind in indicators:
        ind_id: str  = ind["id"]
        name: str    = ind["name_ko"]
        ticker: str  = ind["ticker"] or ""
        unit: str    = ind["unit"] or ""

        if not ticker:
            continue

        # gap 채우기: 마지막 기록일부터 오늘까지 (없으면 30일). 최대 400일.
        last = get_last_date(ind_id)
        days = min(400, max(5, (today - last).days + 3)) if last else 30
        history = fetch_history(ticker, days=days)
        if not history:
            print(f"  {name:<20} {'실패':>12}")
            continue

        # 오늘 값 (최신) + upsert
        rows_to_upsert = [
            {"indicator_id": ind_id, "value": val, "recorded_date": d.isoformat()}
            for d, val in history
        ]
        upsert_values(rows_to_upsert)

        current_val = history[-1][1]
        prev_val    = get_prev_value(ind_id)
        change_str  = fmt_change(current_val, prev_val)

        # 단위별 포맷
        if unit in ("IDR", "KRW"):
            val_str = f"{current_val:,.0f} {unit}"
        elif unit == "CNY":
            val_str = f"{current_val:.4f} {unit}"
        else:
            val_str = f"{current_val:.2f} {unit}"

        print(f"  {name:<20} {val_str:>14}{change_str}")
        success += 1

    # 파생 지표: KRW/IDR = USD/IDR ÷ USD/KRW (수집된 usd_idr·usd_krw로 계산)
    derive_krw_idr()

    print("─" * 50)
    print(f"[indicator_collector] 완료: {success}/{len(indicators)} 성공\n")

    from heartbeat import record
    record("indicator_collector")


if __name__ == "__main__":
    run()
