#!/usr/bin/env python3
"""지표 5년 이력 백필 (2021-09 ~ 2026-08).

작업지시서_KPI지표_5년백필_2021-2026.md 실행 스크립트.
월말(recorded_date = 그 달 마지막 날) 1행 = 1개월 원칙으로 채운다.

티어
  migrate  단위 통일 1회성 작업 (nr_rubber ×10 / cpo·coal 소스 교체 전 삭제)
  1        Yahoo Finance 월봉 — brent_crude · usd_idr · usd_krw · usd_cny (+ krw_idr 파생)
  2        World Bank Pink Sheet — nr_rubber(TSR20) · nickel
  3        인도네시아 공식 — cpo(Kemendag HR) · coal(ESDM HBA I) ·
           bi_rate(BI 결정 + 이월) · idn_inflation(BPS API)
  4        파생·프록시 — carbon_black = brent × 14.0
  5        수기 확인값 CSV — idn_pmi · scfi · synthetic_rubber · steel_wire

원칙
  · 모든 쓰기는 upsert(indicator_id, recorded_date) — 중복 생성 없음
  · 모든 행에 note(출처) + quality(실측/파생/추정) 필수
  · 기본은 "빈 달만 채움". --overwrite 는 전량 갱신, --upgrade-only 는 등급 개선 시에만 갱신
  · 해결하지 못한 달은 조용히 넘기지 않고 미해결 목록으로 출력

사용 예
  python collectors/history_backfill.py --tier 1 --dry-run
  python collectors/history_backfill.py --migrate
  python collectors/history_backfill.py --tier 5 --from-csv data/backfill_history.csv
"""
from __future__ import annotations

import argparse
import calendar
import csv
import io
import os
import statistics
import sys
from datetime import date
from typing import Iterable, Optional

import requests
from dotenv import load_dotenv
from supabase import create_client

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

_sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

ROOT      = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RESEARCH  = os.path.join(ROOT, "data", "research")
CACHE     = os.path.join(ROOT, "data", "cache")
TIMEOUT   = 30
BATCH     = 500

DEFAULT_FROM = "2021-09"
DEFAULT_TO   = "2026-08"

QUALITY_RANK = {"추정": 1, "파생": 2, "실측": 3}

BACKUP_TABLE = "indicator_history_backup_20260824"


# ── 공통 유틸 ────────────────────────────────────────────────────
def _month_end(y: int, m: int) -> date:
    return date(y, m, calendar.monthrange(y, m)[1])


def _parse_ym(s: str) -> tuple[int, int]:
    y, m = s.split("-")
    return int(y), int(m)


def _months_between(frm: str, to: str) -> list[tuple[int, int]]:
    (y1, m1), (y2, m2) = _parse_ym(frm), _parse_ym(to)
    out = []
    y, m = y1, m1
    while (y, m) <= (y2, m2):
        out.append((y, m))
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def _ym(d: date) -> str:
    return f"{d.year}-{d.month:02d}"


def _load_history(ids: Iterable[str], frm: str) -> dict[str, dict[date, tuple[float, str, str]]]:
    """indicator_id → {recorded_date: (value, note, quality)}"""
    y, m = _parse_ym(frm)
    start = date(y, m, 1).isoformat()
    out: dict[str, dict[date, tuple[float, str, str]]] = {}
    page, size = 0, 1000
    while True:
        res = (
            _sb.table("indicator_history")
            .select("indicator_id,value,recorded_date,note,quality")
            .in_("indicator_id", list(ids))
            .gte("recorded_date", start)
            .order("recorded_date")
            .range(page * size, page * size + size - 1)
            .execute()
        )
        rows = res.data or []
        for r in rows:
            d = date.fromisoformat(r["recorded_date"])
            out.setdefault(r["indicator_id"], {})[d] = (
                float(r["value"]), r.get("note") or "", r.get("quality") or "",
            )
        if len(rows) < size:
            break
        page += 1
    return out


def _indicator_meta() -> dict[str, dict]:
    res = _sb.table("market_indicators").select(
        "id,name_ko,unit,unit_native,unit_factor,source_name"
    ).execute()
    return {r["id"]: r for r in (res.data or [])}


