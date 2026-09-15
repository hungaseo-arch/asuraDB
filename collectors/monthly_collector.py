"""
월간 지표 수집기 — BI 기준금리 + 인도네시아 물가 + PMI + 수입관세율 (월 1회)

수집 대상:
  #3  cpo            — Kemendag Harga Referensi CPO (USD/MT, 월 1회 고시)
  #5  coal           — ESDM HBA I (5,300 kcal, USD/MT)
  #14 bi_rate        — Bank Indonesia BI-Rate (웹 스크래핑)
  #15 idn_inflation  — BPS Web API (YoY CPI %)
  #16 idn_pmi        — S&P Global / Trading Economics (웹 스크래핑)
  #33 import_tariff  — 인도네시아 관세청(beacukai) / Kemendag 스크래핑

기록 일자
  recorded_date 는 해당 월의 **마지막 날** (예: 6월 분 → 2026-06-30) 로 저장.
  실제 발표 일자는 지표마다 다르나, 모니터링 시점(말일) 기준으로 단일화.

품질 등급(quality): 실측 = 소스 발표 원본값 · 파생 = 규칙 산출 · 추정 = Proxy/역산

2026-08-24 소스 이관 (5년백필 작업지시서 ②)
  · cpo  : Bursa FCPO(MYR/MT, daily_collector) → Kemendag Harga Referensi(USD/MT)
  · coal : Trading Economics Newcastle(weekly_collector) → ESDM HBA I(USD/MT)
  두 지표 모두 월 1회 정부 고시라 여기(월간)로 옮겼다. 자동 수집 실패 시
  **옛 소스로 되돌아가지 않고** 수동 입력을 요구한다(단위·기준이 다르므로).

실행: uv run python collectors/monthly_collector.py
스케줄: launchd com.asuradb.monthly.plist (매일 새벽 1시 + 내부에서 말일 가드)
"""
import calendar
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

TIMEOUT = 20
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )
}


# ══════════════════════════════════════════════════════════════
#  공통 유틸
# ══════════════════════════════════════════════════════════════

def _month_end(d: date) -> date:
    """주어진 날짜를 같은 달의 마지막 날로 정규화."""
    return date(d.year, d.month, calendar.monthrange(d.year, d.month)[1])


