"""
월별 백필 스크립트 — 2026 지표 월말(month-end) 결손 보충 전용

작업지시서 「KPI지표_월별백필_2026」 이행 도구. 운영 수집기(daily/weekly/monthly)와
분리된 일회성·재실행 안전(idempotent) 스크립트로, **기존 데이터를 절대 삭제하지 않고**
월말 row 만 추가(upsert `on_conflict=indicator_id,recorded_date`)한다.

대상 지표 (yfinance 커버 지표 — 환율 4종·brent_crude — 는 제외):
  nr_rubber cpo nickel            (일일 스크래퍼, daily_collector.py)
  coal carbon_black synthetic_rubber steel_wire scfi   (주간, weekly_collector.py)
  bi_rate idn_inflation idn_pmi   (월간, monthly_collector.py)

월별 값 결정 우선순위:
  1) 해당 월말 row 가 이미 있으면 skip (--overwrite 시에만 갱신)
  2) 파생: 해당 월 안에 일별 row 가 있으면 **월내 최종값**을 월말 날짜로 복제
     note = "derived: <YYYY-MM> 월내 최종가 (<MM-DD>)"
  3) CSV: --from-csv data/backfill_2026.csv 의 확인값 (source_note 필수)
  4) 그 외 → **미해결(unresolved)로 출력에 명시** (조용히 건너뛰지 않음)

사용:
  uv run python collectors/monthly_backfill.py --dry-run
  uv run python collectors/monthly_backfill.py                       # 파생만 실적용
  uv run python collectors/monthly_backfill.py --from-csv data/backfill_2026.csv
  옵션: --from 2026-01  --to 2026-08  --only nr_rubber,cpo  --overwrite
"""
import argparse
import calendar
import csv
import os
import sys
from datetime import date
from typing import Optional

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from supabase import create_client

_sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

# 백필 대상 — yfinance 지표(usd_idr·usd_krw·usd_cny·krw_idr·brent_crude)는
# 일별 시계열이 완전하므로 제외.
TARGETS = [
    "nr_rubber", "cpo", "nickel",
    "coal", "carbon_black", "synthetic_rubber", "steel_wire", "scfi",
    "bi_rate", "idn_inflation", "idn_pmi",
]


def _month_end(y: int, m: int) -> date:
    return date(y, m, calendar.monthrange(y, m)[1])


def _parse_ym(s: str) -> tuple[int, int]:
    y, m = s.split("-")
    return int(y), int(m)


def _months_between(frm: str, to: str) -> list[tuple[int, int]]:
    (fy, fm), (ty, tm) = _parse_ym(frm), _parse_ym(to)
    out, y, m = [], fy, fm
    while (y, m) <= (ty, tm):
        out.append((y, m))
        m += 1
        if m > 12:
            y, m = y + 1, 1
    return out


def _load_history(ids: list[str], frm: str) -> dict[str, list[tuple[date, float]]]:
    """대상 지표의 --from 월초 이후 전체 row 를 한 번에 조회."""
    start = f"{frm}-01"
    rows = (
        _sb.table("indicator_history")
        .select("indicator_id,recorded_date,value")
        .in_("indicator_id", ids)
        .gte("recorded_date", start)
        .order("recorded_date")
        .execute()
        .data
    )
    hist: dict[str, list[tuple[date, float]]] = {i: [] for i in ids}
    for r in rows:
        hist[r["indicator_id"]].append(
            (date.fromisoformat(r["recorded_date"]), float(r["value"]))
        )
    return hist


def _load_csv(path: str) -> dict[tuple[str, str], tuple[float, str]]:
    """backfill CSV 로드 → {(indicator_id, 'YYYY-MM'): (value, source_note)}."""
    out: dict[tuple[str, str], tuple[float, str]] = {}
    with open(path, newline="", encoding="utf-8") as f:
        for i, row in enumerate(csv.DictReader(f), start=2):
            ind = (row.get("indicator_id") or "").strip()
            ym = (row.get("year_month") or "").strip()
            val = (row.get("value") or "").strip()
            note = (row.get("source_note") or "").strip()
            if not ind or not ym:
                continue
            if ind not in TARGETS:
                print(f"  [CSV:{i}행] 대상 외 지표 '{ind}' — 무시", file=sys.stderr)
                continue
            if not note:
                # 작업지시 원칙: 추정·확인값은 반드시 출처(note) 동반
                print(f"  [CSV:{i}행] source_note 누락 ({ind} {ym}) — 무시", file=sys.stderr)
                continue
            try:
                out[(ind, ym)] = (float(val), note)
            except ValueError:
                print(f"  [CSV:{i}행] value 숫자 아님 ({ind} {ym}: {val!r}) — 무시", file=sys.stderr)
    return out