class Planner:
    """계획 수집 → 배치 upsert. 등급·덮어쓰기 규칙을 한 곳에서 처리한다."""

    def __init__(self, hist: dict, overwrite: bool, upgrade_only: bool, dry_run: bool):
        self.hist = hist
        self.overwrite = overwrite
        self.upgrade_only = upgrade_only
        self.dry_run = dry_run
        self.rows: list[dict] = []
        self.skipped = 0
        self.unresolved: list[tuple[str, str, str]] = []

    def add(self, ind: str, d: date, value: float, note: str, quality: str) -> None:
        if quality not in QUALITY_RANK:
            raise ValueError(f"잘못된 quality: {quality!r} ({ind} {d})")
        if not note:
            raise ValueError(f"note 없는 행 금지 ({ind} {d})")
        cur = self.hist.get(ind, {}).get(d)
        if cur is not None:
            cur_q = cur[2]
            if self.upgrade_only:
                if QUALITY_RANK.get(cur_q, 0) >= QUALITY_RANK[quality]:
                    self.skipped += 1
                    return
            elif not self.overwrite:
                self.skipped += 1
                return
            elif QUALITY_RANK.get(cur_q, 0) > QUALITY_RANK[quality]:
                # 추정이 실측을 덮어쓰지 않는다 (--overwrite 여도 등급 하향 금지)
                self.skipped += 1
                return
        self.rows.append({
            "indicator_id": ind,
            "recorded_date": d.isoformat(),
            "value": round(float(value), 6),
            "note": note,
            "quality": quality,
        })

    def miss(self, ind: str, ym: str, reason: str) -> None:
        self.unresolved.append((ind, ym, reason))

    def flush(self) -> int:
        if not self.rows:
            return 0
        if self.dry_run:
            return len(self.rows)
        n = 0
        for i in range(0, len(self.rows), BATCH):
            chunk = self.rows[i:i + BATCH]
            _sb.table("indicator_history").upsert(
                chunk, on_conflict="indicator_id,recorded_date"
            ).execute()
            n += len(chunk)
        return n

    def report(self, title: str) -> None:
        by_ind: dict[str, int] = {}
        for r in self.rows:
            by_ind[r["indicator_id"]] = by_ind.get(r["indicator_id"], 0) + 1
        print(f"\n[{title}] 계획 {len(self.rows)}행 · 기존유지 {self.skipped}행")
        for k in sorted(by_ind):
            q = {}
            for r in self.rows:
                if r["indicator_id"] == k:
                    q[r["quality"]] = q.get(r["quality"], 0) + 1
            qs = " ".join(f"{a}{b}" for a, b in sorted(q.items()))
            print(f"   {k:<16} {by_ind[k]:>3}행  ({qs})")
        if self.unresolved:
            print(f"  ⚠ 미해결 {len(self.unresolved)}건")
            for ind, ym, why in self.unresolved[:40]:
                print(f"     {ind:<16} {ym}  {why}")
            if len(self.unresolved) > 40:
                print(f"     … 외 {len(self.unresolved) - 40}건")


# ── 0) 단위 통일 1회성 마이그레이션 ───────────────────────────────
def run_migrate(dry_run: bool) -> int:
    print("\n[migrate] 단위 통일 · 소스 교체 준비")
    print("=" * 64)

    bk = _sb.table(BACKUP_TABLE).select("indicator_id", count="exact").execute()
    n_backup = bk.count or 0
    if n_backup < 90:
        print(f"  [중단] 백업 테이블 {BACKUP_TABLE} 행수 {n_backup} — 91행 기대. 삭제 불가")
        return 1
    print(f"  백업 확인: {BACKUP_TABLE} {n_backup}행 ✓")

    # 1) nr_rubber USc/kg → USD/MT (×10). 스케일 가드로 2회 적용 방지
    rows = (_sb.table("indicator_history")
            .select("id,value,note,recorded_date")
            .eq("indicator_id", "nr_rubber").execute().data or [])
    if rows:
        mx = max(float(r["value"]) for r in rows)
        already = any("단위환산" in (r.get("note") or "") for r in rows)
        if mx > 1000 or already:
            print(f"  nr_rubber ×10: 건너뜀 (최대값 {mx:,.1f} · 환산표시 {already}) — 이미 적용됨")
        else:
            print(f"  nr_rubber ×10: {len(rows)}행 (최대 {mx:,.1f} → {mx * 10:,.1f})")
            if not dry_run:
                payload = [{
                    "indicator_id": "nr_rubber",
                    "recorded_date": r["recorded_date"],
                    "value": round(float(r["value"]) * 10, 6),
                    "note": (r.get("note") or "").strip() + " · 단위환산 USc/kg→USD/MT (×10)",
                    "quality": "실측",   # 환산은 측정값을 바꾸지 않는다
                } for r in rows]
                for i in range(0, len(payload), BATCH):
                    _sb.table("indicator_history").upsert(
                        payload[i:i + BATCH], on_conflict="indicator_id,recorded_date"
                    ).execute()
                print("    적용 완료 ✓")
    else:
        print("  nr_rubber: 기존 행 없음")

    # 2) cpo · coal 소스 교체 — 값 수준이 달라 혼재 불가 → 삭제 후 재적재
    for ind, why in (("cpo", "Bursa FCPO MYR/MT → Kemendag HR USD/MT"),
                     ("coal", "TE Newcastle → ESDM HBA I")):
        cur = (_sb.table("indicator_history").select("id", count="exact")
               .eq("indicator_id", ind).execute())
        n = cur.count or 0
        print(f"  {ind} 전량 삭제: {n}행 ({why})")
        if n and not dry_run:
            _sb.table("indicator_history").delete().eq("indicator_id", ind).execute()
            print("    삭제 완료 ✓")

    if dry_run:
        print("\n  DRY-RUN — 실제 변경 없음")
    return 0