def upsert(indicator_id: str, record_date: date, value: float,
           note: str = "", quality: str = "실측") -> None:
    # 사용자 요청: "매월 마지막 일 기준" — published 일자/실행 일자와 무관하게
    # 해당 월의 말일로 저장해 시계열을 균일하게 유지.
    # 모든 행은 출처(note)와 품질 등급(실측/파생/추정)을 갖는다 (5년백필 원칙).
    record_date = _month_end(record_date)
    if not note:
        raise ValueError(f"note(출처) 없는 행 금지: {indicator_id} {record_date}")
    if quality not in ("실측", "파생", "추정"):
        raise ValueError(f"quality 값 오류: {quality}")
    _sb.table("indicator_history").upsert(
        {
            "indicator_id":  indicator_id,
            "value":         value,
            "recorded_date": record_date.isoformat(),
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
        d = date.fromisoformat(rows[0]["recorded_date"])
        return d, float(rows[0]["value"])
    return None


_MONTH_MAP = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    "january": 1, "february": 2, "march": 3, "april": 4, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
    "januari": 1, "februari": 2, "maret": 3, "mei": 5, "juni": 6,
    "juli": 7, "agustus": 8, "oktober": 10, "desember": 12,
}


def _parse_date(s: str) -> Optional[date]:
    """다양한 날짜 형식 파싱 (DD/MM/YYYY, YYYY-MM-DD, 22 May 2025 등)."""
    s = s.strip()
    for pat, grp in [
        (r"(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})", lambda m: (int(m.group(3)), int(m.group(2)), int(m.group(1)))),
        (r"(\d{4})-(\d{2})-(\d{2})",               lambda m: (int(m.group(1)), int(m.group(2)), int(m.group(3)))),
    ]:
        m = re.match(pat, s)
        if m:
            try:
                return date(*grp(m))
            except ValueError:
                pass
    for pat, month_grp, day_grp, year_grp in [
        (r"(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})", 2, 1, 3),
        (r"([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})", 1, 2, 3),
        (r"([A-Za-z]+)\s+(\d{4})",               1, None, 2),
    ]:
        m = re.match(pat, s)
        if m:
            mo = _MONTH_MAP.get(m.group(month_grp).lower())
            if not mo:
                continue
            yr = int(m.group(year_grp))
            dy = int(m.group(day_grp)) if day_grp else 1
            try:
                return date(yr, mo, dy)
            except ValueError:
                pass
    return None


# ══════════════════════════════════════════════════════════════
#  #3  팜유 CPO (cpo) — Kemendag Harga Referensi
#  단위: USD/MT (VAT 무관, FOB 기준 고시가)
#  고시: 매월 1일부터 적용되는 Kepmendag. 산정은 전월 평균가 기준.
#  1차: jdih.kemendag.go.id (Kepmendag 원문) · 실무 확인처: GIMNI 집계표
# ══════════════════════════════════════════════════════════════

_CPO_HR_URL   = "https://gimni.org/harga-cpo/"          # Kepmendag HR 집계표
_CPO_JDIH_URL = "https://jdih.kemendag.go.id/"          # 고시 원문(수동 확인)
_CPO_RANGE    = (500.0, 2500.0)                         # USD/MT 유효 범위

# 인도네시아어 월 약어 → 월 번호
_ID_MONTH = {
    "jan": 1, "feb": 2, "peb": 2, "mar": 3, "apr": 4, "mei": 5, "jun": 6,
    "jul": 7, "agt": 8, "ags": 8, "agu": 8, "sep": 9, "okt": 10, "nov": 11, "des": 12,
}


def _parse_id_date(s: str) -> Optional[date]:
    """'01 Agt 2026' 형태의 인도네시아어 날짜 파싱."""
    m = re.search(r"(\d{1,2})\s+([A-Za-z]+)\.?\s+(\d{4})", s.strip())
    if not m:
        return None
    mo = _ID_MONTH.get(m.group(2)[:3].lower())
    if not mo:
        return None
    try:
        return date(int(m.group(3)), mo, int(m.group(1)))
    except ValueError:
        return None


def _parse_id_number(s: str) -> Optional[float]:
    """'US$ 1.029,51' → 1029.51 (인니 표기: . = 천단위, , = 소수점)."""
    m = re.search(r"([\d.]+,\d+|[\d.]+)", s.replace("\u00a0", " "))
    if not m:
        return None
    try:
        return float(m.group(1).replace(".", "").replace(",", "."))
    except ValueError:
        return None


def _fetch_cpo_hr() -> list[tuple[date, float, str]]:
    """Kemendag HR 집계표 → [(적용 시작일, USD/MT, 근거 고시)] 최신순."""
    out: list[tuple[date, float, str]] = []
    try:
        resp = requests.get(_CPO_HR_URL, headers=HEADERS, timeout=TIMEOUT)
        if resp.status_code != 200:
            print(f"  [WARN] HR 집계표 HTTP {resp.status_code}", file=sys.stderr)
            return out
    except Exception as e:
        print(f"  [WARN] HR 집계표 접속 실패: {e}", file=sys.stderr)
        return out

    lo, hi = _CPO_RANGE
    soup = BeautifulSoup(resp.text, "html.parser")
    for table in soup.find_all("table"):
        head = [c.get_text(" ", strip=True).lower() for c in table.find_all(["th", "td"])[:6]]
        if not any("hr" in h and "us$" in h for h in head):
            continue
        for tr in table.find_all("tr"):
            # 날짜 칸이 th 로 오는 표(row header)가 있어 th·td 를 함께 읽는다
            cells = [c.get_text(" ", strip=True) for c in tr.find_all(["th", "td"])]
            if len(cells) < 2:
                continue
            d = _parse_id_date(cells[0])
            v = _parse_id_number(cells[1])
            if d is None or v is None or not (lo <= v <= hi):
                continue
            basis = cells[4] if len(cells) > 4 else ""
            basis = re.sub(r"\s*↗\s*$", "", basis).strip()
            out.append((d, v, basis))
    return sorted(out, key=lambda r: r[0], reverse=True)


def collect_cpo() -> bool:
    print("\n── #3 팜유 CPO — Kemendag Harga Referensi ───────────────")
    rows = _fetch_cpo_hr()

    if not rows:
        latest = _latest_in_db("cpo")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print(f"  ▸ 고시 원문(Kepmendag): {_CPO_JDIH_URL}")
        print(f"  ▸ 집계표: {_CPO_HR_URL}  (USD/MT, 매월 1일 적용)")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:,.2f} USD/MT  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/monthly_collector.py --cpo 996.52")
        print("  ⚠ 옛 소스(Bursa FCPO MYR/MT)로 대체하지 말 것 — 단위·기준이 다르다")
        return False

    saved = 0
    latest = _latest_in_db("cpo")
    threshold = _month_end(latest[0]) if latest else date(1970, 1, 1)
    for d, v, basis in rows:
        m = _month_end(d)
        if m <= threshold:
            continue
        note = f"Kemendag Harga Referensi CPO {m:%Y-%m}"
        if basis:
            note += f" · {basis[:80]}"
        upsert("cpo", m, v, note)
        print(f"  CPO HR {m:%Y-%m}: {v:,.2f} USD/MT  ✓")
        saved += 1

    if saved == 0:
        d, v, _ = rows[0]
        print(f"  최신 고시 {_month_end(d):%Y-%m} {v:,.2f} USD/MT 는 이미 DB 보유 — skip")
    return True