def upsert(indicator_id: str, record_date: date, value: float, note: str) -> None:
    _sb.table("indicator_history").upsert(
        {
            "indicator_id": indicator_id,
            "value": value,
            "recorded_date": record_date.isoformat(),
            "note": note or None,
        },
        on_conflict="indicator_id,recorded_date",
    ).execute()


def run() -> int:
    today = date.today()
    default_to = f"{today.year}-{today.month:02d}"

    ap = argparse.ArgumentParser(description="지표 월말 백필 (추가 전용, 삭제 없음)")
    ap.add_argument("--from", dest="frm", default="2026-01", metavar="YYYY-MM")
    ap.add_argument("--to", dest="to", default=default_to, metavar="YYYY-MM")
    ap.add_argument("--only", default="", help="쉼표구분 indicator_id 목록으로 제한")
    ap.add_argument("--dry-run", action="store_true", help="쓰기 없이 계획만 출력")
    ap.add_argument("--overwrite", action="store_true", help="이미 있는 월말 row 도 갱신")
    ap.add_argument("--from-csv", dest="csv_path", default="", metavar="PATH",
                    help="확인값 CSV (indicator_id,year_month,value,source_note)")
    args = ap.parse_args()

    ids = TARGETS
    if args.only:
        ids = [s.strip() for s in args.only.split(",") if s.strip()]
        bad = [i for i in ids if i not in TARGETS]
        if bad:
            print(f"[ERROR] 대상 외 지표: {', '.join(bad)}\n  대상: {', '.join(TARGETS)}")
            return 1

    months = _months_between(args.frm, args.to)
    csv_vals = _load_csv(args.csv_path) if args.csv_path else {}

    mode = "DRY-RUN (쓰기 없음)" if args.dry_run else "실적용"
    print(f"\n[monthly_backfill] {args.frm} ~ {args.to} · {len(ids)}개 지표 · {mode}")
    print("=" * 60)

    hist = _load_history(ids, args.frm)

    planned: list[tuple[str, date, float, str, str]] = []  # (id, date, value, note, method)
    skipped = 0
    unresolved: list[tuple[str, str, str]] = []            # (id, YYYY-MM, 사유)

    for ind in ids:
        rows = hist.get(ind, [])
        for (y, m) in months:
            me = _month_end(y, m)
            ym = f"{y}-{m:02d}"
            if me > today:
                # 아직 오지 않은 월말(당월 포함) — 일별값이 있으면 잠정 파생, 없으면 CSV
                pass
            existing = next((v for d, v in rows if d == me), None)
            if existing is not None and not args.overwrite:
                skipped += 1
                continue

            in_month = [(d, v) for d, v in rows if d.year == y and d.month == m and d != me]
            if in_month:
                d, v = max(in_month, key=lambda r: r[0])
                note = f"derived: {ym} 월내 최종가 ({d.month:02d}-{d.day:02d})"
                planned.append((ind, me, v, note, "derived"))
                continue

            if (ind, ym) in csv_vals:
                v, note = csv_vals[(ind, ym)]
                planned.append((ind, me, v, note, "csv"))
                continue

            if existing is not None:
                skipped += 1   # --overwrite 인데 새 근거 없음 → 기존값 유지
                continue
            unresolved.append((ind, ym, "월내 일별값 없음 · CSV 확인값 없음"))

    for ind, me, v, note, method in planned:
        tag = "[DRY-RUN] " if args.dry_run else ""
        print(f"  {tag}{ind:<17} {me} = {v:>10,.2f}  [{method}] {note}")
        if not args.dry_run:
            upsert(ind, me, v, note)

    print("\n" + "=" * 60)
    print(f"  upsert {'예정' if args.dry_run else '완료'}: {len(planned)}건 · "
          f"기존 보유 skip: {skipped}건 · 미해결: {len(unresolved)}건")

    if unresolved:
        print("\n  ⚠ 미해결 (값을 확인해 data/backfill_2026.csv 에 추가 후 --from-csv 재실행):")
        for ind, ym, why in unresolved:
            print(f"    - {ind:<17} {ym}  ({why})")

    return 0


if __name__ == "__main__":
    sys.exit(run())