# ── 1) Yahoo Finance 월봉 ────────────────────────────────────────
_YF_TICKER = {
    "brent_crude": "BZ=F",
    "usd_idr": "USDIDR=X",
    "usd_krw": "USDKRW=X",
    "usd_cny": "USDCNY=X",
}
_YF_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{t}?interval={iv}&range=10y"
_UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}


def _yahoo_monthly(ticker: str) -> dict[str, tuple[float, date]]:
    """YYYY-MM → (그 달 마지막 거래일 종가, 그 거래일).

    월봉(interval=1mo)은 선물 연결시리즈에서 달이 통째로 빠지는 구멍이 있어
    일봉을 받아 월별 마지막 종가를 직접 집계한다.
    """
    r = requests.get(_YF_URL.format(t=requests.utils.quote(ticker), iv="1d"),
                     headers=_UA, timeout=TIMEOUT)
    r.raise_for_status()
    res = r.json()["chart"]["result"][0]
    ts = res["timestamp"]
    closes = res["indicators"]["quote"][0]["close"]
    out: dict[str, tuple[float, date]] = {}
    for t, c in zip(ts, closes):
        if c is None:
            continue
        d = date.fromtimestamp(t)
        ym = f"{d.year}-{d.month:02d}"
        prev = out.get(ym)
        if prev is None or d >= prev[1]:
            out[ym] = (float(c), d)
    return out


def run_tier1(months, planner: Planner) -> None:
    series: dict[str, dict[str, tuple[float, date]]] = {}
    for ind, tk in _YF_TICKER.items():
        try:
            series[ind] = _yahoo_monthly(tk)
            print(f"  {ind:<12} {tk:<10} {len(series[ind])}개월 수신")
        except Exception as e:
            print(f"  [FAIL] {ind} ({tk}): {e}", file=sys.stderr)
            series[ind] = {}

    for ind, tk in _YF_TICKER.items():
        for (y, m) in months:
            ym = f"{y}-{m:02d}"
            hit = series[ind].get(ym)
            if hit is None:
                planner.miss(ind, ym, f"Yahoo {tk} 일봉 없음")
                continue
            v, d = hit
            planner.add(ind, _month_end(y, m), v,
                        f"Yahoo Finance {tk} · {ym} 월말 종가 ({d:%m-%d})", "실측")

    # krw_idr = usd_idr ÷ usd_krw (양쪽 모두 있는 달만)
    for (y, m) in months:
        ym = f"{y}-{m:02d}"
        a, b = series["usd_idr"].get(ym), series["usd_krw"].get(ym)
        if a is None or b is None or not b[0]:
            planner.miss("krw_idr", ym, "usd_idr 또는 usd_krw 없음")
            continue
        planner.add("krw_idr", _month_end(y, m), a[0] / b[0],
                    f"파생: USD/IDR({a[0]:,.0f}) ÷ USD/KRW({b[0]:,.2f}) · {ym} 월말", "파생")