# ══════════════════════════════════════════════════════════════
#  #5  석탄 (coal) — ESDM 고시
#  coal = HBA I (5,300 kcal GAR, USD/MT) — 2023-03 도입, 실제 원가 기준
#  고시: 2025-03 부터 매월 2기(1일·15일). 월값은 그 달 고시의 최신값.
#  ※ 참고용 HBA(6,322 kcal)는 2026-08-24 지표 삭제 — 저장하지 않는다.
# ══════════════════════════════════════════════════════════════

_HBA_URL   = "https://www.minerba.esdm.go.id/harga_acuan"
_HBA_RANGE = (30.0, 450.0)   # USD/MT 유효 범위 (2022 피크 HBA 344 포함)


def _fetch_hba() -> list[tuple[date, float]]:
    """ESDM 고시표 → [(고시일, HBA I)]."""
    out: list[tuple[date, float]] = []
    try:
        resp = requests.get(_HBA_URL, headers=HEADERS, timeout=TIMEOUT)
    except Exception as e:
        print(f"  [WARN] ESDM 접속 실패: {e}", file=sys.stderr)
        return out
    if resp.status_code != 200:
        print(f"  [WARN] ESDM HTTP {resp.status_code}", file=sys.stderr)
        return out
    if "Perbaikan" in resp.text or "Maintenance" in resp.text:
        print("  [WARN] ESDM 사이트 점검 중(Sistem Sedang Dalam Perbaikan)", file=sys.stderr)
        return out

    lo, hi = _HBA_RANGE
    soup = BeautifulSoup(resp.text, "html.parser")
    for table in soup.find_all("table"):
        rows_all = [[c.get_text(" ", strip=True) for c in tr.find_all(["th", "td"])]
                    for tr in table.find_all("tr")]
        if not rows_all:
            continue
        headers = [h.upper() for h in rows_all[0]]
        col_i = next((i for i, h in enumerate(headers) if "HBA I" in h or "5.300" in h or "5,300" in h), None)
        if col_i is None:
            continue
        for cells in rows_all[1:]:
            if len(cells) < 2 or col_i >= len(cells):
                continue
            d = _parse_id_date(cells[0]) or _parse_date(cells[0])
            if d is None:
                continue
            v = _parse_id_number(cells[col_i])
            if v is not None and lo <= v <= hi:
                out.append((d, v))
    out.sort(key=lambda r: r[0], reverse=True)
    return out


def collect_coal() -> bool:
    print("\n── #5 석탄 — ESDM HBA I ─────────────────────────────────")
    rows = _fetch_hba()

    if not rows:
        latest = _latest_in_db("coal")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print(f"  ▸ ESDM 고시: {_HBA_URL}  (HBA I = 5,300 kcal GAR, USD/MT)")
        print("  ▸ 2025-03 부터 매월 2기(1일·15일) 고시 — 그 달 최신 고시값을 쓴다")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:,.2f} USD/MT  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/monthly_collector.py --coal 96.92")
        print("  ⚠ 옛 소스(TE Newcastle)로 대체하지 말 것 — 기준 발열량·산정식이 다르다")
        return False

    saved = 0
    latest = _latest_in_db("coal")
    threshold = _month_end(latest[0]) if latest else date(1970, 1, 1)
    by_month: dict[date, tuple[date, float]] = {}
    for d, v in sorted(rows, key=lambda r: r[0]):
        m = _month_end(d)
        if m > threshold:
            by_month[m] = (d, v)   # 같은 달 2기 고시면 나중(15일) 값 채택
    for m, (d, v) in sorted(by_month.items()):
        upsert("coal", m, v, f"ESDM HBA I(5,300 kcal) {m:%Y-%m} · 고시일 {d}")
        print(f"  coal {m:%Y-%m}: {v:,.2f} USD/MT  ✓")
        saved += 1

    if saved == 0:
        print("  최신 고시분은 이미 DB 보유 — skip")
    return True


# ══════════════════════════════════════════════════════════════
#  #15  BI 기준금리 (bi_rate)
#  소스: https://www.bi.go.id/en/fungsi-utama/moneter/bi-rate/
# ══════════════════════════════════════════════════════════════

_BI_URL = "https://www.bi.go.id/en/fungsi-utama/moneter/bi-rate/default.aspx"


def _fetch_bi_rate_html() -> list[tuple[date, float]]:
    """BI 공식 페이지에서 가능한 한 많은 과거 월 행을 수집 → 신구 동시 반환."""
    try:
        resp = requests.get(_BI_URL, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] BI 페이지 접속 실패: {e}", file=sys.stderr)
        return []

    results: list[tuple[date, float]] = []
    soup = BeautifulSoup(resp.text, "html.parser")
    for table in soup.find_all("table"):
        for row in table.find_all("tr"):
            cols = [td.get_text(strip=True) for td in row.find_all(["td", "th"])]
            if len(cols) < 2:
                continue
            d = _parse_date(cols[0])
            if d is None:
                continue
            try:
                val = float(cols[1].replace(",", ".").replace("%", "").strip())
                if 0.5 <= val <= 25.0:
                    results.append((d, val))
            except ValueError:
                continue
    return results


def _fetch_bi_rate_api() -> list[tuple[date, float]]:
    for url in [
        "https://www.bi.go.id/id/api/content/birate",
        "https://www.bi.go.id/en/api/content/birate",
    ]:
        try:
            resp = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
            if resp.status_code != 200:
                continue
            rows = _extract_all_from_json(resp.json(), ("effectiveDate", "date", "tanggal", "period"),
                                          ("biRate", "rate", "value", "bi_rate"), 0.5, 25.0)
            if rows:
                return rows
        except Exception:
            continue
    return []


def _extract_all_from_json(
    data: object,
    date_keys: tuple,
    val_keys: tuple,
    val_min: float,
    val_max: float,
    sink: Optional[list[tuple[date, float]]] = None,
) -> list[tuple[date, float]]:
    """JSON 트리 전체를 순회해 (date_key, val_key) 매칭 row 를 모두 수집."""
    if sink is None:
        sink = []
    if isinstance(data, dict):
        for dk in date_keys:
            for vk in val_keys:
                if dk in data and vk in data:
                    d = _parse_date(str(data[dk]))
                    if d:
                        try:
                            v = float(str(data[vk]).replace("%", "").replace(",", "."))
                            if val_min <= v <= val_max:
                                sink.append((d, v))
                        except ValueError:
                            pass
        for v in data.values():
            _extract_all_from_json(v, date_keys, val_keys, val_min, val_max, sink)
    elif isinstance(data, list):
        for item in data:
            _extract_all_from_json(item, date_keys, val_keys, val_min, val_max, sink)
    return sink


def collect_bi_rate() -> bool:
    print("\n── #14 BI 기준금리 (bi_rate) ──────────────────────────")
    rows = _fetch_bi_rate_html()
    if not rows:
        print("  HTML 파싱 실패 → API 엔드포인트 시도 중...")
        rows = _fetch_bi_rate_api()
    if not rows:
        latest = _latest_in_db("bi_rate")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ 최신값 확인: https://www.bi.go.id/en/fungsi-utama/moneter/bi-rate/default.aspx")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:.2f}%  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/monthly_collector.py --bi-rate 5.25")
        return False

    saved = _upsert_new_months("bi_rate", rows,
                               "Bank Indonesia BI-Rate 공식 페이지 (RDG 결정값)")
    if saved:
        latest_d, latest_v = max(rows, key=lambda r: r[0])
        print(f"  BI-Rate: {latest_v:.2f}%  (latest {_month_end(latest_d)}, +{saved} new month(s))  ✓")
    else:
        print(f"  BI-Rate: 신규 월 없음 (DB 최신과 동일)  ⏭")
    return True


# ══════════════════════════════════════════════════════════════
#  #16  인도네시아 물가 (idn_inflation) — BPS API
# ══════════════════════════════════════════════════════════════

_BPS_BASE = "https://webapi.bps.go.id/v1/api"
# 2026-08-24 정정: 구 변수 1707 은 인플레이션이 아니라 "10세 이상 인터넷 이용 인구
# 비율" 이었다(그동안 잘못된 값을 저장). 실제 인플레이션 변수는 다음 둘이다.
#   2249 = Inflasi Tahunan (Y-on-Y, 2022=100)  · 2024-01 이후 · vervar 151(INDONESIA)
#   1    = Inflasi Bulanan (M-to-M)            · 2020-01 이후 · vervar 9999(INDONESIA)
# Y-on-Y 가 없는 월은 M-to-M 12개월 누적환산으로 산출한다(등급 = 파생).
_VAR_YOY  = "2249"
_VAR_MOM  = "1"
def _bps_series(var: str, years: list[int], key: str) -> dict[str, float]:
    """BPS 국가 전체(INDONESIA) 월별 시계열 → {YYYY-MM: 값}.

    th(연도) 파라미터는 필수이며 1회 호출당 3개년까지만 허용된다.
    연도 id = 연도 − 1900 (예: 2026 → 126). 월 13 은 '연간' 집계라 제외한다.
    """
    out: dict[str, float] = {}
    for i in range(0, len(years), 3):
        win = years[i:i + 3]
        th = f"{win[0] - 1900}:{win[-1] - 1900}" if len(win) > 1 else f"{win[0] - 1900}"
        url = f"{_BPS_BASE}/list/model/data/domain/0000/var/{var}/th/{th}/key/{key}"
        try:
            p = requests.get(url, timeout=60).json()
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
            yid, mm = k[len(prefix):][:3], k[len(prefix):][3:]
            if yid not in yrs or not mm.isdigit():
                continue
            mo = int(mm)
            if not 1 <= mo <= 12:
                continue
            try:
                out[f"{yrs[yid]}-{mo:02d}"] = float(v)
            except (TypeError, ValueError):
                continue
    return out