# ── 2) World Bank Pink Sheet ─────────────────────────────────────
# 배포 URL 은 갱신판마다 해시가 바뀐다 → 공식 페이지에서 매번 탐색하고, 실패 시 알려진 링크 사용
_PINK_PAGE = "https://www.worldbank.org/en/research/commodity-markets"
_PINK_URLS = [
    "https://thedocs.worldbank.org/en/doc/74e8be41ceb20fa0da750cda2f6b9e4e-0050012026/related/CMO-Historical-Data-Monthly.xlsx",
    "https://thedocs.worldbank.org/en/doc/18675f1d1639c7a34d463f59263ba0a2-0050012025/related/CMO-Historical-Data-Monthly.xlsx",
]
_PINK_CACHE = os.path.join(CACHE, "CMO-Historical-Data-Monthly.xlsx")


def _pink_discover() -> list[str]:
    import re
    try:
        html = requests.get(_PINK_PAGE, headers=_UA, timeout=40).text
        found = re.findall(
            r"https://thedocs\.worldbank\.org[^\"')\s]*CMO-Historical-Data-Monthly\.xlsx", html)
        if found:
            print(f"  최신판 링크 확인: …{found[0][-60:]}")
        return list(dict.fromkeys(found))
    except Exception as e:
        print(f"  [WARN] Pink Sheet 링크 탐색 실패: {e}", file=sys.stderr)
        return []


def _pink_download(refresh: bool) -> Optional[str]:
    os.makedirs(CACHE, exist_ok=True)
    if os.path.exists(_PINK_CACHE) and not refresh:
        print(f"  캐시 사용: {_PINK_CACHE}")
        return _PINK_CACHE
    for url in _pink_discover() + _PINK_URLS:
        try:
            r = requests.get(url, headers=_UA, timeout=90)
            r.raise_for_status()
            with open(_PINK_CACHE, "wb") as f:
                f.write(r.content)
            print(f"  다운로드 성공: {url.rsplit('/', 1)[-1]} ({len(r.content) / 1024:,.0f} KB)")
            return _PINK_CACHE
        except Exception as e:
            print(f"  [WARN] {url[:60]}… 실패: {e}", file=sys.stderr)
    return None


def _pink_parse(path: str) -> tuple[dict[str, dict[str, float]], dict[str, str]]:
    """'Monthly Prices' 시트에서 Rubber TSR20 · Nickel 열을 런타임 탐색."""
    from openpyxl import load_workbook

    wb = load_workbook(path, read_only=True, data_only=True)
    sheet = next((s for s in wb.sheetnames if "monthly" in s.lower() and "price" in s.lower()),
                 wb.sheetnames[0])
    ws = wb[sheet]
    grid = [list(r) for r in ws.iter_rows(values_only=True)]
    wb.close()

    want = {"nr_rubber": ("rubber", "tsr20"), "nickel": ("nickel",)}
    col: dict[str, int] = {}
    unit_row_idx = None
    header_row_idx = None
    for i, row in enumerate(grid[:12]):
        cells = [str(c).strip().lower() if c is not None else "" for c in row]
        for ind, keys in want.items():
            if ind in col:
                continue
            for j, c in enumerate(cells):
                if all(k in c for k in keys):
                    col[ind] = j
                    header_row_idx = i
        if col and header_row_idx == i:
            unit_row_idx = i + 1
    missing = [k for k in want if k not in col]
    if missing:
        raise RuntimeError(f"Pink Sheet 열을 찾지 못함: {missing} (시트 {sheet!r})")

    units: dict[str, str] = {}
    if unit_row_idx is not None and unit_row_idx < len(grid):
        for ind, j in col.items():
            u = grid[unit_row_idx][j] if j < len(grid[unit_row_idx]) else None
            units[ind] = str(u).strip() if u else ""

    data: dict[str, dict[str, float]] = {k: {} for k in col}
    for row in grid[(header_row_idx or 0) + 1:]:
        if not row or row[0] is None:
            continue
        label = str(row[0]).strip()
        if "M" not in label:
            continue
        try:
            ys, ms = label.split("M")
            y, m = int(ys), int(ms)
        except ValueError:
            continue
        for ind, j in col.items():
            v = row[j] if j < len(row) else None
            if v in (None, "", "..", "…"):
                continue
            try:
                data[ind][f"{y}-{m:02d}"] = float(v)
            except (TypeError, ValueError):
                continue
    return data, units