def collect_idn_inflation() -> bool:
    print("\n── #15 인도네시아 물가 (idn_inflation) ─────────────────")
    api_key = os.environ.get("BPS_API_KEY", "")
    if not api_key:
        print(
            "  [SKIP] BPS_API_KEY 없음\n"
            "  ▸ 발급: https://webapi.bps.go.id → 가입 → API KEY 탭\n"
            "  ▸ .env 에 BPS_API_KEY=<key> 추가 후 재실행",
            file=sys.stderr,
        )
        return False

    today = date.today()
    years = [today.year - 1, today.year]
    yoy = _bps_series(_VAR_YOY, years, api_key)
    mom = _bps_series(_VAR_MOM, [years[0] - 1] + years, api_key)
    print(f"  Y-on-Y(var {_VAR_YOY}) {len(yoy)}개월 · M-to-M(var {_VAR_MOM}) {len(mom)}개월 수신")
    if not yoy and not mom:
        print("  [FAIL] BPS 응답 데이터 없음", file=sys.stderr)
        return False

    def _yoy_from_mom(y: int, m: int) -> Optional[float]:
        """M-to-M 12개월 누적 → Y-on-Y 환산 (파생)."""
        acc = 1.0
        for i in range(12):
            mm, yy = m - i, y
            while mm <= 0:
                mm += 12
                yy -= 1
            v = mom.get(f"{yy}-{mm:02d}")
            if v is None:
                return None
            acc *= 1 + v / 100
        return (acc - 1) * 100

    latest = _latest_in_db("idn_inflation")
    threshold = _month_end(latest[0]) if latest else date(1970, 1, 1)

    saved, latest_date, latest_val = 0, None, None
    for ym in sorted(set(yoy) | set(mom)):
        y, m = int(ym[:4]), int(ym[5:7])
        d = _month_end(date(y, m, 1))
        if d <= threshold:
            continue
        v, note, quality = yoy.get(ym), "", "실측"
        if v is not None:
            note = f"BPS Web API 변수 {_VAR_YOY} · 인플레이션 Y-on-Y(2022=100) {ym}"
        else:
            v = _yoy_from_mom(y, m)
            if v is None:
                continue
            v, quality = round(v, 2), "파생"
            note = f"파생: BPS 월별 M-to-M(변수 {_VAR_MOM}) 12개월 누적 환산 {ym}"
        upsert("idn_inflation", d, v, note, quality)
        saved += 1
        if latest_date is None or d > latest_date:
            latest_date, latest_val = d, v

    if saved == 0:
        print("  신규 월 없음 (이미 최신)  ✓")
        return True

    print(f"  인플레이션(YoY): {latest_val:.2f}%  ({latest_date.strftime('%Y-%m')})  ✓")
    print(f"  총 {saved}개 레코드 upsert")
    return True


# ══════════════════════════════════════════════════════════════
#  #17  인도네시아 PMI (idn_pmi)
#  소스 1차: S&P Global PMI 페이지 (공식)
#  소스 2차: Trading Economics (백업)
#  발표 주기: 매월 첫 영업일 09:00 WIB
# ══════════════════════════════════════════════════════════════

_SPG_URL = "https://www.pmi.spglobal.com/public/content/Composite/indonesia-manufacturing-pmi"
_TE_URL  = "https://tradingeconomics.com/indonesia/manufacturing-pmi"

# S&P Global JSON API (공식 데이터 엔드포인트)
_SPG_API = "https://www.pmi.spglobal.com/api/pmi/CompositeGetTimeSeriesData"
_SPG_API_PARAMS = {
    "CountryCode": "IDN",
    "SeriesCode":  "Manufacturing",
    "Frequency":   "Monthly",
}


def _fetch_pmi_spglobal_api() -> list[tuple[date, float]]:
    """S&P Global 공식 API — 시계열 전체 반환."""
    results: list[tuple[date, float]] = []
    try:
        resp = requests.get(_SPG_API, params=_SPG_API_PARAMS, headers=HEADERS, timeout=TIMEOUT)
        if resp.status_code != 200:
            return results
        data = resp.json()
        series = data if isinstance(data, list) else data.get("data", data.get("series", []))
        if not isinstance(series, list):
            return results
        for row in series:
            if not isinstance(row, dict):
                continue
            d = _parse_date(str(row.get("date", "")))
            v = row.get("value") or row.get("pmi") or row.get("val")
            if d is None or v is None:
                continue
            try:
                val = float(str(v).replace(",", "."))
                if 30.0 <= val <= 70.0:
                    results.append((d, val))
            except ValueError:
                continue
    except Exception:
        pass
    return results


def _fetch_pmi_spglobal_html() -> list[tuple[date, float]]:
    """S&P Global PMI 페이지 HTML 스크래핑 — 가능한 모든 월."""
    results: list[tuple[date, float]] = []
    try:
        resp = requests.get(_SPG_URL, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] S&P Global 접속 실패: {e}", file=sys.stderr)
        return results

    soup = BeautifulSoup(resp.text, "html.parser")

    # 방법 1: JSON-LD/스크립트
    for script in soup.find_all("script", type="application/json"):
        try:
            import json
            data = json.loads(script.string or "")
            results.extend(_extract_all_from_json(
                data, ("date", "period", "releaseDate"),
                ("value", "pmi", "index", "composite"), 30.0, 70.0,
            ))
        except Exception:
            continue

    # 방법 2: 테이블 내 모든 행
    for table in soup.find_all("table"):
        for row in table.find_all("tr"):
            cols = [td.get_text(strip=True) for td in row.find_all(["td", "th"])]
            if len(cols) < 2:
                continue
            d = _parse_date(cols[0])
            if d is None:
                continue
            try:
                val = float(cols[1].replace(",", "."))
                if 30.0 <= val <= 70.0:
                    results.append((d, val))
            except ValueError:
                continue

    # 방법 3: 단발 텍스트 매칭 (위 둘 다 실패 시 최후 수단)
    if not results:
        text = soup.get_text(" ")
        pmi_match = re.search(r"\b([3-6]\d\.\d)\b", text)
        date_match = re.search(
            r"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)"
            r"\s+\d{4}\b", text,
        )
        if pmi_match and date_match:
            d = _parse_date(date_match.group(0))
            if d:
                try:
                    results.append((d, float(pmi_match.group(1))))
                except ValueError:
                    pass
    return results


def _fetch_pmi_trading_economics() -> list[tuple[date, float]]:
    """Trading Economics 백업 (최신 1건만 — 페이지 구조상 시계열 노출 제한)."""
    results: list[tuple[date, float]] = []
    try:
        resp = requests.get(_TE_URL, headers=HEADERS, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        print(f"  [WARN] Trading Economics 접속 실패: {e}", file=sys.stderr)
        return results

    soup = BeautifulSoup(resp.text, "html.parser")
    text = soup.get_text(" ")

    pmi_pat = re.compile(
        r"(?:Manufacturing PMI|PMI)[^\d]*([3-6]\d\.?\d?)"
        r".*?"
        r"(January|February|March|April|May|June|July|August|September|October|November|December)"
        r"\s+(\d{4})",
        re.IGNORECASE | re.DOTALL,
    )
    m = pmi_pat.search(text[:3000])
    if m:
        d = _parse_date(f"{m.group(2)} {m.group(3)}")
        if d:
            try:
                results.append((d, float(m.group(1))))
            except ValueError:
                pass

    # JSON-LD 전체 row 수집
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            import json
            data = json.loads(script.string or "")
            results.extend(_extract_all_from_json(
                data, ("date", "datePublished", "dateModified"),
                ("value", "pmi", "index"), 30.0, 70.0,
            ))
        except Exception:
            continue
    return results


def collect_idn_pmi() -> bool:
    """인도네시아 Manufacturing PMI 수집."""
    print("\n── #16 인도네시아 PMI (idn_pmi) ────────────────────────")
    print("  발표 주기: 매월 첫 영업일 09:00 WIB (S&P Global)")

    rows = _fetch_pmi_spglobal_api()
    if not rows:
        print("  API 실패 → S&P Global 페이지 스크래핑 시도...")
        rows = _fetch_pmi_spglobal_html()
    if not rows:
        print("  S&P Global 실패 → Trading Economics 백업 시도...")
        rows = _fetch_pmi_trading_economics()

    if not rows:
        latest = _latest_in_db("idn_pmi")
        print("  [FAIL] 자동 수집 실패 — 수동 입력 필요")
        print("  ▸ 최신값 확인: https://www.pmi.spglobal.com")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:.1f}  ({latest[0]})")
        print("  ▸ 수동 실행: uv run python collectors/monthly_collector.py --pmi 52.1")
        print("  ▸ 해석: >50 = 확장, <50 = 위축")
        return False

    saved = _upsert_new_months("idn_pmi", rows,
                               "S&P Global 인도네시아 제조업 PMI (공식 페이지 · TE 백업)")
    if saved:
        latest_d, latest_v = max(rows, key=lambda r: r[0])
        signal = "확장 ▲" if latest_v > 50 else ("위축 ▼" if latest_v < 50 else "보합 ─")
        print(f"  PMI: {latest_v:.1f}  (latest {_month_end(latest_d)}, +{saved} new month(s))  [{signal}]  ✓")
    else:
        print(f"  PMI: 신규 월 없음 (DB 최신과 동일)  ⏭")
    return True


# ══════════════════════════════════════════════════════════════
#  #33  수입관세율 (import_tariff) — Kemendag / beacukai 스크래핑
#  주의: 인도네시아 평균 수입관세율은 정책 변경 빈도가 매우 낮아 (연간 단위)
#       자동 수집 신뢰도가 제한적. 페이지 구조 변경 시 graceful skip.
# ══════════════════════════════════════════════════════════════

_TARIFF_URLS = [
    # Kemendag 무역통계 / 정책 페이지 (정확한 평균관세율 페이지는 가변)
    "https://www.kemendag.go.id/statistik/perdagangan-luar-negeri",
    # 인도네시아 관세청 — BTKI / MFN tariff 안내
    "https://www.beacukai.go.id/arsip/pab/buku-tarif-kepabeanan-indonesia-btki-2022.html",
]