def run_tier2(months, planner: Planner, meta: dict, refresh: bool) -> None:
    path = _pink_download(refresh)
    if not path:
        for ind in ("nr_rubber", "nickel"):
            for (y, m) in months:
                planner.miss(ind, f"{y}-{m:02d}", "Pink Sheet 다운로드 실패")
        return
    data, units = _pink_parse(path)
    print(f"  열 확인: nr_rubber 단위 {units.get('nr_rubber','?')!r} "
          f"({len(data['nr_rubber'])}개월) · nickel 단위 {units.get('nickel','?')!r} "
          f"({len(data['nickel'])}개월)")

    # 저장 단위는 USD/MT. TSR20 은 USD/kg 고시 → ×1000
    factors = {}
    for ind in ("nr_rubber", "nickel"):
        f = float(meta.get(ind, {}).get("unit_factor") or 1)
        u = units.get(ind, "").lower()
        if ind == "nr_rubber" and "kg" not in u:
            print(f"  [경고] nr_rubber 원 단위가 {units.get(ind)!r} — 환산계수 {f} 재확인 필요")
        factors[ind] = f

    for ind in ("nr_rubber", "nickel"):
        for (y, m) in months:
            ym = f"{y}-{m:02d}"
            v = data[ind].get(ym)
            if v is None:
                planner.miss(ind, ym, "Pink Sheet 해당 월 없음")
                continue
            native = units.get(ind) or meta.get(ind, {}).get("unit_native") or "?"
            # 단위 환산은 측정값을 바꾸지 않으므로 등급은 실측 유지, 환산 사실은 note 에 남긴다
            conv = f" · 단위환산 {native}→USD/MT (×{factors[ind]:g})" if factors[ind] != 1 else ""
            planner.add(ind, _month_end(y, m), v * factors[ind],
                        f"World Bank Pink Sheet {ym} 월평균{conv}", "실측")