def _fetch_import_tariff_kemendag() -> list[tuple[date, float]]:
    """Kemendag/beacukai 페이지에서 평균 수입관세율(%) 스크래핑.

    페이지에 "Tarif rata-rata" / "MFN average" / "Average tariff" 등 문구
    근처의 0~30% 범위 숫자를 추출. 실패 시 빈 리스트.
    """
    results: list[tuple[date, float]] = []
    pat = re.compile(
        r"(?:Tarif\s+rata[- ]rata|Average\s+tariff|MFN\s+average|평균\s*관세율)"
        r"[^\d]{0,40}(\d{1,2}(?:[.,]\d{1,2})?)\s*%?",
        re.IGNORECASE,
    )
    for url in _TARIFF_URLS:
        try:
            resp = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
            if resp.status_code != 200:
                continue
            text = BeautifulSoup(resp.text, "html.parser").get_text(" ")
            for m in pat.finditer(text):
                try:
                    val = float(m.group(1).replace(",", "."))
                    if 0.5 <= val <= 30.0:
                        # 페이지에 정확한 발효일자 명시 없는 경우가 많아
                        # 현재 월을 record_date 로 사용 (upsert 가 월말로 정규화).
                        results.append((date.today(), val))
                        break
                except ValueError:
                    continue
        except Exception:
            continue
    return results


def collect_import_tariff() -> bool:
    print("\n── #33 수입관세율 (import_tariff) ──────────────────────")
    print("  소스: Kemendag · beacukai (정책 변경 빈도 낮음 — 연간 단위)")
    rows = _fetch_import_tariff_kemendag()
    if not rows:
        latest = _latest_in_db("import_tariff")
        print("  [FAIL] 자동 수집 실패 — 페이지 구조 변경 가능성")
        print("  ▸ 인도네시아 평균관세율 참고: https://www.kemendag.go.id")
        if latest:
            print(f"  ▸ DB 최근값: {latest[1]:.2f}%  ({latest[0]}) — 정책 미변경 시 그대로 유효")
        print("  ▸ 수동 실행: uv run python collectors/monthly_collector.py --tariff 8.5")
        return False

    saved = _upsert_new_months("import_tariff", rows,
                               "인도네시아 관세청(beacukai)/Kemendag 고시")
    if saved:
        latest_d, latest_v = max(rows, key=lambda r: r[0])
        print(f"  수입관세율: {latest_v:.2f}%  (latest {_month_end(latest_d)}, +{saved} new month(s))  ✓")
    else:
        print(f"  수입관세율: 신규 월 없음 (DB 최신과 동일)  ⏭")
    return True


# ══════════════════════════════════════════════════════════════
#  공통: 신규 월만 upsert (DB gap-fill catchup)
# ══════════════════════════════════════════════════════════════

def _upsert_new_months(
    indicator_id: str,
    rows: list[tuple[date, float]],
    note: str,
) -> int:
    """DB 의 최신 월 이후의 row 만 upsert. backfill 누락 월 자동 보충."""
    latest = _latest_in_db(indicator_id)
    threshold = _month_end(latest[0]) if latest else date(1970, 1, 1)
    # 같은 월에 여러 row 가 오면 최신 published 값으로 압축
    by_month: dict[date, float] = {}
    for d, v in rows:
        m = _month_end(d)
        if m > threshold:
            by_month[m] = v  # 같은 키 들어오면 마지막 값으로 덮어씀
    for m, v in sorted(by_month.items()):
        upsert(indicator_id, m, v, note)
    return len(by_month)


# ══════════════════════════════════════════════════════════════
#  CLI — 수동 값 직접 입력 지원
#  예) uv run python collectors/monthly_collector.py --cpo 996.52
#      uv run python collectors/monthly_collector.py --coal 96.92
#      uv run python collectors/monthly_collector.py --bi-rate 5.25
#      uv run python collectors/monthly_collector.py --inflation 2.42
#      uv run python collectors/monthly_collector.py --pmi 52.1
# ══════════════════════════════════════════════════════════════