# ── 3) 인도네시아 공식 소스 ──────────────────────────────────────
def _read_research_csv(name: str) -> list[dict]:
    path = os.path.join(RESEARCH, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _t3_cpo(months, planner: Planner) -> None:
    rows = {r["month"]: r for r in _read_research_csv("cpo_hr_kemendag.csv")
            if r.get("series") == "cpo_hr"}
    if not rows:
        for (y, m) in months:
            planner.miss("cpo", f"{y}-{m:02d}", "cpo_hr_kemendag.csv 없음")
        return
    for (y, m) in months:
        ym = f"{y}-{m:02d}"
        r = rows.get(ym)
        if not r:
            planner.miss("cpo", ym, "Kemendag HR 고시 확인 안 됨")
            continue
        planner.add("cpo", _month_end(y, m), float(r["value"]),
                    f"Kemendag Harga Referensi CPO {ym} · {r['source']}", "실측")


def _t3_coal(months, planner: Planner) -> None:
    """coal = HBA I(5,300 kcal). HBA I 미도입 구간(~2023-02)은 HBA×중앙비율 역산."""
    rows = _read_research_csv("hba_esdm.csv")
    if not rows:
        for (y, m) in months:
            planner.miss("coal", f"{y}-{m:02d}", "hba_esdm.csv 없음")
        return
    hba   = {r["month"]: r for r in rows if r["series"] == "HBA"}
    hba_i = {r["month"]: r for r in rows if r["series"] == "HBA_I"}

    # HBA(6,322 kcal) 원계열은 역산 계수 산출에만 쓰고 DB 에 저장하지 않는다.
    # (참고 지표 coal_hba_ref 는 2026-08-24 삭제 — 근거는 hba_esdm.csv 와 각 행 note)

    # 역산 계수 = 5,300 kcal 규격 구간(2023-08~)의 HBA I ÷ HBA 중앙값
    ratios = [float(hba_i[k]["value"]) / float(hba[k]["value"])
              for k in sorted(hba_i)
              if k >= "2023-08" and k in hba and float(hba[k]["value"])]
    ratio = round(statistics.median(ratios), 4) if ratios else None
    if ratio:
        print(f"  HBA I ÷ HBA 중앙비율 {ratio} (5,300 kcal 구간 {len(ratios)}개월 기준)")

    for (y, m) in months:
        ym = f"{y}-{m:02d}"
        r = hba_i.get(ym)
        if r:
            planner.add("coal", _month_end(y, m), float(r["value"]),
                        f"ESDM HBA I {ym} · {r['source']}", "실측")
            continue
        b = hba.get(ym)
        if not b or not ratio:
            planner.miss("coal", ym, "HBA I 없음 · 역산 근거도 없음")
            continue
        v = float(b["value"])
        planner.add("coal", _month_end(y, m), v * ratio,
                    f"추정: HBA(6,322) {v:,.2f} × {ratio} (HBA I 미도입 구간)", "추정")


def _t3_bi_rate(months, planner: Planner) -> None:
    decs = sorted(
        ((date.fromisoformat(r["date"]), float(r["rate"]), r["source"])
         for r in _read_research_csv("bi_rate_decisions.csv")),
        key=lambda x: x[0],
    )
    if not decs:
        for (y, m) in months:
            planner.miss("bi_rate", f"{y}-{m:02d}", "bi_rate_decisions.csv 없음")
        return
    for (y, m) in months:
        ym = f"{y}-{m:02d}"
        me = _month_end(y, m)
        applied = [d for d in decs if d[0] <= me]
        if not applied:
            planner.miss("bi_rate", ym, "해당 시점 이전 결정 없음")
            continue
        dd, rate, src = applied[-1]
        if _ym(dd) == ym:
            planner.add("bi_rate", me, rate, f"Bank Indonesia RDG {dd} 결정 · {src}", "실측")
        else:
            planner.add("bi_rate", me, rate, f"BI-Rate {dd} 결정값 유지", "파생")


_BPS_API = "https://webapi.bps.go.id/v1/api/list/model/data/domain/0000"
# 2026-08 확인: 구 변수 1707 은 인플레이션이 아니라 인터넷 이용률 → 사용 금지.
#   2249 = 인플레이션 Y-on-Y (2022=100, 2024년~)  · vervar 151 = INDONESIA
#   1    = 인플레이션 월별 M-to-M (2020년~)        · vervar 9999 = INDONESIA
_BPS_YOY_VAR, _BPS_MOM_VAR = "2249", "1"


def _bps_series(var: str, years: list[int], key: str) -> dict[str, float]:
    """BPS 국가 전체(INDONESIA) 월별 시계열 → {YYYY-MM: 값}. th 는 1회 3개년 제한."""
    out: dict[str, float] = {}
    for i in range(0, len(years), 3):
        win = years[i:i + 3]
        th = f"{win[0] - 1900}:{win[-1] - 1900}" if len(win) > 1 else f"{win[0] - 1900}"
        try:
            p = requests.get(f"{_BPS_API}/var/{var}/th/{th}/key/{key}", timeout=60).json()
        except Exception as e:
            print(f"  [WARN] BPS var {var} th {th}: {e}", file=sys.stderr)
            continue
        if p.get("data-availability") != "available":
            continue
        nat = next((str(v["val"]) for v in p.get("vervar", [])
                    if str(v.get("label", "")).strip().upper() == "INDONESIA"), None)
        yrs = {str(t["val"]): int(t["label"]) for t in p.get("tahun", [])}
        if not nat:
            continue
        prefix = f"{nat}{var}0"
        for k, v in (p.get("datacontent") or {}).items():
            if not k.startswith(prefix):
                continue
            tail = k[len(prefix):]
            yid, mm = tail[:3], tail[3:]
            if yid not in yrs or not mm.isdigit():
                continue
            mo = int(mm)
            if not 1 <= mo <= 12:      # 13 = '연간' 집계 → 제외
                continue
            try:
                out[f"{yrs[yid]}-{mo:02d}"] = float(v)
            except (TypeError, ValueError):
                continue
    return out


def _t3_inflation(months, planner: Planner) -> None:
    key = os.environ.get("BPS_API_KEY", "")
    if not key:
        for (y, m) in months:
            planner.miss("idn_inflation", f"{y}-{m:02d}", "BPS_API_KEY 없음")
        return
    years = sorted({y for (y, _) in months})
    yoy = _bps_series(_BPS_YOY_VAR, years, key)
    mom = _bps_series(_BPS_MOM_VAR, list(range(min(years) - 1, max(years) + 1)), key)
    print(f"  BPS Y-on-Y(var {_BPS_YOY_VAR}) {len(yoy)}개월 · "
          f"M-to-M(var {_BPS_MOM_VAR}) {len(mom)}개월 수신")
    if not yoy and not mom:
        for (y, m) in months:
            planner.miss("idn_inflation", f"{y}-{m:02d}", "BPS 응답 파싱 실패")
        return

    def _yoy_from_mom(y: int, m: int) -> Optional[float]:
        acc = 1.0
        for i in range(12):
            mm = m - i
            yy = y
            while mm <= 0:
                mm += 12
                yy -= 1
            v = mom.get(f"{yy}-{mm:02d}")
            if v is None:
                return None
            acc *= 1 + v / 100
        return (acc - 1) * 100

    for (y, m) in months:
        ym = f"{y}-{m:02d}"
        v = yoy.get(ym)
        if v is not None:
            planner.add("idn_inflation", _month_end(y, m), v,
                        f"BPS Web API 변수 {_BPS_YOY_VAR} · 인플레이션 Y-on-Y(2022=100) {ym}",
                        "실측")
            continue
        d = _yoy_from_mom(y, m)
        if d is None:
            planner.miss("idn_inflation", ym, "BPS Y-on-Y·M-to-M 모두 없음")
            continue
        planner.add("idn_inflation", _month_end(y, m), round(d, 2),
                    f"파생: BPS 월별 M-to-M(변수 {_BPS_MOM_VAR}) 12개월 누적 환산 {ym}", "파생")


def run_tier3(months, planner: Planner) -> None:
    _t3_cpo(months, planner)
    _t3_coal(months, planner)
    _t3_bi_rate(months, planner)
    _t3_inflation(months, planner)


# ── 4) 파생·프록시 ───────────────────────────────────────────────
CARBON_FACTOR = 14.0


def run_tier4(months, planner: Planner) -> None:
    """carbon_black = brent × 14.0. 계획 중인 brent 값도 함께 참조한다."""
    brent = {d: v for d, (v, _, _) in planner.hist.get("brent_crude", {}).items()}
    for r in planner.rows:
        if r["indicator_id"] == "brent_crude":
            brent[date.fromisoformat(r["recorded_date"])] = float(r["value"])
    for (y, m) in months:
        ym, me = f"{y}-{m:02d}", _month_end(y, m)
        b = brent.get(me)
        if b is None:
            planner.miss("carbon_black", ym, "해당 월 brent 값 없음")
            continue
        planner.add("carbon_black", me, b * CARBON_FACTOR,
                    f"Proxy: Brent×{CARBON_FACTOR:.1f} (Brent={b:,.2f})", "추정")


# ── 5) 수기 확인값 CSV ───────────────────────────────────────────
def run_tier5(months, planner: Planner, meta: dict, csv_path: str) -> None:
    if not csv_path:
        csv_path = os.path.join(ROOT, "data", "backfill_history.csv")
    if not os.path.exists(csv_path):
        print(f"  [SKIP] CSV 없음: {csv_path}")
        return
    ok = bad = 0
    with open(csv_path, encoding="utf-8") as f:
        for i, row in enumerate(csv.DictReader(f), start=2):
            ind = (row.get("indicator_id") or "").strip()
            ym  = (row.get("year_month") or "").strip()
            val = (row.get("value") or "").strip()
            unit = (row.get("unit") or "").strip()
            qual = (row.get("quality") or "").strip() or "실측"
            note = (row.get("source_note") or "").strip()
            if not ind or not ym:
                continue
            if ind not in meta:
                print(f"  [{i}행] 등록되지 않은 지표 '{ind}' — 무시", file=sys.stderr); bad += 1; continue
            if not note:
                print(f"  [{i}행] source_note 누락 ({ind} {ym}) — 무시", file=sys.stderr); bad += 1; continue
            if qual not in QUALITY_RANK:
                print(f"  [{i}행] quality 값 오류 {qual!r} ({ind} {ym}) — 무시", file=sys.stderr); bad += 1; continue
            db_unit = (meta[ind].get("unit") or "").strip()
            if unit and db_unit and unit.lower() != db_unit.lower():
                print(f"  [{i}행] 단위 불일치 ({ind} {ym}: CSV {unit!r} vs DB {db_unit!r}) — 무시",
                      file=sys.stderr); bad += 1; continue
            try:
                v = float(val.replace(",", ""))
            except ValueError:
                print(f"  [{i}행] value 숫자 아님 ({ind} {ym}: {val!r}) — 무시", file=sys.stderr); bad += 1; continue
            y, m = _parse_ym(ym)
            if (y, m) not in months:
                continue
            planner.add(ind, _month_end(y, m), v, note, qual)
            ok += 1
    print(f"  CSV 읽기: 유효 {ok}행 · 무시 {bad}행 ({os.path.relpath(csv_path, ROOT)})")

    # CSV 로도 못 채운 달을 미해결로 남긴다 (CSV 에 아예 없는 지표도 포함)
    for ind in TIER_IDS["5"]:
        have = {date.fromisoformat(r["recorded_date"]) for r in planner.rows
                if r["indicator_id"] == ind} | set(planner.hist.get(ind, {}))
        for (y, m) in months:
            if _month_end(y, m) not in have:
                planner.miss(ind, f"{y}-{m:02d}", "CSV 확인값 없음")


# ── 실행 ────────────────────────────────────────────────────────
TIER_IDS = {
    "1": ["brent_crude", "usd_idr", "usd_krw", "usd_cny", "krw_idr"],
    "2": ["nr_rubber", "nickel"],
    "3": ["cpo", "coal", "bi_rate", "idn_inflation"],
    "4": ["carbon_black", "brent_crude"],
    "5": ["idn_pmi", "scfi", "synthetic_rubber", "steel_wire"],
}


def main() -> int:
    ap = argparse.ArgumentParser(description="지표 5년 이력 백필")
    ap.add_argument("--from", dest="frm", default=DEFAULT_FROM, metavar="YYYY-MM")
    ap.add_argument("--to", dest="to", default=DEFAULT_TO, metavar="YYYY-MM")
    ap.add_argument("--tier", default="", help="1~5 (쉼표 구분). 미지정 시 전체")
    ap.add_argument("--only", default="", help="쉼표구분 indicator_id 로 제한")
    ap.add_argument("--migrate", action="store_true", help="단위 통일 1회성 작업만 수행")
    ap.add_argument("--dry-run", action="store_true", help="쓰기 없이 계획만 출력")
    ap.add_argument("--overwrite", action="store_true", help="기존 행도 갱신 (등급 하향은 금지)")
    ap.add_argument("--upgrade-only", action="store_true", help="등급이 개선될 때만 갱신")
    ap.add_argument("--from-csv", dest="csv_path", default="", metavar="PATH")
    ap.add_argument("--refresh-cache", action="store_true", help="Pink Sheet 재다운로드")
    args = ap.parse_args()

    if args.migrate:
        return run_migrate(args.dry_run)

    tiers = [t.strip() for t in args.tier.split(",") if t.strip()] or ["1", "2", "3", "4", "5"]
    bad = [t for t in tiers if t not in TIER_IDS]
    if bad:
        print(f"[ERROR] 알 수 없는 티어: {bad} (가능: 1~5)")
        return 1

    months = _months_between(args.frm, args.to)
    meta = _indicator_meta()
    ids = sorted({i for t in tiers for i in TIER_IDS[t]})
    if args.only:
        want = {s.strip() for s in args.only.split(",") if s.strip()}
        ids = [i for i in ids if i in want]
        if not ids:
            print("[ERROR] --only 조건에 맞는 지표 없음")
            return 1
    unknown = [i for i in ids if i not in meta]
    if unknown:
        print(f"[ERROR] market_indicators 에 없는 지표: {unknown}")
        return 1

    mode = "DRY-RUN (쓰기 없음)" if args.dry_run else "실적용"
    print(f"\n[history_backfill] {args.frm} ~ {args.to} · {len(months)}개월 · "
          f"티어 {','.join(tiers)} · {mode}")
    print("=" * 64)

    hist = _load_history(ids, args.frm)
    planner = Planner(hist, args.overwrite, args.upgrade_only, args.dry_run)

    for t in tiers:
        print(f"\n── Tier {t} ─────────────────────────────────────")
        if t == "1":
            run_tier1(months, planner)
        elif t == "2":
            run_tier2(months, planner, meta, args.refresh_cache)
        elif t == "3":
            run_tier3(months, planner)
        elif t == "4":
            run_tier4(months, planner)
        elif t == "5":
            run_tier5(months, planner, meta, args.csv_path)

    if args.only:
        keep = set(ids)
        planner.rows = [r for r in planner.rows if r["indicator_id"] in keep]
        planner.unresolved = [u for u in planner.unresolved if u[0] in keep]

    planner.report("계획")
    n = planner.flush()
    print(f"\n{'계획' if args.dry_run else 'upsert 완료'}: {n}행")
    return 0


if __name__ == "__main__":
    sys.exit(main())