def _handle_cli_override(args: list[str]) -> bool:
    today = date.today()
    record_date = today  # upsert 가 _month_end 로 정규화
    handled = False

    i = 0
    while i < len(args):
        if args[i] == "--cpo" and i + 1 < len(args):
            val = float(args[i + 1])
            upsert("cpo", record_date, val,
                   "수동 입력 (Kemendag Harga Referensi CPO 고시 확인, USD/MT)")
            print(f"  cpo 수동 저장: {val:,.2f} USD/MT  ({_month_end(record_date)})")
            handled = True; i += 2
        elif args[i] == "--coal" and i + 1 < len(args):
            val = float(args[i + 1])
            upsert("coal", record_date, val,
                   "수동 입력 (ESDM HBA I 5,300 kcal 고시 확인, USD/MT)")
            print(f"  coal 수동 저장: {val:,.2f} USD/MT  ({_month_end(record_date)})")
            handled = True; i += 2
        elif args[i] == "--bi-rate" and i + 1 < len(args):
            val = float(args[i + 1])
            upsert("bi_rate", record_date, val, "수동 입력 (Bank Indonesia RDG 결정값 확인)")
            print(f"  bi_rate 수동 저장: {val:.2f}%  ({_month_end(record_date)})")
            handled = True; i += 2
        elif args[i] == "--inflation" and i + 1 < len(args):
            val = float(args[i + 1])
            upsert("idn_inflation", record_date, val, "수동 입력 (BPS 발표치 확인)")
            print(f"  idn_inflation 수동 저장: {val:.2f}%  ({_month_end(record_date)})")
            handled = True; i += 2
        elif args[i] == "--pmi" and i + 1 < len(args):
            val = float(args[i + 1])
            upsert("idn_pmi", record_date, val, "수동 입력 (S&P Global 발표치 확인)")
            signal = "확장 ▲" if val > 50 else ("위축 ▼" if val < 50 else "보합 ─")
            print(f"  idn_pmi 수동 저장: {val:.1f}  [{signal}]  ({_month_end(record_date)})")
            handled = True; i += 2
        elif args[i] == "--tariff" and i + 1 < len(args):
            val = float(args[i + 1])
            upsert("import_tariff", record_date, val, "수동 입력 (관세 고시 확인)")
            print(f"  import_tariff 수동 저장: {val:.2f}%  ({_month_end(record_date)})")
            handled = True; i += 2
        else:
            i += 1
    return handled


# ══════════════════════════════════════════════════════════════
#  Entry point
# ══════════════════════════════════════════════════════════════

def _needs_catchup() -> bool:
    """직전 월말 기준으로 미보유 지표가 있으면 True (catchup 트리거).

    매월 말일 launchd 실행을 놓치거나 그 사이 발표가 늦어진 경우에도, 다음
    실행 시 자동으로 누락된 월을 채우게 한다. import_tariff 는 연간 단위라
    catchup 판단에서 제외 (무한 retry 방지).
    """
    today = date.today()
    prev_month_end = _month_end(today.replace(day=1) - timedelta(days=1))
    for ind in ("cpo", "coal", "bi_rate", "idn_inflation", "idn_pmi"):
        latest = _latest_in_db(ind)
        if latest is None or _month_end(latest[0]) < prev_month_end:
            return True
    return False


def run() -> None:
    today = date.today()
    print(f"\n[monthly_collector] {today} 월간 지표 수집 시작")
    print("=" * 52)

    # CLI 수동 입력 모드 (--bi-rate / --inflation / --pmi / --tariff)
    if len(sys.argv) > 1:
        if _handle_cli_override(sys.argv[1:]):
            print("\n[monthly_collector] 수동 입력 완료")
            return

    # 자동 실행 가드: 매일 새벽 1시에 launchd 가 깨우지만 실제 수집은
    # (a) 오늘이 말일이거나 (내일이 1일), (b) catchup 필요, (c) --force 시.
    tomorrow_is_first = (today + timedelta(days=1)).day == 1
    force = "--force" in sys.argv
    catchup = _needs_catchup()

    if not (tomorrow_is_first or force or catchup):
        print(f"  말일 아님 + 모든 월간 지표 최신 보유 → 수집 skip")
        print(f"  강제 실행: uv run python collectors/monthly_collector.py --force")
        return

    reason = []
    if tomorrow_is_first: reason.append("말일")
    if catchup:           reason.append("catchup")
    if force:             reason.append("force")
    print(f"  실행 사유: {' / '.join(reason)}")

    ok_cpo       = collect_cpo()
    ok_coal      = collect_coal()
    ok_bi        = collect_bi_rate()
    ok_inflation = collect_idn_inflation()
    ok_pmi       = collect_idn_pmi()
    ok_tariff    = collect_import_tariff()

    print("\n" + "=" * 52)
    results = [
        ("#3  팜유 CPO(HR)",     ok_cpo,       "cpo <USD/MT>"),
        ("#5  석탄 HBA I",       ok_coal,      "coal <USD/MT>"),
        ("#14 BI 기준금리",      ok_bi,        "bi-rate <금리%>"),
        ("#15 인도네시아 물가",  ok_inflation, "inflation <물가%>"),
        ("#16 인도네시아 PMI",   ok_pmi,       "pmi <PMI값>"),
        ("#33 수입관세율",       ok_tariff,    "tariff <관세%>"),
    ]
    success = sum(1 for _, ok, _ in results if ok)
    for name, ok, _ in results:
        status = "✓" if ok else "✗ 수동 입력 필요"
        print(f"  {name:<22} {status}")

    print(f"\n[monthly_collector] 완료: {success}/{len(results)} 성공")

    failed_cmds = [cmd for _, ok, cmd in results if not ok]
    if failed_cmds:
        print("\n수동 입력 명령어:")
        for cmd in failed_cmds:
            print(f"  uv run python collectors/monthly_collector.py --{cmd}")

    from heartbeat import record
    record("monthly_collector")


if __name__ == "__main__":
    run()
